---
okf_version: "0.2"
title: "静的HTMLエクスポートガイド"
description: "オフライン共有やWebサーバー配備に向けた、静的HTML一括エクスポート機能およびGUIツールの利用手順です。"
type: "Guide"
domain: "user-guide"
tags:
  - Export
  - HTML
  - Offline
status: stable
last_updated: 2026-08-25
---

# 静的HTMLエクスポートガイド

SimpleWiki のドキュメント群を一括で静的 HTML サイトとして出力する手順です。

## 1. GUI ツール (`Export-GUI.bat`)
`Export-GUI.bat` をダブルクリックすると専用の GUI 画面が起動し、出力先フォルダや多言語設定（日本語 / 英語）を選択してワンクリックでエクスポートできます。

## 2. 単一ファイル (SPA) モード
`-SingleFile` オプションを指定すると、すべてのドキュメントと画像を1つの `index.html` に統合した自己完結型 HTML が出力されます。
