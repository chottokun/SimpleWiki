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

# --- OKF YAML Front Matter 構文検証関数 ---

# --- モジュールのロード (lib/*.ps1) ---
. (Join-Path $libDir "WikiI18n.ps1")
. (Join-Path $libDir "WikiMetadata.ps1")
. (Join-Path $libDir "WikiSecurity.ps1")
. (Join-Path $libDir "WikiSearch.ps1")
. (Join-Path $libDir "WikiRag.ps1")
. (Join-Path $libDir "WikiViews.ps1")

Import-ExternalI18n -TargetScriptDir $scriptDir

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

# 起動時インデックス事前生成 (ノンブロッキング・バックグラウンド実行)
$initCfg = Get-ConfigJson -TargetScriptDir $scriptDir
$bgIndexingJob = $null
if ($initCfg.search -and $initCfg.search.prebuildIndex -eq $true) {
    try {
        # キャッシュが有効で既に最新が存在する場合は同期読み込み、それ以外は非同期ジョブで構築
        if (-not (Load-WikiIndexCache -TargetWikiDir $wikiDir -TargetScriptDir $scriptDir)) {
            Write-Host "インデックスをバックグラウンドで事前生成中..." -ForegroundColor Cyan
            $bgIndexingJob = Start-Job -ScriptBlock {
                param($targetDir, $baseScriptDir)
                $searchLib = Join-Path $baseScriptDir "lib\WikiSearch.ps1"
                $i18nLib   = Join-Path $baseScriptDir "lib\WikiI18n.ps1"
                if (Test-Path $i18nLib) { . $i18nLib }
                if (Test-Path $searchLib) { . $searchLib }
                Build-WikiIndex -TargetWikiDir $targetDir -TargetScriptDir $baseScriptDir | Out-Null
            } -ArgumentList $wikiDir, $scriptDir
        } else {
            Write-Host "インデックスキャッシュを読み込みました ($($script:WikiIndex.Count) 件)" -ForegroundColor Green
        }
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

$cancelHandler = $null
try {
    $cancelHandler = [System.ConsoleCancelEventHandler]{
        param($sender, $e)
        if ($bgIndexingJob) {
            try { Stop-Job -Job $bgIndexingJob -ErrorAction SilentlyContinue } catch {}
            try { Remove-Job -Job $bgIndexingJob -Force -ErrorAction SilentlyContinue } catch {}
        }
        if ($listener -and $listener.IsListening) {
            try { $listener.Stop() } catch {}
        }
    }
    [System.Console]::add_CancelKeyPress($cancelHandler)
} catch {
    # 非コンソール環境やリダイレクト環境での add_CancelKeyPress 例外を安全に無視
}

try {
    while ($listener.IsListening) {
        $asyncResult = $listener.BeginGetContext($null, $null)
        while (-not $asyncResult.AsyncWaitHandle.WaitOne(200)) {
            if (-not $listener.IsListening) { break }
        }
        if (-not $listener.IsListening) {
            break
        }

        try {
            $context = $listener.EndGetContext($asyncResult)
        } catch [System.ObjectDisposedException], [System.Net.HttpListenerException] {
            break
        } catch {
            if (-not $listener.IsListening) { break }
            throw
        }

        $request  = $context.Request
        $response = $context.Response

        try {
            $rawPath = [System.Net.WebUtility]::UrlDecode($request.Url.LocalPath)
            $queryParams = Get-QueryParams -Request $request
            $config = Get-ConfigJson -TargetScriptDir $scriptDir
            $reqLang = Get-RequestLanguage -QueryParams $queryParams -Cookies $request.Cookies -Config $config

            # 1. API エンドポイント (/api/shutdown, /api/config, /api/index.json, /api/chunks.json, /api/chat)
            if ($rawPath -eq "/api/shutdown" -and $request.HttpMethod -eq "POST") {
                $shutdownMsg = Get-LocalizedStr -Key "shutdown_done_desc" -Lang $reqLang
                $jsonRes = @{ success = $true; message = $shutdownMsg } | ConvertTo-Json
                Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                try { $response.Close() } catch {}
                Write-Host "UIからのシャットダウン要求を受信しました。サーバーを終了します..." -ForegroundColor Yellow
                if ($bgIndexingJob) {
                    try { Stop-Job -Job $bgIndexingJob -ErrorAction SilentlyContinue } catch {}
                    try { Remove-Job -Job $bgIndexingJob -Force -ErrorAction SilentlyContinue } catch {}
                }
                if ($listener.IsListening) {
                    try { $listener.Stop() } catch {}
                }
                break
            }

            if ($rawPath -eq "/api/indexing-status" -and $request.HttpMethod -eq "GET") {
                $statusObj = Get-WikiIndexingStatus -TargetWikiDir $wikiDir -TargetScriptDir $scriptDir
                $jsonRes = $statusObj | ConvertTo-Json
                Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                continue
            }

            if ($rawPath -eq "/api/config") {
                $configPath = Join-Path $scriptDir "config.json"
                if ($request.HttpMethod -eq "GET") {
                    if ($queryParams.ContainsKey("action") -and $queryParams["action"] -eq "indexing_status") {
                        $statusObj = Get-WikiIndexingStatus -TargetWikiDir $wikiDir -TargetScriptDir $scriptDir
                        $jsonRes = $statusObj | ConvertTo-Json
                        Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                        continue
                    }

                    $currCfg = Get-ConfigJson -TargetScriptDir $scriptDir
                    $safeCfg = [ordered]@{
                        search = if ($currCfg.search) { $currCfg.search } else { @{ prebuildIndex = $false; useCache = $false; cacheFolder = ".cache" } }
                        rag    = if ($currCfg.rag) {
                            @{
                                enabled      = [bool]$currCfg.rag.enabled
                                apiUrl       = [string]$currCfg.rag.apiUrl
                                model        = [string]$currCfg.rag.model
                                systemPrompt = [string]$currCfg.rag.systemPrompt
                            }
                        } else { @{ enabled = $false; apiUrl = "http://localhost:11434/v1"; model = "qwen2.5-coder-7b-instruct" } }
                        api    = if ($currCfg.api) { $currCfg.api } else { @{ defaultLimit = 100; maxLimit = 1000 } }
                    }
                    $jsonRes = $safeCfg | ConvertTo-Json -Depth 5
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                    continue
                }

                if ($request.HttpMethod -eq "POST") {
                    # インデックス手動再構築アクション
                    if ($queryParams.ContainsKey("action") -and $queryParams["action"] -eq "rebuild_index") {
                        try {
                            $script:WikiIndex = @()
                            $rebuilt = Build-WikiIndex -TargetWikiDir $wikiDir -ForceRefresh
                            $jsonRes = @{ success = $true; count = $rebuilt.Count; message = "インデックスを正常に再構築しました ($($rebuilt.Count) 件)" } | ConvertTo-Json
                            Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                        } catch {
                            $jsonRes = @{ success = $false; message = "インデックス再構築中にエラーが発生しました: $_" } | ConvertTo-Json
                            Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 500
                        }
                        continue
                    }

                    # ローカルキャッシュ全消去アクション
                    if ($queryParams.ContainsKey("action") -and $queryParams["action"] -eq "clear_all_caches") {
                        try {
                            $clearRes = Clear-AllWikiCaches -TargetScriptDir $scriptDir
                            $jsonRes = @{ success = $true; deletedFiles = $clearRes.deletedFiles; message = "ローカルキャッシュを全消去しました ($($clearRes.deletedFiles) 件のファイルを削除)" } | ConvertTo-Json
                            Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                        } catch {
                            $jsonRes = @{ success = $false; message = "ローカルキャッシュ消去中にエラーが発生しました: $_" } | ConvertTo-Json
                            Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 500
                        }
                        continue
                    }

                    # 設定保存リクエスト
                    $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                    $bodyText = $reader.ReadToEnd()
                    $reqObj = try { $bodyText | ConvertFrom-Json } catch { $null }

                    if ($null -eq $reqObj) {
                        $jsonRes = @{ success = $false; message = "リクエスト JSON のパースに失敗しました。" } | ConvertTo-Json
                        Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 400
                        continue
                    }

                    # 既存設定の読み込み (RAW JSON をハッシュ/辞書形式に変換して保持)
                    $cfgDict = [ordered]@{}
                    if (Test-Path $configPath) {
                        try {
                            $rawJson = Get-Content -Path $configPath -Raw -Encoding UTF8
                            $parsedObj = $rawJson | ConvertFrom-Json
                            # Convert PSCustomObject recursively to OrderedDictionary
                            function Convert-PSObjectToOrdered ($obj) {
                                if ($null -eq $obj) { return $null }
                                if ($obj -is [System.Collections.IDictionary]) { return $obj }
                                if ($obj -is [System.Array] -or $obj -is [System.Collections.IList]) {
                                    $arr = @()
                                    foreach ($item in $obj) { $arr += (Convert-PSObjectToOrdered $item) }
                                    return $arr
                                }
                                if ($obj -is [PSCustomObject]) {
                                    $dict = [ordered]@{}
                                    foreach ($prop in $obj.PSObject.Properties) {
                                        $dict[$prop.Name] = Convert-PSObjectToOrdered $prop.Value
                                    }
                                    return $dict
                                }
                                return $obj
                            }
                            $cfgDict = Convert-PSObjectToOrdered $parsedObj
                        } catch {
                            $cfgDict = [ordered]@{}
                        }
                    }

                    if (-not $cfgDict.Contains("search")) {
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
                            if ([string]::IsNullOrWhiteSpace($cFolder) -or $cFolder -match '[\:\\/]' -or $cFolder -match '\.\.') {
                                $validationError = "キャッシュフォルダ名が無効です。英数字・ハイフン・アンダースコア・ドット始まりのみ許可されています (ディレクトリトラバーサルは禁止)。"
                            } else {
                                $cfgDict["search"]["cacheFolder"] = $cFolder
                            }
                        }
                    }

                    # rag 設定の安全な更新
                    if ($null -eq $validationError -and $reqObj.PSObject.Properties["rag"]) {
                        if (-not $cfgDict.Contains("rag")) {
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
                        if ($rObj.PSObject.Properties["userEmail"]) {
                            $cfgDict["rag"]["userEmail"] = [string]$rObj.userEmail
                        }

                        # アクティベーションコードの検証 ＆ DPAPI への自動変換
                        if ($rObj.PSObject.Properties["activationCode"] -and -not [string]::IsNullOrWhiteSpace($rObj.activationCode)) {
                            $rawActCode = [string]$rObj.activationCode
                            $targetEmail = if ($rObj.PSObject.Properties["userEmail"]) { [string]$rObj.userEmail } else { "" }
                            $decryptedKey = Unprotect-ActivationCode -EncryptedText $rawActCode -Email $targetEmail

                            if ([string]::IsNullOrWhiteSpace($decryptedKey)) {
                                $validationError = "アクティベーションコードが無効です。この PC のマシン ID 用に発行されたコードであるか、メールアドレスが正しいかご確認ください。"
                            } else {
                                # DPAPI で暗号化してローカル保護
                                $dpapiKey = Protect-StringDpapi -PlainText $decryptedKey
                                $cfgDict["rag"]["apiKey"] = $dpapiKey
                            }
                        }
                    }

                    if ($null -ne $validationError) {
                        $respJson = @{ success = $false; message = $validationError } | ConvertTo-Json
                        Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($respJson)) -ContentType "application/json; charset=utf-8" -StatusCode 400
                        continue
                    }

                    try {
                        $jsonContent = $cfgDict | ConvertTo-Json -Depth 10
                        $tmpConfigPath = "$configPath.tmp"

                        # 1. 一時ファイルに安全に書き出し (UTF-8)
                        [System.IO.File]::WriteAllText($tmpConfigPath, $jsonContent, [System.Text.Encoding]::UTF8)

                        # 2. 既存 config.json がある場合、3世代バックアップローテーション
                        if (Test-Path $configPath) {
                            $maxConfigBackups = 3
                            for ($bIdx = $maxConfigBackups - 1; $bIdx -ge 1; $bIdx--) {
                                $oldBak = "$configPath.bak$bIdx"
                                $newBak = "$configPath.bak$($bIdx + 1)"
                                if (Test-Path $oldBak) {
                                    Copy-Item -Path $oldBak -Destination $newBak -Force
                                }
                            }
                            Copy-Item -Path $configPath -Destination "$configPath.bak1" -Force
                        }

                        # 3. アトミック置換
                        Move-Item -Path $tmpConfigPath -Destination $configPath -Force

                        $respJson = @{ success = $true; message = "設定を正常に更新しました (バックアップを作成しました)。" } | ConvertTo-Json
                        Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($respJson)) -ContentType "application/json; charset=utf-8"
                    } catch {
                        if (Test-Path $tmpConfigPath) { Remove-Item -Path $tmpConfigPath -Force -ErrorAction SilentlyContinue }
                        $respJson = @{ success = $false; message = "config.json の書き込みに失敗しました: $_" } | ConvertTo-Json
                        Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($respJson)) -ContentType "application/json; charset=utf-8" -StatusCode 500
                    }
                    continue
                }
            }

            if ($rawPath -eq "/api/index.json") {
                $jsonStr = Get-ApiIndexJson -QueryParams $queryParams
                $bytes   = [System.Text.Encoding]::UTF8.GetBytes($jsonStr)
                Write-SafeHttpResponse -Response $response -Bytes $bytes -ContentType "application/json; charset=utf-8"
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
                        $bakLabel = Get-LocalizedStr -Key "editor_gen_prefix" -Lang $reqLang -FormatArgs @($i)
                        $backups.Add(@{
                            version      = "bak$i"
                            label        = $bakLabel
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
                    $warnPrefix = Get-LocalizedStr -Key "editor_warning_yaml" -Lang $reqLang
                    $resData["warning"] = "$warnPrefix`n・" + ($yamlSyntax.warnings -join "`n・")
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

                $chatLang = if ($reqObj -and $reqObj.lang) { $reqObj.lang.ToString().ToLower().Trim() } else { $reqLang }
                if (-not $script:I18n.ContainsKey($chatLang)) { $chatLang = "ja" }

                $isStream = $true
                if ($reqObj -and $reqObj.PSObject.Properties['stream'] -and $reqObj.stream -eq $false) {
                    $isStream = $false
                }

                if ($isStream) {
                    $response.StatusCode = 200
                    $response.ContentType = "text/event-stream; charset=utf-8"
                    $response.Headers["Cache-Control"] = "no-cache"
                    $response.Headers["Connection"] = "keep-alive"
                    $response.SendChunked = $true

                    $sendSse = {
                        param([string]$Type, [object]$Data)
                        try {
                            $eventObj = @{ type = $Type }
                            if ($Data -is [string]) {
                                $eventObj["content"] = $Data
                            } elseif ($Data -is [hashtable]) {
                                foreach ($k in $Data.Keys) { $eventObj[$k] = $Data[$k] }
                            } elseif ($Data -is [PSCustomObject]) {
                                foreach ($p in $Data.PSObject.Properties) { $eventObj[$p.Name] = $p.Value }
                            }
                            $jsonStr = $eventObj | ConvertTo-Json -Compress -Depth 5
                            $sseBytes = [System.Text.Encoding]::UTF8.GetBytes("data: $jsonStr`n`n")
                            $response.OutputStream.Write($sseBytes, 0, $sseBytes.Length)
                            $response.OutputStream.Flush()
                        } catch { }
                    }

                    if ($reqMode -eq "agentic") {
                        $maxTurns = 5
                        if ($config.rag -and $config.rag.maxAgentTurns) {
                            $maxTurns = [int]$config.rag.maxAgentTurns
                        }
                        $maxDocChars = 2000
                        if ($config.rag -and $config.rag.maxDocCharLength) {
                            $maxDocChars = [int]$config.rag.maxDocCharLength
                        }
                        $customAgenticPrompt = if ($config.rag -and $config.rag.agenticSystemPrompt) { $config.rag.agenticSystemPrompt } else { "" }

                        try {
                            $agentRes = Invoke-AgenticRagChat -ApiUrl $config.rag.apiUrl -ApiKey $config.rag.apiKey -Model $config.rag.model -UserMessage $userMsg -History $processedHistory -WikiDir $wikiDir -MaxTurns $maxTurns -MaxDocChars $maxDocChars -TimeoutSec $timeoutSec -CurrentDoc $currDoc -Lang $chatLang -CustomAgenticPrompt $customAgenticPrompt -Stream -OnThinkingCallback {
                                param($thinkLog)
                                & $sendSse "thinking" $thinkLog
                            } -OnChunkReceived {
                                param($tokenChunk)
                                & $sendSse "token" $tokenChunk
                            }
                            & $sendSse "done" @{
                                mode        = "agentic"
                                answer      = $agentRes.answer
                                thinkingLog = $agentRes.thinkingLog
                                sources     = $agentRes.sources
                            }
                        } catch {
                            & $sendSse "error" @{ message = "Agentic RAG 実行中にエラーが発生しました: $_" }
                        }
                    } else {
                        # Fast RAG Stream
                        Build-WikiIndex -TargetWikiDir $wikiDir | Out-Null
                        $activeDocs = @($script:WikiIndex | Where-Object { $_.Status -in @("active", "stable") })
                        $maxDocs = 3
                        if ($config.rag -and $config.rag.maxContextDocs) {
                            $maxDocs = [int]$config.rag.maxContextDocs
                        }

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
                        if ($currDoc) { $contextDocs.Add($currDoc) }

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

                        $contextStrBuilder = [System.Text.StringBuilder]::new()
                        $sourcesList = [System.Collections.Generic.List[PSObject]]::new()
                        $isChatEn = ($chatLang -eq "en")

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
                            if ($isChatEn) {
                                [void]$contextStrBuilder.AppendLine("■ Document: $($cDoc.Title)")
                                [void]$contextStrBuilder.AppendLine("・Domain: $($cDoc.Domain)")
                                [void]$contextStrBuilder.AppendLine("・Author: $($cDoc.Author)")
                                [void]$contextStrBuilder.AppendLine("・Last Updated: $($cDoc.LastUpdated.ToString('yyyy-MM-dd'))")
                                [void]$contextStrBuilder.AppendLine("・Status: $($cDoc.Status) (active)")
                                [void]$contextStrBuilder.AppendLine("Body:")
                            } else {
                                [void]$contextStrBuilder.AppendLine("■ ドキュメント: $($cDoc.Title)")
                                [void]$contextStrBuilder.AppendLine("・ドメイン: $($cDoc.Domain)")
                                [void]$contextStrBuilder.AppendLine("・著者: $($cDoc.Author)")
                                [void]$contextStrBuilder.AppendLine("・最終更新日: $($cDoc.LastUpdated.ToString('yyyy-MM-dd'))")
                                [void]$contextStrBuilder.AppendLine("・ステータス: $($cDoc.Status) (現行)")
                                [void]$contextStrBuilder.AppendLine("本文:")
                            }
                            [void]$contextStrBuilder.AppendLine($snippet)
                        }

                        $baseSysPrompt = Get-LocalizedStr -Key "default_system_prompt" -Lang $chatLang
                        if ($config.rag -and $config.rag.systemPrompt) {
                            $baseSysPrompt = $config.rag.systemPrompt
                        }
                        $ctxHeader = if ($isChatEn) { "[Referenced Wiki Context]" } else { "[参照Wikiコンテキスト]" }
                        $fullSysPrompt = $baseSysPrompt + [System.Environment]::NewLine + [System.Environment]::NewLine + $ctxHeader + [System.Environment]::NewLine + $contextStrBuilder.ToString()

                        try {
                            $answerText = Invoke-OpenAiChatCompletions -ApiUrl $config.rag.apiUrl -ApiKey $config.rag.apiKey -Model $config.rag.model -SystemPrompt $fullSysPrompt -UserMessage $userMsg -History $processedHistory -TimeoutSec $timeoutSec -Stream -OnChunkReceived {
                                param($tokenChunk)
                                & $sendSse "token" $tokenChunk
                            }
                            & $sendSse "done" @{
                                mode    = "fast"
                                answer  = $answerText
                                sources = $sourcesList
                            }
                        } catch {
                            & $sendSse "error" @{ message = "LLM との通信に失敗しました: $_" }
                        }
                    }

                    try {
                        $response.OutputStream.Close()
                        $response.Close()
                    } catch { }
                    continue
                }

                if ($reqMode -eq "agentic") {
                    # --- Agentic RAG Mode (非ストリーム) ---
                    $maxTurns = 5
                    if ($config.rag -and $config.rag.maxAgentTurns) {
                        $maxTurns = [int]$config.rag.maxAgentTurns
                    }
                    $maxDocChars = 2000
                    if ($config.rag -and $config.rag.maxDocCharLength) {
                        $maxDocChars = [int]$config.rag.maxDocCharLength
                    }

                    $customAgenticPrompt = if ($config.rag -and $config.rag.agenticSystemPrompt) { $config.rag.agenticSystemPrompt } else { "" }

                    try {
                        $agentRes = Invoke-AgenticRagChat -ApiUrl $config.rag.apiUrl -ApiKey $config.rag.apiKey -Model $config.rag.model -UserMessage $userMsg -History $processedHistory -WikiDir $wikiDir -MaxTurns $maxTurns -MaxDocChars $maxDocChars -TimeoutSec $timeoutSec -CurrentDoc $currDoc -Lang $chatLang -CustomAgenticPrompt $customAgenticPrompt
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

                # --- Fast RAG Mode (非ストリーム) ---
                # 1. OKF 文脈検索 (WinRT 形態素解析エンジン)
                Build-WikiIndex -TargetWikiDir $wikiDir | Out-Null
                $activeDocs = @($script:WikiIndex | Where-Object { $_.Status -in @("active", "stable") })

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

                $isChatEn = ($chatLang -eq "en")

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
                    if ($isChatEn) {
                        [void]$contextStrBuilder.AppendLine("■ Document: $($cDoc.Title)")
                        [void]$contextStrBuilder.AppendLine("・Domain: $($cDoc.Domain)")
                        [void]$contextStrBuilder.AppendLine("・Author: $($cDoc.Author)")
                        [void]$contextStrBuilder.AppendLine("・Last Updated: $($cDoc.LastUpdated.ToString('yyyy-MM-dd'))")
                        [void]$contextStrBuilder.AppendLine("・Status: $($cDoc.Status) (active)")
                        [void]$contextStrBuilder.AppendLine("Body:")
                    } else {
                        [void]$contextStrBuilder.AppendLine("■ ドキュメント: $($cDoc.Title)")
                        [void]$contextStrBuilder.AppendLine("・ドメイン: $($cDoc.Domain)")
                        [void]$contextStrBuilder.AppendLine("・著者: $($cDoc.Author)")
                        [void]$contextStrBuilder.AppendLine("・最終更新日: $($cDoc.LastUpdated.ToString('yyyy-MM-dd'))")
                        [void]$contextStrBuilder.AppendLine("・ステータス: $($cDoc.Status) (現行)")
                        [void]$contextStrBuilder.AppendLine("本文:")
                    }
                    [void]$contextStrBuilder.AppendLine($snippet)
                }

                $baseSysPrompt = Get-LocalizedStr -Key "default_system_prompt" -Lang $chatLang
                if ($config.rag -and $config.rag.systemPrompt) {
                    $baseSysPrompt = $config.rag.systemPrompt
                }
                $ctxHeader = if ($isChatEn) { "[Referenced Wiki Context]" } else { "[参照Wikiコンテキスト]" }
                $fullSysPrompt = $baseSysPrompt + [System.Environment]::NewLine + [System.Environment]::NewLine + $ctxHeader + [System.Environment]::NewLine + $contextStrBuilder.ToString()

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
                $pageTitle     = Get-LocalizedStr -Key "recent_updates_title" -Lang $reqLang
                $bodyContent   = Get-RecentViewHtml -Lang $reqLang
            } elseif ($rawPath -eq "/tags") {
                $isDynamicView = $true
                $tagParam      = $queryParams["tag"]
                $pageTitle     = if ($tagParam) { Get-LocalizedStr -Key "tag_results_title" -Lang $reqLang -FormatArgs @($tagParam) } else { Get-LocalizedStr -Key "tag_list_title" -Lang $reqLang }
                $bodyContent   = Get-TagsViewHtml -SelectedTag $tagParam -Lang $reqLang
            } elseif ($rawPath -eq "/maintenance") {
                $isDynamicView = $true
                $pageTitle     = Get-LocalizedStr -Key "maint_dashboard_title" -Lang $reqLang
                $bodyContent   = Get-MaintenanceViewHtml -Lang $reqLang
            } elseif ($rawPath -eq "/authors") {
                $isDynamicView = $true
                $authorParam   = $queryParams["name"]
                $pageTitle     = if ($authorParam) { Get-LocalizedStr -Key "author_results_title" -Lang $reqLang -FormatArgs @($authorParam) } else { Get-LocalizedStr -Key "author_list_title" -Lang $reqLang }
                $bodyContent   = Get-AuthorsViewHtml -SelectedAuthor $authorParam -Lang $reqLang
            } elseif ($rawPath -eq "/settings") {
                $isDynamicView = $true
                $pageTitle     = Get-LocalizedStr -Key "settings_title" -Lang $reqLang
                $bodyContent   = Get-SettingsViewHtml -Lang $reqLang
            } elseif ($rawPath -eq "/search") {
                $isDynamicView = $true
                $qParam        = $queryParams["q"]
                $stParam       = $queryParams["status"]
                $domParam      = $queryParams["domain"]
                $stValue       = if (-not [string]::IsNullOrWhiteSpace($stParam)) { $stParam } else { "active" }
                $pageTitle     = if ($qParam) { (Get-LocalizedStr -Key "search_btn" -Lang $reqLang) + ": " + $qParam } else { Get-LocalizedStr -Key "search_btn" -Lang $reqLang }
                $bodyContent   = Get-SearchViewHtml -Query $qParam -StatusFilter $stValue -DomainFilter $domParam -Lang $reqLang
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
                    $bodyContent   = Get-DirectoryListingHtml -DirFullPath $fullPath -RawUrlPath $rawPath -Lang $reqLang
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

                    $okfTopBar   = Get-OkfTopBarHtml -Meta $meta -RelPath $relPath -Lang $reqLang
                    $okfFooter   = Get-OkfFooterCardHtml -Meta $meta -Lang $reqLang
                    $bodyContent = $okfTopBar + $renderedHtml + $okfFooter
                    $pageTitle   = [System.Net.WebUtility]::HtmlEncode($meta.Title)
                }

                $sidebarHtml = Get-SidebarHtml -currentRelPath $relPath -Lang $reqLang

                $template = @'
<!DOCTYPE html>
<html lang="{18}">
<head>
<meta charset="UTF-8">
<title>{0} - {20} OKF</title>
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
    .shutdown-btn { background: rgba(220, 53, 69, 0.15); color: #f85149; border: 1px solid rgba(248, 81, 73, 0.4); padding: 4px 10px; font-size: 12px; font-weight: bold; border-radius: 4px; cursor: pointer; display: flex; align-items: center; gap: 4px; transition: all 0.2s ease; }
    .shutdown-btn:hover { background: #da3633; color: #fff; border-color: #da3633; }

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
    @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
</style>
</head>
<body>
    <header class="top-header">
        <a href="/" class="brand">{20} <span class="badge badge-active">OKF</span></a>
        <nav class="top-nav">
            <a href="/">{3}</a>
            <a href="/recent">{4}</a>
            <a href="/tags">{5}</a>
            <a href="/maintenance">{6}</a>
            <a href="/authors">{7}</a>
            <a href="/settings">{19}</a>
            <a href="/api/index.json" target="_blank">{8}</a>
        </nav>
        <div style="display: flex; align-items: center; gap: 10px;">
            <select id="wikiLangSelect" onchange="switchWikiLanguage(this.value)" style="padding: 4px 8px; font-size: 12px; border: 1px solid #444; border-radius: 4px; background: #2f363d; color: #fff; cursor: pointer;">
                {9}
            </select>
            <form action="/search" method="GET" accept-charset="UTF-8" class="search-form">
                <input type="text" name="q" placeholder="{10}" required>
                <button type="submit">{11}</button>
            </form>
            <button type="button" class="shutdown-btn" onclick="shutdownWikiServer()" title="{21}">{21}</button>
        </div>
    </header>

    <!-- Global Indexing Progress Banner -->
    <div id="globalIndexingBanner" style="display:none; background: #e8f4fd; border-bottom: 1px solid #c8e1ff; padding: 10px 24px; font-size: 13px; color: #0366d6;">
        <div style="max-width: 1200px; margin: 0 auto; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 10px;">
            <div style="display: flex; align-items: center; gap: 10px;">
                <span class="indexing-spinner" style="display:inline-block; width:14px; height:14px; border:2px solid #0366d6; border-top-color:transparent; border-radius:50%; animation:spin 0.8s linear infinite;"></span>
                <span id="globalIndexingMsg" style="font-weight: 600;"></span>
                <span style="font-size: 12px; color: #586069;">({31})</span>
            </div>
            <div style="display: flex; align-items: center; gap: 10px; min-width: 180px;">
                <div style="flex: 1; height: 6px; background: #d1e5f9; border-radius: 3px; overflow: hidden;">
                    <div id="globalIndexingBar" style="width: 0%; height: 100%; background: #0366d6; transition: width 0.3s;"></div>
                </div>
                <span id="globalIndexingPct" style="font-size: 12px; font-weight: bold; min-width: 35px; text-align: right;">0%</span>
            </div>
        </div>
    </div>

    <div class="layout-container">
        <nav class="sidebar">
            <h2>{12}</h2>
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
                    <span>{13}</span>
                    <select id="wikiEditorHistorySelect" onchange="loadWikiHistoryVersion(this)" style="background: #24292e; color: #fff; border: 1px solid #444; border-radius: 4px; padding: 2px 6px; font-size: 12px; cursor: pointer;">
                        <option value="">{14}</option>
                    </select>
                </div>
                <span style="font-size: 12px; color: #ccc;" id="wikiEditorPath"></span>
            </div>
            <div class="wiki-editor-body">
                <textarea id="wikiEditorTextarea" class="wiki-editor-textarea" placeholder="{15}"></textarea>
            </div>
            <div class="wiki-editor-footer">
                <button class="wiki-editor-cancel-btn" onclick="closeWikiEditor()">{16}</button>
                <button class="wiki-editor-save-btn" onclick="saveWikiMarkdown()">{17}</button>
            </div>
        </div>
    </div>

    <!-- Server Shutdown Overlay -->
    <div id="shutdownOverlay" style="display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0, 0, 0, 0.85); z-index: 99999; justify-content: center; align-items: center; flex-direction: column; color: #fff; text-align: center;">
        <div style="background: #1b1f23; border: 1px solid #444; border-radius: 12px; padding: 40px; max-width: 500px; box-shadow: 0 10px 30px rgba(0,0,0,0.5);">
            <h2 style="margin: 0 0 16px 0; color: #f85149; font-size: 24px; border: none;">{23}</h2>
            <p style="font-size: 15px; color: #d1d5da; margin-bottom: 0; line-height: 1.6;">{24}</p>
        </div>
    </div>

    <script src="/lib/mermaid.min.js"></script>
    <script>
        function shutdownWikiServer() {
            if (!confirm('{22}')) { return; }
            try {
                fetch('/api/shutdown', { method: 'POST' }).catch(function() {});
            } catch(e) {}
            var overlay = document.getElementById('shutdownOverlay');
            if (overlay) { overlay.style.display = 'flex'; }
        }

        function openWikiEditor(btn) {
            const relPath = btn.getAttribute("data-relpath");
            document.getElementById("wikiEditorPath").textContent = relPath;
            document.getElementById("wikiEditorTextarea").value = "{25}";
            document.getElementById("wikiEditorModal").style.display = "flex";

            const selectEl = document.getElementById("wikiEditorHistorySelect");
            selectEl.innerHTML = '<option value="">{14}</option>';

            fetch("/api/raw?relPath=" + encodeURIComponent(relPath))
                .then(res => res.json())
                .then(data => {
                    if (data.markdown !== undefined) {
                        const mdVal = (typeof data.markdown === "object" && data.markdown !== null) ? (data.markdown.value || "") : data.markdown;
                        document.getElementById("wikiEditorTextarea").value = mdVal;
                    } else {
                        document.getElementById("wikiEditorTextarea").value = "{27}";
                    }
                })
                .catch(err => {
                    document.getElementById("wikiEditorTextarea").value = "{27} " + err;
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
            document.getElementById("wikiEditorTextarea").value = "{26}";

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
                        document.getElementById("wikiEditorTextarea").value = "{28}";
                    }
                })
                .catch(err => {
                    document.getElementById("wikiEditorTextarea").value = "{28} " + err;
                });
        }

        function switchWikiLanguage(lang) {
            document.cookie = "lang=" + lang + "; path=/; max-age=31536000";
            location.reload();
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
                        alert("{29}\n\n" + data.warning);
                    } else {
                        alert("{30}");
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

            // -- Global Indexing Status Check & Polling --
            (function() {
                var banner = document.getElementById("globalIndexingBanner");
                var msgEl  = document.getElementById("globalIndexingMsg");
                var barEl  = document.getElementById("globalIndexingBar");
                var pctEl  = document.getElementById("globalIndexingPct");
                if (!banner || !msgEl || !barEl || !pctEl) return;

                var polling = null;
                function checkStatus() {
                    fetch("/api/indexing-status")
                    .then(function(r) { return r.json(); })
                    .then(function(st) {
                        if (st && st.IsBuilding) {
                            banner.style.display = "block";
                            var msgTemplate = "{32}";
                            var current = st.Current || 0;
                            var total = st.Total || 0;
                            var pct = st.Percent || 0;
                            var formattedMsg = msgTemplate ? msgTemplate.replace("__INDEX_CURR__", current).replace("__INDEX_TOTAL__", total) : ("⏳ " + current + " / " + total);
                            msgEl.textContent = formattedMsg;
                            barEl.style.width = pct + "%";
                            pctEl.textContent = pct + "%";

                            if (!polling) {
                                polling = setInterval(checkStatus, 500);
                            }
                        } else {
                            if (polling) {
                                clearInterval(polling);
                                polling = null;
                                barEl.style.width = "100%";
                                pctEl.textContent = "100%";
                                setTimeout(function() {
                                    banner.style.display = "none";
                                }, 1500);
                            }
                        }
                    })
                    .catch(function(e) {
                        if (polling) { clearInterval(polling); polling = null; }
                    });
                }
                checkStatus();
                // 起動直後のスキャン開始ラグを考慮して1秒後にも再試行
                setTimeout(checkStatus, 1000);
            })();
            // -- End Global Indexing Status Check --
        });
    </script>
</body>
</html>
'@
                $chatWidgetHtml = ""
                $config = Get-ConfigJson -TargetScriptDir $scriptDir
                if ($config.rag -and $config.rag.enabled) {
                    $chatWidgetHtml = Get-ChatWidgetHtml -Lang $reqLang
                }

                $navBrand     = Get-LocalizedStr -Key "brand_title" -Lang $reqLang
                $navShutdown  = Get-LocalizedStr -Key "shutdown_btn" -Lang $reqLang
                $shutdownConfirmJs = ConvertTo-JsString (Get-LocalizedStr -Key "shutdown_confirm" -Lang $reqLang)
                $shutdownDoneTitleJs = ConvertTo-JsString (Get-LocalizedStr -Key "shutdown_done_title" -Lang $reqLang)
                $shutdownDoneDescJs = ConvertTo-JsString (Get-LocalizedStr -Key "shutdown_done_desc" -Lang $reqLang)

                $edLoadingJs       = ConvertTo-JsString (Get-LocalizedStr -Key "editor_loading" -Lang $reqLang)
                $edHistoryLoadingJs = ConvertTo-JsString (Get-LocalizedStr -Key "editor_history_loading" -Lang $reqLang)
                $edLoadErrorJs     = ConvertTo-JsString (Get-LocalizedStr -Key "editor_load_error" -Lang $reqLang)
                $edBackupLoadErrJs = ConvertTo-JsString (Get-LocalizedStr -Key "editor_backup_load_err" -Lang $reqLang)
                $edSavedWarningJs  = ConvertTo-JsString (Get-LocalizedStr -Key "editor_saved_warning" -Lang $reqLang)
                $edSavedJs         = ConvertTo-JsString (Get-LocalizedStr -Key "editor_saved" -Lang $reqLang)

                $navHome      = Get-LocalizedStr -Key "home" -Lang $reqLang
                $navRecent    = Get-LocalizedStr -Key "recent_updates" -Lang $reqLang
                $navTags      = Get-LocalizedStr -Key "tags" -Lang $reqLang
                $navMaint     = Get-LocalizedStr -Key "maintenance" -Lang $reqLang
                $navAuthors   = Get-LocalizedStr -Key "authors" -Lang $reqLang
                $navSettings  = Get-LocalizedStr -Key "settings" -Lang $reqLang
                $navApi       = Get-LocalizedStr -Key "api_json" -Lang $reqLang
                $searchHolder = Get-LocalizedStr -Key "search_placeholder" -Lang $reqLang
                $searchBtnTxt = Get-LocalizedStr -Key "search_btn" -Lang $reqLang
                $docListTitle = Get-LocalizedStr -Key "doc_list_title" -Lang $reqLang
                $edTitle      = Get-LocalizedStr -Key "editor_title" -Lang $reqLang
                $edLatest     = Get-LocalizedStr -Key "editor_latest_version" -Lang $reqLang
                $edHolder     = Get-LocalizedStr -Key "editor_placeholder" -Lang $reqLang
                $edCancel     = Get-LocalizedStr -Key "editor_cancel_btn" -Lang $reqLang
                $edSave       = Get-LocalizedStr -Key "editor_save_btn" -Lang $reqLang

                $langOptionsHtml = foreach ($k in ($script:I18n.Keys | Sort-Object)) {
                    $sel = if ($k -eq $reqLang) { "selected" } else { "" }
                    $label = switch ($k) {
                        "ja" { "日本語 (JP)" }
                        "en" { "English (EN)" }
                        default { $k.ToUpper() }
                    }
                    "<option value='$k' $sel>$label</option>"
                }
                $langOptionsStr = $langOptionsHtml -join ""

                $indexingCacheReason = Get-LocalizedStr -Key "indexing_cache_reason" -Lang $reqLang
                $rawIndexingInProg   = Get-LocalizedStr -Key "indexing_in_progress" -Lang $reqLang -FormatArgs @("__INDEX_CURR__", "__INDEX_TOTAL__")
                $indexingInProgressJs = ConvertTo-JsString $rawIndexingInProg

                $fullHtml = $template.Replace("{0}", $pageTitle).Replace("{1}", $sidebarHtml).Replace("{2}", $bodyContent).Replace("{3}", $navHome).Replace("{4}", $navRecent).Replace("{5}", $navTags).Replace("{6}", $navMaint).Replace("{7}", $navAuthors).Replace("{8}", $navApi).Replace("{9}", $langOptionsStr).Replace("{10}", $searchHolder).Replace("{11}", $searchBtnTxt).Replace("{12}", $docListTitle).Replace("{13}", $edTitle).Replace("{14}", $edLatest).Replace("{15}", $edHolder).Replace("{16}", $edCancel).Replace("{17}", $edSave).Replace("{18}", $reqLang).Replace("{19}", $navSettings).Replace("{20}", $navBrand).Replace("{21}", $navShutdown).Replace("{22}", $shutdownConfirmJs).Replace("{23}", $shutdownDoneTitleJs).Replace("{24}", $shutdownDoneDescJs).Replace("{25}", $edLoadingJs).Replace("{26}", $edHistoryLoadingJs).Replace("{27}", $edLoadErrorJs).Replace("{28}", $edBackupLoadErrJs).Replace("{29}", $edSavedWarningJs).Replace("{30}", $edSavedJs).Replace("{31}", $indexingCacheReason).Replace("{32}", $indexingInProgressJs)

                if (-not [string]::IsNullOrWhiteSpace($chatWidgetHtml)) {
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
    if ($null -ne $cancelHandler) {
        try { [System.Console]::remove_CancelKeyPress($cancelHandler) } catch {}
    }
    if ($listener) {
        if ($listener.IsListening) {
            try { $listener.Stop() } catch {}
        }
        try { $listener.Close() } catch {}
    }
}

exit 0

