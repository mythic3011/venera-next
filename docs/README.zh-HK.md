# Venera 中文說明

`venera-next` 係一個 breaking-change、personal-use-first fork。上游
repository 已 archived / read-only，唔再係新 runtime architecture 嘅權威。

此 fork 由 `mythic3011` 以 best-effort 方式維護，不保證同舊有 runtime、storage
或者 source format 相容。

## 文件

- [專案方向與相容性政策](project-direction.md)
- [Source package 與 tag taxonomy](source-packages.md)
- [Reader runtime、data model 與 diagnostics](reader-runtime.md)
- [開發、build 與 release](development.md)
- [貢獻與 issue 政策](contributing.md)
- [Active v2 design](design/SUMMARY.md)

## 核心方向

- UI 只表達 user intent。
- Resolver 負責建立 validated reader identity。
- Domain model、database、repository、runtime 各自擁有清晰 authority。
- Legacy code 只作 reference、import 或 migration，唔可以重新成為 live authority。
- Source install 只接受經 manifest、schema 同 integrity validation 嘅 package artifact。
- Tag taxonomy、mapping、localization 用 JSON data contract，唔寫死喺 source extension code。
- Diagnostics 記錄 evidence，唔負責修補 invalid state。

舊有 `local.db`、`history.db`、`local_favorite.db`、`implicitData.json` 只會視為
optional import source，唔係永久 runtime contract。

Tag translation 來源：[EhTagTranslation](https://github.com/EhTagTranslation/Database)。
