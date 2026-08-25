# PowerShell 日本語文字化け対策 & 5.1 / 7+ 混在環境ベストプラクティス

本ドキュメントでは、日本語Windows環境における PowerShell 5.1（Windows標準）と PowerShell 7+（Core）の混在環境で発生する **文字化け問題** および **互換性トラブル** を完全に解決するための黄金律を解説します。

---

## 1. 日本語文字化けのメカニズムと黄金律

### 1.1 なぜ文字化けが起きるのか？

| 項目 | Windows PowerShell 5.1 (Desktop) | PowerShell 7+ (Core) | 混在時のリスク |
| :--- | :--- | :--- | :--- |
| **`.ps1` / `.psd1` 読込** | **BOMなしは ANSI (CP932/Shift-JIS) と判定** | **BOMなしでも UTF-8 と判定** | 5.1で日本語コメント・文字列が盛大に文字化け |
| **コンソール標準入出力** | OEMコードページ（CP932） | UTF-8 | バッチ経由の出力で日本語が化ける |
| **`Out-File` / `>` の既定** | **UTF-16 LE (Unicode)** | **UTF-8 (BOMなし)** | 生成ファイルの互換性問題 |
| **`Set-Content` の既定** | **ANSI (CP932)** | **UTF-8 (BOMなし)** | 意図しないエンコーディング変換 |

---

### 1.2 混在環境における文字コードの「黄金律」

#### 規則 1: スクリプトファイル（`.ps1`, `.psd1`, `.psm1`）は必ず「UTF-8 with BOM」で保存する
- **理由**: Windows PowerShell 5.1 はファイルの先頭に BOM（Byte Order Mark: `EF BB BF`）がある場合のみ UTF-8 として認識します。BOM が無いと Shift-JIS (CP932) で解釈され、日本語の構文エラーや文字化けが発生します。PowerShell 7+ は BOM の有無にかかわらず UTF-8 を正常に解釈できるため、**「UTF-8 with BOM」が 5.1 / 7+ 双方で最も安全な共通フォーマット** です。

#### 規則 2: バッチファイル（`.bat`）の冒頭で `chcp 65001` を実行する
- バッチファイルの冒頭で `chcp 65001 >nul 2>&1` を実行し、cmd のコードページを UTF-8 に切り替えます。

#### 規則 3: スクリプト内でコンソール出力を UTF-8 に固定する
- スクリプトやバッチランチャーの起動オプションで以下を設定します：

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
```

#### 規則 4: ファイル入出力時は必ず `-Encoding` を明示する
```powershell
# 読み込み
Get-Content -Path ".\data.txt" -Encoding UTF8

# 書き込み（5.1/7+ 共通で安全な明示指定）
Set-Content -Path ".\output.txt" -Value $data -Encoding UTF8
```

---

## 2. PowerShell 5.1 と 7+ の構文・API 互換性ガイド

混在環境向けに配布するスクリプトでは、**PS 5.1 で動作し、PS 7+ でも警告なく動くコード** を書く必要があります。

### 2.1 避けるべき PS 7+ 専用構文（5.1 で構文エラーになるもの）

| 避けるべき構文 (PS 7+) | 互換性のある書き方 (5.1 & 7+ 共通) | 理由 |
| :--- | :--- | :--- |
| **三項演算子**<br/>`$val = $cond ? $a : $b` | `if ($cond) { $val = $a } else { $val = $b }` | 5.1 ではパースエラーになる |
| **Null合体演算子**<br/>`$val = $a ?? $b`<br/>`$a ??= $b` | `if ($null -eq $a) { $val = $b } else { $val = $a }` | 5.1 ではパースエラーになる |
| **パイプライン並列**<br/>`ForEach-Object -Parallel { ... }` | `ForEach-Object { ... }` または `Start-ThreadJob` / Runspace | 5.1 には `-Parallel` パラメーターがない |

---

### 2.2 避けるべきレガシーコマンド（PS 7+ で廃止・動作しないもの）

| 廃止・非推奨コマンド (5.1) | 互換性のある推奨コマンド (5.1 & 7+ 共通) | 理由 |
| :--- | :--- | :--- |
| `Get-WmiObject` | `Get-CimInstance` | PS 7+ で `*-Wmi*` コマンドレットが完全廃止 |
| `gwmi win32_operatingsystem` | `Get-CimInstance -ClassName Win32_OperatingSystem` | 同上 |

---

## 3. モジュール配置パスの混在対応

ユーザーやシステム環境にモジュールを配置する場合、5.1 と 7+ では既定のモジュール探索パスが異なります。

| 対象 | Windows PowerShell 5.1 | PowerShell 7+ |
| :--- | :--- | :--- |
| **ユーザー固有** | `$HOME\Documents\WindowsPowerShell\Modules` | `$HOME\Documents\PowerShell\Modules` |
| **全ユーザー (Program Files)** | `C:\Program Files\WindowsPowerShell\Modules` | `C:\Program Files\PowerShell\Modules` |

### 両対応インストーラーの設計
インストーラーバッチまたはスクリプトでは、両方のディレクトリが存在するか確認し、両方にコピーするか、共通のカスタムパス（例: `C:\Tools\Modules`）に配置して `$env:PSModulePath` に追加するのがベストプラクティスです。

---

## 4. バッチランチャーでの自動エンジン選択

バッチファイル側で `pwsh.exe`（PowerShell 7+）の有無を判定し、インストールされていればモダンエンジンで高速実行、無ければ標準の `powershell.exe`（5.1）へフォールバックします。

```batch
where pwsh >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set "PS_EXE=pwsh"
) else (
    set "PS_EXE=powershell.exe"
)

"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
```
