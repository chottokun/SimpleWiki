# ==============================================================================
#  SimpleWiki - LLM API キー暗号化・設定ユーティリティ
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
param (
    [string]$ApiKey = "",
    [string]$ApiUrl = "",
    [string]$Model = "",
    [ValidateSet("Portable", "Dpapi", "Plain")][string]$Scope = "Portable",
    [string]$ConfigPath = ""
)

$scriptDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
$libDir    = Join-Path $scriptDir "lib"

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $targetConfig = Join-Path $scriptDir "config.json"
} else {
    $targetConfig = [System.IO.Path]::GetFullPath($ConfigPath)
}

# --- モジュールのロード (lib/WikiSecurity.ps1) ---
. (Join-Path $libDir "WikiSecurity.ps1")

# 既存設定の読み込み、無ければ example から生成
$configObj = $null
if (Test-Path $targetConfig) {
    try {
        $jsonRaw = Get-Content -Path $targetConfig -Raw -Encoding UTF8
        $configObj = $jsonRaw | ConvertFrom-Json
    } catch {
        $null = $_ # Suppressed intentionally
    }
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
    $protectedKey = switch ($Scope) {
        "Portable" { Protect-StringAes -PlainText $ApiKey }
        "Dpapi"    { Protect-StringDpapi -PlainText $ApiKey }
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
