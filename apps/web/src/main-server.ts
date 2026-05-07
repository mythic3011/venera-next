import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { serve, type ServerType } from "@hono/node-server";

import { createWebServer } from "./server/create-web-server.js";

export interface StartedWebServer {
  readonly port: number;
  readonly server: ServerType;
  shutdown(): Promise<void>;
}

function resolveStaticRoot(): string | undefined {
  if (process.env.VENERA_WEB_STATIC_ROOT !== undefined) {
    return process.env.VENERA_WEB_STATIC_ROOT;
  }

  const moduleDirectory = dirname(fileURLToPath(import.meta.url));
  const candidates = [
    resolve(moduleDirectory, "../client"),
    resolve(moduleDirectory, "../dist/client"),
  ];

  return candidates.find((candidate) => existsSync(candidate));
}

export function startWebServer(port = Number(process.env.PORT ?? "8787")): StartedWebServer {
  const staticRoot = resolveStaticRoot();
  const webServer = createWebServer(
    staticRoot === undefined
      ? {}
      : { staticRoot },
  );
  const server = serve(
    {
      fetch: webServer.app.fetch,
      hostname: process.env.HOST ?? "127.0.0.1",
      port,
    },
  );

  return {
    port,
    server,
    async shutdown() {
      await webServer.shutdown();
      await new Promise<void>((resolve, reject) => {
        server.close((error) => {
          if (error === undefined) {
            resolve();
            return;
          }

          reject(error);
        });
      });
    },
  };
}

const entryPath = process.argv[1];
if (
  entryPath !== undefined &&
  import.meta.url === new URL(`file://${entryPath}`).href
) {
  const startedServer = startWebServer();
  const stop = () => {
    void startedServer.shutdown();
  };

  process.once("SIGINT", stop);
  process.once("SIGTERM", stop);
}
