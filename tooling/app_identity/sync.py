from __future__ import annotations

import json
import re
from pathlib import Path

from identity_builder import load_identity

ROOT = Path(__file__).resolve().parents[2]


def write_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def replace_regex(text: str, pattern: str, replacement: str, *, expected_count: int | None = None) -> str:
    new_text, count = re.subn(pattern, replacement, text, flags=re.MULTILINE)
    if expected_count is not None and count != expected_count:
        raise RuntimeError(f"{pattern!r} expected {expected_count} matches, got {count}")
    if count == 0:
        raise RuntimeError(f"{pattern!r} had no matches")
    return new_text


def sync_android(identity: dict) -> None:
    app = identity["app"]
    gradle_path = ROOT / "android/app/build.gradle"
    text = gradle_path.read_text(encoding="utf-8")
    text = replace_regex(
        text,
        r'namespace = "[^"]+"',
        f'namespace = "{app["androidNamespace"]}"',
        expected_count=1,
    )
    text = replace_regex(
        text,
        r'applicationId = "[^"]+"',
        f'applicationId = "{app["androidApplicationId"]}"',
        expected_count=1,
    )
    write_text(gradle_path, text)

    manifest_path = ROOT / "android/app/src/main/AndroidManifest.xml"
    text = manifest_path.read_text(encoding="utf-8")
    text = replace_regex(
        text,
        r'(<application\s+[^>]*android:label=")[^"]+(")',
        rf'\1{app["androidLabel"]}\2',
        expected_count=1,
    )
    write_text(manifest_path, text)

    kotlin_root = ROOT / "android/app/src/main/kotlin"
    main_activities = list(kotlin_root.rglob("MainActivity.kt"))
    if len(main_activities) != 1:
        raise RuntimeError(f"Expected exactly one MainActivity.kt, found {len(main_activities)}")
    current_path = main_activities[0]
    target_path = kotlin_root.joinpath(*app["androidNamespace"].split("."), "MainActivity.kt")
    target_path.parent.mkdir(parents=True, exist_ok=True)
    activity_text = current_path.read_text(encoding="utf-8")
    activity_text = replace_regex(
        activity_text,
        r"^package .+$",
        f'package {app["androidNamespace"]}',
        expected_count=1,
    )
    write_text(target_path, activity_text)
    if current_path != target_path:
        current_path.unlink()
        prune_empty_dirs(current_path.parent, stop_at=kotlin_root)


def prune_empty_dirs(path: Path, *, stop_at: Path) -> None:
    current = path
    while current != stop_at and current.exists():
        try:
            current.rmdir()
        except OSError:
            return
        current = current.parent


def sync_apple(identity: dict) -> None:
    app = identity["app"]
    bundle = app["appleBundleId"]
    test_bundle = app["appleTestBundleId"]

    for relative_path in [
        "ios/Runner.xcodeproj/project.pbxproj",
        "macos/Runner.xcodeproj/project.pbxproj",
    ]:
        path = ROOT / relative_path
        lines = path.read_text(encoding="utf-8").splitlines()
        updated_lines = []
        replaced = 0
        for line in lines:
            if "PRODUCT_BUNDLE_IDENTIFIER =" not in line:
                updated_lines.append(line)
                continue
            indent = line[: len(line) - len(line.lstrip())]
            if "RunnerTests;" in line:
                updated_lines.append(
                    f"{indent}PRODUCT_BUNDLE_IDENTIFIER = {test_bundle};"
                )
            else:
                updated_lines.append(f"{indent}PRODUCT_BUNDLE_IDENTIFIER = {bundle};")
            replaced += 1
        if replaced == 0:
            raise RuntimeError(f"No PRODUCT_BUNDLE_IDENTIFIER lines found in {relative_path}")
        write_text(path, "\n".join(updated_lines) + "\n")

    app_info_path = ROOT / "macos/Runner/Configs/AppInfo.xcconfig"
    text = app_info_path.read_text(encoding="utf-8")
    text = replace_regex(
        text,
        r"PRODUCT_BUNDLE_IDENTIFIER = .+",
        f"PRODUCT_BUNDLE_IDENTIFIER = {bundle}",
        expected_count=1,
    )
    text = replace_regex(
        text,
        r"PRODUCT_COPYRIGHT = .+",
        f'PRODUCT_COPYRIGHT = Copyright © {identity["app"]["copyrightYear"]} {identity["app"]["windowsCopyrightOwner"]}. All rights reserved.',
        expected_count=1,
    )
    write_text(app_info_path, text)

    ios_info_path = ROOT / "ios/Runner/Info.plist"
    text = ios_info_path.read_text(encoding="utf-8")
    text = replace_regex(
        text,
        r"<key>CFBundleDisplayName</key>\s*<string>[^<]+</string>",
        f"<key>CFBundleDisplayName</key>\n\t<string>{app['displayName']}</string>",
        expected_count=1,
    )
    text = replace_regex(
        text,
        r"<key>CFBundleName</key>\s*<string>[^<]+</string>",
        f"<key>CFBundleName</key>\n\t<string>{app['executableName']}</string>",
        expected_count=1,
    )
    write_text(ios_info_path, text)


def sync_linux(identity: dict) -> None:
    app = identity["app"]
    path = ROOT / "linux/CMakeLists.txt"
    text = path.read_text(encoding="utf-8")
    text = replace_regex(
        text,
        r'set\(APPLICATION_ID "[^"]+"\)',
        f'set(APPLICATION_ID "{identity["app"]["linuxApplicationId"]}")',
        expected_count=1,
    )
    write_text(path, text)

    app_path = ROOT / "linux/my_application.cc"
    text = app_path.read_text(encoding="utf-8")
    text = replace_regex(
        text,
        r'gtk_header_bar_set_title\(header_bar, "[^"]+"\);',
        f'gtk_header_bar_set_title(header_bar, "{app["displayName"]}");',
        expected_count=1,
    )
    text = replace_regex(
        text,
        r'gtk_window_set_title\(window, "[^"]+"\);',
        f'gtk_window_set_title(window, "{app["displayName"]}");',
        expected_count=1,
    )
    write_text(app_path, text)


def sync_windows(identity: dict) -> None:
    app = identity["app"]
    path = ROOT / "windows/runner/Runner.rc"
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    replacements = {
        'VALUE "CompanyName"': f'            VALUE "CompanyName", "{app["windowsCompanyName"]}" "\\0"',
        'VALUE "FileDescription"': f'            VALUE "FileDescription", "{app["displayName"]}" "\\0"',
        'VALUE "LegalCopyright"': (
            f'            VALUE "LegalCopyright", "Copyright (C) {app["copyrightYear"]} '
            f'{app["windowsCopyrightOwner"]}. All rights reserved." "\\0"'
        ),
        'VALUE "ProductName"': f'            VALUE "ProductName", "{app["displayName"]}" "\\0"',
    }
    seen = set()
    updated_lines = []
    for line in lines:
        replaced = False
        for prefix, replacement in replacements.items():
            if prefix in line:
                updated_lines.append(replacement)
                seen.add(prefix)
                replaced = True
                break
        if not replaced:
            updated_lines.append(line)
    missing = [key for key in replacements if key not in seen]
    if missing:
        raise RuntimeError(f"Missing Windows resource fields: {missing}")
    write_text(path, "\n".join(updated_lines) + "\n")

    for relative_path in ["windows/build.iss", "windows/build_arm64.iss"]:
        iss_path = ROOT / relative_path
        text = iss_path.read_text(encoding="utf-8")
        text = replace_regex(
            text,
            r"AppId=\{\{[0-9A-Fa-f-]+\}",
            f'AppId={{{{{app["windowsAppIdGuid"]}}}',
            expected_count=1,
        )
        write_text(iss_path, text)


def sync_debian(identity: dict) -> None:
    debian = identity["debian"]
    path = ROOT / "debian/debian.yaml"
    text = path.read_text(encoding="utf-8")
    text = replace_regex(
        text,
        r"  Package: .+",
        f'  Package: {debian["packageName"]}',
        expected_count=1,
    )
    text = replace_regex(
        text,
        r"  Maintainer: .+",
        f'  Maintainer: {debian["maintainer"]}',
        expected_count=1,
    )
    text = replace_regex(
        text,
        r"  Description: .+",
        f'  Description: {debian["description"]}',
        expected_count=1,
    )
    write_text(path, text)

    desktop_path = ROOT / "debian/gui/venera.desktop"
    text = desktop_path.read_text(encoding="utf-8")
    text = replace_regex(
        text,
        r"^Name=.+$",
        f'Name={identity["app"]["displayName"]}',
        expected_count=1,
    )
    text = replace_regex(
        text,
        r"^GenericName=.+$",
        f'GenericName={identity["app"]["displayName"]}',
        expected_count=1,
    )
    text = replace_regex(
        text,
        r"^Comment=.+$",
        f'Comment={debian["description"]}',
        expected_count=1,
    )
    write_text(desktop_path, text)


def sync_alt_store(identity: dict) -> None:
    app = identity["app"]
    repo = identity["repo"]
    alt_store = identity["altStore"]
    path = ROOT / "alt_store.json"
    with path.open("r", encoding="utf-8") as file:
        data = json.load(file)

    app_entry = data["apps"][0]
    data["name"] = alt_store["sourceName"]
    data["identifier"] = app["altStoreSourceIdentifier"]
    data["website"] = repo["url"]
    data["subtitle"] = alt_store["sourceSubtitle"]
    data["description"] = alt_store["sourceDescription"]
    data["tintColor"] = alt_store["tintColor"]
    data["iconURL"] = f'{repo["rawBaseUrl"]}/{alt_store["iconPath"]}'

    app_entry["name"] = identity["app"]["name"]
    app_entry["bundleIdentifier"] = app["appleBundleId"]
    app_entry["developerName"] = alt_store["developerName"]
    app_entry["iconURL"] = f'{repo["rawBaseUrl"]}/{alt_store["iconPath"]}'
    app_entry["tintColor"] = alt_store["tintColor"]

    for news_item in data.get("news", []):
        news_item["appID"] = app["appleBundleId"]

    with path.open("w", encoding="utf-8") as file:
        json.dump(data, file, indent=2)
        file.write("\n")


def sync_repo_urls(identity: dict) -> None:
    repo = identity["repo"]
    replacements = {
        "README.md": [
            (r"\(https://github\.com/[^)]+/blob/master/LICENSE\)", f'({repo["blobBaseUrl"]}/LICENSE)'),
            (r"\(https://github\.com/[^)]+/stargazers\)", f'({repo["url"]}/stargazers)'),
            (r"\(https://github\.com/[^)]+/releases\)", f'({repo["releasesUrl"]})'),
            (r"https://img\.shields\.io/github/license/[^)]+", f'https://img.shields.io/github/license/{repo["slug"]}'),
            (r"https://img\.shields\.io/github/stars/[^)?]+", f'https://img.shields.io/github/stars/{repo["slug"]}'),
            (r"https://img\.shields\.io/github/v/release/[^)]+", f'https://img.shields.io/github/v/release/{repo["slug"]}'),
        ],
        ".github/ISSUE_TEMPLATE/config.yml": [
            (r"https://github\.com/[^/]+/venera/blob/master/CONTRIBUTING\.md", repo["contributingUrl"]),
            (r"https://github\.com/[^/]+/venera/blob/master/doc/comic_source\.md", repo["comicSourceDocUrl"]),
            (r"https://github\.com/[^/]+/venera-configs/issues", repo["comicSourceIssuesUrl"]),
        ],
        "pubspec.yaml": [
            (r"url: https://github\.com/[^/]+/venera", f'url: {repo["url"]}'),
        ],
        "lib/foundation/consts.dart": [
            (r'const repoBaseUrl = "https://github\.com/[^"]+";', f'const repoBaseUrl = "{repo["url"]}";'),
        ],
        "lib/foundation/appdata.dart": [
            (r'const _defaultSourceListUrl =\s*"[^"]+";', f'const _defaultSourceListUrl =\n    "{identity["support"]["comicSourceListUrl"]}";'),
        ],
        "lib/init.dart": [
            (r'"https://[^"]+/index\.json";', f'"{identity["support"]["comicSourceListUrl"]}";'),
        ],
        "lib/pages/settings/about.dart": [
            (r'launchUrlString\("https://github\.com/[^"]+"\);', f'launchUrlString("{repo["url"]}");'),
            (r'launchUrlString\("https://t\.me/[^"]+"\);', f'launchUrlString("{identity["support"]["telegramUrl"]}");'),
            (r'AppDio\(\)\.get\(\s*"https://[^"]+/pubspec\.yaml",?\s*\)', f'AppDio().get(\n    "{repo["rawBaseUrl"]}/pubspec.yaml",\n  )'),
            (r'launchUrlString\(\s*"https://github\.com/[^"]+/releases",?\s*\);', f'launchUrlString(\n                    "{repo["releasesUrl"]}",\n                  );'),
        ],
        "windows/build.iss": [
            (r'#define MyAppURL "https://github\.com/[^"]+"', f'#define MyAppURL "{repo["url"]}"'),
            (r'#define MyAppPublisher "[^"]+"', f'#define MyAppPublisher "{identity["app"]["windowsPublisher"]}"'),
        ],
        "windows/build_arm64.iss": [
            (r'#define MyAppURL "https://github\.com/[^"]+"', f'#define MyAppURL "{repo["url"]}"'),
            (r'#define MyAppPublisher "[^"]+"', f'#define MyAppPublisher "{identity["app"]["windowsPublisher"]}"'),
        ],
    }
    for relative_path, patterns in replacements.items():
        path = ROOT / relative_path
        text = path.read_text(encoding="utf-8")
        for pattern, replacement in patterns:
            text = replace_regex(text, pattern, replacement)
        write_text(path, text)


def sync_fastlane_metadata(identity: dict) -> None:
    store = identity["store"]
    base = ROOT / "fastlane/metadata/android/en-US"
    write_text(base / "title.txt", f'{store["title"]}\n')
    write_text(base / "short_description.txt", f'{store["shortDescription"]}\n')
    write_text(base / "full_description.txt", f'{store["fullDescriptionHtml"]}\n')


def sync_workflows() -> None:
    path = ROOT / ".github/workflows/update_alt_store.yml"
    text = path.read_text(encoding="utf-8")
    text = replace_regex(
        text,
        r"python (?:update_alt_store\.py|tooling/app_identity/update_alt_store\.py)",
        "python tooling/app_identity/update_alt_store.py",
        expected_count=1,
    )
    write_text(path, text)


def main() -> None:
    identity = load_identity()
    sync_android(identity)
    sync_apple(identity)
    sync_linux(identity)
    sync_windows(identity)
    sync_debian(identity)
    sync_alt_store(identity)
    sync_repo_urls(identity)
    sync_fastlane_metadata(identity)
    sync_workflows()


if __name__ == "__main__":
    main()
