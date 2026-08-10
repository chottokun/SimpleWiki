# ==============================================================================
#  SimpleWiki - LLM API キー暗号化・設定ユーティリティ
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================
param (
    [string]$ApiKey = "",
    [string]$ApiUrl = "",
    [string]$Model = "",
    [ValidateSet("Portable", "Dpapi", "Plain")][string]$Scope = "Portable",
    [string]$ConfigPath = ""
)

$scriptDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $targetConfig = Join-Path $scriptDir "config.json"
} else {
    $targetConfig = [System.IO.Path]::GetFullPath($ConfigPath)
}

function Protect-StringAes {
    param ([string]$PlainText)
    $salt = [System.Text.Encoding]::UTF8.GetBytes("SimpleWiki-OKF-RAG-2026-Salt")
    $pass = [System.Text.Encoding]::UTF8.GetBytes("SimpleWiki-Portable-Secret-Key-2026")
    $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($pass, $salt, 1000)
    $key = $derive.GetBytes(32)
    $iv  = $derive.GetBytes(16)

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key
    $aes.IV  = $iv
    $encryptor = $aes.CreateEncryptor()

    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $encBytes   = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
    return "ENC:" + [System.Convert]::ToBase64String($encBytes)
}

function Protect-StringDpapi {
    param ([string]$PlainText)
    $isWin = ($env:OS -eq "Windows_NT") -or $IsWindows
    if (-not $isWin) {
        throw [System.PlatformNotSupportedException]::new("DPAPI encryption is only supported on Windows.")
    }
    Add-Type -AssemblyName System.Security
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $enc   = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return "DPAPI:" + [System.Convert]::ToBase64String($enc)
}

# 既存設定の読み込み、無ければ example から生成
$configObj = $null
if (Test-Path $targetConfig) {
    try {
        $jsonRaw = Get-Content -Path $targetConfig -Raw -Encoding UTF8
        $configObj = $jsonRaw | ConvertFrom-Json
    } catch {}
}

if ($null -eq $configObj) {
    $examplePath = Join-Path $scriptDir "config.json.example"
    if (Test-Path $examplePath) {
        $jsonRaw = Get-Content -Path $examplePath -Raw -Encoding UTF8
        $configObj = $jsonRaw | ConvertFrom-Json
    } else {
        $configObj = [PSCustomObject]@{
            rag = [PSCustomObject]@{
                enabled        = $true
                apiUrl         = "http://localhost:11434/v1"
                apiKey         = ""
                model          = "qwen2.5-coder-7b-instruct"
                maxContextDocs = 3
                timeoutSec     = 30
                systemPrompt   = "あなたは社内Wikiのナレッジを元に回答するアシスタントです。提供されたコンテキスト情報のみに基づいて、正確かつ丁寧に回答してください。"
            }
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($ApiUrl)) {
    $configObj.rag.apiUrl = $ApiUrl
}

if (-not [string]::IsNullOrWhiteSpace($Model)) {
    $configObj.rag.model = $Model
}

if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
    $isWin = ($env:OS -eq "Windows_NT") -or $IsWindows
    $protectedKey = switch ($Scope) {
        "Portable" { Protect-StringAes -PlainText $ApiKey }
        "Dpapi"    {
            if (-not $isWin) {
                Write-Warning "DPAPI is only supported on Windows. Falling back to Portable (AES-256) encryption."
                Protect-StringAes -PlainText $ApiKey
            } else {
                Protect-StringDpapi -PlainText $ApiKey
            }
        }
        "Plain"    { $ApiKey }
    }
    $configObj.rag.apiKey = $protectedKey
}

$configObj.rag.enabled = $true

$jsonOutput = $configObj | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($targetConfig, $jsonOutput, [System.Text.Encoding]::UTF8)

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  LLM / RAG 設定の保存が完了しました" -ForegroundColor Green
Write-Host "  設定ファイル: $targetConfig" -ForegroundColor Yellow
Write-Host "  Base URL    : $($configObj.rag.apiUrl)" -ForegroundColor Cyan
Write-Host "  Model       : $($configObj.rag.model)" -ForegroundColor Cyan
if (-not [string]::IsNullOrWhiteSpace($configObj.rag.apiKey)) {
    Write-Host "  API Key     : $($configObj.rag.apiKey.Substring(0, [Math]::Min(12, $configObj.rag.apiKey.Length)))..." -ForegroundColor Cyan
}
Write-Host "==========================================================" -ForegroundColor Green
