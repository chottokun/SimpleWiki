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
        $cacheFiles = Get-ChildItem -Path $cacheDir -Force -Filter ".index-cache-*.json" -File -ErrorAction SilentlyContinue
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
            $cacheItem = Get-Item -LiteralPath $cacheFilePath -Force -ErrorAction SilentlyContinue
            if ($cacheItem) {
                $cacheFileWriteTime = $cacheItem.LastWriteTime
                $currentMdFiles = @(Get-ChildItem -Path $targetDir -Recurse -Filter "*.md" -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notmatch '[\\/]\.(git|lib|tests|dist|\.cache)[\\/]' }) | Where-Object { $null -ne $_ }

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

# --- OKF 検索ヘルパー: ステータス・ドメイン・NOT除外フィルタ判定 ---
function Test-OkfDocFilter {
    param (
        [PSObject]$Item,
        [string]$StatusFilter = "active",
        [string]$DomainFilter = "",
        [string[]]$ExcludeKeywords = @()
    )

    # 1. Status Filter (OKF v0.2: stable/active, draft/wip/review, deprecated/archived/obsolete)
    $stFilterLower = if (-not [string]::IsNullOrWhiteSpace($StatusFilter)) { $StatusFilter.ToLower().Trim() } else { "active" }
    $st = if ($Item.Status) { $Item.Status.ToString().ToLower().Trim() } else { "active" }
    if ($stFilterLower -ne "all" -and $stFilterLower -ne "") {
        $isMatch = ($st -eq $stFilterLower)
        if (-not $isMatch) {
            if ($stFilterLower -eq "active" -and $st -eq "stable") { $isMatch = $true }
            if ($stFilterLower -eq "draft" -and ($st -in @("wip", "review", "in-review"))) { $isMatch = $true }
            if ($stFilterLower -eq "deprecated" -and ($st -in @("archived", "obsolete"))) { $isMatch = $true }
        }
        if (-not $isMatch) { return $false }
    }

    # 2. Domain Filter
    if (-not [string]::IsNullOrWhiteSpace($DomainFilter)) {
        $itemDomain = if ($Item.Domain) { $Item.Domain } else { "" }
        if ($itemDomain -notlike "*$DomainFilter*") { return $false }
    }

    # 3. NOT 除外フィルタ (タイトル/概要/タグ/本文に対象が含まれる場合は除外)
    if ($ExcludeKeywords.Count -gt 0) {
        foreach ($ex in $ExcludeKeywords) {
            $exRegex = [regex]::Escape($ex)
            if (($Item.Title -and $Item.Title -match "(?i)$exRegex") -or
                ($Item.Description -and $Item.Description -match "(?i)$exRegex") -or
                ($Item.Tags -and ($Item.Tags | Where-Object { $_ -match "(?i)$exRegex" })) -or
                ($Item.BodyText -and $Item.BodyText -match "(?i)$exRegex")) {
                return $false
            }
        }
    }

    return $true
}

# --- OKF 検索ヘルパー: 重み付けスコアリング計算 ---
function Get-OkfDocScore {
    param (
        [PSObject]$Item,
        [string]$CleanQuery = "",
        [string[]]$Keywords = @()
    )

    $score = 0
    $matchedKwCount = 0

    # A. フレーズ全体一致ボーナス (Exact Phrase Bonus)
    if ($CleanQuery.Length -ge 2) {
        $phraseRegex = [regex]::Escape($CleanQuery)
        if ($Item.Title -and $Item.Title -match "(?i)$phraseRegex") { $score += 15 }
        if ($Item.Description -and $Item.Description -match "(?i)$phraseRegex") { $score += 10 }
        if ($Item.BodyText -and $Item.BodyText -match "(?i)$phraseRegex") { $score += 8 }
    }

    # B. 形態素単語単位スコアリング
    foreach ($kw in $Keywords) {
        $kwRegex = [regex]::Escape($kw)
        $kwMatched = $false

        # Title (+10)
        if ($Item.Title -and $Item.Title -match $kwRegex) {
            $score += 10
            $kwMatched = $true
        }
        # Tags (+8)
        if ($Item.Tags) {
            $tagMatch = $Item.Tags | Where-Object { $_ -match $kwRegex }
            if ($tagMatch) {
                $score += 8
                $kwMatched = $true
            }
        }
        # Description (+5)
        if ($Item.Description -and $Item.Description -match $kwRegex) {
            $score += 5
            $kwMatched = $true
        }
        # Domain (+4)
        if ($Item.Domain -and $Item.Domain -match $kwRegex) {
            $score += 4
            $kwMatched = $true
        }
        # Author (+3)
        if ($Item.Author -and $Item.Author -match $kwRegex) {
            $score += 3
            $kwMatched = $true
        }
        # BodyText (+1 per hit, max 10)
        if ($Item.BodyText) {
            $bodyMatches = ([regex]::Matches($Item.BodyText, "(?i)$kwRegex")).Count
            if ($bodyMatches -gt 0) {
                $score += [Math]::Min($bodyMatches, 10)
                $kwMatched = $true
            }
        }

        if ($kwMatched) {
            $matchedKwCount++
        }
    }

    # 英数字複数キーワード指定時のAND検証 (すべてヒットしていなければ -1 返却)
    if ($CleanQuery -match '^[a-zA-Z0-9_\-\s]+$' -and $Keywords.Count -gt 1 -and $matchedKwCount -lt $Keywords.Count) {
        return -1
    }

    # 非推奨 (deprecated) 70% スコア減点
    $st = if ($Item.Status) { $Item.Status.ToString().ToLower().Trim() } else { "active" }
    if ($st -eq "deprecated") {
        $score = [Math]::Floor($score * 0.3)
    }

    return $score
}

# --- OKF 検索ヘルパー: スニペット抽出 ---
function Get-OkfDocSnippet {
    param (
        [PSObject]$Item,
        [string[]]$Keywords = @()
    )

    if (-not $Item.BodyText) { return "" }

    $lines = $Item.BodyText -split "\r?\n"
    $matchIdx = -1
    for ($lIdx = 0; $lIdx -lt $lines.Count; $lIdx++) {
        $line = $lines[$lIdx]
        if ($line -match '^\s*---') { continue }
        if ($Keywords.Count -gt 0) {
            foreach ($kw in $Keywords) {
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

    if ($matchIdx -lt 0) { return "" }

    $startLine = [Math]::Max(0, $matchIdx - 2)
    $endLine = [Math]::Min($lines.Count - 1, $matchIdx + 4)
    $snipLines = @($lines[$startLine..$endLine] | Where-Object { $_ -notmatch '^\s*---' })
    $snippet = ($snipLines -join "`n").Trim()
    if ($snippet.Length -gt 400) {
        $snippet = $snippet.Substring(0, 400) + "..."
    }
    return $snippet
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

    # 正規表現パターンの事前エスケープ処理 (ドキュメントループ外で事前計算してCPUサイクルを削減)
    $escapedExcludeKeywords = @(foreach ($ex in $excludeKeywords) { [regex]::Escape($ex) })
    $phraseRegex            = if ($cleanQuery.Length -ge 2) { [regex]::Escape($cleanQuery) } else { $null }
    $escapedKeywords       = @(foreach ($kw in $keywords) { [regex]::Escape($kw) })

    $results = [System.Collections.Generic.List[PSObject]]::new()

    foreach ($item in $script:WikiIndex) {
# --- OKF 讀懃ｴ｢繝倥Ν繝代・: 繧ｹ繝・・繧ｿ繧ｹ繝ｻ繝峨Γ繧､繝ｳ繝ｻNOT髯､螟悶ヵ繧｣繝ｫ繧ｿ蛻､螳・---
function Test-OkfDocFilter {
    param (
        [PSObject]$Item,
        [string]$StatusFilter = "active",
        [string]$DomainFilter = "",
        [string[]]$EscapedExcludeKeywords = @()
    )

    # 1. Status Filter (OKF v0.2: stable/active, draft/wip/review, deprecated/archived/obsolete)
    $stFilterLower = if (-not [string]::IsNullOrWhiteSpace($StatusFilter)) { $StatusFilter.ToLower().Trim() } else { "active" }
    $st = if ($Item.Status) { $Item.Status.ToString().ToLower().Trim() } else { "active" }
    if ($stFilterLower -ne "all" -and $stFilterLower -ne "") {
        $isMatch = ($st -eq $stFilterLower)
        if (-not $isMatch) {
            if ($stFilterLower -eq "active" -and $st -eq "stable") { $isMatch = $true }
            if ($stFilterLower -eq "draft" -and ($st -in @("wip", "review", "in-review"))) { $isMatch = $true }
            if ($stFilterLower -eq "deprecated" -and ($st -in @("archived", "obsolete"))) { $isMatch = $true }
        }
        if (-not $isMatch) { return $false }
    }

    # 2. Domain Filter
    if (-not [string]::IsNullOrWhiteSpace($DomainFilter)) {
        $itemDomain = if ($Item.Domain) { $Item.Domain } else { "" }
        if ($itemDomain -notlike "*$DomainFilter*") { return $false }
    }

    # 3. NOT 髯､螟悶ヵ繧｣繝ｫ繧ｿ (繧ｿ繧､繝医Ν/讎りｦ・繧ｿ繧ｰ/譛ｬ譁・↓蟇ｾ雎｡縺悟性縺ｾ繧後ｋ蝣ｴ蜷医・髯､螟・
    if ($EscapedExcludeKeywords -and $EscapedExcludeKeywords.Count -gt 0) {
        foreach ($exRegex in $EscapedExcludeKeywords) {
            if (($Item.Title -and $Item.Title -match "(?i)$exRegex") -or
                ($Item.Description -and $Item.Description -match "(?i)$exRegex") -or
                ($Item.Tags -and ($Item.Tags | Where-Object { $_ -match "(?i)$exRegex" })) -or
                ($Item.BodyText -and $Item.BodyText -match "(?i)$exRegex")) {
                return $false
            }
        }
    }

    return $true
}

# --- OKF 讀懃ｴ｢繝倥Ν繝代・: 驥阪∩莉倥￠繧ｹ繧ｳ繧｢繝ｪ繝ｳ繧ｰ險育ｮ・---
function Get-OkfDocScore {
    param (
        [PSObject]$Item,
        [string]$PhraseRegex = $null,
        [string[]]$EscapedKeywords = @(),
        [string]$CleanQuery = "",
        [int]$KeywordCount = 0
    )

    $score = 0
    $matchedKwCount = 0

    # A. 繝輔Ξ繝ｼ繧ｺ蜈ｨ菴謎ｸ閾ｴ繝懊・繝翫せ (Exact Phrase Bonus)
    if ($PhraseRegex) {
        if ($Item.Title -and $Item.Title -match "(?i)$PhraseRegex") { $score += 15 }
        if ($Item.Description -and $Item.Description -match "(?i)$PhraseRegex") { $score += 10 }
        if ($Item.BodyText -and $Item.BodyText -match "(?i)$PhraseRegex") { $score += 8 }
    }

    # B. 蠖｢諷狗ｴ蜊倩ｪ槫腰菴阪せ繧ｳ繧｢繝ｪ繝ｳ繧ｰ
    foreach ($kwRegex in $EscapedKeywords) {
        $kwMatched = $false

        # Title (+10)
        if ($Item.Title -and $Item.Title -match $kwRegex) {
            $score += 10
            $kwMatched = $true
        }
        # Tags (+8)
        if ($Item.Tags) {
            $tagMatch = $Item.Tags | Where-Object { $_ -match $kwRegex }
            if ($tagMatch) {
                $score += 8
                $kwMatched = $true
            }
        }
        # Description (+5)
        if ($Item.Description -and $Item.Description -match $kwRegex) {
            $score += 5
            $kwMatched = $true
        }
        # Domain (+4)
        if ($Item.Domain -and $Item.Domain -match $kwRegex) {
            $score += 4
            $kwMatched = $true
        }
        # Author (+3)
        if ($Item.Author -and $Item.Author -match $kwRegex) {
            $score += 3
            $kwMatched = $true
        }
        # BodyText (+1 per hit, max 10)
        if ($Item.BodyText) {
            $bodyMatches = ([regex]::Matches($Item.BodyText, "(?i)$kwRegex")).Count
            if ($bodyMatches -gt 0) {
                $score += [Math]::Min($bodyMatches, 10)
                $kwMatched = $true
            }
        }

        if ($kwMatched) {
            $matchedKwCount++
        }
    }

    # 闍ｱ謨ｰ蟄苓､・焚繧ｭ繝ｼ繝ｯ繝ｼ繝画欠螳壽凾縺ｮAND讀懆ｨｼ (縺吶∋縺ｦ繝偵ャ繝医＠縺ｦ縺・↑縺代ｌ縺ｰ -1 霑泌唆)
    if ($CleanQuery -match '^[a-zA-Z0-9_\-\s]+$' -and $KeywordCount -gt 1 -and $matchedKwCount -lt $KeywordCount) {
        return -1
    }

    # 髱樊耳螂ｨ (deprecated) 70% 繧ｹ繧ｳ繧｢貂帷せ
    $st = if ($Item.Status) { $Item.Status.ToString().ToLower().Trim() } else { "active" }
    if ($st -eq "deprecated") {
        $score = [Math]::Floor($score * 0.3)
    }

    return $score
}

# --- OKF 讀懃ｴ｢繝倥Ν繝代・: 繧ｹ繝九・繝・ヨ謚ｽ蜃ｺ ---
function Get-OkfDocSnippet {
    param (
        [PSObject]$Item,
        [string[]]$EscapedKeywords = @()
    )

    if (-not $Item.BodyText) { return "" }

    $lines = $Item.BodyText -split "\r?\n"
    $matchIdx = -1
    for ($lIdx = 0; $lIdx -lt $lines.Count; $lIdx++) {
        $line = $lines[$lIdx]
        if ($line -match '^\s*---') { continue }
        if ($EscapedKeywords.Count -gt 0) {
            foreach ($kwRegex in $EscapedKeywords) {
                if ($line -match $kwRegex) {
                    $matchIdx = $lIdx
                    break
                }
            }
        }
        if ($matchIdx -ge 0) { break }
    }

    if ($matchIdx -ge 0) {
        $start = [Math]::Max(0, $matchIdx - 1)
        $end   = [Math]::Min($lines.Count - 1, $matchIdx + 2)
        $snipLines = @()
        for ($i = $start; $i -le $end; $i++) {
            $snipLines += $lines[$i].Trim()
        }
        $snip = $snipLines -join " "
        if ($snip.Length -gt 200) { $snip = $snip.Substring(0, 200) + "..." }
        return $snip
    } else {
        return $Item.Description
    }
}

# --- OKF 隍・焚譚｡莉ｶ繝ｻ蠖｢諷狗ｴ繧ｹ繧ｳ繧｢繝ｪ繝ｳ繧ｰ讀懃ｴ｢髢｢謨ｰ ---
function Search-OkfDocs {
    param (
        [string]$Query = "",
        [string]$StatusFilter = "active",
        [string]$DomainFilter = "",
        [int]$Limit = 50
    )

    if (-not $script:WikiIndex -or $script:WikiIndex.Count -eq 0) {
        return @()
    }

    $parsed = Split-SearchQueryTerms -RawQuery $Query
    $cleanQuery      = $parsed.CleanQuery
    $keywords        = $parsed.Keywords
    $excludeKeywords = $parsed.ExcludeKeywords

    # 譌･譛ｬ隱槫ｽ｢諷狗ｴ隗｣譫・(WinRT 繝医・繧ｯ繝翫う繧ｶ繝ｼ) 縺ｫ繧医ｋ繧ｯ繧ｨ繝ｪ諡｡蠑ｵ
    if ($cleanQuery -and $cleanQuery.Length -ge 2 -and ($cleanQuery -match '[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]')) {
        $morphWords = Get-JapaneseWordsWinRT -Text $cleanQuery
        foreach ($mw in $morphWords) {
            if (-not ($keywords -contains $mw)) {
                $keywords += $mw
            }
        }
    }

    # 豁｣隕剰｡ｨ迴ｾ繝代ち繝ｼ繝ｳ縺ｮ莠句燕繧ｨ繧ｹ繧ｱ繝ｼ繝怜・逅・(繝峨く繝･繝｡繝ｳ繝医Ν繝ｼ繝怜､悶〒莠句燕險育ｮ励＠縺ｦCPU繧ｵ繧､繧ｯ繝ｫ繧貞炎貂・
    $escapedExcludeKeywords = @(foreach ($ex in $excludeKeywords) { [regex]::Escape($ex) })
    $phraseRegex            = if ($cleanQuery.Length -ge 2) { [regex]::Escape($cleanQuery) } else { $null }
    $escapedKeywords        = @(foreach ($kw in $keywords) { [regex]::Escape($kw) })

    $results = [System.Collections.Generic.List[PSObject]]::new()

    foreach ($item in $script:WikiIndex) {
        if ($null -eq $item) { continue }

        # 繝輔ぅ繝ｫ繧ｿ蛻､螳・        if (-not (Test-OkfDocFilter -Item $item -StatusFilter $StatusFilter -DomainFilter $DomainFilter -EscapedExcludeKeywords $escapedExcludeKeywords)) {
            continue
        }

        # 繧ｯ繧ｨ繝ｪ縺檎ｩｺ縺ｮ蝣ｴ蜷医・蜈ｨ莉ｶ (繝輔ぅ繝ｫ繧ｿ騾夐℃蛻・ 繧偵せ繧ｳ繧｢1縺ｧ霑斐☆
        if ([string]::IsNullOrWhiteSpace($cleanQuery)) {
            [void]$results.Add([PSCustomObject]@{
                Score   = 1
                Item    = $item
                Snippet = $item.Description
            })
            continue
        }

        # 繧ｹ繧ｳ繧｢繝ｪ繝ｳ繧ｰ險育ｮ・        $score = Get-OkfDocScore -Item $item -PhraseRegex $phraseRegex -EscapedKeywords $escapedKeywords -CleanQuery $cleanQuery -KeywordCount $keywords.Count
        if ($score -le 0) {
            continue
        }

        # 繧ｹ繝九・繝・ヨ謚ｽ蜃ｺ
        $snippet = Get-OkfDocSnippet -Item $item -EscapedKeywords $escapedKeywords

        [void]$results.Add([PSCustomObject]@{
            Score   = $score
            Item    = $item
            Snippet = $snippet
        })
    }

    # 繧ｹ繧ｳ繧｢髯埼・∝酔轤ｹ譎ゅ・譖ｴ譁ｰ譌･髯埼・〒繧ｽ繝ｼ繝医＠縺ｦ Limit 莉ｶ霑泌唆
    $sorted = $results | Sort-Object -Property @{ Expression = { $_.Score }; Descending = $true },
                                              @{ Expression = { if ($_.Item.LastUpdated) { $_.Item.LastUpdated } else { [DateTime]::MinValue } }; Descending = $true } |
                         Select-Object -First $Limit

    return @($sorted)
}