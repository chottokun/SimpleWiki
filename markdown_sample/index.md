---
okf_version: "0.2"
title: "SimpleWiki OKF ナレッジベースへようこそ！"
description: "100% オフライン環境で動作する Google OKF (Open Knowledge Format) 対応 Markdown Wiki サーバー ＆ 静的 HTML エキスポートシステムです。"
author: "human:simplewiki-team"
domain: "ポータル"
tags:
  - OKF
  - Markdown
  - PowerShell
  - Wiki
  - RAG
last_updated: 2026-08-25
status: stable
---

# SimpleWiki OKF ナレッジベースへようこそ！

SimpleWiki は、Windows PowerShell 5.1 / PowerShell 7+ および Windows 11 環境で動作する **100% オフライン対応 Markdown Wiki サーバー ＆ LLM RAG AI チャット ＆ 静的 HTML エキスポートツール** です。

Google が提唱する **OKF (Open Knowledge Format) v0.2** の思想に基づき、Markdown ドキュメントに文脈（種別・著者・最終更新日・状態・カテゴリ・タグ・検証情報）を付与して人間（Human）と AI エージェント（RAG/LLM）の双方に最適化されたナレッジ管理環境を提供します。

---

## 🌟 主な特徴

- 🚀 **100% オフライン動作**: 外部 CDN やデータベース、Node.js / Python などの重いランタイムが一切不要。
- 📁 **リアルタイム・フォルダツリー**: ディレクトリ内に `.md` ファイルを追加・編集するだけで自動的にサイドバーが更新。
- 📄 **Google OKF (Open Knowledge Format) v0.2 準拠**: YAML Front Matter からの属性抽出・自動補完（フォールバック）に対応。
- 🤖 **LLM RAG AI チャットアシスタント ＆ 機械可読 API**:
  - `/api/index.json`: 全ドキュメントの構造化メタデータ一覧
  - `/api/chunks.json`: 見出し (H2/H3) 単位の自動セマンティック分割済み JSON チャンク API
  - `/api/chat`: WinRT 日本語形態素解析 ＋ OKF 文脈検索 ＋ リアルタイムSSEストリーミング ＋ マルチターン対話履歴対応 LLM RAG AI チャット API
- 🌐 **多言語対応 (i18n)**: 日本語/英語のワンクリック切り替え、外部辞書 `i18n.json` 拡張、多言語チャットプロンプト対応。
- ⚙️ **Web 設定管理 (`/settings`) ＆ 3世代バックアップ**: ブラウザからの各種オプション設定と自動ローテーションバックアップ。
- 🔍 **豊富な動的ナビゲーションビュー**:
  - 最近の更新 (`/recent`) | タグ目録 (`/tags`) | 品質ダッシュボード (`/maintenance`) | 著者一覧 (`/authors`) | 全文検索 (`/search`) | システム設定 (`/settings`)
- 🔒 **安全設計 ＆ キー暗号化**: ディレクトリトラバーサル防止 (`403 Forbidden`)、XSS サニタイズ、Windows DPAPI / AES-256 キー暗号化ユーティリティ (`Set-ApiKey.bat`)。
- 🎨 **GitHub スタイル ＆ オフライン Mermaid.js**: GFM テーブル、コードハイライト、タスクリスト、100% オフラインダイアグラム表示対応。

---

## 📂 サブディレクトリ目録 (Subdirectories)

* **[ドキュメント ＆ 仕様 (docs/)](docs/index.md)** - 詳細仕様書、複雑な表サンプル、API 仕様、ユーザーガイド、計算定義
* **[ガイド ＆ 環境構築 (guides/)](guides/index.md)** - 開発環境前提条件、文字コード規約、テスト実行方法

---

## 📄 ドキュメントマップ (Concepts & Documents)

### ルートドキュメント
- 📘 **[プロジェクト概要とシステムアーキテクチャ](概要.md)**: 開発背景、コンポーネント構成、OKF 思想の反映状況
- 📖 **[社内用語定義集 (Glossary)](glossary.md)**: システム名・開発略称定義集（Agentic RAG 用）
- 📝 **[更新履歴 (Update Log)](log.md)**: OKF バンドルの変更履歴

### 仕様 ＆ リファレンス (docs/)
- ⚙️ **[詳細仕様書](docs/詳細仕様.md)**: ルーティング動作、メタデータ補完マトリクス、セキュリティ仕様
- 📊 **[HTML埋め込み表サンプル](docs/complex-table.md)**: 縦横セル結合（colspan/rowspan）、ステータスバッジ、複雑なレイアウトの表表現
- 🤖 **[REST API 仕様書](docs/api/REST-API.md)**: `/api/index.json` および RAG 用 `/api/chunks.json` の仕様と Python 連携コード
- 🧮 **[検索スコアリング計算 (Attested Computation)](docs/computations/search-score.md)**: 検索確定アルゴリズムのパラメータと計算仕様
- 🚀 **[クイックスタートガイド](docs/user-guide/クイックスタート.md)**: Web サーバー起動、GUI ツール、ドラッグ＆ドロップ運用

### ガイド (guides/)
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
- [x] 多言語化 (i18n) ＆ 言語セレクタ ＆ 外部辞書 `i18n.json`
- [x] ディレクトリトラバーサル防止 (`403 Forbidden`)
- [x] XSS 対策 (`HtmlEncode`)
- [x] Google OKF (Open Knowledge Format) v0.2 メタデータ解析 ＆ スマートフォールバック
- [x] スリム・トップバー ＆ 終端フッターカードの 2 段構成 UI
- [x] RAG 用セマンティックチャンク自動分割 API (`/api/chunks.json`)
- [x] 3 段階品質検証フェーズ (AST / Pester / E2E Export) 100% PASS
