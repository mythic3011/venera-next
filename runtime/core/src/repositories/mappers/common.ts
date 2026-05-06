import { createCoreError } from "../../shared/errors.js";
import type { JsonObject } from "../../shared/json.js";
import { isErr, ok, type Result } from "../../shared/result.js";

function invalidPersistedData(message: string, details?: JsonObject) {
  return createCoreError({
    code: "INTERNAL_ERROR",
    message,
    ...(details === undefined ? {} : { details }),
  });
}

export function isoToDate(
  rawValue: string,
  fieldName: string,
): Result<Date> {
  const value = new Date(rawValue);
  if (Number.isNaN(value.getTime())) {
    return {
      ok: false,
      error: invalidPersistedData(`Invalid persisted timestamp for ${fieldName}.`, {
        fieldName,
        rawValue,
      }),
    };
  }

  return ok(value);
}

export function parseJsonObject(
  rawValue: string | null,
  fieldName: string,
): Result<JsonObject | undefined> {
  if (rawValue === null) {
    return ok(undefined);
  }

  try {
    const parsed = JSON.parse(rawValue) as unknown;
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
      return {
        ok: false,
        error: invalidPersistedData(`Invalid persisted JSON object for ${fieldName}.`, {
          fieldName,
        }),
      };
    }

    return ok(parsed as JsonObject);
  } catch (cause) {
    return {
      ok: false,
      error: invalidPersistedData(`Invalid persisted JSON for ${fieldName}.`, {
        fieldName,
        cause: String(cause),
      }),
    };
  }
}

export function ensureEnumValue<TValue extends string>(
  rawValue: string,
  allowedValues: readonly TValue[],
  fieldName: string,
): Result<TValue> {
  if (allowedValues.includes(rawValue as TValue)) {
    return ok(rawValue as TValue);
  }

  return {
    ok: false,
    error: invalidPersistedData(`Invalid persisted enum for ${fieldName}.`, {
      fieldName,
      rawValue,
    }),
  };
}

export function unwrapMappedResult<TValue>(
  result: Result<TValue>,
): TValue {
  if (isErr(result)) {
    throw result.error;
  }

  return result.value;
}
