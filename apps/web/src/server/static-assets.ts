import { serveStatic } from "@hono/node-server/serve-static";
import type { OpenAPIHono } from "@hono/zod-openapi";

export function registerStaticAssets(
  app: OpenAPIHono,
  staticRoot: string,
): void {
  app.use("/assets/*", serveStatic({ root: staticRoot }));
  app.use("/*", async (context, next) => {
    if (context.req.path.startsWith("/api/")) {
      await next();
      return;
    }

    return serveStatic({
      path: "./index.html",
      root: staticRoot,
    })(context, next);
  });
}
