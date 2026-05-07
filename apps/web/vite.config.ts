import { existsSync } from "node:fs";
import { resolve } from "node:path";

import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

const buildTarget = process.env.VENERA_WEB_BUILD_TARGET ?? "client";
const hasClientEntrypoint = existsSync(resolve(__dirname, "src/main.tsx"));

export default defineConfig({
  plugins: buildTarget === "client" && hasClientEntrypoint
    ? [react()]
    : [],
  server: {
    host: "127.0.0.1",
    port: 5173,
    proxy: {
      "/api": {
        changeOrigin: true,
        target: "http://127.0.0.1:8787",
      },
    },
  },
  build: buildTarget === "client"
    ? {
        outDir: "dist/client",
      }
    : {
        outDir: "dist/server",
        rollupOptions: {
          output: {
            entryFileNames: "main-server.js",
          },
        },
        ssr: "src/main-server.ts",
        target: "node20",
      },
  test: {
    environment: "node",
    include: [
      "tests/**/*.test.ts",
    ],
  },
});
