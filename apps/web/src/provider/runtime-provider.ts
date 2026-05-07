import {
  createCoreRuntime,
  type CoreRuntime,
} from "@venera/runtime-core";
import type { RuntimeSummaryDto } from "@venera/runtime-contracts";

import { createWebError, type WebError } from "../server/web-error.js";

type RuntimeSession = Pick<CoreRuntime, "close" | "useCases">;

export type RuntimeCreateComicResult = Awaited<
  ReturnType<CoreRuntime["useCases"]["createCanonicalComic"]["execute"]>
>;

export type RuntimeFactory = () => Promise<RuntimeSession>;

export interface RuntimeProvider {
  getSummary(): RuntimeSummaryDto;
  open(): Promise<RuntimeSummaryDto>;
  close(): Promise<RuntimeSummaryDto>;
  shutdown(): Promise<void>;
  withRuntime<TResult>(
    operation: (runtime: RuntimeSession) => Promise<TResult>,
  ): Promise<TResult>;
}

interface CreateRuntimeProviderOptions {
  readonly createRuntime?: RuntimeFactory;
}

export function createRuntimeProvider(
  options: CreateRuntimeProviderOptions = {},
): RuntimeProvider {
  const createRuntime = options.createRuntime ?? (() => createCoreRuntime({
    databasePath: ":memory:",
  }));

  let openPromise: Promise<RuntimeSession> | null = null;
  let shutdownPromise: Promise<void> | null = null;
  let runtime: RuntimeSession | null = null;
  let activeOperations = 0;
  let state: RuntimeSummaryDto["state"] = "closed";

  async function finalizeShutdown(): Promise<void> {
    const currentRuntime = runtime;
    runtime = null;
    openPromise = null;

    if (currentRuntime !== null) {
      currentRuntime.close();
    }

    state = "closed";
    shutdownPromise = null;
  }

  function getSummary(): RuntimeSummaryDto {
    return {
      mode: "demo-memory",
      state,
      persistence: {
        kind: "memory",
        persisted: false,
        notice: "not-persisted",
      },
    };
  }

  async function open(): Promise<RuntimeSummaryDto> {
    if (state === "shutting_down") {
      throw createWebError("RUNTIME_SHUTTING_DOWN");
    }

    if (runtime !== null) {
      state = "open";
      return getSummary();
    }

    if (openPromise === null) {
      state = "closed";
      openPromise = createRuntime()
        .then((createdRuntime) => {
          runtime = createdRuntime;
          state = "open";
          return createdRuntime;
        })
        .catch((error: unknown) => {
          runtime = null;
          state = "closed";
          openPromise = null;
          throw createRuntimeUnavailableError(error);
        });
    }

    await openPromise;
    return getSummary();
  }

  async function close(): Promise<RuntimeSummaryDto> {
    if (state === "shutting_down") {
      throw createWebError("RUNTIME_SHUTTING_DOWN");
    }

    if (openPromise !== null && runtime === null) {
      await openPromise;
    }

    if (runtime !== null) {
      runtime.close();
    }

    runtime = null;
    openPromise = null;
    state = "closed";
    return getSummary();
  }

  async function shutdown(): Promise<void> {
    if (shutdownPromise !== null) {
      return shutdownPromise;
    }

    if (openPromise !== null && runtime === null) {
      state = "shutting_down";
      shutdownPromise = openPromise
        .catch(() => undefined)
        .then(async () => {
          if (activeOperations === 0) {
            await finalizeShutdown();
          }
        });
      return shutdownPromise;
    }

    if (runtime === null) {
      state = "closed";
      return;
    }

    state = "shutting_down";
    shutdownPromise = (async () => {
      if (activeOperations === 0) {
        await finalizeShutdown();
      }
    })();
    return shutdownPromise;
  }

  async function withRuntime<TResult>(
    operation: (openedRuntime: RuntimeSession) => Promise<TResult>,
  ): Promise<TResult> {
    if (state === "shutting_down") {
      throw createWebError("RUNTIME_SHUTTING_DOWN");
    }

    if (runtime === null) {
      throw createWebError("RUNTIME_NOT_OPEN");
    }

    activeOperations += 1;
    try {
      return await operation(runtime);
    } finally {
      activeOperations -= 1;
      if ((state as RuntimeSummaryDto["state"]) === "shutting_down" && activeOperations === 0) {
        await finalizeShutdown();
      }
    }
  }

  return {
    getSummary,
    open,
    close,
    shutdown,
    withRuntime,
  };
}

function createRuntimeUnavailableError(_error: unknown): WebError {
  return createWebError("RUNTIME_UNAVAILABLE");
}

export type { RuntimeSession };
