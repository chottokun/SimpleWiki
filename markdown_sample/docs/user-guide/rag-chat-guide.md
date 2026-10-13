---
okf_version: "0.2"
title: "AIチャット＆RAG活用ガイド"
description: "ローカルLLMおよびさくらAI APIを活用した、Fast RAGおよびAgentic RAGモードの利用方法です。"
type: "Guide"
domain: "user-guide"
tags:
  - RAG
  - LLM
  - Chat
status: stable
last_updated: 2026-08-25
---

# AIチャット＆RAG活用ガイド

SimpleWiki のローカル AI チャットアシスタントの活用手順です。

## 1. 2つの動作モード
- **Fast RAG**: 高速な1-Passコンテキスト検索により、即座に回答を生成します。
- **Agentic RAG**: ReAct自律調査エージェントが複数のツール（検索、用語集参照、ドキュメント読込）を駆使して多角的に調査します。

## 2. 思考プロセスの確認
Agentic RAG では、エージェントが調査を進める思考ログ（thinkingLog）をアコーディオン形式でリアルタイムに追跡できます。
