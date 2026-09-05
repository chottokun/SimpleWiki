# ==============================================================================
#  SimpleWiki Server HTTP Routing, Endpoint Dispatching & SSE Module
#  Encoding: UTF-8 with BOM
# ==============================================================================

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
        $null = $_ # Suppress client disconnects
    } catch {
        Write-Warning "HTTP Response Send Error: $_"
    }
}

function Invoke-WikiRouteRequest {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
    param (
        [Parameter(Mandatory = $true)][System.Net.HttpListenerContext]$Context,
        [string]$WikiDir = "",
        [string]$ScriptDir = "",
        $Listener = $null,
        $BgIndexingJob = $null
    )

    $request  = $Context.Request
    $response = $Context.Response

    $targetWikiDir = if (-not [string]::IsNullOrWhiteSpace($WikiDir)) { $WikiDir } else { $scriptDir }
    $targetScriptDir = if (-not [string]::IsNullOrWhiteSpace($ScriptDir)) { $ScriptDir } else { $scriptDir }
    $fullWikiDir = $targetWikiDir.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

    $mimeTypes = @{
        ".html" = "text/html; charset=utf-8"
        ".css"  = "text/css; charset=utf-8"
        ".js"   = "application/javascript; charset=utf-8"
        ".json" = "application/json; charset=utf-8"
        ".png"  = "image/png"
        ".jpg"  = "image/jpeg"
        ".jpeg" = "image/jpeg"
        ".gif"  = "image/gif"
        ".svg"  = "image/svg+xml"
        ".ico"  = "image/x-icon"
        ".md"   = "text/markdown; charset=utf-8"
    }

    try {
        $rawPath     = [System.Net.WebUtility]::UrlDecode($request.Url.LocalPath)
        $queryParams = Get-QueryParams -Request $request
        $config      = Get-ConfigJson -TargetScriptDir $targetScriptDir
        $reqLang     = Get-RequestLanguage -QueryParams $queryParams -Cookies $request.Cookies -Config $config

        # 1. API Endpoint Routing
        if ($rawPath -eq "/api/shutdown" -and $request.HttpMethod -eq "POST") {
            $shutdownMsg = Get-LocalizedStr -Key "shutdown_done_desc" -Lang $reqLang
            $jsonRes = @{ success = $true; message = $shutdownMsg } | ConvertTo-Json
            Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
            try { $response.Close() } catch { $null = $_ }
            Write-Host "UIからのシャットダウン要求を受信しました。サーバーを終了します..." -ForegroundColor Yellow
            if ($BgIndexingJob) {
                try { Stop-Job -Job $BgIndexingJob -ErrorAction SilentlyContinue } catch { $null = $_ }
                try { Remove-Job -Job $BgIndexingJob -Force -ErrorAction SilentlyContinue } catch { $null = $_ }
            }
            if ($Listener -and $Listener.IsListening) {
                try { $Listener.Stop() } catch { $null = $_ }
            }
            return $true
        }

        if ($rawPath -eq "/api/indexing-status" -and $request.HttpMethod -eq "GET") {
            $statusObj = Get-WikiIndexingStatus -TargetWikiDir $targetWikiDir -TargetScriptDir $targetScriptDir
            $jsonRes = $statusObj | ConvertTo-Json
            Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
            return $false
        }

        if ($rawPath -eq "/api/config") {
            $configPath = Join-Path $targetScriptDir "config.json"
            if ($request.HttpMethod -eq "GET") {
                if ($queryParams.ContainsKey("action") -and $queryParams["action"] -eq "indexing_status") {
                    $statusObj = Get-WikiIndexingStatus -TargetWikiDir $targetWikiDir -TargetScriptDir $targetScriptDir
                    $jsonRes = $statusObj | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                    return $false
                }
                if ($queryParams.ContainsKey("action") -and $queryParams["action"] -eq "glossary") {
                    $gPath = Join-Path $targetWikiDir "glossary.md"
                    if (-not (Test-Path $gPath)) { $gPath = Join-Path $targetScriptDir "markdown_sample/glossary.md" }
                    $gTerms = Get-GlossaryTerms -GlossaryPath $gPath
                    $jsonRes = @{ success = $true; terms = @($gTerms.Keys) } | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                    return $false
                }

                $currCfg = Get-ConfigJson -TargetScriptDir $targetScriptDir
                $editorEnabled = if ($currCfg.editor -and $null -ne $currCfg.editor.enabled) { [bool]$currCfg.editor.enabled } else { $true }
                $editorMaxBackups = if ($currCfg.editor -and $null -ne $currCfg.editor.maxBackups) { [int]$currCfg.editor.maxBackups } else { 3 }
                $safeCfg = [ordered]@{
                    editor = @{
                        enabled    = $editorEnabled
                        maxBackups = $editorMaxBackups
                    }
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
                return $false
            }

            if ($request.HttpMethod -eq "POST") {
                if ($queryParams.ContainsKey("action") -and $queryParams["action"] -eq "rebuild_index") {
                    try {
                        $script:WikiIndex = @()
                        $rebuilt = Build-WikiIndex -TargetWikiDir $targetWikiDir -ForceRefresh
                        $jsonRes = @{ success = $true; count = $rebuilt.Count; message = "インデックスを正常に再構築しました ($($rebuilt.Count) 件)" } | ConvertTo-Json
                        Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                    } catch {
                        $jsonRes = @{ success = $false; message = "インデックス再構築中にエラーが発生しました: $_" } | ConvertTo-Json
                        Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 500
                    }
                    return $false
                }

                if ($queryParams.ContainsKey("action") -and $queryParams["action"] -eq "clear_all_caches") {
                    try {
                        $clearRes = Clear-AllWikiCaches -TargetScriptDir $targetScriptDir
                        $jsonRes = @{ success = $true; deletedFiles = $clearRes.deletedFiles; message = "ローカルキャッシュを全消去しました ($($clearRes.deletedFiles) 件のファイルを削除)" } | ConvertTo-Json
                        Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                    } catch {
                        $jsonRes = @{ success = $false; message = "ローカルキャッシュ消去中にエラーが発生しました: $_" } | ConvertTo-Json
                        Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 500
                    }
                    return $false
                }

                $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                $bodyText = $reader.ReadToEnd()
                $reqObj = try { $bodyText | ConvertFrom-Json } catch { $null }

                if ($null -eq $reqObj) {
                    $jsonRes = @{ success = $false; message = "リクエスト JSON のパースに失敗しました。" } | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 400
                    return $false
                }

                # Validation: cacheFolder directory traversal check
                if ($reqObj.search -and -not [string]::IsNullOrWhiteSpace($reqObj.search.cacheFolder)) {
                    $cFolder = [string]$reqObj.search.cacheFolder
                    if ($cFolder -match '[\:\/]' -or $cFolder -match '\.\.') {
                        $jsonRes = @{ success = $false; message = "Invalid cacheFolder parameter: path traversal characters detected." } | ConvertTo-Json
                        Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 400
                        return $false
                    }
                }

                $cfgDict = [ordered]@{}
                if (Test-Path $configPath) {
                    try {
                        $rawJson = Get-Content -Path $configPath -Raw -Encoding UTF8
                        $parsedObj = $rawJson | ConvertFrom-Json
                        $cfgDict = Convert-PSObjectToOrdered $parsedObj
                    } catch {
                        $cfgDict = [ordered]@{}
                    }
                }

                if (-not $cfgDict.Contains("search")) {
                    $cfgDict["search"] = [ordered]@{ prebuildIndex = $false; useCache = $false; cacheFolder = ".cache" }
                }
                if ($reqObj.search) {
                    if ($null -ne $reqObj.search.prebuildIndex) { $cfgDict["search"]["prebuildIndex"] = [bool]$reqObj.search.prebuildIndex }
                    if ($null -ne $reqObj.search.useCache) { $cfgDict["search"]["useCache"] = [bool]$reqObj.search.useCache }
                    if (-not [string]::IsNullOrWhiteSpace($reqObj.search.cacheFolder)) { $cfgDict["search"]["cacheFolder"] = [string]$reqObj.search.cacheFolder }
                }

                if (-not $cfgDict.Contains("editor")) {
                    $cfgDict["editor"] = [ordered]@{ enabled = $true; maxBackups = 3 }
                }
                if ($reqObj.editor) {
                    if ($null -ne $reqObj.editor.enabled) { $cfgDict["editor"]["enabled"] = [bool]$reqObj.editor.enabled }
                    if ($null -ne $reqObj.editor.maxBackups) { $cfgDict["editor"]["maxBackups"] = [int]$reqObj.editor.maxBackups }
                }

                if (-not $cfgDict.Contains("rag")) {
                    $cfgDict["rag"] = [ordered]@{ enabled = $false; apiUrl = "http://localhost:11434/v1"; model = "qwen2.5-coder-7b-instruct" }
                }

                if ($reqObj.rag) {
                    if ($null -ne $reqObj.rag.enabled) { $cfgDict["rag"]["enabled"] = [bool]$reqObj.rag.enabled }
                    if (-not [string]::IsNullOrWhiteSpace($reqObj.rag.apiUrl)) { $cfgDict["rag"]["apiUrl"] = [string]$reqObj.rag.apiUrl }
                    if (-not [string]::IsNullOrWhiteSpace($reqObj.rag.model)) { $cfgDict["rag"]["model"] = [string]$reqObj.rag.model }
                    if ($null -ne $reqObj.rag.userEmail) { $cfgDict["rag"]["userEmail"] = [string]$reqObj.rag.userEmail }

                    if (-not [string]::IsNullOrWhiteSpace($reqObj.rag.activationCode)) {
                        $actCode = $reqObj.rag.activationCode.Trim()
                        $currentMid = Get-MachineFingerprint
                        $userMail = if ($reqObj.rag.userEmail) { [string]$reqObj.rag.userEmail } else { "" }
                        $unlockedKey = Unprotect-ActivationCode -EncryptedText $actCode -MachineId $currentMid -Email $userMail
                        if ($unlockedKey) {
                            $protectedSecret = if ($IsWindows -or $env:OS -eq "Windows_NT") {
                                Protect-StringDpapi -PlainText $unlockedKey
                            } else {
                                Protect-StringAes -PlainText $unlockedKey
                            }
                            $cfgDict["rag"]["apiKey"] = $protectedSecret
                        } else {
                            $jsonRes = @{ success = $false; message = "アクティベーションコードの検証に失敗しました。マシンIDまたはコードが不正です。" } | ConvertTo-Json
                            Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 400
                            return $false
                        }
                    }
                }

                # Config backup rotation (up to 3 generations)
                if (Test-Path $configPath) {
                    for ($i = 2; $i -ge 1; $i--) {
                        $oldB = "$configPath.bak$i"
                        $newB = "$configPath.bak$($i + 1)"
                        if (Test-Path $oldB) { Copy-Item -Path $oldB -Destination $newB -Force }
                    }
                    Copy-Item -Path $configPath -Destination "$configPath.bak1" -Force
                }

                $newJson = $cfgDict | ConvertTo-Json -Depth 5
                Set-Content -Path $configPath -Value $newJson -Encoding UTF8

                $jsonRes = @{ success = $true; message = "設定を正常に保存しました。" } | ConvertTo-Json
                Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                return $false
            }
        }

        if ($rawPath -eq "/api/index.json") {
            $jsonRes = Get-ApiIndexJson -QueryParams $queryParams
            Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
            return $false
        }

        # Handle both /api/history and /api/backups
        if (($rawPath -eq "/api/history" -or $rawPath -eq "/api/backups") -and $request.HttpMethod -eq "GET") {
            $relPath = if ($queryParams.ContainsKey("relPath")) { $queryParams["relPath"] } else { "" }
            if ([string]::IsNullOrWhiteSpace($relPath)) {
                $jsonRes = @{ error = "relPath parameter is required" } | ConvertTo-Json
                Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 400
                return $false
            }
            $cleanRel = $relPath.TrimStart('\', '/').Replace('/', '\')
            $fullTarget = Join-Path $targetWikiDir $cleanRel

            $resolvedTarget = [System.IO.Path]::GetFullPath($fullTarget)
            if (-not $resolvedTarget.StartsWith($fullWikiDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                $jsonRes = @{ error = "FORBIDDEN"; message = "Access denied: Path outside Wiki root." } | ConvertTo-Json
                Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 403
                return $false
            }

            $backups = [System.Collections.Generic.List[PSObject]]::new()
            $maxBackups = if ($config.editor -and $null -ne $config.editor.maxBackups) { [int]$config.editor.maxBackups } else { 3 }
            for ($i = 1; $i -le $maxBackups; $i++) {
                $bakPath = "$resolvedTarget.bak$i"
                if (Test-Path $bakPath -PathType Leaf) {
                    $item = Get-Item $bakPath
                    $bakLabel = Get-LocalizedStr -Key "editor_gen_prefix" -Lang $reqLang -FormatArgs @($i)
                    $backups.Add([PSCustomObject]@{
                        version      = "bak$i"
                        label        = $bakLabel
                        lastModified = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                        timestamp    = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    })
                }
            }

            $jsonRes = @{ relPath = $cleanRel; history = $backups; backups = $backups } | ConvertTo-Json -Depth 4
            Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
            return $false
        }

        if ($rawPath -eq "/api/raw" -and $request.HttpMethod -eq "GET") {
            $relPath = if ($queryParams.ContainsKey("relPath")) { $queryParams["relPath"] } else { "" }
            $version = if ($queryParams.ContainsKey("version")) { $queryParams["version"] } else { "" }
            if ([string]::IsNullOrWhiteSpace($relPath)) {
                $jsonRes = @{ error = "relPath parameter is required" } | ConvertTo-Json
                Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 400
                return $false
            }

            $cleanRel = $relPath.TrimStart('\', '/').Replace('/', '\')
            $fullTarget = Join-Path $targetWikiDir $cleanRel

            if (-not [string]::IsNullOrWhiteSpace($version) -and $version -match "^bak\d+$") {
                $fullTarget = "$fullTarget.$version"
            }

            $resolvedTarget = [System.IO.Path]::GetFullPath($fullTarget)
            if (-not $resolvedTarget.StartsWith($fullWikiDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                $jsonRes = @{ error = "FORBIDDEN"; message = "Access denied: Path outside Wiki root." } | ConvertTo-Json
                Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 403
                return $false
            }

            if (-not (Test-Path -LiteralPath $resolvedTarget -PathType Leaf)) {
                $jsonRes = @{ error = "File not found" } | ConvertTo-Json
                Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 404
                return $false
            }

            $rawContent = [System.IO.File]::ReadAllText($resolvedTarget, [System.Text.Encoding]::UTF8)

            $jsonRes = @{ relPath = $cleanRel; version = $version; markdown = $rawContent } | ConvertTo-Json
            Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
            return $false
        }

        if ($rawPath -eq "/api/clear-cache") {
            Clear-WikiIndexCache -TargetScriptDir $targetScriptDir
            $script:CachedSidebarTree = $null
            $jsonRes = @{ success = $true; message = "Cache cleared" } | ConvertTo-Json
            Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
            return $false
        }

        if ($rawPath -eq "/api/save" -and $request.HttpMethod -eq "POST") {
            $currCfg = Get-ConfigJson -TargetScriptDir $targetScriptDir
            $editorEnabled = if ($currCfg.editor -and $null -ne $currCfg.editor.enabled) { [bool]$currCfg.editor.enabled } else { $true }
            if (-not $editorEnabled) {
                $jsonRes = @{ success = $false; error = "Editor is currently disabled by system administrator." } | ConvertTo-Json
                Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 403
                return $false
            }

            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $bodyText = $reader.ReadToEnd()
            $reqObj = try { $bodyText | ConvertFrom-Json } catch { $null }

            if ($null -eq $reqObj -or [string]::IsNullOrWhiteSpace($reqObj.relPath) -or $null -eq $reqObj.markdown) {
                $jsonRes = @{ success = $false; error = "relPath and markdown body are required" } | ConvertTo-Json
                Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 400
                return $false
            }

            $cleanRel = $reqObj.relPath.TrimStart('\', '/').Replace('/', '\')
            $fullTarget = Join-Path $targetWikiDir $cleanRel

            $resolvedTarget = [System.IO.Path]::GetFullPath($fullTarget)
            if (-not $resolvedTarget.StartsWith($fullWikiDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                $jsonRes = @{ success = $false; error = "Access denied: Target path outside Wiki root." } | ConvertTo-Json
                Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 403
                return $false
            }

            $syntaxCheck = Test-YamlFrontMatterSyntax -MdText $reqObj.markdown
            $syntaxWarning = ""
            if (-not $syntaxCheck.isValid) {
                $syntaxWarning = ($syntaxCheck.warnings -join " ")
            }

            $maxBackups = if ($currCfg.editor -and $null -ne $currCfg.editor.maxBackups) { [int]$currCfg.editor.maxBackups } else { 3 }
            if ($maxBackups -gt 0 -and (Test-Path $resolvedTarget)) {
                for ($i = $maxBackups - 1; $i -ge 1; $i--) {
                    $oldBak = "$resolvedTarget.bak$i"
                    $newBak = "$resolvedTarget.bak$($i + 1)"
                    if (Test-Path $oldBak) {
                        Copy-Item -Path $oldBak -Destination $newBak -Force
                    }
                }
                Copy-Item -Path $resolvedTarget -Destination "$resolvedTarget.bak1" -Force
            } else {
                $parentDir = [System.IO.Path]::GetDirectoryName($resolvedTarget)
                if (-not (Test-Path $parentDir)) {
                    $null = New-Item -ItemType Directory -Path $parentDir -Force
                }
            }

            $utf8bom = New-Object System.Text.UTF8Encoding -ArgumentList @($true)
            [System.IO.File]::WriteAllText($resolvedTarget, $reqObj.markdown, $utf8bom)

            # バックグラウンドで自動タグマージを実行 (glossary.md 準拠)
            $gPath = Join-Path $targetWikiDir "glossary.md"
            if (-not (Test-Path $gPath)) { $gPath = Join-Path $targetScriptDir "markdown_sample/glossary.md" }
            if (Test-Path $gPath) {
                try {
                    $tagScript = Join-Path $targetScriptDir "Update-WikiTags.ps1"
                    if (Test-Path $tagScript) {
                        $null = & $tagScript -WikiDir $targetWikiDir -GlossaryPath $gPath -TargetDocPath $resolvedTarget -ErrorAction SilentlyContinue
                    }
                } catch { $null = $_ }
            }

            # メモリ上キャッシュおよびディスクキャッシュの更新
            Build-WikiIndex -TargetWikiDir $targetWikiDir -ForceRefresh | Out-Null
            if ($currCfg.search -and $currCfg.search.useCache -eq $true) {
                Save-WikiIndexCache -TargetWikiDir $targetWikiDir -TargetScriptDir $targetScriptDir | Out-Null
            }
            $script:CachedSidebarTree = $null

            $resPayload = [ordered]@{ success = $true; relPath = $cleanRel }
            if (-not [string]::IsNullOrWhiteSpace($syntaxWarning)) {
                $resPayload["warning"] = "構文警告: $syntaxWarning"
            }
            $jsonRes = $resPayload | ConvertTo-Json
            Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
            return $false
        }

        if ($rawPath -eq "/api/chunks.json") {
            $jsonRes = Get-ApiChunksJson
            Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
            return $false
        }

        if ($rawPath -eq "/api/chat" -and $request.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $bodyText = $reader.ReadToEnd()
            $reqObj = try { $bodyText | ConvertFrom-Json } catch { $null }

            if ($null -eq $reqObj -or [string]::IsNullOrWhiteSpace($reqObj.message)) {
                $jsonRes = @{ error = "Message field is required" } | ConvertTo-Json
                Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 400
                return $false
            }

            if (-not $config.rag -or -not $config.rag.enabled) {
                $jsonRes = @{ error = "RAG feature is disabled in config.json" } | ConvertTo-Json
                Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 400
                return $false
            }

            $userMsg  = $reqObj.message
            $history  = if ($reqObj.history) { @($reqObj.history) } else { @() }
            $mode     = if ($reqObj.mode) { $reqObj.mode.ToLower().Trim() } else { "fast" }
            $lang     = if ($reqObj.lang) { $reqObj.lang.ToLower().Trim() } else { $reqLang }
            $isStream = if ($null -ne $reqObj.stream) { [bool]$reqObj.stream } else { $true }

            $apiUrl   = [string]$config.rag.apiUrl
            $apiKey   = [string]$config.rag.apiKey
            $model    = [string]$config.rag.model

            $currDoc = $null
            if ($reqObj.includeCurrentPage -eq $true -and -not [string]::IsNullOrWhiteSpace($reqObj.currentRelPath)) {
                $cleanCurrRel = $reqObj.currentRelPath.TrimStart('\', '/').Replace('/', '\')
                $fullCurrPath = Join-Path $targetWikiDir $cleanCurrRel
                if (Test-Path $fullCurrPath) {
                    $currDoc = Get-DocumentMetadata -File (Get-Item $fullCurrPath) -RelPath $cleanCurrRel
                }
            }

            # Agentic RAG Mode
            if ($mode -eq "agentic") {
                $customAgentPrompt = if ($config.rag.agentSystemPrompt) { [string]$config.rag.agentSystemPrompt } elseif ($config.rag.systemPrompt) { [string]$config.rag.systemPrompt } else { "" }

                if ($isStream) {
                    $response.ContentType = "text/event-stream; charset=utf-8"
                    $response.Headers.Add("Cache-Control", "no-cache")
                    $response.Headers.Add("Connection", "keep-alive")

                    $outStream = $response.OutputStream
                    $sendSseEvent = {
                        param([string]$Type, [object]$Content, [object]$ExtraData)
                        $evtObj = [ordered]@{ type = $Type }
                        if ($null -ne $Content) { $evtObj["content"] = $Content }
                        if ($ExtraData) {
                            foreach ($p in $ExtraData.psobject.Properties) {
                                $evtObj[$p.Name] = $p.Value
                            }
                        }
                        $jsonStr = $evtObj | ConvertTo-Json -Compress -Depth 5
                        $lineBytes = [System.Text.Encoding]::UTF8.GetBytes("data: $jsonStr`n`n")
                        $outStream.Write($lineBytes, 0, $lineBytes.Length)
                        $outStream.Flush()
                    }

                    $thinkingCallback = {
                        param([string]$StepLog)
                        & $sendSseEvent "thinking" $StepLog $null
                    }

                    $chunkCallback = {
                        param([string]$TokenChunk)
                        & $sendSseEvent "token" $TokenChunk $null
                    }

                    try {
                        $ragResult = Invoke-AgenticRagChat -ApiUrl $apiUrl -ApiKey $apiKey -Model $model -UserMessage $userMsg -History $history -WikiDir $targetWikiDir -CurrentDoc $currDoc -Lang $lang -CustomAgenticPrompt $customAgentPrompt -Stream -OnThinkingCallback $thinkingCallback -OnChunkReceived $chunkCallback

                        $extraObj = [PSCustomObject]@{
                            answer      = $ragResult.answer
                            thinkingLog = $ragResult.thinkingLog
                            sources     = $ragResult.sources
                        }
                        & $sendSseEvent "done" $null $extraObj

                        $doneBytes = [System.Text.Encoding]::UTF8.GetBytes("data: [DONE]`n`n")
                        $outStream.Write($doneBytes, 0, $doneBytes.Length)
                        $outStream.Flush()
                    } catch {
                        & $sendSseEvent "error" $_.Exception.Message $null
                    } finally {
                        try { $response.Close() } catch { $null = $_ }
                    }
                    return $false
                } else {
                    try {
                        $ragResult = Invoke-AgenticRagChat -ApiUrl $apiUrl -ApiKey $apiKey -Model $model -UserMessage $userMsg -History $history -WikiDir $targetWikiDir -CurrentDoc $currDoc -Lang $lang -CustomAgenticPrompt $customAgentPrompt
                        $jsonRes = @{
                            answer      = $ragResult.answer
                            thinkingLog = $ragResult.thinkingLog
                            sources     = $ragResult.sources
                        } | ConvertTo-Json -Depth 5
                        Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                    } catch {
                        $jsonRes = @{ error = "Agentic RAG Execution Error"; message = $_.Exception.Message } | ConvertTo-Json
                        Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 500
                    }
                    return $false
                }
            }

            # Fast RAG Mode
            Build-WikiIndex -TargetWikiDir $targetWikiDir | Out-Null
            $searchResults = Search-OkfDocs -Query $userMsg -StatusFilter "active" -WikiDir $targetWikiDir -MaxResults 5

            $sourcesList = [System.Collections.Generic.List[PSObject]]::new()
            $contextTextBuilder = [System.Text.StringBuilder]::new()

            foreach ($r in $searchResults) {
                $item = $r.Meta
                $relUri = "/" + [Uri]::EscapeUriString($item.RelPath.Replace('\', '/'))
                [void]$sourcesList.Add([PSCustomObject]@{
                    title       = $item.Title
                    relPath     = $item.RelPath
                    relUri      = $relUri
                    lastUpdated = $item.LastUpdated.ToString("yyyy-MM-dd")
                    author      = $item.Author
                    status      = $item.Status
                })

                [void]$contextTextBuilder.AppendLine("--- Document: $($item.Title) ($($item.RelPath)) ---")
                [void]$contextTextBuilder.AppendLine("Description: $($item.Description)")
                if ($r.Snippet) {
                    [void]$contextTextBuilder.AppendLine("Snippet:`n$($r.Snippet)")
                }
            }

            $contextText = $contextTextBuilder.ToString()
            $defaultSysPrompt = Get-LocalizedStr -Key "default_fast_system_prompt" -Lang $lang
            $customPrompt = if ($config.rag.systemPrompt) { [string]$config.rag.systemPrompt } else { $defaultSysPrompt }

            $finalSysPrompt = "$customPrompt`n`n【Wiki Search Context】`n$contextText"
            if ($currDoc -and $currDoc.RelPath) {
                $currSnippet = $currDoc.BodyText
                if ($currSnippet -and $currSnippet.Length -gt 1500) { $currSnippet = $currSnippet.Substring(0, 1500) + "..." }
                $finalSysPrompt += "`n`n【Current Browser Context】`nTitle: $($currDoc.Title) ($($currDoc.RelPath))`nBody:`n$currSnippet"
            }

            if ($isStream) {
                $response.ContentType = "text/event-stream; charset=utf-8"
                $response.Headers.Add("Cache-Control", "no-cache")
                $response.Headers.Add("Connection", "keep-alive")

                $outStream = $response.OutputStream
                $sendSseEvent = {
                    param([string]$Type, [object]$Content, [object]$ExtraData)
                    $evtObj = [ordered]@{ type = $Type }
                    if ($null -ne $Content) { $evtObj["content"] = $Content }
                    if ($ExtraData) {
                        foreach ($p in $ExtraData.psobject.Properties) {
                            $evtObj[$p.Name] = $p.Value
                        }
                    }
                    $jsonStr = $evtObj | ConvertTo-Json -Compress -Depth 5
                    $lineBytes = [System.Text.Encoding]::UTF8.GetBytes("data: $jsonStr`n`n")
                    $outStream.Write($lineBytes, 0, $lineBytes.Length)
                    $outStream.Flush()
                }

                $fullAnswerBuilder = [System.Text.StringBuilder]::new()
                $chunkCallback = {
                    param([string]$TokenChunk)
                    [void]$fullAnswerBuilder.Append($TokenChunk)
                    & $sendSseEvent "token" $TokenChunk $null
                }

                try {
                    $null = Invoke-OpenAiChatCompletions -ApiUrl $apiUrl -ApiKey $apiKey -Model $model -SystemPrompt $finalSysPrompt -UserMessage $userMsg -History $history -Stream -OnChunkReceived $chunkCallback

                    $extraObj = [PSCustomObject]@{
                        answer  = $fullAnswerBuilder.ToString()
                        sources = $sourcesList
                    }
                    & $sendSseEvent "done" $null $extraObj

                    $doneBytes = [System.Text.Encoding]::UTF8.GetBytes("data: [DONE]`n`n")
                    $outStream.Write($doneBytes, 0, $doneBytes.Length)
                    $outStream.Flush()
                } catch {
                    & $sendSseEvent "error" $_.Exception.Message $null
                } finally {
                    try { $response.Close() } catch { $null = $_ }
                }
                return $false
            } else {
                try {
                    $answerText = Invoke-OpenAiChatCompletions -ApiUrl $apiUrl -ApiKey $apiKey -Model $model -SystemPrompt $finalSysPrompt -UserMessage $userMsg -History $history
                    $jsonRes = @{
                        answer  = $answerText
                        sources = $sourcesList
                    } | ConvertTo-Json -Depth 4
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8"
                } catch {
                    $jsonRes = @{ error = "Fast RAG Execution Error"; message = $_.Exception.Message } | ConvertTo-Json
                    Write-SafeHttpResponse -Response $response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jsonRes)) -ContentType "application/json; charset=utf-8" -StatusCode 500
                }
                return $false
            }
        }

        # 2. Dynamic View Routing & Page Rendering
        $isDynamicView = $false
        $pageTitle     = ""
        $bodyContent   = ""

        if ($rawPath -eq "/" -or $rawPath -eq "/index.html") {
            $isDynamicView = $true
            $indexPath     = Join-Path $targetWikiDir "index.md"
            $readmePath    = Join-Path $targetWikiDir "README.md"
            if (Test-Path $indexPath) {
                $mdText      = Get-Content -Path $indexPath -Raw -Encoding UTF8
                $fileObj     = Get-Item $indexPath
                $meta        = Get-DocumentMetadata -File $fileObj -RelPath "index.md" -MdText $mdText
                $builder     = New-Object Markdig.MarkdownPipelineBuilder
                $null        = [Markdig.MarkdownExtensions]::UseAdvancedExtensions($builder)
                $null        = [Markdig.MarkdownExtensions]::UseYamlFrontMatter($builder)
                $pipeline    = $builder.Build()
                $renderedHtml = [Markdig.Markdown]::ToHtml($mdText, $pipeline)
                $editorEnabled = if ($config.editor -and $null -ne $config.editor.enabled) { [bool]$config.editor.enabled } else { $true }
                $okfTopBar   = Get-OkfTopBarHtml -Meta $meta -RelPath "index.md" -Lang $reqLang -EditorEnabled $editorEnabled
                $okfFooter   = Get-OkfFooterCardHtml -Meta $meta -Lang $reqLang
                $bodyContent = $okfTopBar + $renderedHtml + $okfFooter
                $pageTitle   = [System.Net.WebUtility]::HtmlEncode($meta.Title)
            } elseif (Test-Path $readmePath) {
                $mdText      = Get-Content -Path $readmePath -Raw -Encoding UTF8
                $fileObj     = Get-Item $readmePath
                $meta        = Get-DocumentMetadata -File $fileObj -RelPath "README.md" -MdText $mdText
                $builder     = New-Object Markdig.MarkdownPipelineBuilder
                $null        = [Markdig.MarkdownExtensions]::UseAdvancedExtensions($builder)
                $null        = [Markdig.MarkdownExtensions]::UseYamlFrontMatter($builder)
                $pipeline    = $builder.Build()
                $renderedHtml = [Markdig.Markdown]::ToHtml($mdText, $pipeline)
                $editorEnabled = if ($config.editor -and $null -ne $config.editor.enabled) { [bool]$config.editor.enabled } else { $true }
                $okfTopBar   = Get-OkfTopBarHtml -Meta $meta -RelPath "README.md" -Lang $reqLang -EditorEnabled $editorEnabled
                $okfFooter   = Get-OkfFooterCardHtml -Meta $meta -Lang $reqLang
                $bodyContent = $okfTopBar + $renderedHtml + $okfFooter
                $pageTitle   = [System.Net.WebUtility]::HtmlEncode($meta.Title)
            } else {
                $pageTitle   = Get-LocalizedStr -Key "doc_list_title" -Lang $reqLang
                $bodyContent = Get-DirectoryListingHtml -DirFullPath $targetWikiDir -RawUrlPath $rawPath -Lang $reqLang
            }
        } elseif ($rawPath -eq "/recent") {
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
        $filePath = Join-Path $targetWikiDir $relPath

        if (-not (Test-Path $filePath) -and $rawPath.StartsWith("/lib/")) {
            $filePath = Join-Path $targetScriptDir $relPath
        }

        $fullPath = [System.IO.Path]::GetFullPath($filePath)
        $fullScriptLibDir = (Join-Path $targetScriptDir "lib\").TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        $isAllowed = $fullPath.StartsWith($fullWikiDir, [System.StringComparison]::OrdinalIgnoreCase) -or $fullPath.StartsWith($fullScriptLibDir, [System.StringComparison]::OrdinalIgnoreCase)

        if (-not $isDynamicView -and -not $isAllowed) {
            $forbiddenBytes = [System.Text.Encoding]::UTF8.GetBytes("<h1>403 Forbidden</h1>")
            Write-SafeHttpResponse -Response $response -Bytes $forbiddenBytes -StatusCode 403
            return $false
        }

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

                $editorEnabled = if ($config.editor -and $null -ne $config.editor.enabled) { [bool]$config.editor.enabled } else { $true }
                $okfTopBar   = Get-OkfTopBarHtml -Meta $meta -RelPath $relPath -Lang $reqLang -EditorEnabled $editorEnabled
                $okfFooter   = Get-OkfFooterCardHtml -Meta $meta -Lang $reqLang
                $bodyContent = $okfTopBar + $renderedHtml + $okfFooter
                $pageTitle   = [System.Net.WebUtility]::HtmlEncode($meta.Title)
            }

            $fullHtml = Get-MainViewHtml -PageTitle $pageTitle -BodyContent $bodyContent -RelPath $relPath -Lang $reqLang -Config $config
            $bytes    = [System.Text.Encoding]::UTF8.GetBytes($fullHtml)
            Write-SafeHttpResponse -Response $response -Bytes $bytes
            return $false
        } elseif (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            $ext = [System.IO.Path]::GetExtension($fullPath).ToLower()
            $cType = "application/octet-stream"
            if ($mimeTypes.ContainsKey($ext)) {
                $cType = $mimeTypes[$ext]
            }
            $bytes = [System.IO.File]::ReadAllBytes($fullPath)
            Write-SafeHttpResponse -Response $response -Bytes $bytes -ContentType $cType
            return $false
        } else {
            $safePath = [System.Net.WebUtility]::HtmlEncode($rawPath)
            $notFoundBytes = [System.Text.Encoding]::UTF8.GetBytes("<h1>404 Not Found</h1><p>$safePath</p>")
            Write-SafeHttpResponse -Response $response -Bytes $notFoundBytes -StatusCode 404
            return $false
        }
    } catch {
        Write-Warning "Request processing error: $_"
        try {
            $errBytes = [System.Text.Encoding]::UTF8.GetBytes("<h1>500 Internal Server Error</h1>")
            Write-SafeHttpResponse -Response $response -Bytes $errBytes -StatusCode 500
        } catch {
            $null = $_
        }
        return $false
    } finally {
        try { $response.Close() } catch { $null = $_ }
    }
}
