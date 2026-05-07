import { createRoute, z } from "@hono/zod-openapi";

import { API_ROUTES } from "@venera/runtime-contracts";

const runtimeStateSchema = z.enum([
  "closed",
  "open",
  "shutting_down",
]).openapi("RuntimeState");

const runtimeSummarySchema = z.object({
  mode: z.literal("demo-memory"),
  state: runtimeStateSchema,
  persistence: z.object({
    kind: z.literal("memory"),
    persisted: z.literal(false),
    notice: z.literal("not-persisted"),
  }).strict(),
}).strict().openapi("RuntimeSummary");

const runtimeEnvelopeSchema = z.object({
  runtime: runtimeSummarySchema,
}).strict().openapi("RuntimeEnvelope");

const apiErrorSchema = z.object({
  error: z.object({
    code: z.enum([
      "VALIDATION_FAILED",
      "IDEMPOTENCY_KEY_PAYLOAD_MISMATCH",
      "RUNTIME_NOT_OPEN",
      "RUNTIME_UNAVAILABLE",
      "RUNTIME_SHUTTING_DOWN",
      "INTERNAL",
    ]),
    message: z.string().min(1),
  }).strict(),
}).strict().openapi("ApiError");

const jsonObjectOpenApiSchema = z.object({})
  .catchall(z.unknown())
  .openapi({
    type: "object",
    additionalProperties: true,
  });

const createComicRequestSchema = z.object({
  title: z.string().trim().min(1),
  description: z.string().trim().min(1).optional(),
  authorName: z.string().trim().min(1).optional(),
  originHint: z.enum([
    "unknown",
    "local",
    "remote",
    "mixed",
  ]).optional(),
  idempotencyKey: z.string().trim().min(1).optional(),
}).strict().openapi("CreateComicRequest");

const createComicResponseSchema = z.object({
  comic: z.object({
    id: z.string().min(1),
    normalizedTitle: z.string().min(1),
    originHint: z.enum([
      "unknown",
      "local",
      "remote",
      "mixed",
    ]),
    createdAt: z.string().datetime({ offset: true }),
    updatedAt: z.string().datetime({ offset: true }),
  }).strict(),
  metadata: z.object({
    comicId: z.string().min(1),
    title: z.string().min(1),
    description: z.string().min(1).optional(),
    coverPageId: z.string().min(1).optional(),
    coverStorageObjectId: z.string().min(1).optional(),
    authorName: z.string().min(1).optional(),
    metadata: jsonObjectOpenApiSchema.optional(),
    createdAt: z.string().datetime({ offset: true }),
    updatedAt: z.string().datetime({ offset: true }),
  }).strict(),
  primaryTitle: z.object({
    id: z.string().min(1),
    comicId: z.string().min(1),
    title: z.string().min(1),
    normalizedTitle: z.string().min(1),
    locale: z.string().min(1).optional(),
    sourcePlatformId: z.string().min(1).optional(),
    sourceLinkId: z.string().min(1).optional(),
    titleKind: z.enum([
      "primary",
      "source",
      "alias",
    ]),
    createdAt: z.string().datetime({ offset: true }),
  }).strict(),
}).strict().openapi("CreateComicResponse");

const emptyBodySchema = z.object({}).strict();

export const runtimeHealthRoute = createRoute({
  method: "get",
  path: API_ROUTES.runtimeHealth,
  responses: {
    200: {
      content: {
        "application/json": {
          schema: runtimeEnvelopeSchema,
        },
      },
      description: "Current demo runtime status.",
    },
  },
});

export const runtimeOpenRoute = createRoute({
  method: "post",
  path: API_ROUTES.runtimeOpen,
  request: {
    body: {
      content: {
        "application/json": {
          schema: emptyBodySchema,
        },
      },
      required: true,
    },
  },
  responses: {
    200: {
      content: {
        "application/json": {
          schema: runtimeEnvelopeSchema,
        },
      },
      description: "Opened demo runtime status.",
    },
    503: {
      content: {
        "application/json": {
          schema: apiErrorSchema,
        },
      },
      description: "Runtime unavailable or shutting down.",
    },
  },
});

export const runtimeCloseRoute = createRoute({
  method: "post",
  path: API_ROUTES.runtimeClose,
  request: {
    body: {
      content: {
        "application/json": {
          schema: emptyBodySchema,
        },
      },
      required: true,
    },
  },
  responses: {
    200: {
      content: {
        "application/json": {
          schema: runtimeEnvelopeSchema,
        },
      },
      description: "Closed demo runtime status.",
    },
    503: {
      content: {
        "application/json": {
          schema: apiErrorSchema,
        },
      },
      description: "Runtime shutting down.",
    },
  },
});

export const createComicRoute = createRoute({
  method: "post",
  path: API_ROUTES.createComic,
  request: {
    body: {
      content: {
        "application/json": {
          schema: createComicRequestSchema,
        },
      },
      required: true,
    },
  },
  responses: {
    200: {
      content: {
        "application/json": {
          schema: createComicResponseSchema,
        },
      },
      description: "Created or replayed comic.",
    },
    400: {
      content: {
        "application/json": {
          schema: apiErrorSchema,
        },
      },
      description: "Validation error.",
    },
    409: {
      content: {
        "application/json": {
          schema: apiErrorSchema,
        },
      },
      description: "Idempotency conflict or runtime not open.",
    },
    500: {
      content: {
        "application/json": {
          schema: apiErrorSchema,
        },
      },
      description: "Internal error.",
    },
    503: {
      content: {
        "application/json": {
          schema: apiErrorSchema,
        },
      },
      description: "Runtime unavailable.",
    },
  },
});
