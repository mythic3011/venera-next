import type {
  RuntimeCloseRequestCompat,
  RuntimeHealthResponseCompat,
  RuntimeOpenRequestCompat,
} from "@venera/runtime-contracts";
import { type OpenAPIHono } from "@hono/zod-openapi";

import {
  runtimeCloseRoute,
  runtimeHealthRoute,
  runtimeOpenRoute,
} from "./openapi-contracts.js";
import type { RuntimeAdapter } from "../server/types.js";

export function registerRuntimeRoutes(
  app: OpenAPIHono,
  adapter: RuntimeAdapter,
): void {
  app.openapi(runtimeHealthRoute, (context) => {
    const body: RuntimeHealthResponseCompat = adapter.getHealth();
    return context.json(body, 200);
  });

  app.openapi(runtimeOpenRoute, async (context) => {
    const _body: RuntimeOpenRequestCompat = context.req.valid("json");
    const body = await adapter.openRuntime();
    return context.json(body, 200);
  });

  app.openapi(runtimeCloseRoute, async (context) => {
    const _body: RuntimeCloseRequestCompat = context.req.valid("json");
    const body = await adapter.closeRuntime();
    return context.json(body, 200);
  });
}
