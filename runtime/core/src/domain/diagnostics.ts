import type { JsonObject } from "../shared/json.js";
import type {
  ComicId,
  DiagnosticsEventId,
  SourcePlatformId,
} from "./identifiers.js";

export const DIAGNOSTIC_LEVELS = [
  "trace",
  "info",
  "warn",
  "error",
] as const;

export type DiagnosticLevel = (typeof DIAGNOSTIC_LEVELS)[number];

export const DIAGNOSTIC_AUTHORITIES = [
  "canonical_db",
  "storage",
  "source_runtime",
  "unknown",
] as const;

export type DiagnosticAuthority = (typeof DIAGNOSTIC_AUTHORITIES)[number];

export interface DiagnosticsEvent {
  readonly id: DiagnosticsEventId;
  readonly timestamp: Date;
  readonly level: DiagnosticLevel;
  readonly channel: string;
  readonly eventName: string;
  readonly correlationId?: string;
  readonly boundary?: string;
  readonly action?: string;
  readonly authority?: DiagnosticAuthority;
  readonly comicId?: ComicId;
  readonly sourcePlatformId?: SourcePlatformId;
  readonly payload: JsonObject;
}

export interface RecordDiagnosticsEventInput {
  readonly id: DiagnosticsEventId;
  readonly timestamp: Date;
  readonly level: DiagnosticLevel;
  readonly channel: string;
  readonly eventName: string;
  readonly correlationId?: string;
  readonly boundary?: string;
  readonly action?: string;
  readonly authority?: DiagnosticAuthority;
  readonly comicId?: ComicId;
  readonly sourcePlatformId?: SourcePlatformId;
  readonly payload: JsonObject;
}

export interface DiagnosticsQuery {
  readonly level?: DiagnosticLevel;
  readonly channel?: string;
  readonly correlationId?: string;
  readonly limit?: number;
}
