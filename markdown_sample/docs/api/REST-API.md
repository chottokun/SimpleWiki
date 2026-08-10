---
title: "REST API 仕様書 ＆ AI Agent / RAG 連携ガイド"
description: "AI エージェントおよび RAG パイプライン向け機械可読 JSON API エンドポイント (/api/index.json, /api/chunks.json, /api/chat) の詳細仕様書です。"
author: "API 開発チーム"
domain: "仕様/API"
tags:
  - API
  - RAG
  - JSON
  - LLM
  - Mermaid
last_updated: 2026-08-10
status: active
---

# REST API 仕様書 ＆ AI Agent / RAG 連携ガイド

SimpleWiki が提供する AI エージェント（RAG / LLM）および外部ツール向けの構造化 JSON API エンドポイントの仕様書です。

---

## 📡 提供エンドポイント一覧

| メソッド | エンドポイント | 用途・説明 | パラメータ | 認証 |
| :--- | :--- | :--- | :--- | :--- |
| `GET` | `/api/index.json` | Wiki 全件の OKF メタデータ構造化一覧を取得 | なし | 不要 |
| `GET` | `/api/chunks.json` | RAG 用自動 H2/H3 見出し分割済み JSON チャンク一覧を取得 | なし | 不要 |
| `POST` | `/api/chat` | OKF 文脈検索 ＋ LLM RAG AI チャット応答を取得 | `{"message": "質問文"}` | 不要 (`config.json` 依存) |
| `GET` | `/*.md` | 指定相対パスの Raw Markdown 本文を取得 | なし | 不要 |

---

## 🔄 RAG データ取得フロー (Mermaid シーケンス図デモ)

SimpleWiki を RAG のナレッジデータソース（Producer）として利用する際のシーケンス図です。

```mermaid
sequenceDiagram
    autonumber
    participant RAG as RAG インデクサー (Python/LangChain)
    participant Wiki as SimpleWiki API Server
    participant VectorDB as ベクトル DB (Chroma/Qdrant)

    note over RAG,Wiki: パターン A: 事前チャンク化 API (/api/chunks.json) を利用
    RAG->>Wiki: GET /api/chunks.json
    Wiki-->>RAG: JSON (H2/H3分割済み ＋ EnrichedText 付与チャンク)
    loop 各チャンクの登録
        RAG->>VectorDB: chunk["EnrichedText"] を Embedding 化して登録
    end

    note over RAG,Wiki: パターン B: 構造化インデックス API (/api/index.json) を利用
    RAG->>Wiki: GET /api/index.json
    Wiki-->>RAG: JSON (全文書メタデータ一覧)
    loop active 文書の抽出と取得
        RAG->>Wiki: GET /docs/詳細仕様.md
        Wiki-->>RAG: Raw Markdown テキスト
        RAG->>VectorDB: メタデータエンリッチメントの上保存
    end
```

---

## 1. 全文書メタデータインデックス API (`/api/index.json`)

### レスポンス構造例:
```json
[
  {
    "Title": "REST API 仕様書 ＆ AI Agent / RAG 連携ガイド",
    "Description": "AI エージェントおよび RAG パイプライン向け機械可読 JSON API エンドポイントの仕様書です。",
    "Author": "API 開発チーム",
    "Domain": "仕様/API",
    "Tags": ["API", "RAG", "JSON", "LLM"],
    "LastUpdated": "2026-08-09T00:00:00Z",
    "Status": "active",
    "HasYaml": true,
    "RelPath": "docs/api/REST-API.md"
  }
]
```

---

## 2. RAG 用自動チャンク分割 API (`/api/chunks.json`)

Markdown 本文を `#`, `##`, `###` の見出し単位で自動分割し、文脈ヘッダー (`EnrichedText`) をプリセットしたレスポンスです。

### レスポンス構造例:
```json
[
  {
    "ChunkId": "docs/api/REST-API.md#chunk-1",
    "RelPath": "docs/api/REST-API.md",
    "Title": "REST API 仕様書 ＆ AI Agent / RAG 連携ガイド",
    "Domain": "仕様/API",
    "Section": "1. 全文書メタデータインデックス API (/api/index.json)",
    "Tags": ["API", "RAG", "JSON"],
    "LastUpdated": "2026-08-10T00:00:00Z",
    "Status": "active",
    "Content": "### レスポンス構造例:\n```json\n[ ... ]\n```",
    "EnrichedText": "[Document: REST API 仕様書 | Domain: 仕様/API | Section: 1. 全文書メタデータインデックス API | Tags: API, RAG]\n\n### レスポンス構造例:\n```json\n[ ... ]\n```"
  }
]
```

---

## 3. OKF RAG LLM AI チャット API (`/api/chat`)

Wiki 内の `status: active` ドキュメントを自動文脈検索し、グラウンディング（根拠に基づく回答）された AI 応答を取得する POST エンドポイントです。

### リクエスト例 (POST):
```json
{
  "message": "それの使い方は？",
  "history": [
    { "role": "user", "content": "APIはどのようなものがありますか？" },
    { "role": "assistant", "content": "SimpleWiki が提供する API は /api/index.json, /api/chunks.json, /api/chat の 3 つです。" }
  ]
}
```

### レスポンス構造例:
```json
{
  "answer": "SimpleWiki が提供する API は...",
  "sources": [
    {
      "title": "REST API 仕様書 ＆ AI Agent / RAG 連携ガイド",
      "relPath": "docs/api/REST-API.md",
      "relUri": "/docs/api/REST-API.md",
      "lastUpdated": "2026-08-10",
      "author": "API 開発チーム"
    }
  ]
}
```

---

## 💻 Python (LangChain) からの最小呼び出しコード

```python
import requests

# SimpleWiki の /api/chunks.json から1回のリクエストで完成チャンクを取得
chunks = requests.get("http://localhost:8080/api/chunks.json").json()

for chunk in chunks:
    if chunk["Status"] == "active":
        print(f"Ingesting: {chunk['ChunkId']} (Section: {chunk['Section']})")
        # vector_db.add(text=chunk["EnrichedText"], metadata=chunk)
```

---

## 🔗 関連ページへの移動
- [詳細仕様書を見る](../詳細仕様.md)
- [開発環境構築ガイドを見る](../../guides/環境構築.md)
- [ポータルに戻る](../../index.md)
