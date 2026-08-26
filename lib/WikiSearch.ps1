# ==============================================================================
#  SimpleWiki 検索 & 形態素解析 & インデックス構築モジュール
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================

function Get-WikiCachePath {
    param (
        [string]$TargetWikiDir = $script:wikiDir,
        [string]$TargetScriptDir = $scriptDir
    )
    $baseScriptDir = if (-not [string]::IsNullOrWhiteSpace($TargetScriptDir)) { $TargetScriptDir } elseif (-not [string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir } elseif (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { $PWD.Path }
    $config = Get-ConfigJson -TargetScriptDir $baseScriptDir
    $cacheSubFolder = if ($config.search -and -not [string]::IsNullOrWhiteSpace($config.search.cacheFolder)) { $config.search.cacheFolder } else { ".cache" }

    # キャッシュ保存先を TargetWikiDir 直下ではなく、実行元 ($baseScriptDir) 配下の .cache に配置
    $cacheDir = Join-Path $baseScriptDir $cacheSubFolder

    # 読み込み対象ディレクトリパスを正規化してハッシュ値を生成
    $targetDir = if (-not [string]::IsNullOrWhiteSpace($TargetWikiDir)) {
        try {
            (Resolve-Path -LiteralPath $TargetWikiDir -ErrorAction Stop).Path
        } catch {
            [System.IO.Path]::GetFullPath($TargetWikiDir)
        }
    } else {
        $baseScriptDir
    }

    $normPath  = $targetDir.TrimEnd('\', '/').ToLowerInvariant()
    $md5       = [System.Security.Cryptography.MD5]::Create()
    $hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normPath))
    $dirHash   = ($hashBytes | ForEach-Object { "{0:x2}" -f $_ }) -join ""

    return Join-Path $cacheDir ".index-cache-$dirHash.json"
}

function Get-WikiStatusPath {
    param (
        [string]$TargetWikiDir = $script:wikiDir,
        [string]$TargetScriptDir = $scriptDir
    )
    $baseScriptDir = if (-not [string]::IsNullOrWhiteSpace($TargetScriptDir)) { $TargetScriptDir } elseif (-not [string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir } elseif (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { $PWD.Path }
    $config = Get-ConfigJson -TargetScriptDir $baseScriptDir
    $cacheSubFolder = if ($config.search -and -not [string]::IsNullOrWhiteSpace($config.search.cacheFolder)) { $config.search.cacheFolder } else { ".cache" }
    $cacheDir = Join-Path $baseScriptDir $cacheSubFolder

    $targetDir = if (-not [string]::IsNullOrWhiteSpace($TargetWikiDir)) {
        try {
            (Resolve-Path -LiteralPath $TargetWikiDir -ErrorAction Stop).Path
        } catch {
            [System.IO.Path]::GetFullPath($TargetWikiDir)
        }
    } else {
        $baseScriptDir
    }

    $normPath  = $targetDir.TrimEnd('\', '/').ToLowerInvariant()
    $md5       = [System.Security.Cryptography.MD5]::Create()
    $hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normPath))
    $dirHash   = ($hashBytes | ForEach-Object { "{0:x2}" -f $_ }) -join ""

    return Join-Path $cacheDir ".index-status-$dirHash.json"
}

function Clear-AllWikiCaches {
    param (
        [string]$TargetScriptDir = $scriptDir
    )
    $baseDir = if (-not [string]::IsNullOrWhiteSpace($TargetScriptDir)) { $TargetScriptDir } elseif (-not [string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir } else { $PWD.Path }
    $config = Get-ConfigJson -TargetScriptDir $baseDir
    $cacheSubFolder = if ($config.search -and -not [string]::IsNullOrWhiteSpace($config.search.cacheFolder)) { $config.search.cacheFolder } else { ".cache" }
    $cacheDir = Join-Path $baseDir $cacheSubFolder

    $deletedCount = 0
    if (Test-Path $cacheDir) {
        $cacheFiles = Get-ChildItem -Path $cacheDir -Filter ".index-cache-*.json" -File -ErrorAction SilentlyContinue
        foreach ($f in $cacheFiles) {
            try {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
                $deletedCount++
            } catch {
                Write-Warning "キャッシュファイル削除失敗: $($f.FullName)"
            }
        }
    }

    # メモリ内キャッシュも同時に初期化
    $script:WikiIndex = @()
    $script:WikiIndexDirWriteTime = 0
    $script:WikiIndexLastScan = [DateTime]::MinValue
    $script:SidebarMdFiles = @()
    $script:SidebarCachedHtml = $null

    return [PSCustomObject]@{
        success      = $true
        deletedFiles = $deletedCount
        cacheDir     = $cacheDir
    }
}

function Save-WikiIndexCache {
    param (
        [string]$TargetWikiDir = $script:wikiDir,
        [string]$TargetScriptDir = $scriptDir
    )
    try {
        $baseScriptDir = if (-not [string]::IsNullOrWhiteSpace($TargetScriptDir)) { $TargetScriptDir } elseif (-not [string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir } else { $PWD.Path }
        $config = Get-ConfigJson -TargetScriptDir $baseScriptDir
        if (-not ($config.search -and $config.search.useCache -eq $true)) {
            return $false
        }

        $cacheFilePath = Get-WikiCachePath -TargetWikiDir $TargetWikiDir -TargetScriptDir $baseScriptDir
        $cacheDir      = [System.IO.Path]::GetDirectoryName($cacheFilePath)

        if (-not (Test-Path $cacheDir)) {
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        }

        $cachePayload = @{
            Version       = "1.0"
            GeneratedAt   = (Get-Date).ToString("o")
            TargetDir     = $TargetWikiDir
            DirWriteTime  = $script:WikiIndexDirWriteTime.Ticks
            Items         = $script:WikiIndex
        }

        $json = $cachePayload | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($cacheFilePath, $json, [System.Text.Encoding]::UTF8)
        return $true
    } catch {
        Write-Warning "インデックスキャッシュの保存に失敗しました: $_"
        return $false
    }
}

function Load-WikiIndexCache {
    param (
        [string]$TargetWikiDir = $script:wikiDir,
        [string]$TargetScriptDir = $scriptDir
    )
    try {
        $baseScriptDir = if (-not [string]::IsNullOrWhiteSpace($TargetScriptDir)) { $TargetScriptDir } elseif (-not [string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir } else { $PWD.Path }
        $config = Get-ConfigJson -TargetScriptDir $baseScriptDir
        if (-not ($config.search -and $config.search.useCache -eq $true)) {
            return $false
        }

        $cacheFilePath = Get-WikiCachePath -TargetWikiDir $TargetWikiDir -TargetScriptDir $baseScriptDir
        if (-not (Test-Path $cacheFilePath)) { return $false }

        $json = [System.IO.File]::ReadAllText($cacheFilePath, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($json)) { return $false }

        $cacheData = $json | ConvertFrom-Json
        if (-not $cacheData -or $null -eq $cacheData.Items) { return $false }

        $targetDir = if (-not [string]::IsNullOrWhiteSpace($TargetWikiDir)) { $TargetWikiDir } else { $baseScriptDir }
        if ((Test-Path $targetDir) -and (Test-Path -LiteralPath $cacheFilePath)) {
            $cacheItem = Get-Item -LiteralPath $cacheFilePath -ErrorAction SilentlyContinue
            if ($cacheItem) {
                $cacheFileWriteTime = $cacheItem.LastWriteTime
                $currentMdFiles = @(Get-ChildItem -Path $targetDir -Recurse -Filter "*.md" -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notmatch '[\\/]\.(git|lib|tests|dist|\.cache)[\\/]' })

                # ファイル件数が異なる場合（追加・削除された場合）はキャッシュ無効
                if ($currentMdFiles.Count -ne $cacheData.Items.Count) {
                    return $false
                }

                # キャッシュ作成後に更新されたファイルが存在する場合はキャッシュ無効
                $hasNewer = $false
                foreach ($f in $currentMdFiles) {
                    if ($f.LastWriteTime -gt $cacheFileWriteTime) {
                        $hasNewer = $true
                        break
                    }
                }
                if ($hasNewer) {
                    return $false
                }
            }
        }

        $itemList = [System.Collections.Generic.List[PSObject]]::new()
        foreach ($item in $cacheData.Items) {
            $lastUpdated = [DateTime]::MinValue
            if (-not [DateTime]::TryParse($item.LastUpdated, [ref]$lastUpdated)) {
                $lastUpdated = Get-Date
            }
            $psObj = [PSCustomObject]@{
                Title       = $item.Title
                Description = $item.Description
                Author      = $item.Author
                Domain      = $item.Domain
                Tags        = @($item.Tags)
                LastUpdated = $lastUpdated
                Status      = $item.Status
                HasYaml     = [bool]$item.HasYaml
                RelPath     = $item.RelPath
                FullPath    = $item.FullPath
                BodyText    = $item.BodyText
            }
            $itemList.Add($psObj)
        }

        $script:WikiIndex = $itemList.ToArray()
        $script:WikiIndexDirWriteTime = (Get-Item $targetDir).LastWriteTime
        $script:WikiIndexLastScan = Get-Date
        return $true
    } catch {
        Write-Warning "インデックスキャッシュの読み込みに失敗しました: $_"
        return $false
    }
}

if ($null -eq $script:IndexingStatus) {
    $script:IndexingStatus = [PSCustomObject]@{
        IsBuilding = $false
        Total      = 0
        Current    = 0
        Percent    = 0
        LastScan   = [DateTime]::MinValue
    }
}

function Get-WikiIndexingStatus {
    param (
        [string]$TargetWikiDir = $script:wikiDir,
        [string]$TargetScriptDir = $scriptDir
    )
    $baseScriptDir = if (-not [string]::IsNullOrWhiteSpace($TargetScriptDir)) { $TargetScriptDir } elseif (-not [string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir } else { $PWD.Path }
    $targetDir = if (-not [string]::IsNullOrWhiteSpace($TargetWikiDir)) { $TargetWikiDir } else { $baseScriptDir }

    # バックグラウンドプロセスからのステータスファイルが存在すればそれを優先して読み取り
    try {
        $statusFilePath = Get-WikiStatusPath -TargetWikiDir $targetDir -TargetScriptDir $baseScriptDir
        if (Test-Path $statusFilePath) {
            $fileStream = [System.IO.FileStream]::new($statusFilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $streamReader = [System.IO.StreamReader]::new($fileStream, [System.Text.Encoding]::UTF8)
            $statusJson = $streamReader.ReadToEnd()
            $streamReader.Close()
            $fileStream.Close()

            if (-not [string]::IsNullOrWhiteSpace($statusJson)) {
                $statusFromFile = $statusJson | ConvertFrom-Json
                if ($statusFromFile) {
                    $script:IndexingStatus = [PSCustomObject]@{
                        IsBuilding = [bool]$statusFromFile.IsBuilding
                        Total      = [int]$statusFromFile.Total
                        Current    = [int]$statusFromFile.Current
                        Percent    = [int]$statusFromFile.Percent
                        LastScan   = $script:IndexingStatus.LastScan
                    }
                    return $script:IndexingStatus
                }
            }
        }
    } catch {}

    if ($null -eq $script:IndexingStatus) {
        return [PSCustomObject]@{
            IsBuilding = $false
            Total      = 0
            Current    = 0
            Percent    = 0
            LastScan   = [DateTime]::MinValue
        }
    }
    return $script:IndexingStatus
}

function Save-WikiIndexingStatusFile {
    param (
        [PSCustomObject]$StatusObj,
        [string]$TargetWikiDir = $script:wikiDir,
        [string]$TargetScriptDir = $scriptDir
    )
    try {
        $baseScriptDir = if (-not [string]::IsNullOrWhiteSpace($TargetScriptDir)) { $TargetScriptDir } elseif (-not [string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir } else { $PWD.Path }
        $targetDir = if (-not [string]::IsNullOrWhiteSpace($TargetWikiDir)) { $TargetWikiDir } else { $baseScriptDir }
        $statusFilePath = Get-WikiStatusPath -TargetWikiDir $targetDir -TargetScriptDir $baseScriptDir
        $statusDir = [System.IO.Path]::GetDirectoryName($statusFilePath)
        if (-not (Test-Path $statusDir)) { New-Item -ItemType Directory -Path $statusDir -Force | Out-Null }
        $json = $StatusObj | ConvertTo-Json
        [System.IO.File]::WriteAllText($statusFilePath, $json, [System.Text.Encoding]::UTF8)
    } catch {}
}

function Build-WikiIndex {
    param (
        [string]$TargetWikiDir = $script:wikiDir,
        [switch]$ForceRefresh,
        [string]$TargetScriptDir = $scriptDir
    )

    $baseScriptDir = if (-not [string]::IsNullOrWhiteSpace($TargetScriptDir)) { $TargetScriptDir } elseif (-not [string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir } else { $PWD.Path }
    $targetDir = if (-not [string]::IsNullOrWhiteSpace($TargetWikiDir)) { $TargetWikiDir } else { $baseScriptDir }
    if (-not (Test-Path $targetDir)) { return @() }

    $currentWriteTime = (Get-Item $targetDir).LastWriteTime
    if (-not $ForceRefresh -and $script:WikiIndex.Count -gt 0 -and $script:WikiIndexDirWriteTime -eq $currentWriteTime) {
        return $script:WikiIndex
    }

    if (-not $ForceRefresh -and (Load-WikiIndexCache -TargetWikiDir $targetDir -TargetScriptDir $baseScriptDir)) {
        return $script:WikiIndex
    }

    $mdFiles = Get-ChildItem -Path $targetDir -Recurse -Filter "*.md" |
        Where-Object { $_.FullName -notmatch '[\\/]\.(git|lib|tests|dist|\.cache)[\\/]' } |
        Sort-Object FullName

    $totalFiles = $mdFiles.Count
    $script:IndexingStatus = [PSCustomObject]@{
        IsBuilding = $true
        Total      = $totalFiles
        Current    = 0
        Percent    = 0
        LastScan   = $script:WikiIndexLastScan
    }
    Save-WikiIndexingStatusFile -StatusObj $script:IndexingStatus -TargetWikiDir $targetDir -TargetScriptDir $baseScriptDir

    $showProgress = ($totalFiles -ge 5 -and [Environment]::UserInteractive)

    try {
        $indexList = [System.Collections.Generic.List[PSObject]]::new()
        $idx = 0
        foreach ($file in $mdFiles) {
            $idx++
            $relPath = $file.FullName.Substring($targetDir.Length).TrimStart("\", "/")
            $meta    = Get-DocumentMetadata -File $file -RelPath $relPath
            $indexList.Add($meta)

            $pct = if ($totalFiles -gt 0) { [math]::Floor(($idx / $totalFiles) * 100) } else { 100 }
            $script:IndexingStatus.Current = $idx
            $script:IndexingStatus.Percent = $pct

            if ($idx % 10 -eq 0 -or $idx -eq $totalFiles) {
                Save-WikiIndexingStatusFile -StatusObj $script:IndexingStatus -TargetWikiDir $targetDir -TargetScriptDir $baseScriptDir
            }

            if ($showProgress -and ($idx % 5 -eq 0 -or $idx -eq $totalFiles)) {
                try {
                    Write-Progress -Activity "SimpleWiki: Building search index" -Status "[$idx/$totalFiles] $relPath" -PercentComplete $pct
                } catch {}
            }
        }

        $script:WikiIndex = $indexList.ToArray()
        $script:WikiIndexDirWriteTime = $currentWriteTime
        $script:WikiIndexLastScan = Get-Date

        Save-WikiIndexCache -TargetWikiDir $targetDir -TargetScriptDir $baseScriptDir | Out-Null

        return $script:WikiIndex
    } finally {
        if ($showProgress) {
            try { Write-Progress -Activity "SimpleWiki: Building search index" -Completed } catch {}
        }
        $script:IndexingStatus = [PSCustomObject]@{
            IsBuilding = $false
            Total      = $totalFiles
            Current    = $totalFiles
            Percent    = 100
            LastScan   = $script:WikiIndexLastScan
        }
        Save-WikiIndexingStatusFile -StatusObj $script:IndexingStatus -TargetWikiDir $targetDir -TargetScriptDir $baseScriptDir
    }
}

# --- サイドバー (HTML) の自動生成関数 (フォルダ階層対応) ---
function Build-ServerFileTreeNode {
    param ($allMdFiles, $wikiDir)

    $rootNode = [PSCustomObject]@{
        Files      = [System.Collections.Generic.List[PSObject]]::new()
        SubFolders = [ordered]@{}
    }

    foreach ($file in $allMdFiles) {
        $relPath = $file.FullName.Substring($wikiDir.Length).TrimStart("\", "/")
        $parts   = $relPath -split '[\\/]'

        $currentNode = $rootNode
        for ($i = 0; $i -lt $parts.Length - 1; $i++) {
            $folderName = $parts[$i]
            if (-not $currentNode.SubFolders.Contains($folderName)) {
                $currentNode.SubFolders[$folderName] = [PSCustomObject]@{
                    Files      = [System.Collections.Generic.List[PSObject]]::new()
                    SubFolders = [ordered]@{}
                }
            }
            $currentNode = $currentNode.SubFolders[$folderName]
        }
        $currentNode.Files.Add($file)
    }
    return $rootNode
}

function Test-ServerNodeHasActiveFile {
    param ($node, $currentRelPath, $wikiDir)

    foreach ($file in $node.Files) {
        $relPath = $file.FullName.Substring($wikiDir.Length).TrimStart("\", "/")
        if ($relPath -eq $currentRelPath) {
            return $true
        }
    }

    foreach ($folderName in $node.SubFolders.Keys) {
        if (Test-ServerNodeHasActiveFile -node $node.SubFolders[$folderName] -currentRelPath $currentRelPath -wikiDir $wikiDir) {
            return $true
        }
    }

    return $false
}

function Render-ServerFolderTreeHtml {
    param ($node, $currentRelPath, $wikiDir)

    $html = "<ul>`n"

    $sortedFiles = if ($node.Files) {
        @($node.Files | Sort-Object {
            if ($_.BaseName -eq "index") { 0 }
            elseif ($_.BaseName -eq "README") { 1 }
            else { 2 }
        }, BaseName)
    } else { @() }

    foreach ($file in $sortedFiles) {
        $relPath   = $file.FullName.Substring($wikiDir.Length).TrimStart("\", "/")
        $cleanPath = $relPath -replace "\\", "/"
        $webPath   = "/" + [Uri]::EscapeUriString($cleanPath)
        $title     = [System.Net.WebUtility]::HtmlEncode($file.BaseName)

        $activeClass = if ($relPath -eq $currentRelPath) { ' class="active"' } else { '' }
        $html += "  <li class='nav-file'><a href='$webPath'$activeClass>$title</a></li>`n"
    }

    $sortedFolderNames = if ($node.SubFolders) {
        @($node.SubFolders.Keys | Sort-Object)
    } else { @() }

    foreach ($folderName in $sortedFolderNames) {
        $subNode     = $node.SubFolders[$folderName]
        $encodedName = [System.Net.WebUtility]::HtmlEncode($folderName)
        $subHtml     = Render-ServerFolderTreeHtml -node $subNode -currentRelPath $currentRelPath -wikiDir $wikiDir

        $isOpen   = Test-ServerNodeHasActiveFile -node $subNode -currentRelPath $currentRelPath -wikiDir $wikiDir
        $openAttr = if ($isOpen) { " open" } else { "" }

        $html += "  <li class='nav-folder'>`n"
        $html += "    <details$openAttr>`n"
        $html += "      <summary class='folder-title'>📁 $encodedName</summary>`n"
        $html += "      $subHtml`n"
        $html += "    </details>`n"
        $html += "  </li>`n"
    }

    $html += "</ul>"
    return $html
}

$script:SidebarMdFiles = @()
$script:SidebarCachedHtml = $null


function Get-HighlightText {
    param (
        [string]$Text = "",
        [string[]]$Keywords = @()
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }

    $validKws = @($Keywords | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($validKws.Count -eq 0) {
        return [System.Net.WebUtility]::HtmlEncode($Text)
    }

    $escapedPatterns = foreach ($kw in $validKws) { [regex]::Escape($kw) }
    $pattern = "(?i)(" + ($escapedPatterns -join "|") + ")"

    $matches = [regex]::Matches($Text, $pattern)
    if ($matches.Count -eq 0) {
        return [System.Net.WebUtility]::HtmlEncode($Text)
    }

    $sb = New-Object System.Text.StringBuilder
    $lastIdx = 0

    foreach ($m in $matches) {
        if ($m.Index -gt $lastIdx) {
            $chunk = $Text.Substring($lastIdx, $m.Index - $lastIdx)
            [void]$sb.Append([System.Net.WebUtility]::HtmlEncode($chunk))
        }
        $kwMatch = $m.Value
        $encKw   = [System.Net.WebUtility]::HtmlEncode($kwMatch)
        [void]$sb.Append("<mark style='background:#fff3cd; padding:0 2px; border-radius:2px;'>$encKw</mark>")
        $lastIdx = $m.Index + $m.Length
    }

    if ($lastIdx -lt $Text.Length) {
        $remaining = $Text.Substring($lastIdx)
        [void]$sb.Append([System.Net.WebUtility]::HtmlEncode($remaining))
    }

    return $sb.ToString()
}

# --- 検索クエリ解析ヘルパー (NOT構文・除外キーワード分離) ---
function Split-SearchQueryTerms {
    param (
        [string]$Query = ""
    )
    $result = @{
        IncludeKeywords = [System.Collections.Generic.List[string]]::new()
        ExcludeKeywords = [System.Collections.Generic.List[string]]::new()
        CleanQuery      = ""
    }
    if ([string]::IsNullOrWhiteSpace($Query)) { return $result }

    # 全角スペースを半角スペースに正規化
    $normalized = $Query.Trim().Replace([char]0x3000, " ")

    # トークン分割:
    # 1. NOT (大文字小文字不問, スペース有無不問): NOT term, NOTterm, NOT "phrase", NOT"phrase"
    # 2. - or ! (行頭または空白直後): -term, !term, -"phrase", !"phrase"
    # 3. "phrase" or regular term
    $pattern = '(?i:(?<=\s|^)NOT\s*(?:"([^"]+)"|(\S+)))|(?:(?<=\s|^)[-\!](?:"([^"]+)"|(\S+)))|(?:"([^"]+)"|(\S+))'
    $tokens = [regex]::Matches($normalized, $pattern)

    $includeList = [System.Collections.Generic.List[string]]::new()
    $excludeList = [System.Collections.Generic.List[string]]::new()

    foreach ($m in $tokens) {
        if ($m.Groups[1].Success -or $m.Groups[2].Success) {
            # NOT term / NOT "phrase" / NOTterm
            $val = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
            if (-not [string]::IsNullOrWhiteSpace($val)) { [void]$excludeList.Add($val.Trim()) }
        } elseif ($m.Groups[3].Success -or $m.Groups[4].Success) {
            # -term / !term / -"phrase" / !"phrase"
            $val = if ($m.Groups[3].Success) { $m.Groups[3].Value } else { $m.Groups[4].Value }
            if (-not [string]::IsNullOrWhiteSpace($val)) { [void]$excludeList.Add($val.Trim()) }
        } else {
            # Include term / "phrase"
            $val = if ($m.Groups[5].Success) { $m.Groups[5].Value } else { $m.Groups[6].Value }
            if (-not [string]::IsNullOrWhiteSpace($val) -and $val -notmatch '(?i)^NOT$') { [void]$includeList.Add($val.Trim()) }
        }
    }

    $result.IncludeKeywords = $includeList
    $result.ExcludeKeywords = $excludeList
    $result.CleanQuery      = ($includeList -join " ").Trim()
    return $result
}

# --- OKF スコアリングドキュメント検索共通関数 ---
function Search-OkfDocs {
    param (
        [string]$Query = "",
        [string]$StatusFilter = "active",
        [string]$DomainFilter = "",
        [string]$WikiDir = "",
        [int]$MaxResults = 0
    )

    $targetDir = if (-not [string]::IsNullOrWhiteSpace($WikiDir)) { $WikiDir } else { $script:wikiDir }
    if ([string]::IsNullOrWhiteSpace($targetDir)) { $targetDir = $scriptDir }

    if ($null -eq $script:WikiIndex -or $script:WikiIndex.Count -eq 0) {
        if (-not (Load-WikiIndexCache -TargetWikiDir $targetDir)) {
            $status = Get-WikiIndexingStatus -TargetWikiDir $targetDir
            if (-not $status.IsBuilding) {
                Build-WikiIndex -TargetWikiDir $targetDir | Out-Null
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($StatusFilter)) { $StatusFilter = "active" }
    $stFilterLower = $StatusFilter.ToLower().Trim()

    $parsedQuery     = Split-SearchQueryTerms -Query $Query
    $cleanQuery      = $parsedQuery.CleanQuery
    $excludeKeywords = $parsedQuery.ExcludeKeywords

    # --- フレーズ全体一致用正規表現の事前計算 (Exact Phrase Regex Precomputation) ---
    $phraseRegex = $null
    if ($cleanQuery.Length -ge 2) {
        $phraseRegex = [regex]::Escape($cleanQuery)
    }

    # キーワード抽出: WinRT 形態素解析を優先使用
    $keywords = @()
    if (-not [string]::IsNullOrWhiteSpace($cleanQuery)) {
        # 英数字スペース区切りの場合はそのまま単語分割を優先
        if ($cleanQuery -match '^[a-zA-Z0-9_\-\s]+$') {
            $keywords = @($cleanQuery -split '\s+' | Where-Object { $_ -ne "" })
        } else {
            $winrtWords = Get-JapaneseWordsWinRT -Text $cleanQuery
            if ($winrtWords -and $winrtWords.Count -gt 0) {
                $keywords = @($winrtWords)
            } else {
                $keywords = @($cleanQuery -split '\s+' | Where-Object { $_ -ne "" })
            }
        }
    }

    $results = [System.Collections.Generic.List[PSObject]]::new()

    foreach ($item in $script:WikiIndex) {
        # 1. Status Filter (OKF v0.2: stable/active, draft/wip/review, deprecated/archived/obsolete)
        $st = if ($item.Status) { $item.Status.ToString().ToLower().Trim() } else { "active" }
        if ($stFilterLower -ne "all" -and $stFilterLower -ne "") {
            $isMatch = ($st -eq $stFilterLower)
            if (-not $isMatch) {
                if ($stFilterLower -eq "active" -and $st -eq "stable") { $isMatch = $true }
                if ($stFilterLower -eq "draft" -and ($st -in @("wip", "review", "in-review"))) { $isMatch = $true }
                if ($stFilterLower -eq "deprecated" -and ($st -in @("archived", "obsolete"))) { $isMatch = $true }
            }
            if (-not $isMatch) { continue }
        }


        # 2. Domain Filter
        if (-not [string]::IsNullOrWhiteSpace($DomainFilter)) {
            $itemDomain = if ($item.Domain) { $item.Domain } else { "" }
            if ($itemDomain -notlike "*$DomainFilter*") { continue }
        }

        # 3. NOT 除外フィルタ (タイトル/概要/タグ/本文に対象が含まれる場合は除外)
        if ($excludeKeywords.Count -gt 0) {
            $hasExcluded = $false
            foreach ($ex in $excludeKeywords) {
                $exRegex = [regex]::Escape($ex)
                if (($item.Title -and $item.Title -match "(?i)$exRegex") -or
                    ($item.Description -and $item.Description -match "(?i)$exRegex") -or
                    ($item.Tags -and ($item.Tags | Where-Object { $_ -match "(?i)$exRegex" })) -or
                    ($item.BodyText -and $item.BodyText -match "(?i)$exRegex")) {
                    $hasExcluded = $true
                    break
                }
            }
            if ($hasExcluded) { continue }
        }

        if ($keywords.Count -eq 0 -and [string]::IsNullOrWhiteSpace($cleanQuery) -and [string]::IsNullOrWhiteSpace($DomainFilter) -and $stFilterLower -eq "all" -and $excludeKeywords.Count -eq 0) {
            continue
        }

        # 4. 重み付けスコアリング
        $score = 0
        $matchedKwCount = 0

        # --- A. フレーズ全体一致ボーナス (Exact Phrase Bonus) ---
        if ($phraseRegex) {
            if ($item.Title -and $item.Title -match "(?i)$phraseRegex") { $score += 15 }
            if ($item.Description -and $item.Description -match "(?i)$phraseRegex") { $score += 10 }
            if ($item.BodyText -and $item.BodyText -match "(?i)$phraseRegex") { $score += 8 }
        }

        # --- B. 形態素単語単位スコアリング ---
        foreach ($kw in $keywords) {
            $kwRegex = [regex]::Escape($kw)
            $kwMatched = $false

            # Title (+10)
            if ($item.Title -and $item.Title -match $kwRegex) {
                $score += 10
                $kwMatched = $true
            }
            # Tags (+8)
            if ($item.Tags) {
                $tagMatch = $item.Tags | Where-Object { $_ -match $kwRegex }
                if ($tagMatch) {
                    $score += 8
                    $kwMatched = $true
                }
            }
            # Description (+5)
            if ($item.Description -and $item.Description -match $kwRegex) {
                $score += 5
                $kwMatched = $true
            }
            # Domain (+4)
            if ($item.Domain -and $item.Domain -match $kwRegex) {
                $score += 4
                $kwMatched = $true
            }
            # Author (+3)
            if ($item.Author -and $item.Author -match $kwRegex) {
                $score += 3
                $kwMatched = $true
            }
            # BodyText (+1 per hit, max 10)
            if ($item.BodyText) {
                $bodyMatches = ([regex]::Matches($item.BodyText, "(?i)$kwRegex")).Count
                if ($bodyMatches -gt 0) {
                    $score += [Math]::Min($bodyMatches, 10)
                    $kwMatched = $true
                }
            }

            if ($kwMatched) {
                $matchedKwCount++
            }
        }

        # 英数字複数キーワード指定時のAND検証
        if ($cleanQuery -match '^[a-zA-Z0-9_\-\s]+$' -and $keywords.Count -gt 1 -and $matchedKwCount -lt $keywords.Count) {
            continue
        }

        # 非推奨 (deprecated) 70% スコア減点
        if ($st -eq "deprecated") {
            $score = [Math]::Floor($score * 0.3)
        }

        if ($score -gt 0 -or ($keywords.Count -eq 0 -and (-not [string]::IsNullOrWhiteSpace($DomainFilter) -or $stFilterLower -ne "all" -or $excludeKeywords.Count -gt 0))) {
            # スニペット抽出 (キーワードマッチ行の前後の文脈・表を含む最大400文字)
            $snippet = ""
            if ($item.BodyText) {
                $lines = $item.BodyText -split "\r?\n"
                $matchIdx = -1
                for ($lIdx = 0; $lIdx -lt $lines.Count; $lIdx++) {
                    $line = $lines[$lIdx]
                    if ($line -match '^\s*---') { continue }
                    if ($keywords.Count -gt 0) {
                        foreach ($kw in $keywords) {
                            if ($line -match [regex]::Escape($kw)) {
                                $matchIdx = $lIdx
                                break
                            }
                        }
                    } else {
                        if (-not [string]::IsNullOrWhiteSpace($line)) {
                            $matchIdx = $lIdx
                            break
                        }
                    }
                    if ($matchIdx -ge 0) { break }
                }

                if ($matchIdx -ge 0) {
                    $startLine = [Math]::Max(0, $matchIdx - 2)
                    $endLine = [Math]::Min($lines.Count - 1, $matchIdx + 4)
                    $snipLines = @($lines[$startLine..$endLine] | Where-Object { $_ -notmatch '^\s*---' })
                    $snippet = ($snipLines -join "`n").Trim()
                    if ($snippet.Length -gt 400) {
                        $snippet = $snippet.Substring(0, 400) + "..."
                    }
                }
            }

            $results.Add([PSCustomObject]@{
                Meta        = $item
                Score       = $score
                Snippet     = $snippet
            })
        }
    }

    $sorted = @($results | Sort-Object Score -Descending)
    if ($MaxResults -gt 0 -and $sorted.Count -gt $MaxResults) {
        return @($sorted[0..($MaxResults - 1)])
    }
    return $sorted
}

# --- Agentic Tools (PowerShell 内部実行ファンクション) ---

function Get-QueryParams {
    param ([Parameter(Mandatory = $true)][object]$Request)
    $queryDict = @{}
    $rawQuery = $Request.Url.Query
    if (-not [string]::IsNullOrWhiteSpace($rawQuery)) {
        $trimmed = $rawQuery.TrimStart('?')
        $pairs = $trimmed -split '&'
        foreach ($pair in $pairs) {
            if ([string]::IsNullOrWhiteSpace($pair)) { continue }
            $kv = $pair -split '=', 2
            $key = [System.Net.WebUtility]::UrlDecode($kv[0])
            $val = if ($kv.Length -gt 1) { [System.Net.WebUtility]::UrlDecode($kv[1]) } else { "" }
            $queryDict[$key] = $val
        }
    }
    return $queryDict
}

# --- LLM / RAG 暗号解読 ＆ 設定管理関数 ---

function Get-JapaneseWordsWinRT {
    param ([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    $words = [System.Collections.Generic.List[string]]::new()
    try {
        [void][Windows.Data.Text.WordsSegmenter, Windows.Foundation.UniversalApiContract, ContentType = WindowsRuntime]
        $segmenter = [Windows.Data.Text.WordsSegmenter]::CreateWithLanguage("ja-JP")
        $tokens = $segmenter.DetermineProperties($Text)
        foreach ($t in $tokens) {
            $w = $t.Text.Trim()
            if ($w.Length -gt 0 -and $w -notmatch '^[\s\?\!\:\;\,\.\-\_\(\)「」『』【】（）！％＆＝￥？]+$') {
                if ($w -notmatch '^(は|が|の|を|に|で|と|へ|より|から|です|ます|ですか|について|に関して|やり方|方法|教えて|したい|するには)$') {
                    if (-not $words.Contains($w)) {
                        $words.Add($w)
                    }
                }
            }
        }
    } catch {
        # フォールバック (正規表現トークナイズ)
        $termMatches = [regex]::Matches($Text, '[一-龠]+|[ァ-ヴー]{2,}|[a-zA-Z0-9]+')
        foreach ($m in $termMatches) {
            $v = $m.Value.Trim()
            if ($v.Length -ge 2 -and -not $words.Contains($v)) { $words.Add($v) }
        }
    }

    # シノニム / 同義語概念拡張
    if ($words.Contains("セットアップ") -and -not $words.Contains("環境構築")) { $words.Add("環境構築") }
    if ($words.Contains("環境構築") -and -not $words.Contains("セットアップ")) { $words.Add("セットアップ") }

    return $words.ToArray()
}
