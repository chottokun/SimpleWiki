---
okf_version: "0.2"
title: "Webエディタ活用ガイド"
description: "SimpleWiki内蔵エディタによるOKFメタデータと本文の分離編集、および3世代バックアップ機能の利用手順です。"
type: "Guide"
domain: "user-guide"
tags:
  - Editor
  - OKF
  - YAML
status: stable
last_updated: 2026-08-25
---

# Webエディタ活用ガイド

SimpleWiki の内蔵エディタ機能と世代管理バックアップの使い方を説明します。

## 1. エディタの起動
各ドキュメント右上の「✏️ 編集」ボタンをクリックすると、OKF 分離編集モーダルが開きます。

## 2. フォーム入力モードと RAW YAML モード
- **フォーム入力モード**: OKF v0.2 仕様に準拠した項目（Title, Status, Domain, Tags 等）を個別の入力欄で安全に編集できます。
- **RAW YAML モード**: YAML テキストを直接編集できます。

## 3. 世代管理バックアップと復元
保存時に直前の状態が自動でバックアップ（`.bak1`〜`.bak3`）され、モーダル上からいつでも過去世代へロールバックできます。
