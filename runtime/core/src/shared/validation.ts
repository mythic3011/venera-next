import { z } from "zod";

import { applyBrand, type Brand } from "./brand.js";
import { createCoreError } from "./errors.js";
import { err, ok, type Result } from "./result.js";

const UUID_SCHEMA = z.string().uuid();
const RESERVED_ID_VALUES = new Set(["", "_", "__imported__"]);
const ENCODED_ROUTE_PATTERN = /^[^:]+:[^:]+:[^:]+:.+$/;

function buildInvalidIdError(fieldName: string, rawValue: string, reason: string) {
  return createCoreError({
    code: "VALIDATION_ERROR",
    message: `Invalid ${fieldName}.`,
    details: {
      fieldName,
      rawValue,
      reason,
    },
  });
}

export function parseBrandedUuid<TBrand extends string>(
  rawValue: string,
  fieldName: string,
): Result<Brand<string, TBrand>> {
  const value = rawValue.trim();

  if (RESERVED_ID_VALUES.has(value)) {
    return err(buildInvalidIdError(fieldName, rawValue, "reserved_placeholder"));
  }

  if (ENCODED_ROUTE_PATTERN.test(value)) {
    return err(buildInvalidIdError(fieldName, rawValue, "encoded_route_string"));
  }

  const parsed = UUID_SCHEMA.safeParse(value);
  if (!parsed.success) {
    return err(buildInvalidIdError(fieldName, rawValue, "not_uuid"));
  }

  return ok(applyBrand<TBrand>(parsed.data));
}

export function parseRequiredText<TBrand extends string>(
  rawValue: string,
  fieldName: string,
): Result<Brand<string, TBrand>> {
  const value = rawValue.trim();

  if (value.length === 0) {
    return err(
      createCoreError({
        code: "VALIDATION_ERROR",
        message: `Invalid ${fieldName}.`,
        details: {
          fieldName,
          rawValue,
          reason: "empty_string",
        },
      }),
    );
  }

  return ok(applyBrand<TBrand>(value));
}

export function normalizeWhitespace(value: string): string {
  return value.trim().replace(/\s+/g, " ");
}
