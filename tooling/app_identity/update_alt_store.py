from __future__ import annotations

import json
import os
import re
from datetime import datetime
from pathlib import Path

import requests

from identity_builder import load_identity


ROOT = Path(__file__).resolve().parents[2]
ALT_STORE_PATH = ROOT / "alt_store.json"


def prepare_description(text: str) -> str:
    text = re.sub("<[^<]+?>", "", text)
    text = re.sub(r"#{1,6}\s?", "", text)
    text = re.sub(r"\*{2}", "", text)
    text = re.sub(r"(?<=\r|\n)-", "•", text)
    text = re.sub(r"`", '"', text)
    text = re.sub(r"\r\n\r\n", "\r \n", text)
    return text


def fetch_latest_release(repo_slug: str) -> dict | list[dict]:
    api_url = f"https://api.github.com/repos/{repo_slug}/releases"
    headers = {
        "Accept": "application/vnd.github+json",
    }
    response = requests.get(api_url, headers=headers)
    response.raise_for_status()
    return response.json()


def update_json_file_release(
    json_file: Path,
    latest_release: dict | list[dict],
    identity: dict,
) -> None:
    if isinstance(latest_release, list) and latest_release:
        latest_release = latest_release[0]
    else:
        raise RuntimeError("Error getting latest release")

    with json_file.open("r", encoding="utf-8") as file:
        data = json.load(file)

    app = data["apps"][0]
    repo = identity["repo"]
    app_meta = identity["app"]
    alt_store = identity["altStore"]

    full_version = latest_release["tag_name"]
    tag = latest_release["tag_name"]
    version_match = re.search(r"(\d+\.\d+\.\d+)", full_version)
    if version_match is None:
        raise RuntimeError("Error: Could not parse version from tag_name.")
    version = version_match.group(1)

    version_date = latest_release["published_at"]
    date_obj = datetime.strptime(version_date, "%Y-%m-%dT%H:%M:%SZ")
    version_date = date_obj.strftime("%Y-%m-%d")

    description = prepare_description(latest_release["body"])
    build = version.replace(".", "")
    expected_name = alt_store["releaseArtifactNameTemplate"].format(
        version=version,
        build=build,
    )
    assets = latest_release.get("assets", [])
    download_url = None
    size = None
    for asset in assets:
        if asset["name"] == expected_name:
            download_url = asset["browser_download_url"]
            size = asset["size"]
            break

    if download_url is None or size is None:
        raise RuntimeError("Error: IPA file not found in release assets.")

    version_entry = {
        "version": version,
        "date": version_date,
        "localizedDescription": description,
        "downloadURL": download_url,
        "size": size,
    }

    duplicate_entries = [item for item in app["versions"] if item["version"] == version]
    if duplicate_entries:
        app["versions"].remove(duplicate_entries[0])

    app["versions"].insert(0, version_entry)
    app.update(
        {
            "version": version,
            "versionDate": version_date,
            "versionDescription": description,
            "downloadURL": download_url,
            "size": size,
            "bundleIdentifier": app_meta["appleBundleId"],
            "developerName": alt_store["developerName"],
        }
    )

    if "news" not in data:
        data["news"] = []

    news_identifier = f"release-{full_version}"
    date_string = date_obj.strftime("%d/%m/%y")
    news_entry = {
        "appID": app_meta["appleBundleId"],
        "caption": alt_store["newsCaption"],
        "date": latest_release["published_at"],
        "identifier": news_identifier,
        "notify": True,
        "tintColor": alt_store["tintColor"],
        "title": f"{full_version} - {identity['app']['displayName']}  {date_string}",
        "url": f"{repo['releasesUrl']}/tag/{tag}",
    }

    news_entry_exists = any(item["identifier"] == news_identifier for item in data["news"])
    if not news_entry_exists:
        data["news"].append(news_entry)

    with json_file.open("w", encoding="utf-8") as file:
        json.dump(data, file, indent=2)
        file.write("\n")


def main() -> None:
    identity = load_identity()
    repo_slug = identity["repo"]["slug"]
    if "NIGHTLY_LINK" in os.environ:
        raise RuntimeError("Nightly AltStore updates are not configured for the fork yet.")
    latest_release = fetch_latest_release(repo_slug)
    update_json_file_release(ALT_STORE_PATH, latest_release, identity)


if __name__ == "__main__":
    main()
