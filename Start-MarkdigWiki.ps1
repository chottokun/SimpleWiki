# ==============================================================================
#  Markdig + PowerShell 100% オフライン対応 Wiki サーバー
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================
param (
    [int]$Port = 8080,
    [string]$RootFolder = "",
    [switch]$DotSourceOnly
)

# スクリプト自身のディレクトリ ($PSScriptRoot) から lib フォルダを参照
$scriptDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
$libDir    = Join-Path $scriptDir "lib"

# ドキュメントルートの設定 (指定がない場合は markdown_sample フォルダ、存在しない場合は $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($RootFolder)) {
    $sampleDir = Join-Path $scriptDir "markdown_sample"
    if (Test-Path $sampleDir) {
        $wikiDir = $sampleDir
    } else {
        $wikiDir = $scriptDir
    }
} else {
    $wikiDir = [System.IO.Path]::GetFullPath($RootFolder)
}

if (-not (Test-Path $wikiDir)) {
    Write-Error "指定されたルートフォルダが見つかりません:`n$wikiDir"
    exit 1
}

$fullWikiDir = $wikiDir.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

# --- 1. Markdig.dll および依存ライブラリのロード ---
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

# --- モジュールのロード (lib/*.ps1) ---
. (Join-Path $libDir "WikiMetadata.ps1")
. (Join-Path $libDir "WikiSecurity.ps1")
. (Join-Path $libDir "WikiSearch.ps1")
. (Join-Path $libDir "WikiRag.ps1")
. (Join-Path $libDir "WikiViews.ps1")

# --- 安全な HTTP レスポンス送信関数 ---
function Write-SafeHttpResponse {
    param (
        [Parameter(Mandatory = $true)]$Response,
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [string]$ContentType = "text/html; charset=utf-8",
        [int]$StatusCode = 200
    )
    try {
        $Response.StatusCode = $StatusCode
        $Response.ContentType = $ContentType
        $Response.ContentLength64 = $Bytes.Length
        $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
    } catch [System.Net.HttpListenerException], [System.IO.IOException], [System.ObjectDisposedException] {
        # クライアントが応答完了前に接続を切断・再読み込みした場合の不必要なエラー出力を安全に抑制
    } catch {
        Write-Warning "HTTP応答送信エラー: $_"
    }
}

if ($DotSourceOnly) { return }

if ($MyInvocation.InvocationName -eq '.') { return }

# --- 3. HttpListener の起動 ---
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

# 起動時インデックス事前生成 (ノンブロッキング配慮 & エラーハンドリング)
$initCfg = Get-ConfigJson -TargetScriptDir $scriptDir
if ($initCfg.search -and $initCfg.search.prebuildIndex -eq $true) {
    try {
        Write-Host "インデックスを事前生成中..." -ForegroundColor Cyan
        $prebuilt = Build-WikiIndex -TargetWikiDir $wikiDir
        Write-Host "インデックス事前生成完了 ($($prebuilt.Count) 件のドキュメント)" -ForegroundColor Green
    } catch {
        Write-Warning "起動時のインデックス事前生成中にエラーが発生しましたが、サーバー起動を継続します: $_"
    }
}

# 既定のブラウザで開く
Start-Process $prefix

$mimeTypes = @{
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".gif"  = "image/gif"
    ".svg"  = "image/svg+xml"
    ".css"  = "text/css; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
}

try {
    while ($listener.IsListening) {
        $context  = $listener.GetContext()
        $request  = $context.Request
        $response = $context.Response

        try {
            $rawPath = [System.Net.WebUtility]::UrlDecode($request.Url.LocalPath)
            $queryParams = Get-QueryParams -Request $request

            # 1. API エンドポイント (/api/index.json, /api/chunks.json, /api/chat, /api/config)
            if ($rawPath -eq "/api/index.json") {
                $jsonStr = Get-ApiIndexJson -QueryParams $queryParams
                $bytes   = [System.Text.Encoding]::UTF8.GetBytes($jsonStr)
                Write-SafeHttpResponse -Response $response -Bytes $bytes -ContentType "application/json; charset=utf-8"
                continue
            }

            if ($rawPath.StartsWith("/api/config") -and $request.HttpMethod -eq "POST") {
                if ($queryParams.ContainsKey("action") -and $queryParams["action"] -eq "rebuild_index") {
                    try {
                        Build-WikiIndex -TargetWikiDir $wikiDir -ForceRefresh | Out-Null
                        $respJson = @{ success = $true; message = "インデックスの再構築が完了しました ($($script:WikiIndex.Count) 件)" } | ConvertTo-Json
                        Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($respJson)) -ContentType "application/json; charset=utf-8"
                    } catch {
                        $respJson = @{ success = $false; message = "インデックス再構築中にエラーが発生しました: $_" } | ConvertTo-Json
                        Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($respJson)) -ContentType "application/json; charset=utf-8" -StatusCode 500
                    }
                    continue
                }

                $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                $bodyText = $reader.ReadToEnd()
                $reqObj = try { $bodyText | ConvertFrom-Json } catch { $null }

                if (-not $reqObj) {
                    $respJson = @{ success = $false; message = "無効な JSON リクエストデータです。" } | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($respJson)) -ContentType "application/json; charset=utf-8" -StatusCode 400
                    continue
                }

                # パラメータのバリデーションとサニタイズ
                $configPath = Join-Path $scriptDir "config.json"
                $existingConfig = Get-ConfigJson -TargetScriptDir $scriptDir
                $cfgDict = @{}

                # 既存設定の読み込み
                if ($existingConfig) {
                    if ($existingConfig.rag) {
                        $cfgDict["rag"] = [ordered]@{
                            enabled        = [bool]$existingConfig.rag.enabled
                            apiUrl         = [string]$existingConfig.rag.apiUrl
                            apiKey         = [string]$existingConfig.rag.apiKey
                            model          = [string]$existingConfig.rag.model
                            maxContextDocs = if ($existingConfig.rag.maxContextDocs) { [int]$existingConfig.rag.maxContextDocs } else { 3 }
                            maxHistoryTurns= if ($existingConfig.rag.maxHistoryTurns) { [int]$existingConfig.rag.maxHistoryTurns } else { 3 }
                            maxHistoryChars= if ($existingConfig.rag.maxHistoryChars) { [int]$existingConfig.rag.maxHistoryChars } else { 4000 }
                            timeoutSec     = if ($existingConfig.rag.timeoutSec) { [int]$existingConfig.rag.timeoutSec } else { 30 }
                            systemPrompt   = [string]$existingConfig.rag.systemPrompt
                        }
                    }
                    if ($existingConfig.api) {
                        $cfgDict["api"] = [ordered]@{
                            defaultLimit = if ($existingConfig.api.defaultLimit) { [int]$existingConfig.api.defaultLimit } else { 100 }
                            maxLimit     = if ($existingConfig.api.maxLimit) { [int]$existingConfig.api.maxLimit } else { 1000 }
                        }
                    }
                    if ($existingConfig.search) {
                        $cfgDict["search"] = [ordered]@{
                            prebuildIndex = [bool]$existingConfig.search.prebuildIndex
                            useCache      = [bool]$existingConfig.search.useCache
                            cacheFolder   = [string]$existingConfig.search.cacheFolder
                        }
                    }
                }

                if (-not $cfgDict.ContainsKey("search")) {
                    $cfgDict["search"] = [ordered]@{ prebuildIndex = $false; useCache = $false; cacheFolder = ".cache" }
                }

                # バリデーションエラー用変数
                $validationError = $null

                # search 設定の安全な更新
                if ($reqObj.PSObject.Properties["search"]) {
                    $sObj = $reqObj.search
                    if ($sObj.PSObject.Properties["prebuildIndex"]) {
                        $cfgDict["search"]["prebuildIndex"] = [bool]$sObj.prebuildIndex
                    }
                    if ($sObj.PSObject.Properties["useCache"]) {
                        $cfgDict["search"]["useCache"] = [bool]$sObj.useCache
                    }
                    if ($sObj.PSObject.Properties["cacheFolder"]) {
                        $cFolder = [string]$sObj.cacheFolder
                        if ([string]::IsNullOrWhiteSpace($cFolder) -or $cFolder -match '[\:\\/\.\.]') {
                            $validationError = "キャッシュフォルダ名が無効です。英数字・ハイフン・アンダースコア・ドット始まりのみ許可されています (ディレクトリトラバーサルは禁止)。"
                        } else {
                            $cfgDict["search"]["cacheFolder"] = $cFolder
                        }
                    }
                }

                # rag 設定の安全な更新
                if (-not $validationError -and $reqObj.PSObject.Properties["rag"]) {
                    if (-not $cfgDict.ContainsKey("rag")) {
                        $cfgDict["rag"] = [ordered]@{ enabled = $false; apiUrl = "http://localhost:11434/v1"; model = "qwen2.5-coder-7b-instruct" }
                    }
                    $rObj = $reqObj.rag
                    if ($rObj.PSObject.Properties["enabled"]) {
                        $cfgDict["rag"]["enabled"] = [bool]$rObj.enabled
                    }
                    if ($rObj.PSObject.Properties["apiUrl"] -and -not [string]::IsNullOrWhiteSpace($rObj.apiUrl)) {
                        $cfgDict["rag"]["apiUrl"] = [string]$rObj.apiUrl
                    }
                    if ($rObj.PSObject.Properties["model"] -and -not [string]::IsNullOrWhiteSpace($rObj.model)) {
                        $cfgDict["rag"]["model"] = [string]$rObj.model
                    }
                }

                if ($validationError) {
                    $respJson = @{ success = $false; message = $validationError } | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($respJson)) -ContentType "application/json; charset=utf-8" -StatusCode 400
                    continue
                }

                try {
                    $jsonContent = $cfgDict | ConvertTo-Json -Depth 5
                    [System.IO.File]::WriteAllText($configPath, $jsonContent, [System.Text.Encoding]::UTF8)
                    $respJson = @{ success = $true; message = "設定を正常に更新しました。" } | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($respJson)) -ContentType "application/json; charset=utf-8"
                } catch {
                    $respJson = @{ success = $false; message = "config.json の書き込みに失敗しました: $_" } | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($respJson)) -ContentType "application/json; charset=utf-8" -StatusCode 500
                }
                continue
            }

            if ($rawPath -eq "/api/backups" -and $request.HttpMethod -eq "GET") {
                $relPath = $queryParams["relPath"]
                if ([string]::IsNullOrWhiteSpace($relPath)) {
                    $jsonRes = @{ error = "INVALID_REQUEST"; message = "relPath が指定されていません。" } | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 400
                    continue
                }
                $cleanRel = $relPath.TrimStart("/").Replace("/", "\")
                $filePath = Join-Path $wikiDir $cleanRel
                $fullPath = [System.IO.Path]::GetFullPath($filePath)
                if (-not $fullPath.StartsWith($fullWikiDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $jsonRes = @{ error = "FORBIDDEN"; message = "アクセスが禁止されています。" } | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 403
                    continue
                }
                $backups = [System.Collections.Generic.List[PSObject]]::new()
                $config = Get-ConfigJson -TargetScriptDir $scriptDir
                $maxBackups = 3
                if ($config.editor -and $config.editor.maxBackups -ne $null) {
                    $maxBackups = [int]$config.editor.maxBackups
                }
                for ($i = 1; $i -le $maxBackups; $i++) {
                    $bakPath = "$fullPath.bak$i"
                    if (Test-Path $bakPath -PathType Leaf) {
                        $item = Get-Item $bakPath
                        $backups.Add(@{
                            version      = "bak$i"
                            label        = "世代 $i (.bak$i)"
                            lastModified = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                        })
                    }
                }
                $jsonRes = @{ backups = $backups } | ConvertTo-Json
                Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                continue
            }

            if ($rawPath -eq "/api/raw" -and $request.HttpMethod -eq "GET") {
                $relPath = $queryParams["relPath"]
                $version = $queryParams["version"]
                if ([string]::IsNullOrWhiteSpace($relPath)) {
                    $jsonRes = @{ error = "INVALID_REQUEST"; message = "relPath が指定されていません。" } | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 400
                    continue
                }
                $cleanRel = $relPath.TrimStart("/").Replace("/", "\")
                $filePath = Join-Path $wikiDir $cleanRel
                $targetPath = $filePath
                if (-not [string]::IsNullOrWhiteSpace($version) -and $version -match "^bak\d+$") {
                    $targetPath = "$filePath.$version"
                }
                $fullPath = [System.IO.Path]::GetFullPath($targetPath)
                if (-not $fullPath.StartsWith($fullWikiDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $jsonRes = @{ error = "FORBIDDEN"; message = "アクセスが禁止されています。" } | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 403
                    continue
                }
                if (-not (Test-Path $fullPath -PathType Leaf)) {
                    $jsonRes = @{ error = "NOT_FOUND"; message = "ファイルが見つかりません。" } | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 404
                    continue
                }
                $content = [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8)
                $jsonRes = @{ markdown = $content } | ConvertTo-Json
                Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                continue
            }

            if ($rawPath -eq "/api/clear-cache") {
                $script:SidebarMdFiles = @()
                $script:SidebarCachedHtml = $null
                Build-WikiIndex -TargetWikiDir $wikiDir -ForceRefresh | Out-Null
                $jsonRes = @{ success = $true } | ConvertTo-Json
                Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                continue
            }

            if ($rawPath -eq "/api/save" -and $request.HttpMethod -eq "POST") {
                $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                $bodyText = $reader.ReadToEnd()
                $reqObj = try { $bodyText | ConvertFrom-Json } catch { $null }
                if (-not $reqObj -or [string]::IsNullOrWhiteSpace($reqObj.relPath) -or $reqObj.markdown -eq $null) {
                    $jsonRes = @{ error = "INVALID_REQUEST"; message = "リクエストデータが不正です。" } | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 400
                    continue
                }
                $relPath = $reqObj.relPath
                $cleanRel = $relPath.TrimStart("/").Replace("/", "\")
                $filePath = Join-Path $wikiDir $cleanRel
                $fullPath = [System.IO.Path]::GetFullPath($filePath)
                if (-not $fullPath.StartsWith($fullWikiDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $jsonRes = @{ error = "FORBIDDEN"; message = "アクセスが禁止されています。" } | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 403
                    continue
                }
                # バックアップ(世代管理)設定の取得
                $config = Get-ConfigJson -TargetScriptDir $scriptDir
                $maxBackups = 3
                if ($config.editor -and $config.editor.maxBackups -ne $null) {
                    $maxBackups = [int]$config.editor.maxBackups
                }

                # バックアップの世代管理 (回転処理)
                if ($maxBackups -gt 0 -and (Test-Path $fullPath)) {
                    for ($i = $maxBackups - 1; $i -ge 1; $i--) {
                        $oldBak = "$fullPath.bak$i"
                        $newBak = "$fullPath.bak$($i + 1)"
                        if (Test-Path $oldBak) {
                            Copy-Item -Path $oldBak -Destination $newBak -Force
                        }
                    }
                    Copy-Item -Path $fullPath -Destination "$fullPath.bak1" -Force
                }

                # UTF-8 with BOM で保存
                $utf8bom = New-Object System.Text.UTF8Encoding -ArgumentList @($true)
                [System.IO.File]::WriteAllText($fullPath, $reqObj.markdown, $utf8bom)

                # インデックスの更新を強制
                Build-WikiIndex -TargetWikiDir $wikiDir -ForceRefresh | Out-Null

                # サイドバーキャッシュもクリア
                $script:SidebarMdFiles = @()
                $script:SidebarCachedHtml = $null

                # YAML Front Matter 構文検証 (ソフトLint)
                $yamlSyntax = Test-YamlFrontMatterSyntax -MdText $reqObj.markdown
                $resData = @{ success = $true }
                if (-not $yamlSyntax.isValid -and $yamlSyntax.warnings.Count -gt 0) {
                    $resData["warning"] = "⚠️ YAML Front Matter に記述エラーが見つかりました:`n・" + ($yamlSyntax.warnings -join "`n・")
                }

                $jsonRes = $resData | ConvertTo-Json
                Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                continue
            }

            if ($rawPath -eq "/api/chunks.json") {
                $jsonStr = Get-ApiChunksJson
                $bytes   = [System.Text.Encoding]::UTF8.GetBytes($jsonStr)
                Write-SafeHttpResponse -Response $response -Bytes $bytes -ContentType "application/json; charset=utf-8"
                continue
            }

            if ($rawPath -eq "/api/chat" -and $request.HttpMethod -eq "POST") {
                $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                $bodyText = $reader.ReadToEnd()
                $reqObj = try { $bodyText | ConvertFrom-Json } catch { $null }

                $config = Get-ConfigJson -TargetScriptDir $scriptDir
                if (-not $config.rag -or -not $config.rag.enabled) {
                    $jsonRes = @{ error = "LLM_DISABLED"; message = "LLM RAG チャット機能は現在無効です。config.json を設定してください。" } | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 400
                    continue
                }

                $userMsg = ""
                if ($reqObj -and $reqObj.message) {
                    $userMsg = $reqObj.message.Trim()
                }
                if ([string]::IsNullOrWhiteSpace($userMsg)) {
                    $jsonRes = @{ error = "INVALID_REQUEST"; message = "質問メッセージが空です。" } | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 400
                    continue
                }

                # 会話履歴 (history) と設定パラメータの取得
                $maxHistoryTurns = 3
                if ($config.rag -and $config.rag.maxHistoryTurns -ne $null) {
                    $maxHistoryTurns = [Math]::Max(0, [Math]::Min(10, [int]$config.rag.maxHistoryTurns))
                }
                $maxHistoryChars = 4000
                if ($config.rag -and $config.rag.maxHistoryChars -ne $null) {
                    $maxHistoryChars = [Math]::Max(500, [int]$config.rag.maxHistoryChars)
                }

                $processedHistory = [System.Collections.Generic.List[PSObject]]::new()
                if ($maxHistoryTurns -gt 0 -and $reqObj -and $reqObj.history) {
                    $rawHist = @($reqObj.history)
                    $maxMsgs = $maxHistoryTurns * 2
                    if ($rawHist.Count -gt $maxMsgs) {
                        $rawHist = $rawHist[($rawHist.Count - $maxMsgs)..($rawHist.Count - 1)]
                    }
                    
                    $currentTotalChars = 0
                    $validHist = [System.Collections.Generic.List[PSObject]]::new()
                    for ($hIdx = $rawHist.Count - 1; $hIdx -ge 0; $hIdx--) {
                        $item = $rawHist[$hIdx]
                        if ($item -and $item.role -and $item.content) {
                            $cText = $item.content.ToString()
                            if (($currentTotalChars + $cText.Length) -le $maxHistoryChars -or $validHist.Count -eq 0) {
                                if ($cText.Length -gt $maxHistoryChars) {
                                    $cText = $cText.Substring(0, $maxHistoryChars) + "..."
                                }
                                $currentTotalChars += $cText.Length
                                $validHist.Insert(0, [PSCustomObject]@{ role = $item.role.ToString(); content = $cText })
                            }
                        }
                    }
                    $processedHistory = $validHist
                }

                $reqMode = "fast"
                if ($reqObj -and $reqObj.mode -and $reqObj.mode.ToString().ToLower() -eq "agentic") {
                    $reqMode = "agentic"
                }

                $timeoutSec = 30
                if ($config.rag -and $config.rag.timeoutSec) {
                    $timeoutSec = [int]$config.rag.timeoutSec
                }

                $includeCurrentPage = $true
                if ($reqObj -and $reqObj.PSObject.Properties['includeCurrentPage'] -and $reqObj.includeCurrentPage -eq $false) {
                    $includeCurrentPage = $false
                }
                $currentRelPath = ""
                if ($reqObj -and $reqObj.currentRelPath) {
                    $currentRelPath = $reqObj.currentRelPath.ToString().TrimStart('/', '\')
                }

                # 現在開いているページのドキュメントメタデータ取得 (オプション)
                $currDoc = $null
                if ($includeCurrentPage -and -not [string]::IsNullOrWhiteSpace($currentRelPath) -and $currentRelPath.EndsWith(".md", [System.StringComparison]::OrdinalIgnoreCase)) {
                    $fullCurrPath = Join-Path $wikiDir $currentRelPath
                    if (Test-Path -LiteralPath $fullCurrPath -PathType Leaf) {
                        $fileObj = Get-Item -LiteralPath $fullCurrPath
                        $currDoc = Get-DocumentMetadata -File $fileObj -RelPath $currentRelPath
                    }
                }

                if ($reqMode -eq "agentic") {
                    # --- Agentic RAG Mode (ReAct 自律調査) ---
                    $maxTurns = 5
                    if ($config.rag -and $config.rag.maxAgentTurns) {
                        $maxTurns = [int]$config.rag.maxAgentTurns
                    }
                    $maxDocChars = 2000
                    if ($config.rag -and $config.rag.maxDocCharLength) {
                        $maxDocChars = [int]$config.rag.maxDocCharLength
                    }

                    try {
                        $agentRes = Invoke-AgenticRagChat -ApiUrl $config.rag.apiUrl -ApiKey $config.rag.apiKey -Model $config.rag.model -UserMessage $userMsg -History $processedHistory -WikiDir $wikiDir -MaxTurns $maxTurns -MaxDocChars $maxDocChars -TimeoutSec $timeoutSec -CurrentDoc $currDoc
                        $jsonRes = @{
                            mode        = "agentic"
                            answer      = $agentRes.answer
                            thinkingLog = $agentRes.thinkingLog
                            sources     = $agentRes.sources
                        } | ConvertTo-Json -Depth 5
                        Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                    } catch {
                        $jsonRes = @{ error = "LLM_ERROR"; message = "Agentic RAG 実行中にエラーが発生しました: $_" } | ConvertTo-Json
                        Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 500
                    }
                    continue
                }

                # --- Fast RAG Mode (1-Pass) ---
                # 1. OKF 文脈検索 (WinRT 形態素解析エンジン)
                Build-WikiIndex -TargetWikiDir $wikiDir | Out-Null
                $activeDocs = @($script:WikiIndex | Where-Object { $_.Status -eq "active" })

                $maxDocs = 3
                if ($config.rag -and $config.rag.maxContextDocs) {
                    $maxDocs = [int]$config.rag.maxContextDocs
                }

                # 会話履歴 + 現在の質問を統合して単語抽出
                $searchQueryText = $userMsg
                if ($processedHistory.Count -gt 0) {
                    $lastUserTurn = $processedHistory | Where-Object { $_.role -eq "user" } | Select-Object -Last 1
                    if ($lastUserTurn) {
                        $searchQueryText = $lastUserTurn.content + " " + $userMsg
                    }
                }
                $keywords = Get-JapaneseWordsWinRT -Text $searchQueryText

                $docScores = [System.Collections.Generic.List[PSObject]]::new()
                foreach ($doc in $activeDocs) {
                    $score = 0
                    foreach ($kw in $keywords) {
                        $kwRegex = [regex]::Escape($kw)
                        if ($doc.Title -and $doc.Title -match $kwRegex) { $score += 10 }
                        if ($doc.Tags) {
                            $tm = $doc.Tags | Where-Object { $_ -match $kwRegex }
                            if ($tm) { $score += 8 }
                        }
                        if ($doc.Description -and $doc.Description -match $kwRegex) { $score += 5 }
                        if ($doc.BodyText -and $doc.BodyText -match $kwRegex) { $score += 2 }
                    }
                    if ($score -gt 0) {
                        $docScores.Add([PSCustomObject]@{ Doc = $doc; Score = $score })
                    }
                }

                $topScored = @($docScores | Sort-Object Score -Descending | Select-Object -First $maxDocs)
                $contextDocs = [System.Collections.Generic.List[PSObject]]::new()

                # 開いているページを第一最優先コンテキストとして追加
                if ($currDoc) {
                    $contextDocs.Add($currDoc)
                }

                if ($topScored.Count -gt 0) {
                    foreach ($ts in $topScored) {
                        if (-not $currDoc -or $ts.Doc.RelPath -ne $currDoc.RelPath) {
                            $contextDocs.Add($ts.Doc)
                        }
                    }
                } else {
                    $takeCount = [Math]::Min($maxDocs, $activeDocs.Count)
                    $fallbackDocs = @($activeDocs | Sort-Object LastUpdated -Descending | Select-Object -First $takeCount)
                    foreach ($fd in $fallbackDocs) {
                        if (-not $currDoc -or $fd.RelPath -ne $currDoc.RelPath) {
                            $contextDocs.Add($fd)
                        }
                    }
                }

                # 2. システムプロンプト構築 (OKF メタデータ + 本文スニペット)
                $contextStrBuilder = [System.Text.StringBuilder]::new()
                $sourcesList = [System.Collections.Generic.List[PSObject]]::new()

                foreach ($cDoc in $contextDocs) {
                    $relUri = "/" + [Uri]::EscapeUriString($cDoc.RelPath.Replace('\', '/'))
                    $sourcesList.Add([PSCustomObject]@{
                        title       = $cDoc.Title
                        relPath     = $cDoc.RelPath
                        relUri      = $relUri
                        lastUpdated = $cDoc.LastUpdated.ToString("yyyy-MM-dd")
                        author      = $cDoc.Author
                    })

                    $snippet = $cDoc.BodyText
                    if ($snippet -and $snippet.Length -gt 800) {
                        $snippet = $snippet.Substring(0, 800) + "..."
                    }
                    [void]$contextStrBuilder.AppendLine("---")
                    [void]$contextStrBuilder.AppendLine("■ ドキュメント: $($cDoc.Title)")
                    [void]$contextStrBuilder.AppendLine("・ドメイン: $($cDoc.Domain)")
                    [void]$contextStrBuilder.AppendLine("・著者: $($cDoc.Author)")
                    [void]$contextStrBuilder.AppendLine("・最終更新日: $($cDoc.LastUpdated.ToString('yyyy-MM-dd'))")
                    [void]$contextStrBuilder.AppendLine("・ステータス: $($cDoc.Status) (現行)")
                    [void]$contextStrBuilder.AppendLine("本文:")
                    [void]$contextStrBuilder.AppendLine($snippet)
                }

                $baseSysPrompt = "あなたは社内Wikiのナレッジを元に回答するアシスタントです。"
                if ($config.rag -and $config.rag.systemPrompt) {
                    $baseSysPrompt = $config.rag.systemPrompt
                }
                $fullSysPrompt = $baseSysPrompt + [System.Environment]::NewLine + [System.Environment]::NewLine + "[参照Wikiコンテキスト]" + [System.Environment]::NewLine + $contextStrBuilder.ToString()

                # 3. LLM 呼び出し
                try {
                    $answerText = Invoke-OpenAiChatCompletions -ApiUrl $config.rag.apiUrl -ApiKey $config.rag.apiKey -Model $config.rag.model -SystemPrompt $fullSysPrompt -UserMessage $userMsg -History $processedHistory -TimeoutSec $timeoutSec
                    $jsonRes = @{
                        mode    = "fast"
                        answer  = $answerText
                        sources = $sourcesList
                    } | ConvertTo-Json -Depth 4
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                } catch {
                    $jsonRes = @{ error = "LLM_ERROR"; message = "LLM との通信に失敗しました: $_" } | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 500
                }
                continue
            }

            # 2. 動的ビュー判定
            $isDynamicView = $false
            $bodyContent   = ""
            $pageTitle     = "Wiki"

            if ($rawPath -eq "/recent") {
                $isDynamicView = $true
                $pageTitle     = "最近の更新"
                $bodyContent   = Get-RecentViewHtml
            } elseif ($rawPath -eq "/tags") {
                $isDynamicView = $true
                $tagParam      = $queryParams["tag"]
                $pageTitle     = if ($tagParam) { "タグ: $tagParam" } else { "タグ一覧" }
                $bodyContent   = Get-TagsViewHtml -SelectedTag $tagParam
            } elseif ($rawPath -eq "/maintenance") {
                $isDynamicView = $true
                $pageTitle     = "品質・メンテナンス"
                $bodyContent   = Get-MaintenanceViewHtml
            } elseif ($rawPath -eq "/authors") {
                $isDynamicView = $true
                $authorParam   = $queryParams["name"]
                $pageTitle     = if ($authorParam) { "著者: $authorParam" } else { "著者一覧" }
                $bodyContent   = Get-AuthorsViewHtml -SelectedAuthor $authorParam
            } elseif ($rawPath -eq "/settings") {
                $isDynamicView = $true
                $pageTitle     = "システム設定"
                $bodyContent   = Get-SettingsViewHtml
            } elseif ($rawPath -eq "/search") {
                $isDynamicView = $true
                $qParam        = $queryParams["q"]
                $stParam       = $queryParams["status"]
                $domParam      = $queryParams["domain"]
                $stValue       = if (-not [string]::IsNullOrWhiteSpace($stParam)) { $stParam } else { "active" }
                $pageTitle     = if ($qParam) { "検索: $qParam" } else { "検索" }
                $bodyContent   = Get-SearchViewHtml -Query $qParam -StatusFilter $stValue -DomainFilter $domParam
            }

            $relPath  = $rawPath.TrimStart("/").Replace("/", "\")
            $filePath = Join-Path $wikiDir $relPath

            # /lib/ 配下のリソース要求はスクリプト直下の lib フォルダへフォールバック
            if (-not (Test-Path $filePath) -and $rawPath.StartsWith("/lib/")) {
                $filePath = Join-Path $scriptDir $relPath
            }

            # 安全性検証: ディレクトリトラバーサル防止 ($fullWikiDir または $scriptDir\lib)
            $fullPath = [System.IO.Path]::GetFullPath($filePath)
            $fullScriptLibDir = (Join-Path $scriptDir "lib\").TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
            $isAllowed = $fullPath.StartsWith($fullWikiDir, [System.StringComparison]::OrdinalIgnoreCase) -or $fullPath.StartsWith($fullScriptLibDir, [System.StringComparison]::OrdinalIgnoreCase)
            
            if (-not $isDynamicView -and -not $isAllowed) {
                $forbiddenBytes = [System.Text.Encoding]::UTF8.GetBytes("<h1>403 Forbidden</h1>")
                Write-SafeHttpResponse -Response $response -Bytes $forbiddenBytes -StatusCode 403
                continue
            }

            # ディレクトリの場合: index.md/README.md フォールバックまたはフォルダ一覧表示
            if (-not $isDynamicView -and (Test-Path -LiteralPath $fullPath -PathType Container)) {
                $dirIndexPath  = Join-Path $fullPath "index.md"
                $dirReadmePath = Join-Path $fullPath "README.md"
                if (Test-Path -LiteralPath $dirIndexPath -PathType Leaf) {
                    $fullPath = [System.IO.Path]::GetFullPath($dirIndexPath)
                    $relPath  = (($relPath.TrimEnd('\') + '\index.md').TrimStart('\'))
                } elseif (Test-Path -LiteralPath $dirReadmePath -PathType Leaf) {
                    $fullPath = [System.IO.Path]::GetFullPath($dirReadmePath)
                    $relPath  = (($relPath.TrimEnd('\') + '\README.md').TrimStart('\'))
                } else {
                    $isDynamicView = $true
                    $dirName       = if ([string]::IsNullOrEmpty($relPath.TrimEnd('\'))) { "ルート" } else { [System.Net.WebUtility]::HtmlEncode($relPath.TrimEnd('\').Replace('\', ' / ')) }
                    $pageTitle     = "📁 $dirName - フォルダ一覧"
                    $bodyContent   = Get-DirectoryListingHtml -DirFullPath $fullPath -RawUrlPath $rawPath
                }
            }

            # 3. HTML レンダリング (Markdown または動的ビュー)
            if ($isDynamicView -or ((Test-Path -LiteralPath $fullPath -PathType Leaf) -and ($fullPath.EndsWith(".md")))) {
                if (-not $isDynamicView) {
                    $mdText   = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
                    if ($null -eq $mdText) { $mdText = "" }
                    $fileObj  = Get-Item -LiteralPath $fullPath
                    $meta     = Get-DocumentMetadata -File $fileObj -RelPath $relPath -MdText $mdText

                    $builder  = New-Object Markdig.MarkdownPipelineBuilder
                    $null     = [Markdig.MarkdownExtensions]::UseAdvancedExtensions($builder)
                    $null     = [Markdig.MarkdownExtensions]::UseYamlFrontMatter($builder)
                    $pipeline = $builder.Build()
                    $renderedHtml = [Markdig.Markdown]::ToHtml($mdText, $pipeline)

                    $okfTopBar   = Get-OkfTopBarHtml -Meta $meta -RelPath $relPath
                    $okfFooter   = Get-OkfFooterCardHtml -Meta $meta
                    $bodyContent = $okfTopBar + $renderedHtml + $okfFooter
                    $pageTitle   = [System.Net.WebUtility]::HtmlEncode($meta.Title)
                }

                $sidebarHtml = Get-SidebarHtml -currentRelPath $relPath

                $template = @'
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<title>{0} - SimpleWiki OKF</title>
<style>
    * { box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; margin: 0; padding: 0; display: flex; flex-direction: column; height: 100vh; color: #24292e; background-color: #fff; }
    header.top-header { background: #1b1f23; color: #fff; padding: 10px 20px; display: flex; align-items: center; justify-content: space-between; flex-shrink: 0; }
    header.top-header a.brand { color: #fff; font-weight: bold; font-size: 16px; text-decoration: none; display: flex; align-items: center; gap: 8px; }
    header.top-header nav.top-nav { display: flex; gap: 15px; align-items: center; }
    header.top-header nav.top-nav a { color: #d1d5da; text-decoration: none; font-size: 13px; padding: 4px 8px; border-radius: 4px; }
    header.top-header nav.top-nav a:hover { color: #fff; background: rgba(255,255,255,0.1); }
    header.top-header form.search-form { display: flex; gap: 4px; }
    header.top-header form.search-form input { padding: 4px 8px; font-size: 12px; border: 1px solid #444; border-radius: 4px; background: #2f363d; color: #fff; }
    header.top-header form.search-form button { padding: 4px 8px; font-size: 12px; border: none; border-radius: 4px; background: #0366d6; color: #fff; cursor: pointer; }
    .layout-container { display: flex; flex: 1; overflow: hidden; }
    nav.sidebar { width: 260px; background-color: #f6f8fa; border-right: 1px solid #e1e4e8; padding: 20px 10px; overflow-y: auto; flex-shrink: 0; }
    nav.sidebar h2 { font-size: 13px; text-transform: uppercase; color: #586069; margin: 0 0 10px 10px; letter-spacing: 0.5px; }
    nav.sidebar ul { list-style: none; padding: 0; margin: 0; }
    nav.sidebar ul ul { padding-left: 12px; margin-top: 2px; }
    nav.sidebar li.nav-folder { margin-top: 4px; margin-bottom: 4px; }
    nav.sidebar summary.folder-title { font-weight: bold; font-size: 13px; color: #586069; padding: 4px 6px; cursor: pointer; user-select: none; }
    nav.sidebar summary.folder-title:hover { color: #0366d6; }
    nav.sidebar li.nav-file a { display: block; padding: 4px 8px; color: #0366d6; text-decoration: none; border-radius: 6px; font-size: 13px; word-break: break-all; }
    nav.sidebar li.nav-file a:hover { background-color: #f0f3f6; text-decoration: none; }
    nav.sidebar li.nav-file a.active { background-color: #0366d6; color: #ffffff; font-weight: bold; }
    main { flex: 1; padding: 30px 50px; overflow-y: auto; }
    .markdown-body { max-width: 900px; margin: 0 auto; line-height: 1.6; }
    h1, h2, h3 { border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; margin-top: 24px; margin-bottom: 16px; }
    code { background: rgba(27,31,35,0.05); padding: 0.2em 0.4em; border-radius: 3px; font-family: monospace; }
    pre { background: #f6f8fa; padding: 16px; border-radius: 6px; overflow: auto; }
    pre code { background: transparent; padding: 0; }
    blockquote { border-left: 4px solid #dfe2e5; color: #6a737d; margin: 0; padding-left: 1em; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 16px; }
    table th, table td { border: 1px solid #dfe2e5; padding: 8px 13px; }
    table th { background: #f6f8fa; }
    img { max-width: 100%; }
    
    /* OKF Custom Components */
    .edit-doc-btn { background: #0366d6; color: #fff; border: none; padding: 3px 8px; border-radius: 4px; font-size: 11px; font-weight: bold; cursor: pointer; margin-left: 10px; }
    .edit-doc-btn:hover { background: #0255b3; }

    /* Editor Modal Styles */
    .wiki-editor-modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); z-index: 10000; justify-content: center; align-items: center; }
    .wiki-editor-container { background: #fff; border-radius: 8px; width: 90%; max-width: 1000px; height: 85%; display: flex; flex-direction: column; overflow: hidden; box-shadow: 0 4px 24px rgba(0,0,0,0.2); }
    .wiki-editor-header { background: #1b1f23; color: #fff; padding: 12px 18px; font-weight: bold; font-size: 14px; display: flex; justify-content: space-between; align-items: center; }
    .wiki-editor-body { flex: 1; padding: 15px; display: flex; flex-direction: column; gap: 10px; }
    .wiki-editor-textarea { flex: 1; resize: none; font-family: monospace; font-size: 14px; padding: 10px; border: 1px solid #ddd; border-radius: 4px; outline: none; }
    .wiki-editor-textarea:focus { border-color: #0366d6; }
    .wiki-editor-footer { padding: 10px 18px; border-top: 1px solid #e1e4e8; display: flex; justify-content: flex-end; gap: 10px; background: #f6f8fa; }
    .wiki-editor-save-btn { background: #28a745; color: #fff; border: none; padding: 8px 16px; border-radius: 6px; font-weight: bold; cursor: pointer; }
    .wiki-editor-save-btn:hover { background: #218838; }
    .wiki-editor-cancel-btn { background: #6c757d; color: #fff; border: none; padding: 8px 16px; border-radius: 6px; font-weight: bold; cursor: pointer; }
    .wiki-editor-cancel-btn:hover { background: #5a6268; }
    .okf-top-bar { display: flex; align-items: center; justify-content: space-between; font-size: 12px; color: #586069; margin-bottom: 16px; border-bottom: 1px dashed #e1e4e8; padding-bottom: 8px; }
    .okf-footer-card { background: #f8f9fa; border: 1px solid #e1e4e8; border-radius: 6px; padding: 16px; margin-top: 40px; }
    .okf-footer-header { display: flex; justify-content: space-between; align-items: center; font-size: 13px; font-weight: bold; color: #444; border-bottom: 1px solid #e1e4e8; padding-bottom: 8px; margin-bottom: 10px; }
    .okf-footer-meta { display: flex; gap: 20px; font-size: 12px; color: #586069; margin-top: 10px; }
    .okf-api-link { font-size: 11px; color: #0366d6; text-decoration: none; padding: 2px 8px; background: #e1e4e8; border-radius: 12px; }
    .okf-api-link:hover { background: #0366d6; color: #fff; }
    .okf-desc { font-size: 13px; color: #586069; margin: 6px 0 10px 0; }
    .okf-tags { display: flex; gap: 6px; flex-wrap: wrap; margin-top: 10px; }
    .tag-badge { background: #e1e4e8; color: #0366d6; text-decoration: none; padding: 2px 8px; border-radius: 12px; font-size: 12px; }
    .tag-badge:hover { background: #0366d6; color: #fff; }
    .badge { padding: 3px 8px; border-radius: 12px; font-size: 11px; font-weight: bold; text-transform: uppercase; }
    .badge-active { background: #28a745; color: #fff; }
    .badge-draft { background: #ffc107; color: #212529; }
    .badge-deprecated { background: #dc3545; color: #fff; }
    .warning-banner { background: #fff3cd; border: 1px solid #ffeeba; color: #856404; padding: 12px 16px; border-radius: 6px; margin-bottom: 16px; }
    .maint-section { margin-bottom: 30px; padding: 16px; border-radius: 6px; }
    .warning-box { background: #fff8f8; border: 1px solid #f5c6cb; }
    .info-box { background: #fffcf0; border: 1px solid #ffeba8; }
    .danger-box { background: #fdf2f2; border: 1px solid #f5c6cb; }
    .tag-cloud { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 20px; }
    .tag-cloud-item { padding: 8px 14px; background: #f1f8ff; border: 1px solid #c8e1ff; border-radius: 20px; text-decoration: none; color: #0366d6; font-weight: bold; }
    .tag-cloud-item:hover { background: #0366d6; color: #fff; }
    .muted { color: #6a737d; font-size: 12px; }
    .search-item { border-bottom: 1px solid #e1e4e8; padding: 12px 0; }
    .search-item h3 { border: none; margin: 0 0 6px 0; font-size: 16px; }
</style>
</head>
<body>
    <header class="top-header">
        <a href="/" class="brand">📖 SimpleWiki <span class="badge badge-active">OKF</span></a>
        <nav class="top-nav">
            <a href="/">🏠 Home</a>
            <a href="/recent">🕒 最近の更新</a>
            <a href="/tags">🏷️ タグ一覧</a>
            <a href="/maintenance">🧹 メンテナンス</a>
            <a href="/authors">👥 著者一覧</a>
            <a href="/settings">⚙️ 設定</a>
            <a href="/api/index.json" target="_blank">🤖 API (JSON)</a>
        </nav>
        <form action="/search" method="GET" accept-charset="UTF-8" class="search-form">
            <input type="text" name="q" placeholder="Wikiを検索..." required>
            <button type="submit">検索</button>
        </form>
    </header>
    <div class="layout-container">
        <nav class="sidebar">
            <h2>📄 ドキュメント一覧</h2>
            {1}
        </nav>
        <main>
            <div class="markdown-body">
                {2}
            </div>
        </main>
    </div>

    <!-- Wiki Editor Modal -->
    <div id="wikiEditorModal" class="wiki-editor-modal">
        <div class="wiki-editor-container">
            <div class="wiki-editor-header">
                <div style="display: flex; align-items: center; gap: 12px;">
                    <span>📝 Markdown エディター</span>
                    <select id="wikiEditorHistorySelect" onchange="loadWikiHistoryVersion(this)" style="background: #24292e; color: #fff; border: 1px solid #444; border-radius: 4px; padding: 2px 6px; font-size: 12px; cursor: pointer;">
                        <option value="">最新版 (編集用)</option>
                    </select>
                </div>
                <span style="font-size: 12px; color: #ccc;" id="wikiEditorPath"></span>
            </div>
            <div class="wiki-editor-body">
                <textarea id="wikiEditorTextarea" class="wiki-editor-textarea" placeholder="Markdown を記述してください..."></textarea>
            </div>
            <div class="wiki-editor-footer">
                <button class="wiki-editor-cancel-btn" onclick="closeWikiEditor()">キャンセル</button>
                <button class="wiki-editor-save-btn" onclick="saveWikiMarkdown()">保存</button>
            </div>
        </div>
    </div>

    <script src="/lib/mermaid.min.js"></script>
    <script>
        function openWikiEditor(btn) {
            const relPath = btn.getAttribute("data-relpath");
            document.getElementById("wikiEditorPath").textContent = relPath;
            document.getElementById("wikiEditorTextarea").value = "読み込み中...";
            document.getElementById("wikiEditorModal").style.display = "flex";

            const selectEl = document.getElementById("wikiEditorHistorySelect");
            selectEl.innerHTML = '<option value="">最新版 (編集用)</option>';

            fetch("/api/raw?relPath=" + encodeURIComponent(relPath))
                .then(res => res.json())
                .then(data => {
                    if (data.markdown !== undefined) {
                        const mdVal = (typeof data.markdown === "object" && data.markdown !== null) ? (data.markdown.value || "") : data.markdown;
                        document.getElementById("wikiEditorTextarea").value = mdVal;
                    } else {
                        document.getElementById("wikiEditorTextarea").value = "エラー: 読み込みに失敗しました。";
                    }
                })
                .catch(err => {
                    document.getElementById("wikiEditorTextarea").value = "エラー: " + err;
                });

            fetch("/api/backups?relPath=" + encodeURIComponent(relPath))
                .then(res => res.json())
                .then(data => {
                    if (data.backups && data.backups.length > 0) {
                        data.backups.forEach(b => {
                            const opt = document.createElement("option");
                            opt.value = b.version;
                            opt.textContent = `${b.label} (${b.lastModified})`;
                            selectEl.appendChild(opt);
                        });
                    }
                })
                .catch(err => console.error("Backup list fetch error:", err));
        }

        function loadWikiHistoryVersion(selectEl) {
            const relPath = document.getElementById("wikiEditorPath").textContent;
            const version = selectEl.value;
            document.getElementById("wikiEditorTextarea").value = "履歴読込中...";

            let url = "/api/raw?relPath=" + encodeURIComponent(relPath);
            if (version) {
                url += "&version=" + encodeURIComponent(version);
            }

            fetch(url)
                .then(res => res.json())
                .then(data => {
                    if (data.markdown !== undefined) {
                        const mdVal = (typeof data.markdown === "object" && data.markdown !== null) ? (data.markdown.value || "") : data.markdown;
                        document.getElementById("wikiEditorTextarea").value = mdVal;
                    } else {
                        document.getElementById("wikiEditorTextarea").value = "エラー: 履歴の読み込みに失敗しました。";
                    }
                })
                .catch(err => {
                    document.getElementById("wikiEditorTextarea").value = "エラー: " + err;
                });
        }

        function closeWikiEditor() {
            document.getElementById("wikiEditorModal").style.display = "none";
        }

        function saveWikiMarkdown() {
            const relPath = document.getElementById("wikiEditorPath").textContent;
            const markdown = document.getElementById("wikiEditorTextarea").value;

            fetch("/api/save", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ relPath: relPath, markdown: markdown })
            })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    if (data.warning) {
                        alert("保存しました。\n\n" + data.warning);
                    } else {
                        alert("保存しました。");
                    }
                    location.reload();
                } else {
                    alert("保存エラー: " + (data.message || "原因不明"));
                }
            })
            .catch(err => {
                alert("通信エラー: " + err);
            });
        }

        document.addEventListener("DOMContentLoaded", function() {
            // -- Start of Sidebar Auto-Expand & Active Highlight --
            try {
                var currentPath = decodeURIComponent(location.pathname);
                var sidebar = document.querySelector("nav.sidebar");
                if (sidebar) {
                    var activeLink = sidebar.querySelector('a[href="' + currentPath + '"]');
                    if (!activeLink) {
                        var pathNoSlash = currentPath.replace(/\/$/, "");
                        activeLink = sidebar.querySelector('a[href="' + pathNoSlash + '"]') || sidebar.querySelector('a[href="' + currentPath + '/"]');
                    }
                    if (activeLink) {
                        activeLink.classList.add("active");
                        activeLink.scrollIntoView({ block: "nearest" });
                        
                        var parent = activeLink.parentElement;
                        while (parent && parent !== sidebar) {
                            if (parent.tagName === "DETAILS") {
                                parent.open = true;
                            }
                            parent = parent.parentElement;
                        }
                    }
                }
            } catch(e) { console.error("Sidebar activation error:", e); }
            // -- End of Sidebar Auto-Expand & Active Highlight --

            document.querySelectorAll("pre code.language-mermaid").forEach(function(el) {
                var pre = el.parentElement;
                var div = document.createElement("div");
                div.className = "mermaid";
                div.textContent = el.textContent;
                pre.replaceWith(div);
            });
            if (typeof mermaid !== "undefined") {
                mermaid.initialize({ startOnLoad: true, theme: "default" });
            }
        });
    </script>
</body>
</html>
'@
                $fullHtml = $template.Replace("{0}", $pageTitle).Replace("{1}", $sidebarHtml).Replace("{2}", $bodyContent)

                $config = Get-ConfigJson -TargetScriptDir $scriptDir
                if ($config.rag -and $config.rag.enabled) {
                    $chatWidgetHtml = Get-ChatWidgetHtml
                    $fullHtml = $fullHtml.Replace("</body>", "$chatWidgetHtml`n</body>")
                }

                $bytes = [System.Text.Encoding]::UTF8.GetBytes($fullHtml)
                Write-SafeHttpResponse -Response $response -Bytes $bytes

            # 画像やその他静的ファイルの返却処理
            } elseif (Test-Path -LiteralPath $fullPath -PathType Leaf) {
                $ext = [System.IO.Path]::GetExtension($fullPath).ToLower()
                $cType = "application/octet-stream"
                if ($mimeTypes.ContainsKey($ext)) {
                    $cType = $mimeTypes[$ext]
                }
                $bytes = [System.IO.File]::ReadAllBytes($fullPath)
                Write-SafeHttpResponse -Response $response -Bytes $bytes -ContentType $cType

            # 404 Not Found (XSS 対策済み)
            } else {
                $safePath = [System.Net.WebUtility]::HtmlEncode($rawPath)
                $notFoundBytes = [System.Text.Encoding]::UTF8.GetBytes("<h1>404 Not Found</h1><p>$safePath</p>")
                Write-SafeHttpResponse -Response $response -Bytes $notFoundBytes -StatusCode 404
            }
        } finally {
            try { $response.Close() } catch {}
        }
    }
} finally {
    if ($listener.IsListening) {
        $listener.Stop()
        $listener.Close()
    }
}
