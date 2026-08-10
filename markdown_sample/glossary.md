---
title: "社内用語定義集 (Glossary)"
description: "社内で使用される専門用語、ツール名、略称の定義集です。Agentic RAG の lookup_glossary ツール等から参照されます。"
author: "ナレッジ管理チーム"
domain: "共通/用語集"
tags:
  - 用語集
  - Glossary
  - K-DAT
  - OKF
last_updated: 2026-08-10
status: active
---

# 社内用語定義集 (Glossary)

社内で使用されるシステム名、開発用語、ツール略称の定義一覧です。

---

## K-DAT

* **正式名称**: Knowledge Data Transfer & Backup Tool
* **概要**: 研究所および基幹システム専用の高速データバックアップ＆アーカイブツール。
* **注意点**:
  - バックアップ実行時は DB 接続セッションを一時ロックするため、夜間メンテナンス時間帯にのみ実施してください。
  - レプリケーション完了フラグが立つ前にサービスを再起動しないでください。

---

## OKF (Open Knowledge Format)

* **概要**: ドキュメントの文脈・メタデータ（著者、更新日、ステータス、タグ等）を YAML Front Matter で構造化保持する知識記述フォーマット。
* **目的**: LLM RAG における古い情報（非推奨ドキュメント）の教示（ハルシネーション）を防止し、情報の透明性と更新状態を機械可読にする。

---

## ReAct (Reasoning and Acting)

* **概要**: LLM が思考（Reasoning）とツール実行（Acting）を対話形式で自律的に繰り返し、複雑な調査課題を解決するエージェントフレームワーク。
* **SimpleWiki での利用**: Agentic RAG モードにて `search_okf`, `lookup_glossary`, `read_doc`, `get_linked_docs` などのツールを組み合わせて使用。
