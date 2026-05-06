import type { CoreRepositories } from "./repositories.js";
import type {
  CoreClockPort,
  CoreIdGeneratorPort,
  CoreTransactionPort,
} from "./system.js";

export interface CoreUseCaseDependencies {
  readonly clock: CoreClockPort;
  readonly idGenerator: CoreIdGeneratorPort;
  readonly transaction: CoreTransactionPort;
  readonly repositories: CoreRepositories;
}
