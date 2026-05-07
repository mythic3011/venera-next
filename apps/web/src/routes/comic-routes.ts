import type {
  CreateComicRequest,
  CreateComicResponse,
} from "@venera/runtime-contracts";
import { type OpenAPIHono } from "@hono/zod-openapi";

import { createComicRoute } from "./openapi-contracts.js";
import type { RuntimeAdapter } from "../server/types.js";

export function registerComicRoutes(
  app: OpenAPIHono,
  adapter: RuntimeAdapter,
): void {
  type CreateComicRouteContext = {
    readonly req: {
      valid(target: "json"): CreateComicRequest;
    };
    json(body: CreateComicResponse, status: 200): Response;
  };

  const createComicHandler = async (context: CreateComicRouteContext): Promise<Response> => {
    const body: CreateComicRequest = context.req.valid("json");
    const response = await adapter.createComic(body);
    return context.json(response, 200);
  };

  app.openapi(createComicRoute as never, createComicHandler as never);
}
