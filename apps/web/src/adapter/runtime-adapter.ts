import type {
  CreateComicRequest,
  RuntimeCloseResponseCompat,
  RuntimeHealthResponseCompat,
  RuntimeOpenResponseCompat,
} from "@venera/runtime-contracts";
import {
  createComicResponseSchema,
  runtimeCloseResponseSchema,
  runtimeHealthResponseSchema,
  runtimeOpenResponseSchema,
} from "@venera/runtime-contracts";
import type { z } from "zod";

import type {
  RuntimeCreateComicResult,
  RuntimeProvider,
} from "../provider/runtime-provider.js";
import { createWebError, isWebError, type WebError } from "../server/web-error.js";

export interface RuntimeAdapter {
  getHealth(): RuntimeHealthResponseCompat;
  openRuntime(): Promise<RuntimeOpenResponseCompat>;
  closeRuntime(): Promise<RuntimeCloseResponseCompat>;
  createComic(input: CreateComicRequest): Promise<z.infer<typeof createComicResponseSchema>>;
}

interface CreateRuntimeAdapterOptions {
  readonly provider: RuntimeProvider;
}

export function createRuntimeAdapter(
  options: CreateRuntimeAdapterOptions,
): RuntimeAdapter {
  return {
    getHealth() {
      return {
        runtime: options.provider.getSummary(),
      };
    },
    async openRuntime() {
      return {
        runtime: await options.provider.open(),
      };
    },
    async closeRuntime() {
      return {
        runtime: await options.provider.close(),
      };
    },
    async createComic(input) {
      const result = await options.provider.withRuntime<RuntimeCreateComicResult>((runtime) => {
        return runtime.useCases.createCanonicalComic.execute({
          title: input.title,
          ...(input.description === undefined ? {} : { description: input.description }),
          ...(input.authorName === undefined ? {} : { authorName: input.authorName }),
          ...(input.originHint === undefined ? {} : { originHint: input.originHint }),
          ...(input.idempotencyKey === undefined ? {} : { idempotencyKey: input.idempotencyKey }),
        });
      });

      if (!result.ok) {
        throw mapRuntimeResultError(result);
      }

      return {
        comic: {
          id: result.value.comic.id,
          normalizedTitle: result.value.comic.normalizedTitle,
          originHint: result.value.comic.originHint,
          createdAt: result.value.comic.createdAt.toISOString(),
          updatedAt: result.value.comic.updatedAt.toISOString(),
        },
        metadata: {
          comicId: result.value.metadata.comicId,
          title: result.value.metadata.title,
          description: result.value.metadata.description,
          coverPageId: result.value.metadata.coverPageId,
          coverStorageObjectId: result.value.metadata.coverStorageObjectId,
          authorName: result.value.metadata.authorName,
          metadata: sanitizeMetadata(result.value.metadata.metadata),
          createdAt: result.value.metadata.createdAt.toISOString(),
          updatedAt: result.value.metadata.updatedAt.toISOString(),
        },
        primaryTitle: {
          id: result.value.primaryTitle.id,
          comicId: result.value.primaryTitle.comicId,
          title: result.value.primaryTitle.title,
          normalizedTitle: result.value.primaryTitle.normalizedTitle,
          locale: result.value.primaryTitle.locale,
          sourcePlatformId: result.value.primaryTitle.sourcePlatformId,
          sourceLinkId: result.value.primaryTitle.sourceLinkId,
          titleKind: result.value.primaryTitle.titleKind,
          createdAt: result.value.primaryTitle.createdAt.toISOString(),
        },
      };
    },
  };
}

export function mapUnknownErrorToWebError(error: unknown): WebError {
  if (isWebError(error)) {
    return error;
  }

  return createWebError("INTERNAL");
}

function mapRuntimeResultError(result: Extract<RuntimeCreateComicResult, { ok: false }>): WebError {
  const code = result.error.code;
  if (code === "VALIDATION_ERROR") {
    return createWebError("VALIDATION_FAILED");
  }

  if (code === "IDEMPOTENCY_CONFLICT") {
    return createWebError("IDEMPOTENCY_KEY_PAYLOAD_MISMATCH");
  }

  return createWebError("INTERNAL");
}

function sanitizeMetadata(
  value: unknown,
): z.infer<typeof createComicResponseSchema>["metadata"]["metadata"] {
  if (value === undefined) {
    return undefined;
  }

  return JSON.parse(JSON.stringify(value)) as z.infer<typeof createComicResponseSchema>["metadata"]["metadata"];
}
