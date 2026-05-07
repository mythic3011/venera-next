import type {
  ApiErrorResponse,
  CreateComicRequest,
} from "@venera/runtime-contracts";
import {
  API_ROUTES,
  apiErrorSchema,
  createComicResponseSchema,
  runtimeCloseResponseSchema,
  runtimeHealthResponseSchema,
  runtimeOpenResponseSchema,
} from "@venera/runtime-contracts";
import type { ZodType, z } from "zod";

export class ApiClientError extends Error {
  readonly code: ApiErrorResponse["error"]["code"] | undefined;
  readonly status: number | undefined;

  constructor(message: string, options: {
    readonly code?: ApiErrorResponse["error"]["code"];
    readonly status?: number;
  } = {}) {
    super(message);
    this.name = "ApiClientError";
    this.code = options.code;
    this.status = options.status;
  }
}

interface CreateApiClientOptions {
  readonly baseUrl?: string;
  readonly fetch?: typeof fetch;
}

interface ApiClient {
  getRuntimeHealth(): Promise<z.infer<typeof runtimeHealthResponseSchema>>;
  openRuntime(): Promise<z.infer<typeof runtimeOpenResponseSchema>>;
  closeRuntime(): Promise<z.infer<typeof runtimeCloseResponseSchema>>;
  createComic(input: CreateComicRequest): Promise<z.infer<typeof createComicResponseSchema>>;
}

const emptyBody = {};

export function createApiClient(
  options: CreateApiClientOptions = {},
): ApiClient {
  const baseUrl = options.baseUrl ?? "";
  const fetchImplementation = options.fetch ?? fetch;

  async function request<TResponse>(
    path: string,
    init: RequestInit,
    schema: ZodType<TResponse>,
  ): Promise<TResponse> {
    const response = await fetchImplementation(`${baseUrl}${path}`, init);
    const payload = await response.json() as unknown;

    if (!response.ok) {
      const parsedError = apiErrorSchema.safeParse(payload);
      if (parsedError.success) {
        throw new ApiClientError(parsedError.data.error.message, {
          code: parsedError.data.error.code,
          status: response.status,
        });
      }

      throw new ApiClientError("API returned an invalid error payload.", {
        status: response.status,
      });
    }

    const parsed = schema.safeParse(payload);
    if (!parsed.success) {
      throw new ApiClientError("API returned an invalid success payload.", {
        status: response.status,
      });
    }

    return parsed.data;
  }

  return {
    getRuntimeHealth() {
      return request(API_ROUTES.runtimeHealth, {
        method: "GET",
      }, runtimeHealthResponseSchema);
    },
    openRuntime() {
      return request(API_ROUTES.runtimeOpen, {
        method: "POST",
        headers: {
          "content-type": "application/json",
        },
        body: JSON.stringify(emptyBody),
      }, runtimeOpenResponseSchema);
    },
    closeRuntime() {
      return request(API_ROUTES.runtimeClose, {
        method: "POST",
        headers: {
          "content-type": "application/json",
        },
        body: JSON.stringify(emptyBody),
      }, runtimeCloseResponseSchema);
    },
    createComic(input) {
      return request(API_ROUTES.createComic, {
        method: "POST",
        headers: {
          "content-type": "application/json",
        },
        body: JSON.stringify(input),
      }, createComicResponseSchema);
    },
  };
}

export const defaultApiClient = createApiClient();
