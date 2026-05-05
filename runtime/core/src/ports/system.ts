import type { Result } from "../shared/result.js";

export interface CoreClockPort {
  now(): Date;
}

export interface CoreIdGeneratorPort {
  create(): string;
}

export interface CoreTransactionPort {
  runInTransaction<TValue>(
    operation: () => Promise<Result<TValue>>,
  ): Promise<Result<TValue>>;
}
