import type { BoundaryConfig } from "./src/scripts/boundary-scan.js";

const config: BoundaryConfig = {
  files: [
    "src/adapter/**/*.ts",
    "src/client/**/*.ts",
    "src/client/**/*.tsx",
    "src/provider/**/*.ts",
    "src/routes/**/*.ts",
    "src/server/**/*.ts",
    "src/ui/**/*.tsx",
    "src/App.tsx",
    "src/main-server.ts",
    "src/main.tsx",
  ],
  rules: [
    {
      name: "client-must-not-import-server",
      from: [
        /^src\/client\//,
        /^src\/ui\//,
        /^src\/App\.tsx$/,
        /^src\/main\.tsx$/,
      ],
      forbidden: [
        /^src\/adapter\//,
        /^src\/provider\//,
        /^src\/routes\//,
        /^src\/server\//,
        /^src\/main-server\.ts$/,
        /^@venera\/runtime-core$/,
      ],
    },
    {
      name: "ui-calls-client-api-only",
      from: [
        /^src\/ui\//,
        /^src\/App\.tsx$/,
      ],
      forbidden: [
        /^src\/client\/(?!api\/client\.ts$)/,
      ],
    },
    {
      name: "server-must-not-import-client",
      from: [
        /^src\/adapter\//,
        /^src\/provider\//,
        /^src\/routes\//,
        /^src\/server\//,
        /^src\/main-server\.ts$/,
      ],
      forbidden: [
        /^src\/client\//,
        /^src\/ui\//,
        /^src\/App\.tsx$/,
        /^src\/main\.tsx$/,
      ],
    },
    {
      name: "runtime-core-imports-belong-to-provider",
      from: [
        /^src\/(?!provider\/).+\.(ts|tsx)$/,
      ],
      forbidden: [
        /^@venera\/runtime-core$/,
      ],
    },
  ],
};

export default config;
