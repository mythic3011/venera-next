import { createCoreError, type CoreErrorCode } from "../shared/errors.js";
import { err, type Result } from "../shared/result.js";

export function fail<TValue = never>(
  code: CoreErrorCode,
  message: string,
  details?: Record<string, string | number | boolean | null | undefined>,
): Result<TValue> {
  const normalizedDetails = details === undefined
    ? undefined
    : Object.fromEntries(
      Object.entries(details).filter(([, value]) => value !== undefined),
    );

  return err(
    createCoreError({
      code,
      message,
      ...(normalizedDetails === undefined ? {} : { details: normalizedDetails }),
    }),
  );
}

export function unexpectedFailure<TValue = never>(
  message: string,
  cause: unknown,
): Result<TValue> {
  return err(
    createCoreError({
      code: "INTERNAL_ERROR",
      message,
      cause,
    }),
  );
}

export function withOptional<
  TValue extends object,
  TKey extends string,
  TOptionalValue,
>(
  value: TValue,
  key: TKey,
  optionalValue: TOptionalValue | undefined,
): TValue & Partial<Record<TKey, TOptionalValue>> {
  if (optionalValue === undefined) {
    return value;
  }

  return {
    ...value,
    [key]: optionalValue,
  };
}
