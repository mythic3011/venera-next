import type { OpenAPIHono } from "@hono/zod-openapi";
import { OpenAPIHono as HonoApp } from "@hono/zod-openapi";
import { Scalar } from "@scalar/hono-api-reference";

import {
  createRuntimeAdapter,
  mapUnknownErrorToWebError,
} from "../adapter/runtime-adapter.js";
import {
  createRuntimeProvider,
  type RuntimeProvider,
} from "../provider/runtime-provider.js";
import { registerComicRoutes } from "../routes/comic-routes.js";
import { registerRuntimeRoutes } from "../routes/runtime-routes.js";
import { registerStaticAssets } from "./static-assets.js";
import { isWebError } from "./web-error.js";

export interface CreateWebServerOptions {
  readonly provider?: RuntimeProvider;
  readonly staticRoot?: string;
}

export interface WebServer {
  readonly app: OpenAPIHono;
  shutdown(): Promise<void>;
}

export function createWebServer(options: CreateWebServerOptions = {}): WebServer {
  const provider = options.provider ?? createRuntimeProvider();
  const adapter = createRuntimeAdapter({ provider });
  const app = new HonoApp({
    defaultHook(result, context) {
      if (!result.success) {
        return context.json({
          error: {
            code: "VALIDATION_FAILED",
            message: "Request validation failed.",
          },
        }, 400);
      }
    },
  });

  app.doc31("/api/openapi.json", {
    openapi: "3.1.0",
    info: {
      title: "Venera Demo Runtime API",
      version: "0.1.0",
    },
  });

  app.get("/api/docs", Scalar({
    pageTitle: "Venera Demo Runtime API",
    url: "/api/openapi.json",
  }));

  registerRuntimeRoutes(app, adapter);
  registerComicRoutes(app, adapter);

  app.onError((error, context) => {
    const webError = isWebError(error) ? error : mapUnknownErrorToWebError(error);
    return context.json({
      error: {
        code: webError.code,
        message: webError.message,
      },
    }, webError.status as 400 | 409 | 500 | 503);
  });

  if (options.staticRoot !== undefined) {
    registerStaticAssets(app, options.staticRoot);
  }

  return {
    app,
    async shutdown() {
      await provider.shutdown();
    },
  };
}
