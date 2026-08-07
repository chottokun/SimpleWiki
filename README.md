# SimpleWiki

Windows PowerShell 5.1 / PowerShell 7+ および Windows 11 環境で動作する 100% オフライン対応の Markdown Wiki サーバー ＆ 静的 HTML エキスポートツールです。

## プロジェクト記録 (Evidence-Based Project Record)

- **開発目的**:
  1. 任意ディレクトリの Markdown ファイルを閉域網・オフライン環境で即座に Web Wiki 化。
  2. IIS, Nginx, Apache などの外部 Web サーバー向けに一括で静的 HTML サイトを生成・デプロイ。
- **機能概要**:
  - `Start-MarkdigWiki.ps1` / `.bat`: HTTP サーバー形式によるリアルタイム閲覧（任意フォルダ指定 `-RootFolder` 対応）。
  - `Export-MarkdigWiki.ps1` / `.bat`: マークダウン群を静的 `.html` サイトへ一括変換（本文内・サイドバーの `.md` 相互リンクを `.html` へ自動変換）。
- **セキュリティ対策**:
  - Absolute Path 判定によるディレクトリトラバーサル防止 (`403 Forbidden`)。
  - `HtmlEncode` による XSS サニタイズ。
- **エンコーディング規定 (`AGENTS.md`)**:
  - `.ps1` スクリプト: UTF-8 with BOM (`EF BB BF`)
  - `.bat` バッチファイル: UTF-8 without BOM (No-BOM)

---

## 使い方

### 1. リアルタイム Wiki サーバーの起動

#### このレポジトリのドキュメントを閲覧する
`Start-MarkdigWiki.bat` をダブルクリックします。

#### 任意のフォルダのドキュメントを閲覧する
- **ドラッグ＆ドロップ**: 閲覧したい Markdown フォルダを `Start-MarkdigWiki.bat` にドラッグ＆ドロップします。
- **PowerShell から実行**:
  ```powershell
  .\Start-MarkdigWiki.ps1 -RootFolder "D:\MyDocs\ProjectWiki" -Port 8080
  ```

---

### 2. 静的 HTML サイトへのエキスポート (Web サーバー配信用)

#### このレポジトリの全ドキュメントを `dist/` へ変換・出力する
`Export-MarkdigWiki.bat` をダブルクリックします。

#### 任意フォルダのドキュメントを静的 HTML 化する
- **ドラッグ＆ドロップ**: 変換したい Markdown フォルダを `Export-MarkdigWiki.bat` にドラッグ＆ドロップします。
- **PowerShell から実行**:
  ```powershell
  .\Export-MarkdigWiki.ps1 -RootFolder "D:\MyDocs\ProjectWiki" -OutputDir "C:\inetpub\wwwroot\wiki"
  ```
  ※ 本文およびサイドバー内の `.md` への相互リンクがすべて `.html` に置換され、完全に独立した静的 Web サイトとして動作します。

---

## テストと検証

### Pester 自動テスト
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path .\tests\Start-MarkdigWiki.Tests.ps1"
```
- **検証結果**: 全 8 件のテストをパス（Markdig ロード、任意フォルダ閲覧、パス安全性、XSS サニタイズ、HTML エキスポートおよび `.html` リンク変換）。
