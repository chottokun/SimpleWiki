# ==============================================================================
#  WikiSearch.ps1
#  OKF Search Engine, Cache Management, and Hierarchical Tree Generator
#  Encoding: UTF-8 with BOM
# ==============================================================================

# --- Index Cache & Progress Management Functions ---

function Get-WikiCachePath {
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
    $baseScriptDir = if (-not [string]::IsNullOrWhiteSpace($TargetScriptDir)) { $TargetScriptDir } elseif (-not [string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir } elseif (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { $PWD.Path }
    $config = Get-ConfigJson -TargetScriptDir $baseScriptDir
    $cacheSubFolder = if ($config.search -and -not [string]::IsNullOrWhiteSpace($config.search.cacheFolder)) { $config.search.cacheFolder } else { ".cache" }
    $cacheDir = Join-Path $baseScriptDir $cacheSubFolder

    $removedCount = 0
    if (Test-Path $cacheDir) {
        $cacheFiles = Get-ChildItem -Path $cacheDir -Filter ".index-cache-*.json" -File -ErrorAction SilentlyContinue
        foreach ($cf in $cacheFiles) {
            try {
                Remove-Item -LiteralPath $cf.FullName -Force -ErrorAction Stop
                $removedCount++
            } catch {}
        }
        $statusFiles = Get-ChildItem -Path $cacheDir -Filter ".index-status-*.json" -File -ErrorAction SilentlyContinue
        foreach ($sf in $statusFiles) {
            try { Remove-Item -LiteralPath $sf.FullName -Force -ErrorAction SilentlyContinue } catch {}
        }
    }

    $script:WikiIndex = @()
    $script:WikiIndexLastScan = [DateTime]::MinValue
    $script:WikiIndexDirWriteTime = [DateTime]::MinValue
    $script:SidebarCachedHtml = $null
    $script:IndexingStatus = [PSCustomObject]@{
        IsBuilding = $false
        Total      = 0
        Current    = 0
        Percent    = 0
        LastScan   = [DateTime]::MinValue
    }

    return [PSCustomObject]@{
        deletedFiles = $removedCount
        success      = $true
    }
}

function Save-WikiIndexCache {
    param (
        [string]$TargetWikiDir = $script:wikiDir,
        [string]$TargetScriptDir = $scriptDir
    )
    try {
        $baseScriptDir = if (-not [string]::IsNullOrWhiteSpace($TargetScriptDir)) { $TargetScriptDir } elseif (-not [string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir } elseif (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { $PWD.Path }
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
        Write-Warning ("Failed to save index cache: {0}" -f $_)
        return $false
    }
}

function Load-WikiIndexCache {
    param (
        [string]$TargetWikiDir = $script:wikiDir,
        [string]$TargetScriptDir = $scriptDir
    )
    try {
        $baseScriptDir = if (-not [string]::IsNullOrWhiteSpace($TargetScriptDir)) { $TargetScriptDir } elseif (-not [string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir } elseif (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { $PWD.Path }
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
                    Where-Object { $_.FullName -notmatch '[\\/](\.git|lib|tests|dist|\.cache|scratch)[\\/]' })

                if ($currentMdFiles.Count -ne $cacheData.Items.Count) {
                    return $false
                }

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
                Title        = $item.Title
                Description  = $item.Description
                Author       = $item.Author
                Domain       = $item.Domain
                Tags         = @($item.Tags)
                LastUpdated  = $lastUpdated
                Status       = $item.Status
                Version      = $item.Version
                Reviewer     = $item.Reviewer
                SupersededBy = $item.SupersededBy
                TrustTier    = $item.TrustTier
                Provenance   = $item.Provenance
                Computations = $item.Computations
                Contributors = $item.Contributors
                Related      = $item.Related
                HasYaml      = [bool]$item.HasYaml
                RelPath      = $item.RelPath
                FullPath     = $item.FullPath
                BodyText     = $item.BodyText
            }
            $itemList.Add($psObj)
        }

        $script:WikiIndex = $itemList.ToArray()
        $script:WikiIndexDirWriteTime = (Get-Item $targetDir).LastWriteTime
        $script:WikiIndexLastScan = Get-Date
        return $true
    } catch {
        Write-Warning ("Failed to load index cache: {0}" -f $_)
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

    try {
        $statusFilePath = Get-WikiStatusPath -TargetWikiDir $targetDir -TargetScriptDir $baseScriptDir
        if (Test-Path $statusFilePath) {
            $statusJson = [System.IO.File]::ReadAllText($statusFilePath, [System.Text.Encoding]::UTF8)
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
        [string]$TargetScriptDir = $scriptDir,
        [switch]$ForceRefresh
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

    $mdFiles = @(Get-ChildItem -Path $targetDir -Recurse -Filter "*.md" |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|lib|tests|dist|\.cache|scratch)[\\/]' } |
        Sort-Object FullName)

    $totalFiles = $mdFiles.Count
    $script:IndexingStatus = [PSCustomObject]@{
        IsBuilding = $true
        Total      = $totalFiles
        Current    = 0
        Percent    = 0
        LastScan   = $script:WikiIndexLastScan
    }
    Save-WikiIndexingStatusFile -StatusObj $script:IndexingStatus -TargetWikiDir $targetDir -TargetScriptDir $baseScriptDir

    $indexList = [System.Collections.Generic.List[PSObject]]::new()
    $idx = 0
    try {
        foreach ($file in $mdFiles) {
            $idx++
            $relPath = $file.FullName.Substring($targetDir.Length).TrimStart("\", "/")
            $meta    = Get-DocumentMetadata -File $file -RelPath $relPath
            $indexList.Add($meta)

            $pct = if ($totalFiles -gt 0) { [int][Math]::Floor(($idx / $totalFiles) * 100) } else { 100 }
            $script:IndexingStatus.Current = $idx
            $script:IndexingStatus.Percent = $pct

            if ($idx % 50 -eq 0 -or $idx -eq $totalFiles) {
                Save-WikiIndexingStatusFile -StatusObj $script:IndexingStatus -TargetWikiDir $targetDir -TargetScriptDir $baseScriptDir
            }
        }
    } finally {
        $script:WikiIndex = $indexList.ToArray()
        $script:WikiIndexDirWriteTime = $currentWriteTime
        $script:WikiIndexLastScan = Get-Date

        Save-WikiIndexCache -TargetWikiDir $targetDir -TargetScriptDir $baseScriptDir | Out-Null

        $script:IndexingStatus = [PSCustomObject]@{
            IsBuilding = $false
            Total      = $totalFiles
            Current    = $totalFiles
            Percent    = 100
            LastScan   = $script:WikiIndexLastScan
        }
        Save-WikiIndexingStatusFile -StatusObj $script:IndexingStatus -TargetWikiDir $targetDir -TargetScriptDir $baseScriptDir
    }

    return $script:WikiIndex
}

# --- Sidebar Tree Generation Functions ---

function Build-FileTreeNode {
    param(
        [Parameter(Mandatory = $false)][string]$wikiDir = "",
        [Parameter(Mandatory = $false)][string]$baseDir = "",
        [Parameter(Mandatory = $false)][string]$currentRelPath = "",
        [Parameter(Mandatory = $false)][string]$pageRelPath = "",
        [Parameter(Mandatory = $false)]$allMdFiles = $null
    )

    $node = [PSCustomObject]@{
        Files      = [System.Collections.Generic.List[PSObject]]::new()
        SubFolders = [System.Collections.Specialized.OrderedDictionary]::new()
    }

    if ($allMdFiles -and $allMdFiles.Count -gt 0) {
        $prefix = if ($wikiDir) { $wikiDir.TrimEnd('\', '/') } else { "" }
        foreach ($file in $allMdFiles) {
            $fullName = if ($file.FullName) { $file.FullName } else { $file.ToString() }
            $rel = if ($prefix -and $fullName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $fullName.Substring($prefix.Length).TrimStart('\', '/')
            } else {
                $fullName.TrimStart('\', '/')
            }

            $parts = $rel -split '[\\/]'
            if ($parts.Length -eq 1) {
                $node.Files.Add([PSCustomObject]@{
                    Name     = $parts[0]
                    RelPath  = $rel.Replace('\', '/')
                    Title    = if ($file.BaseName) { $file.BaseName } else { [System.IO.Path]::GetFileNameWithoutExtension($parts[0]) }
                    IsActive = ($rel.Replace('\', '/') -eq $pageRelPath)
                })
            } else {
                $currNode = $node
                for ($p = 0; $p -lt $parts.Length - 1; $p++) {
                    $folder = $parts[$p]
                    if (-not $currNode.SubFolders.Contains($folder)) {
                        $currNode.SubFolders[$folder] = [PSCustomObject]@{
                            Files      = [System.Collections.Generic.List[PSObject]]::new()
                            SubFolders = [System.Collections.Specialized.OrderedDictionary]::new()
                        }
                    }
                    $currNode = $currNode.SubFolders[$folder]
                }
                $fileName = $parts[-1]
                $currNode.Files.Add([PSCustomObject]@{
                    Name     = $fileName
                    RelPath  = $rel.Replace('\', '/')
                    Title    = if ($file.BaseName) { $file.BaseName } else { [System.IO.Path]::GetFileNameWithoutExtension($fileName) }
                    IsActive = ($rel.Replace('\', '/') -eq $pageRelPath)
                })
            }
        }
        return $node
    }

    $targetDir = if ([string]::IsNullOrWhiteSpace($baseDir)) { $wikiDir } else { $baseDir }
    if (-not (Test-Path $targetDir)) { return $node }

    $items = Get-ChildItem -Path $targetDir | Sort-Object { -not $_.PSIsContainer }, Name
    foreach ($item in $items) {
        if ($item.PSIsContainer) {
            $subBase = $item.FullName
            $subRel  = if ([string]::IsNullOrWhiteSpace($currentRelPath)) { $item.Name } else { "$currentRelPath/$($item.Name)" }
            $node.SubFolders[$item.Name] = Build-FileTreeNode -wikiDir $wikiDir -baseDir $subBase -currentRelPath $subRel -pageRelPath $pageRelPath
        } else {
            if ($item.Extension -eq ".md") {
                $docRel = if ([string]::IsNullOrWhiteSpace($currentRelPath)) { $item.Name } else { "$currentRelPath/$($item.Name)" }
                $docMeta = Get-DocumentMetadata -File $item -RelPath $docRel
                $node.Files.Add([PSCustomObject]@{
                    Name     = $item.Name
                    RelPath  = $docRel
                    Title    = $docMeta.Title
                    IsActive = ($docRel -eq $pageRelPath)
                })
            }
        }
    }
    return $node
}

function Test-ExportNodeHasActiveFile {
    param(
        [Parameter(Mandatory = $true)]$node,
        [Parameter(Mandatory = $false)][string]$pageRelPath = "",
        [Parameter(Mandatory = $false)]$currentFile = $null
    )

    $targetRel = if ($currentFile) {
        if ($currentFile.FullName) { $currentFile.FullName } else { $currentFile.ToString() }
    } else {
        $pageRelPath
    }

    if ([string]::IsNullOrWhiteSpace($targetRel)) { return $false }
    $normTarget = $targetRel.Replace('\', '/').ToLower()

    foreach ($f in $node.Files) {
        $fRel = if ($f.RelPath) { $f.RelPath.Replace('\', '/').ToLower() } elseif ($f.FullName) { $f.FullName.Replace('\', '/').ToLower() } else { "" }
        if ($fRel -eq $normTarget -or $normTarget.EndsWith($fRel)) { return $true }
    }
    foreach ($subKey in $node.SubFolders.Keys) {
        $sub = $node.SubFolders[$subKey]
        if (Test-ExportNodeHasActiveFile -node $sub -pageRelPath $pageRelPath -currentFile $currentFile) { return $true }
    }
    return $false
}

function Render-FileTreeHtml {
    param(
        [Parameter(Mandatory = $true)]$node,
        [Parameter(Mandatory = $true)][string]$pageRelPath,
        [Parameter(Mandatory = $true)][string]$relPrefix
    )

    $html = "<ul>`n"
    foreach ($f in $node.Files) {
        $activeClass = if ($f.IsActive) { " class='active'" } else { "" }
        $targetHtmlRel = ($f.RelPath -replace '\.md$', '.html').Replace('\', '/')
        $href = if ([string]::IsNullOrWhiteSpace($relPrefix)) { $targetHtmlRel } else { "$relPrefix/$targetHtmlRel" }
        $encTitle = [System.Net.WebUtility]::HtmlEncode($f.Title)
        $html += "  <li class='nav-file'><a href='$href'$activeClass>$encTitle</a></li>`n"
    }

    foreach ($folderName in $node.SubFolders.Keys) {
        $subNode     = $node.SubFolders[$folderName]
        $encodedName = [System.Net.WebUtility]::HtmlEncode($folderName)
        $subHtml     = Render-FileTreeHtml -node $subNode -pageRelPath $pageRelPath -relPrefix $relPrefix

        $isOpen   = Test-ExportNodeHasActiveFile -node $subNode -pageRelPath $pageRelPath
        $openAttr = if ($isOpen) { " open" } else { "" }

        $html += "  <li class='nav-folder'>`n"
        $html += "    <details$openAttr>`n"
        $html += "      <summary class='folder-title'>&#128193; $encodedName</summary>`n"
        $html += "      $subHtml`n"
        $html += "    </details>`n"
        $html += "  </li>`n"
    }

    $html += "</ul>"
    return $html
}

function Build-ServerFileTreeNode {
    param(
        [Parameter(Mandatory = $false)][string]$wikiDir = "",
        [Parameter(Mandatory = $false)][string]$baseDir = "",
        [Parameter(Mandatory = $false)][string]$currentRelPath = "",
        [Parameter(Mandatory = $false)]$allMdFiles = $null
    )

    $node = [PSCustomObject]@{
        Files      = [System.Collections.Generic.List[PSObject]]::new()
        SubFolders = [System.Collections.Specialized.OrderedDictionary]::new()
    }

    if ($allMdFiles -and $allMdFiles.Count -gt 0) {
        $prefix = if ($wikiDir) { $wikiDir.TrimEnd('\', '/') } else { "" }
        foreach ($file in $allMdFiles) {
            $fullName = if ($file.FullName) { $file.FullName } else { $file.ToString() }
            $rel = if ($prefix -and $fullName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $fullName.Substring($prefix.Length).TrimStart('\', '/')
            } else {
                $fullName.TrimStart('\', '/')
            }

            $parts = $rel -split '[\\/]'
            if ($parts.Length -eq 1) {
                $node.Files.Add([PSCustomObject]@{
                    Name     = $parts[0]
                    RelPath  = $rel.Replace('\', '/')
                    Title    = [System.IO.Path]::GetFileNameWithoutExtension($parts[0])
                })
            } else {
                $currNode = $node
                for ($p = 0; $p -lt $parts.Length - 1; $p++) {
                    $folder = $parts[$p]
                    if (-not $currNode.SubFolders.Contains($folder)) {
                        $currNode.SubFolders[$folder] = [PSCustomObject]@{
                            Files      = [System.Collections.Generic.List[PSObject]]::new()
                            SubFolders = [System.Collections.Specialized.OrderedDictionary]::new()
                        }
                    }
                    $currNode = $currNode.SubFolders[$folder]
                }
                $fileName = $parts[-1]
                $currNode.Files.Add([PSCustomObject]@{
                    Name     = $fileName
                    RelPath  = $rel.Replace('\', '/')
                    Title    = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                })
            }
        }
        return $node
    }

    $targetDir = if ([string]::IsNullOrWhiteSpace($baseDir)) { $wikiDir } else { $baseDir }
    if (-not (Test-Path $targetDir)) {
        return $node
    }

    $items = Get-ChildItem -Path $targetDir | Sort-Object { -not $_.PSIsContainer }, Name
    foreach ($item in $items) {
        if ($item.PSIsContainer) {
            $subBase = $item.FullName
            $subRel  = if ([string]::IsNullOrWhiteSpace($currentRelPath)) { $item.Name } else { "$currentRelPath/$($item.Name)" }
            $node.SubFolders[$item.Name] = Build-ServerFileTreeNode -wikiDir $wikiDir -baseDir $subBase -currentRelPath $subRel
        } else {
            if ($item.Extension -eq ".md") {
                $docRel = if ([string]::IsNullOrWhiteSpace($currentRelPath)) { $item.Name } else { "$currentRelPath/$($item.Name)" }
                $docMeta = Get-DocumentMetadata -File $item -RelPath $docRel
                $node.Files.Add([PSCustomObject]@{
                    Name     = $item.Name
                    RelPath  = $docRel
                    Title    = $docMeta.Title
                })
            }
        }
    }
    return $node
}

function Test-ServerNodeHasActiveFile {
    param(
        [Parameter(Mandatory = $true)]$node,
        [Parameter(Mandatory = $false)][string]$currentRelPath = "",
        [Parameter(Mandatory = $false)][string]$wikiDir = "",
        [Parameter(Mandatory = $false)]$allMdFiles = $null
    )

    if ([string]::IsNullOrWhiteSpace($currentRelPath)) { return $false }
    $normCurrent = $currentRelPath.Replace('\', '/').ToLower()

    if ($node.Files) {
        foreach ($f in $node.Files) {
            $fRel = if ($f.RelPath) { $f.RelPath.Replace('\', '/').ToLower() } elseif ($f.FullName) { $f.FullName.Replace('\', '/').ToLower() } else { "" }
            if ($fRel -eq $normCurrent -or $normCurrent.EndsWith($fRel)) { return $true }
        }
    }
    if ($node.SubFolders) {
        foreach ($subKey in $node.SubFolders.Keys) {
            $sub = $node.SubFolders[$subKey]
            if (Test-ServerNodeHasActiveFile -node $sub -currentRelPath $currentRelPath -wikiDir $wikiDir -allMdFiles $allMdFiles) { return $true }
        }
    }
    return $false
}

function Render-ServerFolderTreeHtml {
    param(
        [Parameter(Mandatory = $true)]$node,
        [Parameter(Mandatory = $false)][string]$currentRelPath = "",
        [Parameter(Mandatory = $false)][string]$wikiDir = "",
        [Parameter(Mandatory = $false)]$allMdFiles = $null
    )

    if ($null -eq $node) { return "<ul>`n</ul>" }

    $html = "<ul>`n"

    # Sort files: pin index.md and README.md to the top, then sort alphabetically
    $sortedFiles = if ($node.Files) {
        @($node.Files | Sort-Object -Property @{
            Expression = {
                $n = if ($_.Name) { $_.Name.ToLower() } elseif ($_.BaseName) { "$($_.BaseName.ToLower()).md" } elseif ($_.FullName) { [System.IO.Path]::GetFileName($_.FullName).ToLower() } else { "" }
                if ($n -eq "index.md" -or $n -eq "index") { return 0 }
                if ($n -eq "readme.md" -or $n -eq "readme") { return 1 }
                return 2
            }
        }, @{
            Expression = {
                $n = if ($_.BaseName) { $_.BaseName.ToLower() } elseif ($_.Name) { $_.Name.ToLower() } elseif ($_.Title) { $_.Title.ToLower() } else { "" }
                return $n
            }
        })
    } else { @() }

    foreach ($f in $sortedFiles) {
        if (-not $f) { continue }
        $rel = if ($f.RelPath) {
            $f.RelPath
        } elseif ($f.FullName -and $wikiDir -and $f.FullName.StartsWith($wikiDir, [System.StringComparison]::OrdinalIgnoreCase)) {
            $f.FullName.Substring($wikiDir.Length).TrimStart('\', '/')
        } elseif ($f.FullName) {
            [System.IO.Path]::GetFileName($f.FullName)
        } elseif ($f.Name) {
            $f.Name
        } elseif ($f.BaseName) {
            "$($f.BaseName).md"
        } else {
            ""
        }

        $title = if ($f.Title) {
            $f.Title
        } elseif ($f.BaseName) {
            $f.BaseName
        } elseif ($f.Name) {
            [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        } elseif ($f.FullName) {
            [System.IO.Path]::GetFileNameWithoutExtension($f.FullName)
        } else {
            "Untitled"
        }

        $activeClass = if ($currentRelPath -and $rel -eq $currentRelPath) { " class='active'" } else { "" }
        $relUri = "/" + [Uri]::EscapeUriString($rel.Replace('\', '/'))
        $encTitle = [System.Net.WebUtility]::HtmlEncode($title)
        $html += "  <li class='nav-file'><a href='$relUri'$activeClass>$encTitle</a></li>`n"
    }

    foreach ($folderName in $node.SubFolders.Keys) {
        $subNode     = $node.SubFolders[$folderName]
        $encodedName = [System.Net.WebUtility]::HtmlEncode($folderName)
        $subHtml     = Render-ServerFolderTreeHtml -node $subNode -currentRelPath $currentRelPath -wikiDir $wikiDir -allMdFiles $allMdFiles

        $isOpen   = Test-ServerNodeHasActiveFile -node $subNode -currentRelPath $currentRelPath -wikiDir $wikiDir -allMdFiles $allMdFiles
        $openAttr = if ($isOpen) { " open" } else { "" }

        $html += "  <li class='nav-folder'>`n"
        $html += "    <details$openAttr>`n"
        $html += "      <summary class='folder-title'>&#128193; $encodedName</summary>`n"
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

    $escapedWords = @(foreach ($w in $validKws) { [regex]::Escape($w) })
    $pattern = "(" + ($escapedWords -join "|") + ")"

    $parts = [regex]::Split($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($p in $parts) {
        if ([string]::IsNullOrEmpty($p)) { continue }
        $isMatch = $false
        foreach ($w in $validKws) {
            if ($p.Equals($w, [System.StringComparison]::OrdinalIgnoreCase)) {
                $isMatch = $true
                break
            }
        }
        $encoded = [System.Net.WebUtility]::HtmlEncode($p)
        if ($isMatch) {
            [void]$sb.Append("<mark class='search-highlight'>$encoded</mark>")
        } else {
            [void]$sb.Append($encoded)
        }
    }
    return $sb.ToString()
}

function Split-SearchQueryTerms {
    param (
        [string]$RawQuery = "",
        [string]$Query = ""
    )

    $targetQuery = if (-not [string]::IsNullOrWhiteSpace($RawQuery)) { $RawQuery } else { $Query }
    $result = [PSCustomObject]@{
        CleanQuery      = ""
        IncludeKeywords = @()
        ExcludeKeywords = @()
        Keywords        = @()
    }

    if ([string]::IsNullOrWhiteSpace($targetQuery)) {
        return $result
    }

    $includeList = [System.Collections.Generic.List[string]]::new()
    $excludeList = [System.Collections.Generic.List[string]]::new()

    $qNorm = $targetQuery -replace '[\u3000]', ' '
    $pattern = '(?i)(?:^|\s+)(?:NOT\s*|[\-!])(?:"([^"]+)"|([^\s]+))|(?:^|\s+)(?:"([^"]+)"|([^\s]+))'
    $matchesObj = [regex]::Matches($qNorm, $pattern)

    foreach ($m in $matchesObj) {
        if ($m.Groups[1].Success -or $m.Groups[2].Success) {
            $term = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
            $term = $term.Trim()
            if ($term.Length -gt 0 -and -not $excludeList.Contains($term)) {
                $excludeList.Add($term)
            }
        } elseif ($m.Groups[3].Success -or $m.Groups[4].Success) {
            $term = if ($m.Groups[3].Success) { $m.Groups[3].Value } else { $m.Groups[4].Value }
            $term = $term.Trim()
            if ($term.Length -gt 0 -and -not $includeList.Contains($term)) {
                $includeList.Add($term)
            }
        }
    }

    $result.IncludeKeywords = @($includeList)
    $result.ExcludeKeywords = @($excludeList)
    $result.Keywords        = @($includeList)
    $result.CleanQuery      = ($includeList -join " ").Trim()
    return $result
}

function Get-QueryParams {
    param ([Parameter(Mandatory = $true)][object]$Request)
    $queryDict = @{}
    $rawQuery = if ($Request -and $Request.Url) { $Request.Url.Query } else { "" }
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
            if ($w.Length -gt 0 -and $w -notmatch '^[\s\?\!\:\;\,\.\-\_\(\)\u300c\u300d\u300e\u300f\u3010\u3011\uff08\uff09\uff01\uff05\uff06\uff1d\uffe5\uff1f]+$') {
                if ($w -notmatch '^(\u306f|\u304c|\u306e|\u3092|\u306b|\u3067|\u3068|\u3078|\u3088\u308a|\u304b\u3089|\u3067\u3059|\u307e\u3059|\u3067\u3059\u304b|\u306b\u3064\u3044\u3066|\u306b\u95a2\u3057\u3066|\u3084\u308a\u65b9|\u65b9\u6cd5|\u6559\u3048\u3066|\u3057\u305f\u3044|\u3059\u308b\u306b\u306f)$') {
                    if (-not $words.Contains($w)) {
                        $words.Add($w)
                    }
                }
            }
        }
    } catch {
        $termMatches = [regex]::Matches($Text, '[\u4e00-\u9faf]+|[\u30a1-\u30f6\u30fc]{2,}|[a-zA-Z0-9]+')
        foreach ($m in $termMatches) {
            $v = $m.Value.Trim()
            if ($v.Length -ge 2 -and -not $words.Contains($v)) { $words.Add($v) }
        }
    }

    $kwSetup = [regex]::Unescape("\u30bb\u30c3\u30c8\u30a2\u30c3\u30d7")
    $kwEnv   = [regex]::Unescape("\u74b0\u5883\u69cb\u7bc9")

    if ($words.Contains($kwSetup) -and -not $words.Contains($kwEnv)) { $words.Add($kwEnv) }
    if ($words.Contains($kwEnv) -and -not $words.Contains($kwSetup)) { $words.Add($kwSetup) }

    return $words.ToArray()
}

function Test-OkfDocFilter {
    param (
        [PSObject]$Item,
        [string]$StatusFilter = "active",
        [string]$DomainFilter = "",
        [string[]]$EscapedExcludeKeywords = @()
    )

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

    if (-not [string]::IsNullOrWhiteSpace($DomainFilter)) {
        $itemDomain = if ($Item.Domain) { $Item.Domain } else { "" }
        if ($itemDomain -notlike "*$DomainFilter*") { return $false }
    }

    if ($EscapedExcludeKeywords -and $EscapedExcludeKeywords.Count -gt 0) {
        foreach ($exRegex in $EscapedExcludeKeywords) {
            if (($Item.Title -and $Item.Title -match "(?i)$exRegex") -or
                ($Item.Description -and $Item.Description -match "(?i)$exRegex") -or
                ($Item.Tags -and ($Item.Tags -join " ") -match "(?i)$exRegex") -or
                ($Item.BodyText -and $Item.BodyText -match "(?i)$exRegex")) {
                return $false
            }
        }
    }

    return $true
}

function Get-OkfDocScore {
    param (
        [PSObject]$Item,
        [string]$PhraseRegex,
        [string[]]$EscapedKeywords = @(),
        [string[]]$Keywords = @(),
        [string]$CleanQuery = "",
        [int]$KeywordCount = 0
    )

    $score = 0
    $matchedKwCount = 0

    $kwsToUse = if ($EscapedKeywords -and $EscapedKeywords.Count -gt 0) { $EscapedKeywords } else { $Keywords }

    if ($PhraseRegex) {
        if ($Item.Title -and $Item.Title -match "(?i)$PhraseRegex") {
            $score += 50
        }
        if ($Item.Description -and $Item.Description -match "(?i)$PhraseRegex") {
            $score += 20
        }
    }

    foreach ($kwRegex in $kwsToUse) {
        $kwMatched = $false

        if ($Item.Title -and $Item.Title -match "(?i)$kwRegex") {
            $score += 20
            $kwMatched = $true
        }

        if ($Item.Tags) {
            $tagStr = $Item.Tags -join " "
            if ($tagStr -match "(?i)$kwRegex") {
                $score += 15
                $kwMatched = $true
            }
        }

        if ($Item.Description -and $Item.Description -match "(?i)$kwRegex") {
            $score += 10
            $kwMatched = $true
        }

        if ($Item.BodyText) {
            $bodyMatches = [regex]::Matches($Item.BodyText, "(?i)$kwRegex").Count
            if ($bodyMatches -gt 0) {
                $score += [Math]::Min($bodyMatches, 10)
                $kwMatched = $true
            }
        }

        if ($kwMatched) {
            $matchedKwCount++
        }
    }

    if ($CleanQuery -match '^[a-zA-Z0-9_\-\s]+$' -and $KeywordCount -gt 1 -and $matchedKwCount -lt $KeywordCount) {
        return -1
    }

    $st = if ($Item.Status) { $Item.Status.ToString().ToLower().Trim() } else { "active" }
    if ($st -eq "deprecated") {
        $score = [Math]::Floor($score * 0.3)
    }

    return $score
}

function Get-OkfDocSnippet {
    param (
        [PSObject]$Item,
        [string[]]$EscapedKeywords = @(),
        [string[]]$Keywords = @()
    )

    if (-not $Item.BodyText) {
        if ($Item.Description) { return $Item.Description } else { return "" }
    }

    $kwsToUse = if ($EscapedKeywords -and $EscapedKeywords.Count -gt 0) { $EscapedKeywords } else { $Keywords }

    $lines = $Item.BodyText -split "\r?\n"
    $matchIdx = -1
    for ($lIdx = 0; $lIdx -lt $lines.Count; $lIdx++) {
        $line = $lines[$lIdx]
        if ($line -match '^\s*---') { continue }
        if ($kwsToUse.Count -gt 0) {
            foreach ($kwRegex in $kwsToUse) {
                if ($line -match "(?i)$kwRegex") {
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
        if ($Item.Description) { return $Item.Description } else { return "" }
    }
}

function Search-OkfDocs {
    param (
        [string]$Query = "",
        [string]$StatusFilter = "active",
        [string]$DomainFilter = "",
        [string]$WikiDir = "",
        [int]$MaxResults = 0,
        [int]$Limit = 50
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

    if ($MaxResults -gt 0) { $Limit = $MaxResults }
    if (-not $script:WikiIndex -or $script:WikiIndex.Count -eq 0) {
        return @()
    }

    $parsed = Split-SearchQueryTerms -RawQuery $Query
    $cleanQuery      = $parsed.CleanQuery
    $keywords        = @($parsed.Keywords)
    $excludeKeywords = @($parsed.ExcludeKeywords)

    if ($cleanQuery -and $cleanQuery.Length -ge 2 -and ($cleanQuery -match '[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]')) {
        $morphWords = Get-JapaneseWordsWinRT -Text $cleanQuery
        foreach ($mw in $morphWords) {
            if (-not ($keywords -contains $mw)) {
                $keywords += $mw
            }
        }
    }

    $escapedExcludeKeywords = @(foreach ($ex in $excludeKeywords) { [regex]::Escape($ex) })
    $phraseRegex            = if ($cleanQuery.Length -ge 2) { [regex]::Escape($cleanQuery) } else { $null }
    $escapedKeywords        = @(foreach ($kw in $keywords) { [regex]::Escape($kw) })

    $results = [System.Collections.Generic.List[PSObject]]::new()

    foreach ($item in $script:WikiIndex) {
        if ($null -eq $item) { continue }

        if (-not (Test-OkfDocFilter -Item $item -StatusFilter $StatusFilter -DomainFilter $DomainFilter -EscapedExcludeKeywords $escapedExcludeKeywords)) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($cleanQuery)) {
            [void]$results.Add([PSCustomObject]@{
                Score        = 1
                Item         = $item
                Meta         = $item
                Snippet      = $item.Description
                RelPath      = $item.RelPath
                Title        = $item.Title
                Description  = $item.Description
                Domain       = $item.Domain
                Tags         = $item.Tags
                Status       = $item.Status
                LastUpdated  = $item.LastUpdated
                BodyText     = $item.BodyText
            })
            continue
        }

        $score = Get-OkfDocScore -Item $item -PhraseRegex $phraseRegex -EscapedKeywords $escapedKeywords -Keywords $keywords -CleanQuery $cleanQuery -KeywordCount $keywords.Count
        if ($score -le 0) {
            continue
        }

        $snippet = Get-OkfDocSnippet -Item $item -EscapedKeywords $escapedKeywords -Keywords $keywords

        [void]$results.Add([PSCustomObject]@{
            Score        = $score
            Item         = $item
            Meta         = $item
            Snippet      = $snippet
            RelPath      = $item.RelPath
            Title        = $item.Title
            Description  = $item.Description
            Domain       = $item.Domain
            Tags         = $item.Tags
            Status       = $item.Status
            LastUpdated  = $item.LastUpdated
            BodyText     = $item.BodyText
        })
    }

    $sorted = $results | Sort-Object -Property @{ Expression = { $_.Score }; Descending = $true },
                                              @{ Expression = { if ($_.Item.LastUpdated) { $_.Item.LastUpdated } else { [DateTime]::MinValue } }; Descending = $true } |
                         Select-Object -First $Limit

    return @($sorted)
}