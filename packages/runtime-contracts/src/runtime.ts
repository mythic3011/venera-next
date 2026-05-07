import { z, type ZodType } from "zod";

import { ApiErrorResponseSchema } from "./errors.js";

export type HttpMethod = "GET" | "POST";

export interface RouteContract<TMethod extends HttpMethod, TPath extends string, TRequest, TResponse> {
  readonly method: TMethod;
  readonly path: TPath;
  readonly request: ZodType<TRequest>;
  readonly response: ZodType<TResponse>;
  readonly error: typeof ApiErrorResponseSchema;
}

const EmptyRequestSchema = z.object({}).strict();

export const RuntimeSummarySchema = z.object({
  mode: z.literal("demo-memory"),
  persisted: z.literal(false),
  persistence: z.literal("not persisted"),
}).strict();

export const RuntimeHealthRequestSchema = EmptyRequestSchema;
export const RuntimeHealthResponseSchema = z.object({
  status: z.literal("ok"),
  runtime: RuntimeSummarySchema,
}).strict();

export const RuntimeOpenRequestSchema = EmptyRequestSchema;
export const RuntimeOpenResponseSchema = z.object({
  status: z.literal("open"),
  runtime: RuntimeSummarySchema,
}).strict();

export const RuntimeCloseRequestSchema = EmptyRequestSchema;
export const RuntimeCloseResponseSchema = z.object({
  status: z.literal("closed"),
  runtime: RuntimeSummarySchema,
}).strict();

export const RUNTIME_HEALTH_PATH = "/api/runtime/health";
export const RUNTIME_OPEN_PATH = "/api/runtime/open";
export const RUNTIME_CLOSE_PATH = "/api/runtime/close";

export const RuntimeHealthRoute: RouteContract<
  "GET",
  typeof RUNTIME_HEALTH_PATH,
  z.infer<typeof RuntimeHealthRequestSchema>,
  z.infer<typeof RuntimeHealthResponseSchema>
> = {
  method: "GET",
  path: RUNTIME_HEALTH_PATH,
  request: RuntimeHealthRequestSchema,
  response: RuntimeHealthResponseSchema,
  error: ApiErrorResponseSchema,
};

export const RuntimeOpenRoute: RouteContract<
  "POST",
  typeof RUNTIME_OPEN_PATH,
  z.infer<typeof RuntimeOpenRequestSchema>,
  z.infer<typeof RuntimeOpenResponseSchema>
> = {
  method: "POST",
  path: RUNTIME_OPEN_PATH,
  request: RuntimeOpenRequestSchema,
  response: RuntimeOpenResponseSchema,
  error: ApiErrorResponseSchema,
};

export const RuntimeCloseRoute: RouteContract<
  "POST",
  typeof RUNTIME_CLOSE_PATH,
  z.infer<typeof RuntimeCloseRequestSchema>,
  z.infer<typeof RuntimeCloseResponseSchema>
> = {
  method: "POST",
  path: RUNTIME_CLOSE_PATH,
  request: RuntimeCloseRequestSchema,
  response: RuntimeCloseResponseSchema,
  error: ApiErrorResponseSchema,
};

export type RuntimeSummary = z.infer<typeof RuntimeSummarySchema>;
export type RuntimeHealthRequest = z.infer<typeof RuntimeHealthRequestSchema>;
export type RuntimeHealthResponse = z.infer<typeof RuntimeHealthResponseSchema>;
export type RuntimeOpenRequest = z.infer<typeof RuntimeOpenRequestSchema>;
export type RuntimeOpenResponse = z.infer<typeof RuntimeOpenResponseSchema>;
export type RuntimeCloseRequest = z.infer<typeof RuntimeCloseRequestSchema>;
export type RuntimeCloseResponse = z.infer<typeof RuntimeCloseResponseSchema>;
