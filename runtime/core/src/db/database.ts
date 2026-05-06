import { AsyncLocalStorage } from "node:async_hooks";

import Database from "better-sqlite3";
import { Kysely, SqliteDialect, type Transaction } from "kysely";

import type { CoreError } from "../shared/errors.js";
import { createCoreError } from "../shared/errors.js";
import { err, type Result } from "../shared/result.js";
import type { CoreTransactionPort } from "../ports/system.js";
import type { CoreDatabaseSchema } from "./schema.js";

export interface CreateCoreDatabaseOptions {
  readonly databasePath: string;
}

export interface CoreDatabaseHandle {
  readonly db: Kysely<CoreDatabaseSchema>;
  close(): void;
}

export interface QueryExecutorProvider {
  current(): Kysely<CoreDatabaseSchema> | Transaction<CoreDatabaseSchema>;
}

export interface RuntimeDatabaseHandle extends CoreDatabaseHandle {
  readonly executorProvider: QueryExecutorProvider;
  readonly transactionPort: CoreTransactionPort;
}

class TransactionRollbackSignal extends Error {
  constructor(readonly error: CoreError) {
    super("Transaction rollback requested.");
    this.name = "TransactionRollbackSignal";
  }
}

class QueryExecutorContext implements QueryExecutorProvider, CoreTransactionPort {
  private readonly storage = new AsyncLocalStorage<Transaction<CoreDatabaseSchema>>();

  constructor(private readonly db: Kysely<CoreDatabaseSchema>) {}

  current(): Kysely<CoreDatabaseSchema> | Transaction<CoreDatabaseSchema> {
    return this.storage.getStore() ?? this.db;
  }

  async runInTransaction<TValue>(
    operation: () => Promise<Result<TValue>>,
  ): Promise<Result<TValue>> {
    try {
      return await this.db.transaction().execute((transaction) =>
        this.storage.run(transaction, async () => {
          const result = await operation();
          if (!result.ok) {
            throw new TransactionRollbackSignal(result.error);
          }

          return result;
        }),
      );
    } catch (cause) {
      if (cause instanceof TransactionRollbackSignal) {
        return err(cause.error);
      }

      return err(
        createCoreError({
          code: "INTERNAL_ERROR",
          message: "Transaction failed.",
          cause,
        }),
      );
    }
  }
}

function enableForeignKeys(database: Database.Database): void {
  database.pragma("foreign_keys = ON");
}

export function openRuntimeDatabase(
  options: CreateCoreDatabaseOptions,
): RuntimeDatabaseHandle {
  const sqlite = new Database(options.databasePath);
  enableForeignKeys(sqlite);

  const db = new Kysely<CoreDatabaseSchema>({
    dialect: new SqliteDialect({
      database: sqlite,
    }),
  });

  const executorProvider = new QueryExecutorContext(db);

  return {
    db,
    executorProvider,
    transactionPort: executorProvider,
    close() {
      db.destroy();
      sqlite.close();
    },
  };
}

export function createCoreDatabase(
  options: CreateCoreDatabaseOptions,
): CoreDatabaseHandle {
  const handle = openRuntimeDatabase(options);
  return {
    db: handle.db,
    close: handle.close,
  };
}
