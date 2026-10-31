// TEMPORARY LEGACY VENERA JS COMIC SOURCE.
// First-party references:
// - Venera-Next doc/api/comic_source.zh.md + doc/api/js.zh.md
// - LANraragi tools/openapi.yaml, Search API + Archive API.
//
// No import/export/require: load as ONE .js file in the old Venera JS runtime.
// No API key or cloud sync. Do not grant this source unrestricted private LAN
// access at a v2 plugin boundary. Source is single-instance per source key.

class LANraragiTemporarySource extends ComicSource {
    name = "LANraragi (Temporary)";
    key = "lanraragi_temporary";
    version = "0.1.0";
    minAppVersion = "1.16.0";
    url = "";

    settings = {
        server: {
            title: "Server URL (HTTPS preferred)",
            type: "input",
            default: "",
            validator: "^https?://[^/?#]+(?:/[^?#]*)?$"
        },
        allow_http: {
            title: "Allow plain HTTP (trusted LAN only)",
            type: "switch",
            default: false
        }
    };

    translation = {
        zh_TW: {
            "Server URL (HTTPS preferred)": "伺服器 URL（建議 HTTPS）",
            "Allow plain HTTP (trusted LAN only)": "允許 HTTP（只限可信任 LAN）"
        },
        zh_CN: {
            "Server URL (HTTPS preferred)": "服务器 URL（建议 HTTPS）",
            "Allow plain HTTP (trusted LAN only)": "允许 HTTP（仅可信任局域网）"
        },
        en: {}
    };

    // The legacy runtime's URL API is not guaranteed, so use strict
    // string validation without new URL(). This does not substitute
    // a host-owned SSRF policy, DNS pinning, or redirect enforcement.
    baseUrl = () => {
        const value = String(this.loadSetting("server") || "").trim();
        const match = /^(https?):\/\/([^/?#]+)(\/[^?#]*)?$/i.exec(value);
        if (!match || match[2].includes("@") || match[2].includes("\\") ||
            (match[3] || "").includes("\\") ||
            /(?:^|\/)\.\.(?:\/|$)/.test(match[3] || "")) {
            throw new Error("Set a valid LANraragi Server URL in Source Settings.");
        }
        if (match[1].toLowerCase() === "http" &&
            this.loadSetting("allow_http") !== true) {
            throw new Error("Plain HTTP is disabled. Enable it explicitly for a trusted LAN.");
        }
        return value.replace(/\/+$/, "");
    };

    archiveId = id => {
        const value = String(id || "").toLowerCase();
        if (!/^[a-f0-9]{40}$/.test(value)) {
            throw new Error("Invalid LANraragi archive ID.");
        }
        return value;
    };

    json = async path => {
        const response = await Network.get(this.baseUrl() + path, {
            "Accept": "application/json"
        });
        if (response.status === 401 || response.status === 403) {
            throw new Error("LANraragi requires authentication. This temporary source supports only authorized unauthenticated read endpoints.");
        }
        if (response.status === 204) {
            throw new Error("LANraragi search index is not initialized yet.");
        }
        if (response.status !== 200) {
            throw new Error("LANraragi HTTP " + response.status);
        }
        try {
            return JSON.parse(response.body);
        } catch (_) {
            throw new Error("LANraragi returned invalid JSON.");
        }
    };

    coverKey = id => "lrr-cover:" + this.archiveId(id);

    parseTags = raw => {
        const groups = {};
        if (typeof raw !== "string") return groups;
        for (const entry of raw.split(",")) {
            const tag = entry.trim();
            if (!tag) continue;
            const separator = tag.indexOf(":");
            const namespace = separator > 0 ? tag.slice(0, separator).trim() : "tags";
            const value = separator > 0 ? tag.slice(separator + 1).trim() : tag;
            if (!value) continue;
            if (!groups[namespace]) groups[namespace] = [];
            groups[namespace].push(value);
        }
        return groups;
    };

    toComic = item => {
        const id = this.archiveId(item.arcid);
        return new Comic({
            id,
            title: String(item.title || item.filename || id),
            cover: this.coverKey(id),
            subtitle: String(item.summary || ""),
            tags: typeof item.tags === "string" ?
                item.tags.split(",").map(x => x.trim()).filter(Boolean) : []
        });
    };

    // Do not trust a returned external URL; extract only the path from
    // the documented LANraragi /api/archives/{id}/page[?&]path=... form.
    // Reconstruct requests under the user's configured server origin.
    pageKey = (archiveId, item) => {
        if (typeof item !== "string" || item.length > 8192) {
            throw new Error("Invalid page entry from LANraragi.");
        }
        const match = /(?:^|\/)api\/archives\/([a-f0-9]{40})\/page[?&]path=([^&#]+)/i.exec(item);
        if (!match || match[1].toLowerCase() !== archiveId) {
            throw new Error("Unexpected LANraragi image URL format.");
        }
        let path;
        try {
            path = decodeURIComponent(match[2]);
        } catch (_) {
            throw new Error("Invalid encoded image filename.");
        }
        if (!path || path.length > 4096 || path.startsWith("/") ||
            path.includes("\\") || path.includes("\0") ||
            path.split("/").some(part => part === ".." || part === ".")) {
            throw new Error("Unsafe image filename.");
        }
        return "lrr-page:" + archiveId + ":" + encodeURIComponent(path);
    };

    imageUrl = key => {
        const text = String(key || "");
        if (text.startsWith("lrr-cover:")) {
            return this.baseUrl() + "/api/archives/" +
                this.archiveId(text.slice("lrr-cover:".length)) + "/thumbnail";
        }
        if (!text.startsWith("lrr-page:")) {
            throw new Error("Invalid LANraragi image key.");
        }
        const data = text.slice("lrr-page:".length);
        const separator = data.indexOf(":");
        if (separator < 0) throw new Error("Invalid image key.");
        const id = this.archiveId(data.slice(0, separator));
        const pathKey = data.slice(separator + 1);
        let path;
        try {
            path = decodeURIComponent(pathKey);
        } catch (_) {
            throw new Error("Invalid image key encoding.");
        }
        if (!path || path.startsWith("/") || path.includes("\\") ||
            path.includes("\0") || path.split("/").some(x => x === ".." || x === ".")) {
            throw new Error("Unsafe image key.");
        }
        return this.baseUrl() + "/api/archives/" + id +
            "/page?path=" + encodeURIComponent(path);
    };

    search = {
        optionList: [],
        // Cursor-based offset avoids assuming the server's configurable page size.
        // 'start' is a raw offset; groupby_tanks=false keeps IDs archive-centric.
        loadNext: async (keyword, options, next) => {
            const start = next === null || next === undefined ? 0 : Number(next);
            if (!Number.isSafeInteger(start) || start < 0 || start > 1000000) {
                throw new Error("Invalid search cursor.");
            }
            const value = String(keyword || "").trim().slice(0, 256);
            const response = await this.json("/api/search?filter=" +
                encodeURIComponent(value) + "&start=" + start +
                "&groupby_tanks=false");
            if (!response || !Array.isArray(response.data)) {
                throw new Error("Invalid LANraragi search response.");
            }
            const comics = response.data.map(x => this.toComic(x));
            const total = Number(response.recordsFiltered);
            const end = start + comics.length;
            const more = comics.length > 0 &&
                Number.isSafeInteger(total) && total >= 0 && end < total;
            return {
                comics,
                next: more ? String(end) : null
            };
        }
    };

    comic = {
        // Each LANraragi archive is an unchaptered Venera work.
        loadInfo: async id => {
            const archiveId = this.archiveId(id);
            const item = await this.json("/api/archives/" + archiveId + "/metadata");
            if (!item || typeof item !== "object" || Array.isArray(item)) {
                throw new Error("Invalid LANraragi metadata.");
            }
            return new ComicDetails({
                title: String(item.title || item.filename || archiveId),
                cover: this.coverKey(archiveId),
                description: String(item.summary || ""),
                tags: this.parseTags(item.tags),
                chapters: null
            });
        },

        // No global "current archive" state: concurrent calls are safe.
        loadEp: async (id, epId) => {
            if (epId !== null && epId !== undefined && epId !== "") {
                throw new Error("Archive does not contain chapters.");
            }
            const archiveId = this.archiveId(id);
            const data = await this.json("/api/archives/" + archiveId + "/files");
            if (!data || !Array.isArray(data.pages)) {
                throw new Error("LANraragi did not return a page list.");
            }
            if (data.pages.length === 0) {
                throw new Error("LANraragi archive has no extracted pages yet.");
            }
            // Preserve returned order, do not reverse/sort filenames.
            return {images: data.pages.map(item => this.pageKey(archiveId, item))};
        },

        // The image loader owns actual HTTP requests. No API token is
        // included in metadata, image keys, query strings, or source files.
        onImageLoad: (imageKey, comicId, epId) => ({
            url: this.imageUrl(imageKey)
        }),

        // MUST be synchronous per Venera source API.
        onThumbnailLoad: imageKey => ({
            url: this.imageUrl(imageKey)
        })
    };
}
