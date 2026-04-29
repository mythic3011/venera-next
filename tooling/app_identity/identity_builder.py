from __future__ import annotations

import json
from pathlib import Path


IDENTITY_PATH = Path(__file__).with_name("identity.json")


def load_identity() -> dict:
    with IDENTITY_PATH.open("r", encoding="utf-8") as file:
        raw = json.load(file)
    return build_identity(raw)


def build_identity(raw: dict) -> dict:
    app = dict(raw["app"])
    repo = dict(raw["repo"])
    support = dict(raw.get("support", {}))
    alt_store = dict(raw.get("altStore", {}))
    store = dict(raw.get("store", {}))
    debian = dict(raw.get("debian", {}))

    base_id = app["baseId"]
    repo_slug = repo["slug"]
    branch = repo.get("defaultBranch", "master")
    publisher = app["publisher"]
    app_name = app["name"]

    app.setdefault("displayName", app_name)
    app.setdefault("androidLabel", app["displayName"])
    app["androidNamespace"] = base_id
    app["androidApplicationId"] = base_id
    app["appleBundleId"] = base_id
    app["appleTestBundleId"] = f"{base_id}.RunnerTests"
    app["linuxApplicationId"] = base_id
    app["windowsPublisher"] = publisher
    app["windowsCompanyName"] = publisher
    app["windowsCopyrightOwner"] = publisher
    app["altStoreSourceIdentifier"] = f"{base_id}.source"

    repo["url"] = f"https://github.com/{repo_slug}"
    repo["releasesUrl"] = f'{repo["url"]}/releases'
    repo["blobBaseUrl"] = f'{repo["url"]}/blob/{branch}'
    repo["rawBaseUrl"] = f"https://raw.githubusercontent.com/{repo_slug}/{branch}"
    repo["contributingUrl"] = f'{repo["blobBaseUrl"]}/CONTRIBUTING.md'
    repo["comicSourceDocUrl"] = f'{repo["blobBaseUrl"]}/doc/comic_source.md'
    comic_source_issues_slug = repo.get("comicSourceIssuesSlug")
    if comic_source_issues_slug:
        repo["comicSourceIssuesUrl"] = f"https://github.com/{comic_source_issues_slug}/issues"

    alt_store.setdefault("sourceName", app_name)
    alt_store.setdefault("developerName", publisher)
    store.setdefault("title", app["displayName"])

    debian.setdefault("packageName", app["executableName"])
    debian.setdefault("maintainer", publisher)

    return {
        "app": app,
        "repo": repo,
        "support": support,
        "altStore": alt_store,
        "store": store,
        "debian": debian,
    }
