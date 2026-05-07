import { z } from "zod";

export const API_ERROR_CODES = [
  "VALIDATION_FAILED",
  "IDEMPOTENCY_KEY_PAYLOAD_MISMATCH",
  "RUNTIME_NOT_OPEN",
  "RUNTIME_UNAVAILABLE",
  "RUNTIME_SHUTTING_DOWN",
  "INTERNAL",
] as const;

export const ApiErrorCodeSchema = z.enum(API_ERROR_CODES);

export const ApiErrorSchema = z.object({
  code: ApiErrorCodeSchema,
  message: z.string().trim().min(1),
}).strict();

export const ApiErrorResponseSchema = z.object({
  error: ApiErrorSchema,
}).strict();

export type ApiErrorCode = z.infer<typeof ApiErrorCodeSchema>;
export type ApiError = z.infer<typeof ApiErrorSchema>;
export type ApiErrorResponse = z.infer<typeof ApiErrorResponseSchema>;
