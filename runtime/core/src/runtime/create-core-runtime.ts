import { randomUUID } from "node:crypto";

import { createCoreUseCases, type CoreUseCases } from "../application/index.js";
import {
  createCoreDatabase,
  openRuntimeDatabase,
  type CreateCoreDatabaseOptions,
} from "../db/database.js";
import { migrateCoreDatabase } from "../db/migrations.js";
import { seedCoreDatabase } from "../db/seed.js";
import type { CoreRepositories } from "../ports/repositories.js";
import { createCoreRepositories } from "../repositories/sqlite-repositories.js";

export { createCoreDatabase };

export interface CreateCoreRuntimeOptions extends CreateCoreDatabaseOptions {
  readonly migrate?: boolean;
  readonly seed?: boolean;
}

export interface CoreRuntime {
  readonly db: ReturnType<typeof createCoreDatabase>["db"];
  readonly repositories: CoreRepositories;
  readonly useCases: CoreUseCases;
  close(): void;
}

export async function createCoreRuntime(
  options: CreateCoreRuntimeOptions,
): Promise<CoreRuntime> {
  const handle = openRuntimeDatabase({
    databasePath: options.databasePath,
  });

  if (options.migrate ?? true) {
    await migrateCoreDatabase(handle.db);
  }

  if (options.seed ?? true) {
    await seedCoreDatabase(handle.db);
  }

  const repositories = createCoreRepositories(handle.executorProvider);
  const useCases = createCoreUseCases({
    clock: {
      now: () => new Date(),
    },
    idGenerator: {
      create: () => randomUUID(),
    },
    transaction: handle.transactionPort,
    repositories,
  });

  return {
    db: handle.db,
    repositories,
    useCases,
    close: handle.close,
  };
}
