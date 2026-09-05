# ==============================================================================
#  Markdig + PowerShell 100% オフライン対応 Wiki サーバー
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
param (
    [int]$Port = 8080,
    [string]$RootFolder = "",
    [switch]$DotSourceOnly
)

# スクリプト自身のディレクトリ ($PSScriptRoot) から lib フォルダを参照
$scriptDir = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "lib"))) {
    [System.IO.Path]::GetFullPath($PSScriptRoot)
} elseif ($PSScriptRoot) {
    [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
} else {
    [System.IO.Path]::GetFullPath($PWD.Path)
}
$libDir = Join-Path $scriptDir "lib"

# --- モジュールのロード (lib/*.ps1) ---
. (Join-Path $libDir "WikiI18n.ps1")
. (Join-Path $libDir "WikiMetadata.ps1")
. (Join-Path $libDir "WikiSecurity.ps1")
. (Join-Path $libDir "WikiSearch.ps1")
. (Join-Path $libDir "WikiRag.ps1")
. (Join-Path $libDir "WikiViews.ps1")
. (Join-Path $libDir "WikiEditorTemplate.ps1")
. (Join-Path $libDir "WikiServer.ps1")

# ドキュメントルートの設定 (指定がない場合は markdown_sample フォルダ、存在しない場合は $PSScriptRoot)
$wikiDir     = Get-WikiDir -RootFolder $RootFolder -TargetScriptDir $scriptDir

# --- Markdig.dll および依存ライブラリのロード ---
$markdigDll = Join-Path $libDir "Markdig.dll"
if (-not (Test-Path $markdigDll)) {
    Write-Error "'lib' フォルダに Markdig.dll が見つかりません:`n$markdigDll"
    exit 1
}

Get-ChildItem -Path $libDir -Filter "*.dll" | ForEach-Object {
    if ($IsWindows -or $env:OS -eq "Windows_NT") {
        Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
    }
    Add-Type -Path $_.FullName
}

Import-ExternalI18n -TargetScriptDir $scriptDir

if ($DotSourceOnly) { return }

if ($MyInvocation.InvocationName -eq '.') { return }

# --- HttpListener の起動 ---
$listener = New-Object System.Net.HttpListener
$prefix   = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
} catch {
    Write-Error "ポート $Port でのサーバー起動に失敗しました。既に起動していないか確認してください。"
    exit 1
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  Markdig 完全オフライン Wiki サーバー起動中" -ForegroundColor Green
Write-Host "  ドキュメントルート: $wikiDir" -ForegroundColor Yellow
Write-Host "  URL: $prefix" -ForegroundColor Cyan
Write-Host "  ※ 終了するにはこのウィンドウで [Ctrl + C] を押してください" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Green

# 起動時インデックス事前生成 (ノンブロッキング・バックグラウンド実行)
$initCfg = Get-ConfigJson -TargetScriptDir $scriptDir
$bgIndexingJob = $null
if ($initCfg.search -and $initCfg.search.prebuildIndex -eq $true) {
    try {
        if (-not (Load-WikiIndexCache -TargetWikiDir $wikiDir -TargetScriptDir $scriptDir)) {
            Write-Host "インデックスをバックグラウンドで事前生成中..." -ForegroundColor Cyan
            $jobScript = [scriptblock]::Create("
                param(`$wDir, `$sDir)
                . (Join-Path `$sDir 'lib/WikiI18n.ps1')
                . (Join-Path `$sDir 'lib/WikiMetadata.ps1')
                . (Join-Path `$sDir 'lib/WikiSearch.ps1')
                Build-WikiIndex -TargetWikiDir `$wDir -ForceRefresh | Out-Null
                Save-WikiIndexCache -TargetWikiDir `$wDir -TargetScriptDir `$sDir | Out-Null
            ")
            $bgIndexingJob = Start-Job -ScriptBlock $jobScript -ArgumentList $wikiDir, $scriptDir
        } else {
            Write-Host "ディスクキャッシュからインデックスを高速ロードしました ($($script:WikiIndex.Count) 件)" -ForegroundColor Green
        }
    } catch {
        Write-Warning "インデックス事前生成エラー: $_"
    }
}

# Ctrl+C キャンセル処理のハンドラ登録
$cancelHandler = $null
try {
    $cancelHandler = [System.ConsoleCancelEventHandler]{
        param($evtSender, $evtArgs)
        $null = $evtSender
        $null = $evtArgs
        Write-Host "`nサーバーを停止しています..." -ForegroundColor Yellow
        if ($bgIndexingJob) {
            try { Stop-Job -Job $bgIndexingJob -ErrorAction SilentlyContinue } catch { $null = $_ }
            try { Remove-Job -Job $bgIndexingJob -Force -ErrorAction SilentlyContinue } catch { $null = $_ }
        }
        if ($listener -and $listener.IsListening) {
            try { $listener.Stop() } catch { $null = $_ }
        }
    }
    [System.Console]::add_CancelKeyPress($cancelHandler)
} catch {
    $null = $_ # 非コンソール環境での add_CancelKeyPress 例外を安全に無視
}

try {
    while ($listener.IsListening) {
        $asyncResult = $listener.BeginGetContext($null, $null)
        while (-not $asyncResult.AsyncWaitHandle.WaitOne(200)) {
            if (-not $listener.IsListening) { break }
        }
        if (-not $listener.IsListening) { break }

        try {
            $context = $listener.EndGetContext($asyncResult)
        } catch [System.ObjectDisposedException], [System.Net.HttpListenerException] {
            break
        } catch {
            if (-not $listener.IsListening) { break }
            throw
        }

        $isShutdown = Invoke-WikiRouteRequest -Context $context -WikiDir $wikiDir -ScriptDir $scriptDir -Listener $listener -BgIndexingJob $bgIndexingJob
        if ($isShutdown) { break }
    }
} finally {
    if ($null -ne $cancelHandler) {
        try { [System.Console]::remove_CancelKeyPress($cancelHandler) } catch { $null = $_ }
    }
    if ($listener) {
        if ($listener.IsListening) {
            try { $listener.Stop() } catch { $null = $_ }
        }
        $listener.Close()
    }
}
