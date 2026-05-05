import { CoreError } from "./errors.js";

export interface OkResult<TValue> {
  readonly ok: true;
  readonly value: TValue;
}

export interface ErrResult {
  readonly ok: false;
  readonly error: CoreError;
}

export type Result<TValue> = OkResult<TValue> | ErrResult;

export function ok<TValue>(value: TValue): Result<TValue> {
  return {
    ok: true,
    value,
  };
}

export function err<TValue = never>(error: CoreError): Result<TValue> {
  return {
    ok: false,
    error,
  };
}

export function isOk<TValue>(result: Result<TValue>): result is OkResult<TValue> {
  return result.ok;
}

export function isErr<TValue>(result: Result<TValue>): result is ErrResult {
  return !result.ok;
}
