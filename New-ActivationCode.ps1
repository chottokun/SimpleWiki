# ==============================================================================
#  SimpleWiki - マシンバインド・アクティベーションコード発行ツール (管理者用)
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================
param (
    [string]$ApiKey = "",
    [string]$MachineId = "",
    [string]$Email = "",
    [switch]$Legacy
)

$scriptDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
$libDir    = Join-Path $scriptDir "lib"

# --- モジュールのロード (lib/WikiSecurity.ps1) ---
. (Join-Path $libDir "WikiSecurity.ps1")

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  SimpleWiki アクティベーションコード生成ツール" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green

# 1. API キーの入力（未指定時に対話取得）
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    # 既存の config.json から自動検出を試みる
    $configPath = Join-Path $scriptDir "config.json"
    $defaultKey = ""
    if (Test-Path $configPath) {
        try {
            $cfg = Get-ConfigJson -TargetScriptDir $scriptDir
            if ($cfg.rag -and $cfg.rag.apiKey) {
                $resolved = Get-ResolvedSecret -SecretValue $cfg.rag.apiKey
                if ($resolved) { $defaultKey = $resolved }
            }
        } catch {}
    }

    if ($defaultKey) {
        $masked = $defaultKey.Substring(0, [Math]::Min(8, $defaultKey.Length)) + "..."
        $inputKey = Read-Host "API キーを入力してください (空欄で config.json の既存キー [$masked] を使用)"
        $ApiKey = if ([string]::IsNullOrWhiteSpace($inputKey)) { $defaultKey } else { $inputKey }
    } else {
        while ([string]::IsNullOrWhiteSpace($ApiKey)) {
            $ApiKey = Read-Host "API キー (sk-... 等) を入力してください"
        }
    }
}

# 2. 方式の選択 / マシンIDの入力
$localMachineId = Get-MachineFingerprint
$isLegacy = $Legacy
if (-not $isLegacy -and [string]::IsNullOrWhiteSpace($MachineId)) {
    Write-Host "`n発行タイプを選択してください:" -ForegroundColor Cyan
    Write-Host "  [1] マシン固有ロック形式 (推奨: 指定PC専用)" -ForegroundColor White
    Write-Host "  [2] 従来ポータブル形式 (どのPCでも動作する共通コード)" -ForegroundColor White
    $typeChoice = Read-Host "選択 (1 または 2 / 既定値: 1)"
    if ($typeChoice -eq "2") {
        $isLegacy = $true
    } else {
        $inputMachine = Read-Host "ユーザーのマシンID (例: $localMachineId) を入力してください (空欄で自PCのID)"
        $MachineId = if ([string]::IsNullOrWhiteSpace($inputMachine)) { $localMachineId } else { $inputMachine }
    }
}

$activationCode = ""
if ($isLegacy -or $MachineId -eq "PORTABLE" -or $MachineId -eq "ALL") {
    $activationCode = Protect-StringAes -PlainText $ApiKey
    $typeLabel = "従来ポータブル形式 (共通)"
    $MachineId = "ALL (どのPCでも動作可能)"
} else {
    # 3. メールアドレスの入力（任意）
    if ([string]::IsNullOrWhiteSpace($Email)) {
        $inputEmail = Read-Host "ユーザーのメールアドレスを入力してください (任意 / なしの場合は Enter)"
        $Email = if ([string]::IsNullOrWhiteSpace($inputEmail)) { "" } else { $inputEmail.Trim() }
    }
    $activationCode = Protect-ActivationCode -ApiKey $ApiKey -MachineId $MachineId -Email $Email
    $typeLabel = "マシン固有ロック形式"
}

# クリップボードへのコピー試行
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    [System.Windows.Forms.Clipboard]::SetText($activationCode)
    $clipMsg = " (クリップボードにコピーしました)"
} catch {
    $clipMsg = ""
}

Write-Host "`n----------------------------------------------------------" -ForegroundColor Yellow
Write-Host "  対象マシンID : $MachineId" -ForegroundColor Cyan
if ($Email) {
    Write-Host "  対象メール   : $Email" -ForegroundColor Cyan
}
Write-Host "  発行コード   : $activationCode$clipMsg" -ForegroundColor Green
Write-Host "----------------------------------------------------------" -ForegroundColor Yellow
Write-Host "※ ユーザーにこの『発行コード』をお伝えください。" -ForegroundColor White
Write-Host "   ユーザー側の設定画面で入力すると自動でアクティベーションされます。`n" -ForegroundColor White
