---
type: "Table Showcase"
title: "HTML埋め込み表（複雑なテーブル）サンプル"
description: "Markdown内にHTML形式の <table> タグを埋め込んで表現する、セル結合（colspan/rowspan）、ステータスバッジ、複数行リストを含む高度な表のサンプル集です。"
author: "human:simplewiki-team"
domain: "サンプル/レイアウト"
tags:
  - HTML表
  - 複雑な表
  - Markdown
  - スタイリング
status: stable
last_updated: 2026-08-25
generated:
  by: "human:simplewiki-team"
  at: "2026-08-25T00:00:00Z"
verified:
  - by: "human:ui-lead"
    at: "2026-08-25T00:00:00Z"
---

# 📊 HTML埋め込み表（複雑なテーブル）サンプル

SimpleWiki では、標準の Markdown 形式の表（GFM Table）に加えて、**HTML形式の `<table>` タグを直接 Markdown ファイル内に埋め込んで表示**することが可能です。

Markdown 形式の表では表現が難しい「セルの縦横結合（`rowspan` / `colspan`）」「セル内の改行・箇条書き」「ステータスバッジの埋め込み」などの高度で複雑なレイアウトに活用できます。

---

> [!TIP]
> **記述上の注意点**:
> HTMLブロックをMarkdown内に記述する際は、`<table>` の直前と `</table>` の直後に**必ず空行**を挿入してください。空行を入れることでMarkdig等のパースエンジンがHTMLブロックとして正しく認識します。

---

## 1. 縦横セル結合テーブル（システム構成・権限マトリクス）

`rowspan` や `colspan` を使用した多層ヘッダーとカテゴリ結合の例です。

<table>
  <thead>
    <tr>
      <th rowspan="2">レイヤー</th>
      <th rowspan="2">コンポーネント</th>
      <th colspan="2">アクセス権限</th>
      <th rowspan="2">備考</th>
    </tr>
    <tr>
      <th>管理者 (Admin)</th>
      <th>一般ユーザー (User)</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td rowspan="2" style="font-weight: bold; background: #fafbfc;">フロントエンド</td>
      <td>Web GUI View</td>
      <td><span style="color: green; font-weight: bold;">フルアクセス</span></td>
      <td><span style="color: green; font-weight: bold;">閲覧のみ</span></td>
      <td>ブラウザベースの管理画面</td>
    </tr>
    <tr>
      <td>チャット UI Widget</td>
      <td><span style="color: green; font-weight: bold;">フルアクセス</span></td>
      <td><span style="color: green; font-weight: bold;">対話可</span></td>
      <td>WinRT 形態素解析連携</td>
    </tr>
    <tr>
      <td rowspan="3" style="font-weight: bold; background: #fafbfc;">バックエンド API</td>
      <td><code>/api/index.json</code></td>
      <td><span style="color: green; font-weight: bold;">取得可</span></td>
      <td><span style="color: green; font-weight: bold;">取得可</span></td>
      <td>OKF インデックスデータ</td>
    </tr>
    <tr>
      <td><code>/api/chunks.json</code></td>
      <td><span style="color: green; font-weight: bold;">取得可</span></td>
      <td><span style="color: green; font-weight: bold;">取得可</span></td>
      <td>セマンティック分割チャンク</td>
    </tr>
    <tr>
      <td><code>/api/chat</code></td>
      <td><span style="color: green; font-weight: bold;">設定変更可</span></td>
      <td><span style="color: gray;">制限あり</span></td>
      <td>LLM AI チャット応答 API</td>
    </tr>
  </tbody>
</table>

---

## 2. セル内改行・リストを含む複雑な仕様比較表

標準 Markdown 表では難しい「セル内での箇条書き」「コードブロック指定」「カラーバッジ」を組み合わせた表示例です。

<table>
  <thead>
    <tr>
      <th>形式</th>
      <th>メリット</th>
      <th>デメリット</th>
      <th>推奨ユースケース</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>Markdown 形式の表</strong><br><code>| Header | Header |</code></td>
      <td>
        <ul>
          <li>記述が簡潔で読みやすい</li>
          <li>標準的なテキストエディタで直感的に編集可能</li>
        </ul>
      </td>
      <td>
        <ul>
          <li>セルの結合（<code>colspan</code> / <code>rowspan</code>）が不可</li>
          <li>セル内で複数行の改行や複雑な要素の配置が難しい</li>
        </ul>
      </td>
      <td><span class="badge" style="background: #28a745; color: white;">標準</span> 簡易なデータ一覧、エラーコード表</td>
    </tr>
    <tr>
      <td><strong>HTML 埋め込み表</strong><br><code>&lt;table&gt;...&lt;/table&gt;</code></td>
      <td>
        <ul>
          <li><code>rowspan</code> / <code>colspan</code> による自在なセル結合</li>
          <li>セル内にリスト、画像、カスタムCSSスタイル、コードタグ等を自由に配置可能</li>
        </ul>
      </td>
      <td>
        <ul>
          <li>HTMLタグの記述が増えるため生テキストの視認性が下がる</li>
        </ul>
      </td>
      <td><span class="badge" style="background: #0366d6; color: white;">高度</span> 複雑な仕様マトリクス、比較表、製品スペック表</td>
    </tr>
  </tbody>
</table>

---

## 3. インラインCSSスタイリング付きステータス表

インラインスタイル（`background-color`, `border-left` など）をセル単位で指定したグラフィカルなステータスダッシュボードの例です。

<table>
  <thead>
    <tr>
      <th>モジュール名</th>
      <th>バージョン</th>
      <th>稼働ステータス</th>
      <th>詳細・メモ</th>
    </tr>
  </thead>
  <tbody>
    <tr style="background-color: #f6ffed;">
      <td><strong>Start-MarkdigWiki.ps1</strong></td>
      <td><code>v1.2.0</code></td>
      <td><span style="background: #52c41a; color: white; padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: bold;">ACTIVE</span></td>
      <td>Web サーバー ＆ チャット UI 機能正常動作中</td>
    </tr>
    <tr style="background-color: #f6ffed;">
      <td><strong>Export-MarkdigWiki.ps1</strong></td>
      <td><code>v1.2.0</code></td>
      <td><span style="background: #52c41a; color: white; padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: bold;">ACTIVE</span></td>
      <td>静的 HTML 一括エクスポート機能正常動作中</td>
    </tr>
    <tr style="background-color: #fff7e6;">
      <td><strong>RAG Semantic Chunker</strong></td>
      <td><code>v0.9.5</code></td>
      <td><span style="background: #fa8c16; color: white; padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: bold;">BETA</span></td>
      <td>H2/H3 見出し分割アルゴリズム評価中</td>
    </tr>
  </tbody>
</table>

---

## 🔗 関連ページへの移動
- [詳細仕様書を見る](詳細仕様.md)
- [REST API 仕様書を見る](api/REST-API.md)
- [ドキュメント一覧に戻る](index.md)
- [トップポータルに戻る](../index.md)
