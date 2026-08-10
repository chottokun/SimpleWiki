# SimpleWiki

Windows PowerShell 5.1 / PowerShell 7+ および Windows 11 環境で動作する **100% オフライン対応 Markdown Wiki サーバー ＆ LLM RAG AI チャット ＆ 静的 HTML エキスポートツール** です。

---

## プロジェクト記録 (Evidence-Based Project Record)

- **開発目的**:
  1. 任意ディレクトリの Markdown ドキュメント群を閉域網・オフライン環境で即座に Web Wiki 化。
  2. IIS, Nginx, Apache などの外部 Web サーバー向けに一括で静的 HTML サイトを生成・デプロイ。
  3. WinRT 形態素解析と LLM RAG による閉域網・ローカル AI チャットアシスタントの統合。
  4. GUI ツール (`Export-GUI.bat`) による直感的なフォルダ選択とエキスポート。
- **アーキテクチャ概要**:
  - **リアルタイム閲覧 & OKF ナレッジハブ**: `System.Net.HttpListener` によるローカル Web サーバー (`http://localhost:8080/`)
  - **🤖 2モード制 LLM RAG AI チャットアシスタント ＆ POST `/api/chat` API**:
    - **⚡ Fast RAG (高速1-Pass)** / **🧠 Agentic RAG (ReAct自律調査)** の2モード選択トグル機能。
    - **4つの Agentic Tools**: `search_okf` (重み付け検索), `lookup_glossary` (用語定義抽出), `read_doc` (本文取得・非推奨警告), `get_linked_docs` (相対リンク追跡) による自律探索。
    - **思考プロセス (`thinkingLog`) の可視化**: UI 上でのアコーディオン開閉による探索ステップ追跡。
    - さくら AI API / Ollama / LM Studio / OpenAI 等の各種 REST LLM エンドポイントへ対応。
    - **WinRT 日本語形態素解析 (`Get-JapaneseWordsWinRT`)**: Windows 10/11 OS 内蔵の `Windows.Data.Text.WordsSegmenter` による完全依存 0 の分かち書き ＆ 助詞ストップワード自動除去。
    - **マルチターン対話履歴 (history) 管理 ＆ 安全文字数ガード**: `config.json` で可変調整（`maxHistoryTurns: 3`, `maxHistoryChars: 4000`, `maxAgentTurns: 5`, `maxDocCharLength: 2000`）。
    - **高度なチャット UI**: Markdown 表（`<table>`）、コードブロック（`<pre><code>`）、リストの完全描画、`📋 コピー` ボタン、`⛶ 拡大/縮小` トグル、`🧹 履歴クリア` ボタンを標準搭載。
  - **🔒 API Key 暗号化ユーティリティ (`Set-ApiKey.bat` / `Set-ApiKey.ps1`)**:
    - Windows DPAPI またはポータブル AES-256 暗号化（`ENC:...` / `DPAPI:...`）により、`config.json` 内の API キーを安全に保護。
  - **Google OKF (Open Knowledge Format) 思想の準拠**: YAML Front Matter からの文脈抽出・自動補完 (フォールバック)・OKF メタデータカード描画
  - **AI エージェント / LLM 用機械可読 API**: `/api/index.json` (メタデータ), `/api/chunks.json` (自動セマンティック分割チャンク), `/api/chat` (AI チャット)
  - **動的ナビゲーション & ビュー**: 最近の更新 (`/recent`), タグ集計/検索 (`/tags`), 品質・メンテナンスダッシュボード (`/maintenance`), 著者ディレクトリ (`/authors`), AND 検索 (`/search`)
  - **静的エキスポート**: `Export-MarkdigWiki.ps1` による OKF メタデータカード同梱型 HTML 一括出力
  - **Markdown レンダリング**: .NET 4.6.2 ビルド版 `Markdig.dll` (GFM テーブル・コードブロック・タスクリスト・YamlFrontMatter 対応)
  - **図形・ダイアグラム**: `lib/mermaid.min.js` 同梱による 100% オフライン Mermaid ダイアグラム表示
- **セキュリティ機能**:
  - `[System.IO.Path]::GetFullPath` による絶対パス判定でのディレクトリトラバーサル防止 (`403 Forbidden`)。
  - `[System.Net.WebUtility]::HtmlEncode` による YAML 属性値・パスの XSS サニタイズ。
- **ファイルエンコーディング規約 (`AGENTS.md`)**:
  - スクリプトファイル (`.ps1`): **UTF-8 with BOM (`EF BB BF`)** (Windows PowerShell 5.1 での日本語化け防止)
  - バッチファイル (`.bat`): **UTF-8 without BOM (No-BOM)** (`cmd.exe` の `・ｿ` エラー防止)

---

## フォルダ構成

```text
SimpleWiki/
├── Start-MarkdigWiki.ps1   <-- Web サーバー & RAG AI チャット起動スクリプト (UTF-8 with BOM)
├── Start-MarkdigWiki.bat   <-- Web サーバー起動バッチ (UTF-8 No-BOM)
├── Set-ApiKey.ps1          <-- LLM API キー暗号化・設定スクリプト (UTF-8 with BOM)
├── Set-ApiKey.bat          <-- API キー設定用 ExecutionPolicy Bypass バッチ (UTF-8 No-BOM)
├── Export-MarkdigWiki.ps1  <-- OKF 対応静的 HTML エキスポートスクリプト (UTF-8 with BOM)
├── Export-MarkdigWiki.bat  <-- 静的 HTML エキスポートバッチ (UTF-8 No-BOM)
├── Export-GUI.ps1          <-- 静的 HTML エキスポート GUI (UTF-8 with BOM)
├── Export-GUI.bat          <-- GUI 起動用バッチ (UTF-8 No-BOM)
├── config.json.example     <-- LLM RAG 設定ファイルテンプレート
├── config.json             <-- ローカル LLM RAG 設定（自動生成・暗号化保存）
├── templates/
│   └── okf-template.md     <-- OKF 準拠ドキュメント新規作成テンプレート
├── lib/
│   ├── Markdig.dll          <-- .NET Framework 4.6.2 ビルド版 Markdig.dll
│   ├── System.Memory.dll    <-- .NET 4.8 依存アセンブリ
│   └── mermaid.min.js       <-- オフライン用 Mermaid.js (MIT License)
├── markdown_sample/         <-- サンプルドキュメントフォルダ (OKF メタデータ記述例付き)
│   ├── index.md             <-- トップページ
│   ├── 概要.md               <-- プロジェクト概要
│   ├── docs/
│   │   ├── 詳細仕様.md       <-- サブフォルダ内サンプル
│   │   └── api/
│   │       └── REST-API.md   <-- REST API 仕様書 & AI Agent 連携ガイド
│   └── images/
│       └── architecture.svg <-- サンプル SVG 画像
├── tests/
│   └── Start-MarkdigWiki.Tests.ps1 <-- Pester 自動テストスイート (全50件)
└── README.md                <-- プロジェクト記録
```

---

## 使い方

### 1. 静的 HTML エキスポート GUI ツール (推奨)

`Export-GUI.bat` をダブルクリックして起動します。

1. **入力 Markdown フォルダ** を参照ボタン（または直接入力）で選択します。
2. **出力先 HTML フォルダ** を選択します。
3. **[🚀 エキスポート実行]** ボタンを押すと、一括で静的 HTML サイトが生成されます。
4. 完了後、ダイアログから出力先フォルダを直接エクスプローラーで開くことができます。

---

### 2. リアルタイム Wiki サーバー ＆ OKF ナレッジハブの起動

#### サンプルドキュメント (`markdown_sample/`) を閲覧する
`Start-MarkdigWiki.bat` をダブルクリックします。

#### 任意のフォルダのドキュメントを閲覧する
- **ドラッグ＆ドロップ**: 閲覧したい Markdown フォルダを `Start-MarkdigWiki.bat` にドラッグ＆ドロップします。
- **PowerShell から実行**:
  ```powershell
  .\Start-MarkdigWiki.ps1 -RootFolder "D:\MyDocs\ProjectWiki" -Port 8080
  ```

#### 提供エンドポイント / 機能
- **`http://localhost:8080/`**: ホーム・Markdown 閲覧画面 (OKF メタデータ付き)
- **`http://localhost:8080/recent`**: 最近の更新ドキュメント一覧
- **`http://localhost:8080/tags`**: タグ目録 / タグクラウド
- **`http://localhost:8080/maintenance`**: 風化ドキュメント (>365日)・下書き・非推奨の管理画面
- **`http://localhost:8080/authors`**: 著者一覧ディレクトリ
- **`http://localhost:8080/search?q=キーワード`**: 全文検索
- **`http://localhost:8080/api/index.json`**: AI エージェント / LLM 用機械可読 JSON インデックス
- **`http://localhost:8080/api/chunks.json`**: RAG 用自動 H2 見出しセマンティック分割済み JSON チャンク API

---

### 3. バッチ / コマンドラインでのエキスポート

#### サンプルドキュメントを `dist/` へ変換する
`Export-MarkdigWiki.bat` をダブルクリックします。

#### 任意フォルダのドキュメントをエキスポートする
- **ドラッグ＆ドロップ**: 変換したい Markdown フォルダを `Export-MarkdigWiki.bat` にドラッグ＆ドロップします。
- **PowerShell から実行**:
  ```powershell
  .\Export-MarkdigWiki.ps1 -RootFolder "D:\MyDocs\ProjectWiki" -OutputDir "C:\inetpub\wwwroot\wiki"
  ```

---

## 依存ライブラリと Windows 11 互換性について

### **完全スタンドアロン（追加インストール不要）**
- **Windows 11 標準動作保証**: Windows 11 に標準でプリインストールされている **Windows PowerShell 5.1** および **.NET Framework 4.8** の環境のみでそのまま起動・動作します。
- **事前同梱ライブラリ (`lib/`)**:
  - `Markdig.dll`: .NET Framework 4.6.2 ビルド版 Markdown パーサー (GFM / YAML Front Matter 対応)
  - `System.Memory.dll` / `System.Buffers.dll` / `System.Numerics.Vectors.dll` / `System.Runtime.CompilerServices.Unsafe.dll`: .NET 依存補助アセンブリ
  - `mermaid.min.js`: オフライン表示用 Mermaid.js ライブラリ
- **インターネット接続不要**: `nuget` や `npm` によるオンラインパッケージ取得、管理者権限のインストール作業は一切不要です。リポジトリを展開するだけで 100% 閉域網・オフライン環境で動作します。

---

## テストと品質検証

### 3段階の品質検証フェーズ (Syntax AST / Pester / E2E Export)
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path .\tests\Start-MarkdigWiki.Tests.ps1"
```
- **検証結果**: 全 40 件の Pester 自動テストが **100% PASS**。
  - **1. スクリプト構文・AST検証**: 全 `.ps1` ファイルの構文解析・トークン検証に合格
  - **2. Pester 単体・統合・セキュリティテスト (全 40 件)**:
    - Markdig アセンブリロード & GFM パイプライン構築
    - ディレクトリトラバーサル防止 (`403 Forbidden`)
    - XSS サニタイズ (404 パス、タイトル、検索フォーム、OKF 属性値)
    - OKF メタデータ解析・YAML パース例外処理・自動補完 (フォールバック)・カンマ区切りタグ対応
    - OKF 動的ビュー生成 (`/recent`, `/tags`, `/maintenance`, `/authors`, `/search`)
    - OKF 文脈検索エンジン重み付けスコアリング & AND 条件検索
    - 全角スペース（`U+3000`）による検索単語分解対応
    - URL エンコードされた UTF-8 日本語クエリパラメータのデコード (`Get-QueryParams`)
    - クライアント接続切断時のソケット例外非破壊保護 (`Write-SafeHttpResponse`)
    - AI エージェント用 API JSON 出力 (`/api/index.json`)
    - RAG 用セマンティックチャンク自動分割 API 出力 (`/api/chunks.json`)
    - 静的 HTML エキスポート (`Export-MarkdigWiki.ps1`) とトップバー/フッターメタデータカード統合
  - **3. E2E エキスポート検証**: 実フォルダでの全 HTML 相互リンク・CSS/JS 出力検証に成功

---

## ライセンス・第三者ソフトウェア表記について

* **本プロジェクト (SimpleWiki)**: **MIT License**
* **第三者オープンソースアセンブリ / ライブラリ**:
  - `Markdig.dll`: MIT License
  - `mermaid.min.js`: MIT License
  - `.NET System.*` アセンブリ: MIT License (by .NET Foundation)

詳細なライセンス全文および著作権表示は [LICENSE.md](LICENSE.md) をご覧ください。商用・個人利用・社内展開を含め自由に再配布いただけます。

