# SimpleWiki ナレッジベース更新履歴 (Update Log)

本ファイルは、OKF (Open Knowledge Format) v0.2 仕様に準拠したナレッジバンドルの変更履歴記録です。

---

## 2026-08-25

* **Refactor**: OKF (Open Knowledge Format) v0.2 仕様への完全適合化を実施。
* **Creation**: 全コンセプトドキュメントへの OKF YAML Frontmatter (`type`, `status: stable`, `generated`, `verified`, `sources`) の付与。
* **Creation**: 段階的開示（Progressive Disclosure）のための階層別インデックスファイル (`docs/index.md`, `docs/api/index.md`, `docs/user-guide/index.md`, `docs/computations/index.md`, `guides/index.md`) を配置。
* **Creation**: OKF Attested Computation 仕様に基づく検索スコアリング確定ロジックドキュメント (`docs/computations/search-score.md`) を新設。
* **Update**: 出典と脚注（Footnotes `[^source-id]`）のクロスリファレンス整合性を検証。

## 2026-08-12

* **Creation**: HTML 埋め込み複雑表サンプル (`docs/complex-table.md`) の作成。

## 2026-08-10

* **Creation**: 社内用語定義集 (`glossary.md`) および REST API 仕様書 (`docs/api/REST-API.md`) の初期作成。

## 2026-08-09

* **Creation**: プロジェクト概要 (`概要.md`)、クイックスタート (`docs/user-guide/クイックスタート.md`)、開発環境構築ガイド (`guides/環境構築.md`) の初期作成。
