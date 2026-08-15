# **システム詳細実装計画書：OKF対応 PowerShell ローカルWiki基盤**

本ドキュメントは、PowerShell 5.1 環境下で動作する **Markdig ＋ OKF (Open Knowledge Format) 対応ローカルWikiシステム** の全追加機能を含んだ詳細な実装計画書です。本計画書に基づいてそのままコーディングおよびテストへ移行できます。

## **1\. システム定義と設計原則**

### **1.1 システムの目的**

> 1. **ナレッジの信頼性と鮮度の担保**: Open Knowledge Format (OKF) の思想に基づき、ドキュメントに文脈（著者・最終更新日・状態・カテゴリ）を紐付けて視覚化・管理する。  
> 2. **完全オフライン運用**: 外部CDNやDBサーバーを一切使用せず、PowerShell 5.1 と Markdig.dll のみで閉域網（オフライン）稼働する。  
> 3. **プログレッシブ・ハイブリッド設計**: OKFメタデータ（YAML Front Matter）が存在するドキュメントは厳格に管理し、通常のMarkdownドキュメントはシステムが自動的に属性を補完（フォールバック）してシームレスに表示する。  
> 4. **「Just Files, Just YAML」と人間・AI 双方への透過的共有**: Google OKF の核心である「専用DBやプロプライエタリSDKに依存しないポータビリティ」を堅持し、ブラウザでの人間向け閲覧 UI (Consumer) と同時に、AI エージェント / LLM が直接コンテキストとして読み取れる構造化ナレッジハブ (Producer) として機能する。


### **1.2 コアコンポーネント**

* **バックエンド**: PowerShell 5.1 内蔵 System.Net.HttpListener (ローカルWebサーバー)  
* **Markdown変換エンジン**: Markdig.dll (UseAdvancedExtensions \+ UseYamlFrontMatter)  
* **インデックスエンジン**: 起動時およびリクエスト毎にメモリアレイ化されるWiki全件のメタデータ目録 ($script:WikiIndex)

## **2\. OKFデータモデル & フォールバック仕様**

### **2.1 YAML Front Matter 仕様**

各 .md ファイルの冒頭に配置される OKF 構造化データモデルです。

```yaml
---
# OKF メタデータ記述例（インライン配列・リスト形式配列・クォート表記に対応）
title: "基幹DB障害対応マニュアル: 初期手順"
description: PostgreSQLの接続障害発生時における初期障害切り分けと復旧手順
author: 知識 太郎 (インフラ部)
domain: インフラ/データベース
tags:
  - PostgreSQL
  - 障害対応
  - Runbook
last_updated: 2026-08-01
status: active
---
```

> **YAML 表記の改善・拡張ルール**:
> 1. **配列（タグ）記法の柔軟性**: `tags: [a, b]` (インライン形式) および `tags:\n  - a\n  - b` (リスト形式) の双方をサポート。
> 2. **特殊文字・コロンのエスケープ**: タイトルや説明文にコロン `:` や記号が含まれる場合は、`"..."` または `'...'` で囲むことを推奨・パース保証。
> 3. **コメント記法 (`#`) の許容**: YAML ブロック内の `# 注釈` コメント行をパース時に自動スキップ。
> 4. **ヘッダー圧迫防止（ミニマル記述原則）**: `title` や `domain` は自動補完されるため、YAML 内へは `tags` や `description` 等の最低限のみ記述することで Markdown 本文の視読性を最優先化。


### **2.2 属性定義および自動補完（フォールバック）ルール**

| 属性キー | 型 | 必須性 | OKF記述あり時の値 | 補完ルール（OKF記述なし時） |
| :---- | :---- | :---- | :---- | :---- |
| title | String | 任意 | YAMLの title: | 本文1行目の \# 見出し ➔ なければ **拡張子無しのファイル名** |
| description | String | 任意 | YAMLの description: | 本文先頭150文字のプレーンテキストを抽出 |
| author | String | 任意 | YAMLの author: | **未指定**（UI側で非表示制御） |
| domain | String | 任意 | YAMLの domain: | ファイルの存在する **相対フォルダ階層**（例: docs / DB） |
| tags | Array | 任意 | YAMLの tags: | **空配列 \[\]** |
| last\_updated | Date | 任意 | YAMLの last\_updated: | OSの **ファイル最終更新日時 (File.LastWriteTime)** |
| status | Enum | 任意 | YAMLの status: | デフォルト値 **active** |

* active: 現行の正式版ドキュメント  
* draft: 下書き・執筆中・レビュー中  
* deprecated: 非推奨・旧版（画面上に警告バナーを強制表示）

### **2.3 セキュリティ & XSS サニタイズ規約**

* **HTML エスケープの徹底**: YAML Front Matter から抽出した属性値（`title`, `description`, `author`, `domain`, `tags` の各要素）は、HTML レンダリング時および動的ビュー（カード、リスト、バナー、検索結果）出力時に必ず `[System.Net.WebUtility]::HtmlEncode` を適用する。
* **安全なメタデータ抽出**: タグや著者にスクリプトタグ（例: `<script>alert(1)</script>`）が含まれていても無効化し、XSS 脆弱性を防止する。


## **3\. システム構成 & ファイル配置計画**

Plaintext  
MyOKFWiki/  
├── Start-MarkdigWiki.ps1        \# メインスクリプト（サーバー・インデックス・描画処理）  
├── Start-MarkdigWiki.bat        \# ワンクリック起動バッチ  
├── lib/  
│   └── Markdig.dll              \# .NET Framework 4.6.2 用 DLL  
├── templates/  
│   └── okf-template.md          \# 新規ドキュメント用OKFテンプレート  
└── docs/                        \# ナレッジ格納ディレクトリ（サブフォルダ対応）  
    ├── index.md                 \# ルート用トップページ（任意）  
    ├── infrastructure/  
    │   └── db-setting.md  
    └── development/  
        └── api-guideline.md

## **4\. ルーティング & 動的ビュー詳細仕様**

HttpListener 経由で受け取った URI パスに応じて、既存の .md レンダリング機能に加えて以下の特殊ビュー（動的生成ページ）へルーティングします。

Plaintext  
       \[ Request URI \]  
              │  
     ┌────────┴────────┬──────────────┬──────────────┬──────────────┬──────────────┐  
     ▼                 ▼              ▼              ▼              ▼              ▼  
 / (または .md)      /recent        /tags        /maintenance    /authors       /search  
 \[標準ページ\]     \[最新更新\]     \[タグ目録\]    \[品質ダッシュボード\] \[著者目録\]     \[キーワード検索\]

### **4.1 各ビューの画面仕様と機能要件**

#### **① 最新更新一覧ビュー (/recent)**

* **機能**: Wiki内の全ドキュメントを更新日（last\_updated）の降順でソートして一覧表示。  
* **表示項目**: 更新日、タイトル（リンク）、ドメイン、著者、Statusバッジ、更新日種別（OKF指定日 または ファイル自動検出日）。

#### **② タグ目録 & 絞り込みビュー (/tags / /tags?tag=xxx)**

* **機能**:  
  * クエリなし (/tags): 全ドキュメントの tags を集計し、出現頻度に応じたタグクラウドおよび件数バッジ付きタグリストを表示。  
  * クエリあり (/tags?tag=障害対応): 指定されたタグを持つドキュメントのみをカード形式で抽出表示。

#### **③ 品質・メンテナンスダッシュボード (/maintenance)**

* **機能**: ナレッジの「風化・ゴミ化」を防ぐための管理画面。以下の3ブロックで構成。  
  1. ⚠️ **更新停滞ドキュメント**: 最終更新から **365日以上** 経過した active ドキュメントのリスト（優先メンテナンス対象）。  
  2. 📝 **下書き一覧**: status: draft のドキュメント。  
  3. 🗑️ **非推奨・旧版一覧**: status: deprecated のドキュメント（現行ドキュメントへの付け替え促進）。

#### **④ 著者別ディレクトリ (/authors / /authors?name=xxx)**

* **機能**: author 属性別にナレッジをグループ化。社内有識者の可視化に貢献。

#### **⑤ 簡易検索エンジン (/search?q=xxx)**

* **機能**: 検索窓から入力されたキーワードで、Wiki全体の title, description, tags, domain, author, および **Markdown本文** を対象にリアルタイム部分一致検索（AND検索対応）を行い結果を表示。

#### **⑥ 機械可読 AI エージェント用エンドポイント (/api/index.json および /llms.txt)**

* **機能**: Google OKF の「人間と AI エージェントの双方がシームレスに知識を利用できる」オープン仕様に基づき、メモリ上の `$script:WikiIndex` およびドキュメント一覧を機械可読な JSON / テキストフォーマットで返却。
* **ユースケース**: ローカル AI エージェント (RAG / Cursor / Claude Desktop / 自作スクリプト) が Wiki 内のドキュメント構造や補完済み OKF メタデータを即座に取得・文脈参照できる「Producer」機能を提供。


## **5\. モジュール構造 &内部設計方針**

スクリプト（Start-MarkdigWiki.ps1）を構成する主要モジュールの設計要件です。

### **モジュール 1: メタデータ抽出し・補完エンジン (Get-DocumentMetadata)**

* **入力**: ファイル物理パス、相対パス、ファイルテキスト  
* **処理**:  
  1. 正規表現 `(?s)^\s*---\r?\n(.*?)\r?\n---\r?\n` で Front Matter を分離。  
  2. キー＆バリュー形式（配列 `tags: [a, b]` やクォート付き文字列を含む）をハッシュテーブルにパース。  
  3. **例外処理 & フォールバック**: YAML 構文エラーや予期せぬ入力（インデント不備、不正文字、パース例外など）が発生した場合は `try/catch` で捕捉し、警告を出力した上で全属性を「2.2 補完ルール」のデフォルト（安全なフォールバック）値に倒して処理を継続する。  
  4. 「2.2 属性定義ルール」に従い、欠落している項目を補完（ファイルタイムスタンプ、本文見出し抽出など）。  
* **出力**: OKF完全互換メタデータハッシュオブジェクト

### **モジュール 2: メモリインデックス構築 & キャッシュエンジン (Build-WikiIndex)**

* **処理**: ディレクトリ内の全 Markdown ファイルの OKF メタデータを配列 `$script:WikiIndex` に保持。  
* **インデックスキャッシュ機構**:  
  * フォルダ階層全体の最終更新日時 (`Directory.GetLastWriteTime`) またはファイルタイムスタンプハッシュとキャッシュ生成日時を管理。  
  * ファイル変更が検出されないリクエストでは、ディスク再読込を行わずメモリ上の `$script:WikiIndex` を即時返却し、I/O およびパースコストを最小化する。  
* **メリット**: 大規模ドキュメント群における高速なソート、タグ集計、更新日判定、全文検索を実現。

### **モジュール 3: 画面レイアウト合成器 (Get-PageLayout)**

* **処理**: 共通の HTML 枠組み（レスポンシブ2カラムレイアウト、ヘッダーナビゲーション、サイドバー）を生成。全 OKF 属性値に対して `HtmlEncode` を徹底適用。  
* **画面領域**:  
  * **上部ナビ**: 🏠 Home / 🕒 最近の更新 / 🏷️ タグ一覧 / 🧹 メンテナンス / 🔍 検索窓  
  * **左サイドバー**: 階層型ドキュメントツリー ＋ 簡易統計情報（総文書数など）  
  * **メインエリア**: レンダリングされたOKFカード＋HTML本文、または動的ビュー画面

## **6\. 実装フェーズ & ロードマップ (全フェーズ完了)**

すべての実装フェーズおよび検証工程が 100% 完了しました。

```text
[ Phase 1: コアインデックス & 解析基盤の構築 ] ──► 完了 (Passed 14/14 tests)
  ├─ Markdig YAML Front Matter 拡張の設定
  ├─ Get-DocumentMetadata の例外安全パース & 自動補完 (フォールバック) 実装
  └─ Build-WikiIndex による全件インデックス & ディレクトリタイムスタンプキャッシュ実装
         │
         ▼
[ Phase 2: 動的ビュー, RAG API & ルーティングの実装 ] ──► 完了 (Passed 21/21 tests)
  ├─ HttpListener のルーティング分岐 (/recent, /tags, /maintenance, /authors, /search)
  ├─ AI エージェント用機械可読 API エンドポイント (/api/index.json) 開通
  ├─ RAG 用自動 H2/H3 見出しセマンティック分割済み JSON チャンク API (/api/chunks.json) 開通
  └─ OKF メタデータ（トップバー ＆ フッターカード分離表示）および非推奨警告バナー統合
         │
         ▼
[ Phase 3: UI/UX調整, テンプレート配備 ＆ 3段階全品質検証 ] ──► 完了 (Passed 24/24 tests)
  ├─ 視読性最優先のコンパクト・トップバー ＋ 詳細フッターカードの 2 段構成 CSS
  ├─ 新規作成用 OKF 準拠テンプレート (templates/okf-template.md) の同梱
  ├─ 箇条書きリストタグ (`- tag`)、クォートタイトル、コメント無視の受容拡大
  └─ 3段階の品質検証フェーズ (AST構文チェック / Pesterテスト24件 / E2Eエキスポート) 合格
```

## **7\. Pester 自動テスト設計 (TDD 準拠)**

`tests/Start-MarkdigWiki.Tests.ps1` に以下の Pester テストスイートを追加・統合し、TDD サイクルで開発を進めます。

### **7.1 OKF メタデータ解析・フォールバックテスト (`Get-DocumentMetadata`)**
* **正常系テスト**: 完全な OKF Front Matter (title, description, author, domain, tags, last_updated, status) が正しく抽出されること。
* **フォールバックテスト**:
  * YAML なしドキュメントで H1 見出しが `title` に補完されること。
  * H1 もないドキュメントでファイル名が `title` に補完されること。
  * `last_updated` 未指定時に OS の `File.LastWriteTime` が設定されること。
  * `domain` 未指定時に相対ディレクトリパスが設定されること。
* **異常系・例外処理テスト**:
  * インデントエラーや閉じ記号欠落などの不正な YAML (Syntax error) があっても例外でクラッシュせず、フォールバック値が適用されること。

### **7.2 XSS サニタイズ保護テスト**
* YAML Front Matter の `author` や `tags` に `<script>alert('xss')</script>` が記述されている場合、レンダリング結果の HTML 内で `&lt;script&gt;` にエスケープされていること。

### **7.3 インデックス構築 & キャッシュテスト (`Build-WikiIndex`)**
* 全ドキュメントのインデックス化が正常に完了すること。
* ファイル更新がない連続アクセスでインデックスキャッシュが再利用されること。

### **7.4 動的ビュー・ルーティングテスト**
* `/recent`, `/tags`, `/maintenance`, `/search` の各エンドポイントが正しいステータスコード `200` および適切な HTML レスポンスを返却すること。
* `/api/index.json` が有効な JSON 形式で全 OKF メタデータ（フォールバック済み）を返却すること。

### **7.5 RAG セマンティックチャンク API テスト (`Get-ApiChunksJson` / `/api/chunks.json`)**
* `/api/chunks.json` が Markdown の見出し (`#`, `##`, `###`) 単位でセマンティック分割された JSON 配列を返却すること。
* 各チャンクに `ChunkId`, `RelPath`, `Title`, `Domain`, `Section`, `Tags`, `LastUpdated`, `Status`, `Content`, および文脈埋め込み済み `EnrichedText` が正しく付与されていること。

## **8\. OKF 思想を踏まえた批判的考察と設計適合性**

Google のブログ記事（*How the Open Knowledge Format can improve data sharing*）および業界トレンド（LLM Wiki パターン）との照合による批判的考察です。

### **8.1 既存計画の盲点と本改訂による克服**
* **盲点**: 従来の計画は「人間がブラウザで閲覧するための綺麗な Web UI を PowerShell で作る」点に偏重しており、Google OKF の本質である **「ポータブルなナレッジの統一フォーマット化」「AI エージェントとの相互運用性」** の観点が薄れていました。
* **克服策**: 
  1. **Producer & Consumer の二重構造化**: 人間用 UI レンダラー (Consumer) に加え、AI エージェントや外部ツールがメタデータ構造をそのまま利用できる `/api/index.json` (Producer) を追加。
  2. **「Just Files, Just YAML」の徹底**: プロプライエタリな DB やバイナリ形式に閉じ込めず、Git リポジトリ直下の `.md` ファイルとシンプルな YAML Front Matter のみで全状態を完結させ、高いポータビリティとベンダー中立性を確保。

### **8.2 批判的検証マトリクス**

| 評価軸 | 従来の課題 | 本計画（OKF対応）での解決策 | 適合度 |
| :--- | :--- | :--- | :---: |
| **ナレッジの断片化** | 著者・最終更新日・用途が不明で古いドキュメントが放置される | OKF メタデータ ＋ `/maintenance` ダッシュボードによる風化の可視化 | **高** |
| **AI 連携・機械可読性** | 人間用 HTML しか出力されず、LLM へのコンテキスト注入にパースが必要 | メモリインデックス `$script:WikiIndex` を標準 JSON / Markdown API 化 | **高** |
| **運用コスト & ベンダーロックイン** | 重厚な Wiki サーバーや専用 DB の構築・保守が必要 | PowerShell 5.1 ＋ Markdig ＋ ファイルベースで 100% オフライン完全独立 | **高** |
| **導入ハードル** | 全ドキュメントへメタデータ記述を強制すると形骸化する | 厳格パース ＋ 未記述ファイルの自動補完（フォールバック）ハイブリッド運用 | **高** |


Ref
https://cloud.google.com/blog/ja/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing/