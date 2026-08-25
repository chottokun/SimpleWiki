# PowerShell 配布（powershell-distribution）スキル 利用ガイド

`powershell-distribution` は、PowerShell スクリプトやモジュールを **「エンドユーザー（一般社員/非エンジニア）」** や **「運用管理者・CI/CD」** 向けに安全・確実・簡単にパッケージング・配布するための Antigravity 専門スキルです。

---

## 1. クイックスタート：Antigravity での利用方法

本スキルは自動認識（Progressive Disclosure）に対応しているため、チャットで以下のように自然言語で指示するだけで、最適なテンプレートやスクリプトを用いて作業を代行・アシストします。

### よくあるプロンプト例（エージェントへの指示）

| 目的 | プロンプト例 | エージェントの動作 |
| :--- | :--- | :--- |
| **新規プロジェクト作成** | `「配布を見据えたPowerShellツールのプロジェクトを新規作成して」` | `src/`, `tests/`, `build/`, `docs/` を自動生成し `build.ps1` をセットアップ |
| **既存スクリプトのバッチ化** | `「この .ps1 を社内配布用にダブルクリックで動くバッチにして」` | `New-BatchPackage.ps1` を使って Bypass/UTF-8対応の `.bat` を生成 |
| **管理者権限ツールの配布** | `「UACダイアログを出して管理者として実行するランチャーを作って」` | `launcher-elevated.bat` を適用して管理者昇格ランチャーを生成 |
| **1ファイルでの配布** | `「メール添付しやすいように1ファイル完結のハイブリッドバッチにして」` | `hybrid-single-file.bat` 形式で .bat 内にスクリプトを内包 |
| **リリースビルド** | `「distフォルダにリリース用ZIPとバッチを作成して」` | `build.ps1` を実行し、UTF-8 BOM正規化とパッケージングを実施 |
| **モジュール事前診断** | `「このモジュールがPSGallery/社内リポジトリに公開できるか検証して」` | `Test-ModuleReadiness.ps1` で構文・マニフェスト整合性を自動チェック |

---

## 2. コマンドラインツール（直接実行する場合）

本スキルに同梱されている PowerShell スクリプトは、ターミナルから直接実行することも可能です。

### ① プロジェクトの雛形作成（`New-PowerShellProject.ps1`）
配布を見据えた標準ディレクトリ構造（`src/`, `tests/`, `build/`, `docs/`）を一発で作成します。

```powershell
# 単体ツール向けプロジェクトを作成
powershell -ExecutionPolicy Bypass -File .agents/skills/powershell-distribution/scripts/New-PowerShellProject.ps1 -ProjectPath "C:\Projects\MyTool" -Type Tool

# モジュール開発向けプロジェクトを作成
powershell -ExecutionPolicy Bypass -File .agents/skills/powershell-distribution/scripts/New-PowerShellProject.ps1 -ProjectPath "C:\Projects\MyModule" -Type Module
```

---

### ② バッチラッパーの自動生成（`New-BatchPackage.ps1`）
任意の `.ps1` から指定した形式のバッチファイルや配布用 ZIP を即座に生成します。

```powershell
# 通常のダブルクリックランチャー（実行後に結果画面を維持）
powershell -ExecutionPolicy Bypass -File .agents/skills/powershell-distribution/scripts/New-BatchPackage.ps1 -ScriptPath ".\MyScript.ps1" -Type Basic -IncludePause

# 管理者権限（UAC昇格）自動要求バッチ
powershell -ExecutionPolicy Bypass -File .agents/skills/powershell-distribution/scripts/New-BatchPackage.ps1 -ScriptPath ".\Setup.ps1" -Type Elevated

# 単一ファイル完結型ハイブリッド（.bat内にPS1を内包）
powershell -ExecutionPolicy Bypass -File .agents/skills/powershell-distribution/scripts/New-BatchPackage.ps1 -ScriptPath ".\Diagnostics.ps1" -Type Hybrid

# バッチとスクリプトをまとめて ZIP パッケージ化
powershell -ExecutionPolicy Bypass -File .agents/skills/powershell-distribution/scripts/New-BatchPackage.ps1 -ScriptPath ".\MyTool.ps1" -Type Basic -CreateZip
```

---

### ③ 配布前健全性診断（`Test-ModuleReadiness.ps1`）
公開前にマニフェスト（`.psd1`）の構文、エクスポート関数の一致、AST構文解析を行います。

```powershell
powershell -ExecutionPolicy Bypass -File .agents/skills/powershell-distribution/scripts/Test-ModuleReadiness.ps1 -Path ".\src\MyModule"
```

---

## 3. リファレンス & テンプレート構成一覧

| ファイル | 種別 | 説明 |
| :--- | :--- | :--- |
| [`SKILL.md`](./SKILL.md) | スキル定義 | Antigravity が読み込むメイン指示書 |
| [`references/project-structure-and-build.md`](./references/project-structure-and-build.md) | リファレンス | 開発ディレクトリと配布用 `dist/` の分離設計 |
| [`references/encoding-and-compatibility.md`](./references/encoding-and-compatibility.md) | リファレンス | 日本語文字化け対策（UTF-8 BOM）と PS 5.1 / 7+ 混在対応 |
| [`references/batch-distribution-patterns.md`](./references/batch-distribution-patterns.md) | リファレンス | バッチランチャーの仕組み、UAC昇格、引数転送の技術詳細 |
| [`references/manifest-and-versioning.md`](./references/manifest-and-versioning.md) | リファレンス | `.psd1` マニフェスト設計とセマンティックバージョニング |
| [`references/repositories-and-publishing.md`](./references/repositories-and-publishing.md) | リファレンス | PSResourceGet, PSGallery, Azure, 内部SMB共有での公開 |
| [`references/signing-and-security.md`](./references/signing-and-security.md) | リファレンス | Authenticode デジタル署名と ExecutionPolicy 対策 |
| [`templates/build.ps1.template`](./templates/build.ps1.template) | テンプレート | `src/` から `dist/` を自動生成・検証するビルドスクリプト雛形 |
| [`templates/launcher-basic.bat.template`](./templates/launcher-basic.bat.template) | テンプレート | 標準ダブルクリックランチャー雛形 |
| [`templates/launcher-elevated.bat.template`](./templates/launcher-elevated.bat.template) | テンプレート | UAC自動昇格ランチャー雛形 |
| [`templates/hybrid-single-file.bat.template`](./templates/hybrid-single-file.bat.template) | テンプレート | 単一ファイルハイブリッド雛形 |
| [`templates/installer.bat.template`](./templates/installer.bat.template) | テンプレート | アプリ配置＆デスクトップショートカット作成インストーラー雛形 |
| [`templates/module-manifest.psd1.template`](./templates/module-manifest.psd1.template) | テンプレート | 高速・安全なモジュールマニフェスト雛形 |

---

## 4. トラブルシューティング（よくある問題と解決法）

### Q1. PowerShell 5.1 環境で実行すると日本語が文字化け・構文エラーになる
- **原因**: スクリプトが「BOMなしUTF-8」で保存されているため、5.1 が Shift-JIS (CP932) と誤認しています。
- **解決策**: ファイルを **「UTF-8 with BOM」** で保存し直してください。`build.ps1` を実行すれば全ファイルが自動的に UTF-8 with BOM に正規化されます。

### Q2. バッチファイルをダブルクリックすると一瞬でウィンドウが閉じてしまう
- **原因**: スクリプトがエラーで終了したか、正常終了時に画面が閉じている。
- **解決策**: `New-BatchPackage.ps1` に `-IncludePause` を付けるか、バッチ末尾に `pause` を配置してください。

### Q3. 管理者権限が必要なのに「アクセスが拒否されました」となる
- **原因**: 一般権限で実行されている。
- **解決策**: `-Type Elevated` を指定して、自動で UAC ダイアログを表示するランチャーを生成してください。
