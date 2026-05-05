# Import Comic

## Introduction

Venera supports importing comics from local files.
However, the comic files must be in a specific format.

## Restore Local Downloads

If you migrated the app and kept the local download folder but lost database entries, you can restore the local library by scanning the current local path.

- Open `Local` -> `Import` -> `Restore local downloads`.
- The app scans the current local storage path and rebuilds entries in the unified database.
- It does not copy files or add favorites.
- Duplicates (same title or directory) are skipped.

**Behind the scenes:** Restoration queries the unified comics database and reconstructs local library entries by scanning your downloads folder.

Make sure the local storage path in Settings points to the folder that contains
the downloaded comics before running this.

## Comic Directory

A directory considered as a comic directory only if it follows one of the following two types of structure:

**Without Chapter**

```
comic_directory
├── cover.[ext]
├── img1.[ext]
├── img2.[ext]
├── img3.[ext]
├── ...
```

**With Chapter**

```
comic_directory
├── cover.[ext]
├── chapter1
│   ├── img1.[ext]
│   ├── img2.[ext]
│   ├── img3.[ext]
│   ├── ...
├── chapter2
│   ├── img1.[ext]
│   ├── img2.[ext]
│   ├── img3.[ext]
│   ├── ...
├── ...
```

The file name can be anything, but the extension must be a valid image extension.

The page order is determined by the file name. App will sort the files by name and display them in that order.

Cover image is optional.
If there is a file named `cover.[ext]` in the directory, it will be considered as the cover image.
Otherwise, the first image will be considered as the cover image.

The name of directory will be used as comic title. And the name of chapter directory will be used as chapter title.

## Archive

Venera supports importing comics from archive files and PDF files.

The archive file must follow [Comic Book Archive](https://en.wikipedia.org/wiki/Comic_book_archive_file) format.

Currently, Venera supports the following archive formats:

- `.cbz`
- `.cb7`
- `.zip`
- `.7z`

And PDF format:

- `.pdf`

## Nested Bundle Archive

If an archive contains multiple child archives and/or PDFs, Venera detects it as
a nested bundle and asks how to import:

- **One comic with chapters**: import each child item as one chapter/part.
- **Separate comics**: import each child item as its own local comic.

Mac metadata files like `__MACOSX` and `._*` are ignored automatically.

## Page Order

Imported pages are naturally sorted (for example, `1, 2, 10`).

You can manually reorder pages after import from:

- `Local` -> comic menu -> `Reorder Pages`

**How it works:** Page reordering uses an overlay system that preserves the original page order in the database while storing your custom ordering separately. This non-mutating approach ensures the app can rebuild your library without losing reorder preferences if data is synced or migrated.

**Limitations:**

- Manual page reorder is only supported for app-managed local comics (comics stored in Venera's local storage path).
- Reorders are stored in the unified comics database and are preserved across app sessions.
