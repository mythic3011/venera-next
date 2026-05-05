import type { CoreUseCaseDependencies } from "../ports/use-case-dependencies.js";
import { CreateCanonicalComic } from "./create-canonical-comic.js";
import { OpenReader } from "./open-reader.js";
import { ResolveReaderTarget } from "./resolve-reader-target.js";
import { UpdateReaderPosition } from "./update-reader-position.js";

export interface CoreUseCases {
  readonly createCanonicalComic: CreateCanonicalComic;
  readonly resolveReaderTarget: ResolveReaderTarget;
  readonly openReader: OpenReader;
  readonly updateReaderPosition: UpdateReaderPosition;
}

export function createCoreUseCases(
  dependencies: CoreUseCaseDependencies,
): CoreUseCases {
  return {
    createCanonicalComic: new CreateCanonicalComic(dependencies),
    resolveReaderTarget: new ResolveReaderTarget(dependencies),
    openReader: new OpenReader(dependencies),
    updateReaderPosition: new UpdateReaderPosition(dependencies),
  };
}
