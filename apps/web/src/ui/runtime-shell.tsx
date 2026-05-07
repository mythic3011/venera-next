import type {
  CreateComicResponse,
  RuntimeSummaryDto,
} from "@venera/runtime-contracts";
import {
  useEffect,
  useMemo,
  useState,
} from "react";

import {
  ApiClientError,
  defaultApiClient,
} from "../client/api/client.js";

function nextIdempotencyKey(): string {
  return globalThis.crypto.randomUUID();
}

export function RuntimeShell() {
  const [authorName, setAuthorName] = useState("");
  const [createdComic, setCreatedComic] = useState<CreateComicResponse | null>(null);
  const [description, setDescription] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [idempotencyKey, setIdempotencyKey] = useState(() => nextIdempotencyKey());
  const [isBusy, setIsBusy] = useState(false);
  const [runtimeSummary, setRuntimeSummary] = useState<RuntimeSummaryDto | null>(null);
  const [title, setTitle] = useState("Demo Comic");

  const runtimeBadge = useMemo(() => {
    if (runtimeSummary === null) {
      return "unloaded";
    }

    return `${runtimeSummary.mode} / ${runtimeSummary.state}`;
  }, [runtimeSummary]);

  async function refreshRuntime(): Promise<void> {
    const response = await defaultApiClient.getRuntimeHealth();
    setRuntimeSummary(response.runtime);
  }

  useEffect(() => {
    void refreshRuntime().catch((error: unknown) => {
      setErrorMessage(readErrorMessage(error));
    });
  }, []);

  async function runWithBusyState(
    operation: () => Promise<void>,
  ): Promise<void> {
    setIsBusy(true);
    setErrorMessage(null);

    try {
      await operation();
    } catch (error: unknown) {
      setErrorMessage(readErrorMessage(error));
    } finally {
      setIsBusy(false);
    }
  }

  return (
    <main className="shell">
      <section className="hero">
        <div>
          <p className="eyebrow">Venera Runtime Smoke</p>
          <h1>demo-memory</h1>
          <p className="supporting">
            This shell talks to an in-memory runtime only. Data is not persisted.
          </p>
        </div>
        <div className="status-panel">
          <span className="status-label">Runtime</span>
          <strong>{runtimeBadge}</strong>
          <span className="status-note">Persistence: not-persisted</span>
        </div>
      </section>

      <section className="toolbar">
        <button
          disabled={isBusy}
          onClick={() => {
            void runWithBusyState(async () => {
              await refreshRuntime();
            });
          }}
          type="button"
        >
          Refresh
        </button>
        <button
          disabled={isBusy}
          onClick={() => {
            void runWithBusyState(async () => {
              const response = await defaultApiClient.openRuntime();
              setRuntimeSummary(response.runtime);
            });
          }}
          type="button"
        >
          Open Demo Runtime
        </button>
        <button
          disabled={isBusy}
          onClick={() => {
            void runWithBusyState(async () => {
              const response = await defaultApiClient.closeRuntime();
              setRuntimeSummary(response.runtime);
            });
          }}
          type="button"
        >
          Close Runtime
        </button>
      </section>

      <section className="form-layout">
        <form
          className="editor"
          onSubmit={(event) => {
            event.preventDefault();
            void runWithBusyState(async () => {
              const response = await defaultApiClient.createComic({
                title,
                description: description || undefined,
                authorName: authorName || undefined,
                idempotencyKey,
              });
              setCreatedComic(response);
              await refreshRuntime();
            });
          }}
        >
          <header>
            <h2>Create comic</h2>
            <p>Retry the same request with a stable idempotency key.</p>
          </header>

          <label>
            <span>Title</span>
            <input
              onChange={(event) => {
                setTitle(event.target.value);
              }}
              type="text"
              value={title}
            />
          </label>

          <label>
            <span>Description</span>
            <textarea
              onChange={(event) => {
                setDescription(event.target.value);
              }}
              rows={3}
              value={description}
            />
          </label>

          <label>
            <span>Author</span>
            <input
              onChange={(event) => {
                setAuthorName(event.target.value);
              }}
              type="text"
              value={authorName}
            />
          </label>

          <label>
            <span>Idempotency key</span>
            <div className="idempotency-row">
              <input
                onChange={(event) => {
                  setIdempotencyKey(event.target.value);
                }}
                type="text"
                value={idempotencyKey}
              />
              <button
                disabled={isBusy}
                onClick={() => {
                  setIdempotencyKey(nextIdempotencyKey());
                }}
                type="button"
              >
                New Key
              </button>
            </div>
          </label>

          <button
            className="primary"
            disabled={isBusy}
            type="submit"
          >
            {isBusy ? "Working..." : "Create Comic"}
          </button>
        </form>

        <aside className="results">
          <header>
            <h2>Last result</h2>
          </header>
          {createdComic === null ? (
            <p className="placeholder">No comic created yet.</p>
          ) : (
            <dl className="detail-list">
              <div>
                <dt>Comic ID</dt>
                <dd>{createdComic.comic.id}</dd>
              </div>
              <div>
                <dt>Title</dt>
                <dd>{createdComic.metadata.title}</dd>
              </div>
              <div>
                <dt>Normalized</dt>
                <dd>{createdComic.comic.normalizedTitle}</dd>
              </div>
              <div>
                <dt>Idempotency key</dt>
                <dd>{idempotencyKey}</dd>
              </div>
            </dl>
          )}
          {errorMessage === null ? null : (
            <p className="error">{errorMessage}</p>
          )}
        </aside>
      </section>
    </main>
  );
}

function readErrorMessage(error: unknown): string {
  if (error instanceof ApiClientError) {
    return error.message;
  }

  if (error instanceof Error) {
    return error.message;
  }

  return "Unexpected UI error.";
}
