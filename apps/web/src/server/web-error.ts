import {
  RUNTIME_ERROR_TABLE,
  type RuntimeErrorCode,
} from "@venera/runtime-contracts";

type WebErrorStatus = 400 | 409 | 500 | 503;

export class WebError extends Error {
  readonly code: RuntimeErrorCode;
  readonly status: WebErrorStatus;

  constructor(code: RuntimeErrorCode) {
    super(RUNTIME_ERROR_TABLE[code].message);
    this.name = "WebError";
    this.code = code;
    this.status = RUNTIME_ERROR_TABLE[code].status as WebErrorStatus;
  }
}

export function createWebError(code: RuntimeErrorCode): WebError {
  return new WebError(code);
}

export function isWebError(value: unknown): value is WebError {
  return value instanceof WebError;
}
