---
title: "SimpleWiki OKF ナレッジベースへようこそ！"
description: "100% オフライン環境で動作する Google OKF (Open Knowledge Format) 対応 Markdown Wiki サーバー ＆ 静的 HTML エキスポートシステムです。"
author: "SimpleWiki 開発チーム"
domain: "ポータル"
tags:
  - OKF
  - Markdown
  - PowerShell
  - Wiki
  - RAG
last_updated: 2026-08-09
status: active
---

# SimpleWiki OKF ナレッジベースへようこそ！

SimpleWiki は、Windows PowerShell 5.1 / PowerShell 7+ および Windows 11 環境で動作する **100% オフライン対応 Markdown Wiki サーバー ＆ 静的 HTML エキスポートツール** です。

Google が提唱する **OKF (Open Knowledge Format)** の思想に基づき、Markdown ドキュメントに文脈（著者・最終更新日・状態・カテゴリ・タグ）を付与して人間（Human）と AI エージェント（RAG/LLM）の双方に最適化されたナレッジ管理環境を提供します。

---

## 🌟 主な特徴

- 🚀 **100% オフライン動作**: 外部 CDN やデータベース、Node.js / Python などの重いランタイムが一切不要。
- 📁 **リアルタイム・フォルダツリー**: ディレクトリ内に `.md` ファイルを追加・編集するだけで自動的にサイドバーが更新。
- 📄 **Google OKF (Open Knowledge Format) 準拠**: YAML Front Matter からの属性抽出・自動補完（フォールバック）に対応。
- 🤖 **AI エージェント / RAG 用機械可読 API**:
  - `/api/index.json`: 全ドキュメントの構造化メタデータ一覧
  - `/api/chunks.json`: 見出し (H2/H3) 単位の自動セマンティック分割済み JSON チャンク API
- 🔍 **豊富な動的ナビゲーションビュー**:
  - 🕒 [最近の更新](/recent) | 🏷️ [タグ目録](/tags) | 🧹 [品質ダッシュボード](/maintenance) | 👥 [著者一覧](/authors) | 🔍 [全文検索](/search)
- 🔒 **安全設計**: ディレクトリトラバーサル防止機能 (`403 Forbidden`)、XSS サニタイズ (`HtmlEncode`) を標準完備。
- 🎨 **GitHub スタイル ＆ オフライン Mermaid.js**: GFM テーブル、コードハイライト、タスクリスト、100% オフラインダイアグラム表示対応。

---

## 🔗 Wiki 内ナビゲーション ＆ 相互リンク（ワードリンク）

文章中のキーワードから、他ページや特定の見出しへ直感的に相互リンクできます。

### ドキュメントマップ

- 📘 **[プロジェクト概要とシステムアーキテクチャ](概要.md)**: 開発背景、コンポーネント構成、OKF 思想の反映状況
- ⚙️ **[詳細仕様書](docs/詳細仕様.md)**: ルーティング動作、メタデータ補完マトリクス、セキュリティ仕様
- 🤖 **[REST API 仕様書](docs/api/REST-API.md)**: `/api/index.json` および RAG 用 `/api/chunks.json` の仕様と Python 連携コード
- 🚀 **[クイックスタートガイド](docs/user-guide/クイックスタート.md)**: Web サーバー起動、GUI ツール、ドラッグ＆ドロップ運用
- 🛠️ **[開発環境構築ガイド](guides/環境構築.md)**: 開発前提条件、文字コード規約 (BOM付き UTF-8)、Pester 自動テスト

---

## 記法別相互リンク例

| リンク種別 | Markdown 記述例 | 説明 |
| :--- | :--- | :--- |
| **同階層リンク** | `[概要](概要.md)` | 同じフォルダ内のページへリンク |
| **サブフォルダリンク** | `[API仕様](docs/api/REST-API.md)` | 下位フォルダのページへリンク |
| **親フォルダリンク** | `[トップ](index.md)` | 上位フォルダのページへリンク |
| **見出しアンカーリンク** | `[ルーティング詳細](docs/詳細仕様.md#ルーティング仕様)` | 特定見出し (`#見出し名`) へ直接ジャンプ |

---

## 📋 システムチェックリスト

- [x] `Markdig.dll` (.NET Framework 4.6.2) による高度 Markdown パース
- [x] ディレクトリトラバーサル防止 (`403 Forbidden`)
- [x] XSS 対策 (`HtmlEncode`)
- [x] Google OKF YAML Front Matter 解析 ＆ スマートフォールバック
- [x] スリム・トップバー ＆ 終端フッターカードの 2 段構成 UI
- [x] RAG 用セマンティックチャンク自動分割 API (`/api/chunks.json`)
- [x] 3 段階品質検証フェーズ (AST / Pester 24件 / E2E Export) 100% PASS
