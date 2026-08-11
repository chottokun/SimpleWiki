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
    Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
    Add-Type -Path $_.FullName
}

# --- OKF メタデータ抽出し ＆ 自動補完 (フォールバック) 関数 ---
function Get-DocumentMetadata {
    param (
        [Parameter(Mandatory = $true)]$File,
        [string]$RelPath = "",
        [string]$MdText = ""
    )

    if ([string]::IsNullOrEmpty($MdText) -and $File -and (Test-Path $File.FullName)) {
        $MdText = Get-Content -Path $File.FullName -Raw -Encoding UTF8
    }

    $hasYaml  = $false
    $bodyText = $MdText
    $yamlDict = @{}

    if ($MdText -match '(?s)^\s*---\r?\n(.*?)\r?\n---\r?\n(.*)$') {
        $hasYaml  = $true
        $rawYaml  = $matches[1]
        $bodyText = $matches[2]

        try {
            $currentKey = $null
            $lines = $rawYaml -split '\r?\n'
            foreach ($line in $lines) {
                if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }

                if ($currentKey -and $line -match '^\s*-\s+(.*)$') {
                    $itemVal = $matches[1].Trim().Trim('"', "'")
                    if (-not $yamlDict.ContainsKey($currentKey) -or $yamlDict[$currentKey] -isnot [System.Collections.IList]) {
                        $yamlDict[$currentKey] = [System.Collections.Generic.List[string]]::new()
                    }
                    [void]$yamlDict[$currentKey].Add($itemVal)
                    continue
                }

                if ($line -match '^\s*([a-zA-Z0-9_\-]+)\s*:\s*(.*)$') {
                    $key = $matches[1].ToLower().Trim()
                    $val = $matches[2].Trim()
                    $currentKey = $key

                    if ($val -match '^\[(.*)\]$') {
                        $items = $matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"', "'") } | Where-Object { $_ -ne "" }
                        $yamlDict[$key] = @($items)
                    } elseif (-not [string]::IsNullOrWhiteSpace($val)) {
                        $val = $val.Trim('"', "'")
                        $yamlDict[$key] = $val
                    }
                }
            }
        } catch {
            Write-Warning "YAML parsing failed for $RelPath : $_"
        }
    }

    # Title
    $title = ""
    if ($yamlDict.ContainsKey("title") -and -not [string]::IsNullOrWhiteSpace($yamlDict["title"])) {
        $title = $yamlDict["title"]
    } else {
        if ($bodyText -match '(?m)^\s*#\s+(.+)$') {
            $title = $matches[1].Trim()
        } elseif ($File) {
            $title = $File.BaseName
        } else {
            $title = "Untitled"
        }
    }

    # Description
    $description = ""
    if ($yamlDict.ContainsKey("description") -and -not [string]::IsNullOrWhiteSpace($yamlDict["description"])) {
        $description = $yamlDict["description"]
    } else {
        $cleanBody = $bodyText -replace '(?m)^\s*#+\s*', '' -replace '[\*\`\[\]\(\)]', '' -replace '\s+', ' '
        $cleanBody = $cleanBody.Trim()
        if ($cleanBody.Length -gt 150) {
            $description = $cleanBody.Substring(0, 150) + "..."
        } else {
            $description = $cleanBody
        }
    }

    # Author
    $author = ""
    if ($yamlDict.ContainsKey("author") -and -not [string]::IsNullOrWhiteSpace($yamlDict["author"])) {
        $author = $yamlDict["author"]
    }

    # Domain
    $domain = ""
    if ($yamlDict.ContainsKey("domain") -and -not [string]::IsNullOrWhiteSpace($yamlDict["domain"])) {
        $domain = $yamlDict["domain"]
    } else {
        if (-not [string]::IsNullOrWhiteSpace($RelPath)) {
            $dir = [System.IO.Path]::GetDirectoryName($RelPath)
            $domain = if ([string]::IsNullOrWhiteSpace($dir)) { "root" } else { $dir.Replace('\', '/') }
        } else {
            $domain = "root"
        }
    }

    # Tags
    $tags = @()
    if ($yamlDict.ContainsKey("tags")) {
        if ($yamlDict["tags"] -is [System.Collections.IEnumerable] -and $yamlDict["tags"] -isnot [string]) {
            $tags = @($yamlDict["tags"])
        } elseif (-not [string]::IsNullOrWhiteSpace($yamlDict["tags"])) {
            $rawStr = $yamlDict["tags"].ToString()
            $tags = @($rawStr -split ',\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    }

    # LastUpdated
    $lastUpdated = if ($File) { $File.LastWriteTime } else { Get-Date }
    if ($yamlDict.ContainsKey("last_updated") -and -not [string]::IsNullOrWhiteSpace($yamlDict["last_updated"])) {
        $parsedDate = [DateTime]::MinValue
        if ([DateTime]::TryParse($yamlDict["last_updated"], [ref]$parsedDate)) {
            $lastUpdated = $parsedDate
        }
    }

    # Status (active, draft, deprecated)
    $status = "active"
    if ($yamlDict.ContainsKey("status") -and -not [string]::IsNullOrWhiteSpace($yamlDict["status"])) {
        $st = $yamlDict["status"].ToString().ToLower().Trim()
        if ($st -in @("active", "draft", "deprecated")) {
            $status = $st
        }
    }

    return [PSCustomObject]@{
        Title       = $title
        Description = $description
        Author      = $author
        Domain      = $domain
        Tags        = $tags
        LastUpdated = $lastUpdated
        Status      = $status
        HasYaml     = $hasYaml
        RelPath     = $RelPath
        FullPath    = if ($File) { $File.FullName } else { "" }
        BodyText    = $bodyText
    }
}

# --- 全件インデックス構築 & キャッシュ機能 ---
$script:WikiIndex = @()
$script:WikiIndexLastScan = [DateTime]::MinValue
$script:WikiIndexDirWriteTime = [DateTime]::MinValue

function Build-WikiIndex {
    param (
        [string]$TargetWikiDir = $wikiDir,
        [switch]$ForceRefresh
    )

    if (-not (Test-Path $TargetWikiDir)) { return @() }

    $currentWriteTime = (Get-Item $TargetWikiDir).LastWriteTime
    if (-not $ForceRefresh -and $script:WikiIndex.Count -gt 0 -and $script:WikiIndexDirWriteTime -eq $currentWriteTime) {
        return $script:WikiIndex
    }

    $mdFiles = Get-ChildItem -Path $TargetWikiDir -Recurse -Filter "*.md" |
        Where-Object { $_.FullName -notmatch '[\\/]\.(git|lib|tests|dist)[\\/]' } |
        Sort-Object FullName

    $indexList = [System.Collections.Generic.List[PSObject]]::new()
    foreach ($file in $mdFiles) {
        $relPath = $file.FullName.Substring($TargetWikiDir.Length).TrimStart("\", "/")
        $meta    = Get-DocumentMetadata -File $file -RelPath $relPath
        $indexList.Add($meta)
    }

    $script:WikiIndex = $indexList.ToArray()
    $script:WikiIndexDirWriteTime = $currentWriteTime
    $script:WikiIndexLastScan = Get-Date

    return $script:WikiIndex
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

    foreach ($file in $node.Files) {
        $relPath   = $file.FullName.Substring($wikiDir.Length).TrimStart("\", "/")
        $cleanPath = $relPath -replace "\\", "/"
        $webPath   = "/" + [Uri]::EscapeUriString($cleanPath)
        $title     = [System.Net.WebUtility]::HtmlEncode($file.BaseName)

        $activeClass = if ($relPath -eq $currentRelPath) { ' class="active"' } else { '' }
        $html += "  <li class='nav-file'><a href='$webPath'$activeClass>$title</a></li>`n"
    }

    foreach ($folderName in $node.SubFolders.Keys) {
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

function Get-SidebarHtml {
    param ($currentRelPath)
    
    $mdFiles = Get-ChildItem -Path $wikiDir -Recurse -Filter "*.md" | 
        Where-Object { $_.FullName -notmatch '[\\/]\.(git|lib|tests|dist)[\\/]' } |
        Sort-Object FullName

    $treeNode = Build-ServerFileTreeNode -allMdFiles $mdFiles -wikiDir $wikiDir
    return Render-ServerFolderTreeHtml -node $treeNode -currentRelPath $currentRelPath -wikiDir $wikiDir
}

# --- OKF トップバー ＆ フッターカード レンダリング関数 ---
function Get-OkfTopBarHtml {
    param ([Parameter(Mandatory = $true)]$Meta)

    $domain      = [System.Net.WebUtility]::HtmlEncode($Meta.Domain)
    $statusBadge = switch ($Meta.Status) {
        "draft"      { '<span class="badge badge-draft">📝 Draft</span>' }
        "deprecated" { '<span class="badge badge-deprecated">🗑️ Deprecated</span>' }
        default      { '<span class="badge badge-active">✅ Active</span>' }
    }

    $tagsHtml = ""
    if ($Meta.Tags -and $Meta.Tags.Count -gt 0) {
        $tagBadges = foreach ($t in $Meta.Tags) {
            $encTag = [System.Net.WebUtility]::HtmlEncode($t)
            $urlTag = [Uri]::EscapeDataString($t)
            "<a href='/tags?tag=$urlTag' class='tag-badge'>🏷️ $encTag</a>"
        }
        $tagsHtml = "<div class='okf-tags'>" + ($tagBadges -join " ") + "</div>"
    }

    $warningBanner = if ($Meta.Status -eq "deprecated") {
        '<div class="warning-banner">⚠️ <strong>警告: 非推奨ドキュメント</strong><br>このドキュメントは非推奨または旧版です。最新の情報を参照してください。</div>'
    } else { "" }

    return @"
$warningBanner
<div class="okf-top-bar">
    <div class="okf-top-left">
        <span class="okf-domain">📁 $domain</span>
        $statusBadge
    </div>
    $tagsHtml
</div>
"@
}

function Get-OkfFooterCardHtml {
    param ([Parameter(Mandatory = $true)]$Meta)

    $desc    = [System.Net.WebUtility]::HtmlEncode($Meta.Description)
    $author  = [System.Net.WebUtility]::HtmlEncode($Meta.Author)
    $lastUpd = $Meta.LastUpdated.ToString("yyyy-MM-dd")

    $tagsHtml = ""
    if ($Meta.Tags -and $Meta.Tags.Count -gt 0) {
        $tagBadges = foreach ($t in $Meta.Tags) {
            $encTag = [System.Net.WebUtility]::HtmlEncode($t)
            $urlTag = [Uri]::EscapeDataString($t)
            "<a href='/tags?tag=$urlTag' class='tag-badge'>🏷️ $encTag</a>"
        }
        $tagsHtml = "<div class='okf-tags'>" + ($tagBadges -join " ") + "</div>"
    }

    $authorHtml = if (-not [string]::IsNullOrWhiteSpace($author)) {
        $urlAuthor = [Uri]::EscapeDataString($Meta.Author)
        "<span class='okf-author'>👤 著者: <a href='/authors?name=$urlAuthor'>$author</a></span>"
    } else { "" }

    $descHtml = if (-not [string]::IsNullOrWhiteSpace($desc)) {
        "<p class='okf-desc'>$desc</p>"
    } else { "" }

    return @"
<footer class="okf-footer-card">
    <div class="okf-footer-header">
        <span class="okf-footer-title">ℹ️ ドキュメント メタデータ (OKF)</span>
        <a href="/api/index.json" target="_blank" class="okf-api-link">🤖 API (JSON)</a>
    </div>
    $descHtml
    <div class="okf-footer-meta">
        $authorHtml
        <span>📅 最終更新: $lastUpd</span>
    </div>
    $tagsHtml
</footer>
"@
}

# 互換用別名関数
function Get-OkfCardHtml {
    param ([Parameter(Mandatory = $true)]$Meta)
    return (Get-OkfTopBarHtml -Meta $Meta) + (Get-OkfFooterCardHtml -Meta $Meta)
}

# --- 機械可読 API JSON 生成関数 (AI エージェント / LLM 用) ---
function Get-ApiIndexJson {
    Build-WikiIndex -TargetWikiDir $wikiDir | Out-Null
    $exportItems = foreach ($item in $script:WikiIndex) {
        [PSCustomObject]@{
            Title       = $item.Title
            Description = $item.Description
            Author      = $item.Author
            Domain      = $item.Domain
            Tags        = $item.Tags
            LastUpdated = $item.LastUpdated.ToString("yyyy-MM-ddTHH:mm:ssZ")
            Status      = $item.Status
            HasYaml     = $item.HasYaml
            RelPath     = $item.RelPath
        }
    }
    return ($exportItems | ConvertTo-Json -Depth 3)
}

# --- RAG / LLM 用セマンティックチャンク JSON 生成関数 (/api/chunks.json) ---
function Get-ApiChunksJson {
    Build-WikiIndex -TargetWikiDir $wikiDir | Out-Null

    $allChunks = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($item in $script:WikiIndex) {
        $body = $item.BodyText
        if ([string]::IsNullOrWhiteSpace($body)) { continue }

        $lines = $body -split '\r?\n'
        $currentSection = $item.Title
        $currentContentLines = [System.Collections.Generic.List[string]]::new()
        $chunkIndex = 0

        foreach ($line in $lines) {
            if ($line -match '^\s*#{1,3}\s+(.+)$') {
                if ($currentContentLines.Count -gt 0) {
                    $contentText = ($currentContentLines -join "`n").Trim()
                    if (-not [string]::IsNullOrWhiteSpace($contentText)) {
                        $chunkIndex++
                        $tagStr = if ($item.Tags) { $item.Tags -join ", " } else { "" }
                        $enriched = "[Document: $($item.Title) | Domain: $($item.Domain) | Section: $currentSection | Tags: $tagStr]`n`n$contentText"
                        
                        [void]$allChunks.Add([PSCustomObject]@{
                            ChunkId      = "$($item.RelPath)#chunk-$chunkIndex"
                            RelPath      = $item.RelPath
                            Title        = $item.Title
                            Domain       = $item.Domain
                            Section      = $currentSection
                            Tags         = $item.Tags
                            LastUpdated  = $item.LastUpdated.ToString("yyyy-MM-ddTHH:mm:ssZ")
                            Status       = $item.Status
                            Content      = $contentText
                            EnrichedText = $enriched
                        })
                    }
                    $currentContentLines.Clear()
                }
                $currentSection = $matches[1].Trim()
            } else {
                [void]$currentContentLines.Add($line)
            }
        }

        if ($currentContentLines.Count -gt 0) {
            $contentText = ($currentContentLines -join "`n").Trim()
            if (-not [string]::IsNullOrWhiteSpace($contentText)) {
                $chunkIndex++
                $tagStr = if ($item.Tags) { $item.Tags -join ", " } else { "" }
                $enriched = "[Document: $($item.Title) | Domain: $($item.Domain) | Section: $currentSection | Tags: $tagStr]`n`n$contentText"

                [void]$allChunks.Add([PSCustomObject]@{
                    ChunkId      = "$($item.RelPath)#chunk-$chunkIndex"
                    RelPath      = $item.RelPath
                    Title        = $item.Title
                    Domain       = $item.Domain
                    Section      = $currentSection
                    Tags         = $item.Tags
                    LastUpdated  = $item.LastUpdated.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    Status       = $item.Status
                    Content      = $contentText
                    EnrichedText = $enriched
                })
            }
        }
    }

    return ($allChunks | ConvertTo-Json -Depth 4)
}

# --- 最近の更新一覧ビュー生成関数 ---
function Get-RecentViewHtml {
    Build-WikiIndex -TargetWikiDir $wikiDir | Out-Null
    $sorted = $script:WikiIndex | Sort-Object LastUpdated -Descending

    $rowsHtml = foreach ($item in $sorted) {
        $relUri   = "/" + [Uri]::EscapeUriString($item.RelPath.Replace('\', '/'))
        $title    = [System.Net.WebUtility]::HtmlEncode($item.Title)
        $domain   = [System.Net.WebUtility]::HtmlEncode($item.Domain)
        $author   = [System.Net.WebUtility]::HtmlEncode($item.Author)
        $lastUpd  = $item.LastUpdated.ToString("yyyy-MM-dd")
        $status   = [System.Net.WebUtility]::HtmlEncode($item.Status)
        "<tr><td>$lastUpd</td><td><a href='$relUri'>$title</a></td><td>$domain</td><td>$author</td><td><span class='badge badge-$status'>$status</span></td></tr>"
    }

    return @"
<h1>🕒 最近の更新ドキュメント</h1>
<p>Wiki内の全ドキュメントを更新日順に表示しています。</p>
<table class="okf-table">
    <thead>
        <tr><th>最終更新日</th><th>タイトル</th><th>ドメイン</th><th>著者</th><th>状態</th></tr>
    </thead>
    <tbody>
        $($rowsHtml -join "`n")
    </tbody>
</table>
"@
}

# --- タグ目録 & 絞り込みビュー生成関数 ---
function Get-TagsViewHtml {
    param ([string]$SelectedTag = "")

    Build-WikiIndex -TargetWikiDir $wikiDir | Out-Null

    if ([string]::IsNullOrWhiteSpace($SelectedTag)) {
        $tagCounts = @{}
        foreach ($item in $script:WikiIndex) {
            foreach ($t in $item.Tags) {
                if (-not [string]::IsNullOrWhiteSpace($t)) {
                    if ($tagCounts.ContainsKey($t)) { $tagCounts[$t]++ } else { $tagCounts[$t] = 1 }
                }
            }
        }

        $cloudHtml = foreach ($t in ($tagCounts.Keys | Sort-Object)) {
            $encTag = [System.Net.WebUtility]::HtmlEncode($t)
            $urlTag = [Uri]::EscapeDataString($t)
            $count  = $tagCounts[$t]
            "<a href='/tags?tag=$urlTag' class='tag-cloud-item'>🏷️ $encTag <span class='tag-count'>($count)</span></a>"
        }

        return @"
<h1>🏷️ タグ一覧</h1>
<div class="tag-cloud">
    $($cloudHtml -join " ")
</div>
"@
    } else {
        $filtered = @($script:WikiIndex | Where-Object { $_.Tags -contains $SelectedTag })
        $encTag   = [System.Net.WebUtility]::HtmlEncode($SelectedTag)

        $cardsHtml = foreach ($item in $filtered) {
            $relUri = "/" + [Uri]::EscapeUriString($item.RelPath.Replace('\', '/'))
            $title  = [System.Net.WebUtility]::HtmlEncode($item.Title)
            $desc   = [System.Net.WebUtility]::HtmlEncode($item.Description)
            "<div class='search-item'><h3><a href='$relUri'>$title</a></h3><p>$desc</p></div>"
        }

        return @"
<h1>🏷️ タグ: $encTag</h1>
<p><a href="/tags">← 全タグ一覧へ戻る</a></p>
<div class="tag-results">
    $($cardsHtml -join "`n")
</div>
"@
    }
}

# --- 品質・メンテナンスダッシュボード生成関数 ---
function Get-MaintenanceViewHtml {
    Build-WikiIndex -TargetWikiDir $wikiDir | Out-Null
    $now = Get-Date

    $staleDocs      = @($script:WikiIndex | Where-Object { $_.Status -eq "active" -and ($now - $_.LastUpdated).TotalDays -ge 365 })
    $draftDocs      = @($script:WikiIndex | Where-Object { $_.Status -eq "draft" })
    $deprecatedDocs = @($script:WikiIndex | Where-Object { $_.Status -eq "deprecated" })

    function Render-DocList ($docArray) {
        $arr = @($docArray)
        if ($arr.Count -eq 0) { return "<p class='empty-msg'>該当ドキュメントはありません。</p>" }
        $items = foreach ($item in $arr) {
            $relUri  = "/" + [Uri]::EscapeUriString($item.RelPath.Replace('\', '/'))
            $title   = [System.Net.WebUtility]::HtmlEncode($item.Title)
            $lastUpd = $item.LastUpdated.ToString("yyyy-MM-dd")
            "<li><a href='$relUri'>$title</a> <span class='muted'>($lastUpd)</span></li>"
        }
        return "<ul>" + ($items -join "") + "</ul>"
    }

    return @"
<h1>🧹 品質・メンテナンスダッシュボード</h1>
<p>ドキュメントの風化を防ぎ、ナレッジの信頼性を維持するための管理画面です。</p>

<div class="maint-section warning-box">
    <h2>⚠️ 更新停滞ドキュメント (最終更新から365日以上経過)</h2>
    $(Render-DocList $staleDocs)
</div>

<div class="maint-section info-box">
    <h2>📝 下書き一覧 (status: draft)</h2>
    $(Render-DocList $draftDocs)
</div>

<div class="maint-section danger-box">
    <h2>🗑️ 非推奨・旧版一覧 (status: deprecated)</h2>
    $(Render-DocList $deprecatedDocs)
</div>
"@
}

# --- 著者一覧ビュー生成関数 ---
function Get-AuthorsViewHtml {
    param ([string]$SelectedAuthor = "")

    Build-WikiIndex -TargetWikiDir $wikiDir | Out-Null

    if ([string]::IsNullOrWhiteSpace($SelectedAuthor)) {
        $authors = @($script:WikiIndex | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Author) } | Group-Object Author)

        $listHtml = foreach ($g in ($authors | Sort-Object Name)) {
            $encAuthor = [System.Net.WebUtility]::HtmlEncode($g.Name)
            $urlAuthor = [Uri]::EscapeDataString($g.Name)
            $count     = $g.Count
            "<li><a href='/authors?name=$urlAuthor'>👤 $encAuthor</a> <span class='muted'>($count 件)</span></li>"
        }

        return @"
<h1>👥 著者一覧</h1>
<ul>
    $($listHtml -join "`n")
</ul>
"@
    } else {
        $filtered  = @($script:WikiIndex | Where-Object { $_.Author -eq $SelectedAuthor })
        $encAuthor = [System.Net.WebUtility]::HtmlEncode($SelectedAuthor)

        $itemsHtml = foreach ($item in $filtered) {
            $relUri = "/" + [Uri]::EscapeUriString($item.RelPath.Replace('\', '/'))
            $title  = [System.Net.WebUtility]::HtmlEncode($item.Title)
            "<li><a href='$relUri'>$title</a></li>"
        }

        return @"
<h1>👥 著者: $encAuthor</h1>
<p><a href="/authors">← 全著者一覧へ戻る</a></p>
<ul>
    $($itemsHtml -join "`n")
</ul>
"@
    }
}

# --- キーワードハイライト処理関数 ---
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
        Build-WikiIndex -TargetWikiDir $targetDir | Out-Null
    }

    if ([string]::IsNullOrWhiteSpace($StatusFilter)) { $StatusFilter = "active" }
    $stFilterLower = $StatusFilter.ToLower().Trim()

    $keywords = if (-not [string]::IsNullOrWhiteSpace($Query)) {
        @($Query -split '\s+' | Where-Object { $_ -ne "" })
    } else { @() }

    $results = [System.Collections.Generic.List[PSObject]]::new()

    foreach ($item in $script:WikiIndex) {
        # 1. Status Filter
        $st = if ($item.Status) { $item.Status.ToString().ToLower().Trim() } else { "active" }
        if ($stFilterLower -ne "all" -and $stFilterLower -ne "" -and $st -ne $stFilterLower) {
            continue
        }

        # 2. Domain Filter
        if (-not [string]::IsNullOrWhiteSpace($DomainFilter)) {
            $itemDomain = if ($item.Domain) { $item.Domain } else { "" }
            if ($itemDomain -notlike "*$DomainFilter*") { continue }
        }

        if ($keywords.Count -eq 0 -and [string]::IsNullOrWhiteSpace($DomainFilter) -and $stFilterLower -eq "all") {
            continue
        }

        # 3. 重み付けスコアリング & AND 判定
        $score = 0
        $matchedKwCount = 0

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

        # AND条件検証
        if ($keywords.Count -gt 0 -and $matchedKwCount -lt $keywords.Count) {
            continue
        }

        # 非推奨 (deprecated) 70% スコア減点
        if ($st -eq "deprecated") {
            $score = [Math]::Floor($score * 0.3)
        }

        if ($score -gt 0 -or ($keywords.Count -eq 0 -and (-not [string]::IsNullOrWhiteSpace($DomainFilter) -or $stFilterLower -ne "all"))) {
            # スニペット抽出
            $snippet = ""
            if ($item.BodyText) {
                $lines = $item.BodyText -split "\r?\n"
                foreach ($line in $lines) {
                    if ($line -match '^\s*---') { continue }
                    $hasMatch = $false
                    if ($keywords.Count -gt 0) {
                        foreach ($kw in $keywords) {
                            if ($line -match [regex]::Escape($kw)) {
                                $hasMatch = $true
                                break
                            }
                        }
                    } else {
                        if (-not [string]::IsNullOrWhiteSpace($line)) { $hasMatch = $true }
                    }
                    if ($hasMatch) {
                        $snippet = $line.Trim()
                        break
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
function Invoke-ToolSearchOkf {
    param (
        [string]$Query = "",
        [string]$Domain = "",
        [string]$WikiDir = ""
    )
    $targetDir = if (-not [string]::IsNullOrWhiteSpace($WikiDir)) { $WikiDir } else { $script:wikiDir }
    if ([string]::IsNullOrWhiteSpace($targetDir)) { $targetDir = $scriptDir }

    $res = Search-OkfDocs -Query $Query -DomainFilter $Domain -StatusFilter "active" -WikiDir $targetDir -MaxResults 3

    # 1. ドメイン絞り込みで0件だった場合、全ドメインでフォールバック検索
    if ($res.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($Domain)) {
        $res = Search-OkfDocs -Query $Query -DomainFilter "" -StatusFilter "active" -WikiDir $targetDir -MaxResults 3
    }

    # 2. クエリ全体で0件だった場合、日本語形態素単語分割でフォールバック検索
    if ($res.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($Query)) {
        $kwList = Get-JapaneseWordsWinRT -Text $Query
        if ($kwList -and $kwList.Count -gt 0) {
            $subQuery = $kwList -join " "
            if ($subQuery -ne $Query) {
                $res = Search-OkfDocs -Query $subQuery -DomainFilter "" -StatusFilter "active" -WikiDir $targetDir -MaxResults 3
            }
        }
    }

    if ($res.Count -eq 0) {
        return "検索結果は見つかりませんでした。domain を空文字 '' に指定して全Wiki検索を試すか、別のキーワードを指定してください。"
    }
    $sb = [System.Text.StringBuilder]::new()
    foreach ($r in $res) {
        $meta = $r.Meta
        [void]$sb.AppendLine("---")
        [void]$sb.AppendLine("■ タイトル: $($meta.Title) (Path: $($meta.RelPath))")
        [void]$sb.AppendLine("・ドメイン: $($meta.Domain) | 著者: $($meta.Author) | 更新: $($meta.LastUpdated.ToString('yyyy-MM-dd'))")
        [void]$sb.AppendLine("・概要: $($meta.Description)")
        [void]$sb.AppendLine("・スニペット: $($r.Snippet)")
    }
    return $sb.ToString()
}

function Invoke-ToolReadDoc {
    param (
        [string]$RelPath = "",
        [string]$WikiDir = "",
        [int]$MaxChars = 2000
    )
    if ([string]::IsNullOrWhiteSpace($RelPath)) { return "エラー: RelPath が指定されていません。" }

    $targetDir = if (-not [string]::IsNullOrWhiteSpace($WikiDir)) { $WikiDir } else { $script:wikiDir }
    if ([string]::IsNullOrWhiteSpace($targetDir)) { $targetDir = $scriptDir }

    $cleanRel = $RelPath.TrimStart('\', '/').Replace('/', '\')
    $full = Join-Path $targetDir $cleanRel

    if (-not (Test-Path $full)) {
        Build-WikiIndex -TargetWikiDir $targetDir | Out-Null
        $found = $script:WikiIndex | Where-Object { $_.RelPath -eq $cleanRel -or $_.RelPath -like "*$cleanRel*" } | Select-Object -First 1
        if ($found) {
            $full = Join-Path $targetDir $found.RelPath
            $cleanRel = $found.RelPath
        } else {
            return "エラー: ドキュメント 『$RelPath』 が見つかりません。"
        }
    }

    $fileObj = Get-Item $full
    $meta = Get-DocumentMetadata -File $fileObj -RelPath $cleanRel
    if ($meta.Status -eq "deprecated") {
        return "⚠️ 警告: ドキュメント 『$cleanRel』 は非推奨 (deprecated) です。現行Active情報ではありません。"
    }

    $body = $meta.BodyText
    if ([string]::IsNullOrWhiteSpace($body)) { return "ドキュメント本文は空です。" }

    if ($MaxChars -gt 0 -and $body.Length -gt $MaxChars) {
        $body = $body.Substring(0, $MaxChars) + "`n...[文字数制限により以降省略 (最大 $MaxChars 文字)]"
    }

    return "■ ドキュメント: $($meta.Title) ($cleanRel)`n$body"
}

function Invoke-ToolLookupGlossary {
    param (
        [string]$Term = "",
        [string]$WikiDir = ""
    )
    if ([string]::IsNullOrWhiteSpace($Term)) { return "エラー: Term が指定されていません。" }

    $targetDir = if (-not [string]::IsNullOrWhiteSpace($WikiDir)) { $WikiDir } else { $script:wikiDir }
    if ([string]::IsNullOrWhiteSpace($targetDir)) { $targetDir = $scriptDir }

    Build-WikiIndex -TargetWikiDir $targetDir | Out-Null

    $glossaryDoc = $script:WikiIndex | Where-Object { $_.RelPath -like "*glossary.md*" -or $_.Title -like "*用語*" } | Select-Object -First 1
    if ($glossaryDoc -and $glossaryDoc.BodyText) {
        $lines = $glossaryDoc.BodyText -split "\r?\n"
        $termRegex = [regex]::Escape($Term)
        $matchedBlock = [System.Collections.Generic.List[string]]::new()
        $recording = $false

        foreach ($line in $lines) {
            if ($line -match "(?i)^\s*#{1,4}\s+.*$termRegex" -or $line -match "(?i)^\s*[\*\-]\s+.*$termRegex") {
                $recording = $true
            } elseif ($recording -and $line -match "^\s*#{1,3}\s+") {
                break
            }
            if ($recording) {
                $matchedBlock.Add($line)
            }
        }

        if ($matchedBlock.Count -gt 0) {
            return "📖 用語集 ($($glossaryDoc.RelPath)) より抽出:`n" + ($matchedBlock -join "`n")
        }
    }

    $results = Search-OkfDocs -Query $Term -StatusFilter "active" -WikiDir $targetDir -MaxResults 2
    if ($results.Count -gt 0) {
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine("📖 用語 『$Term』 に関連するドキュメント記述:")
        foreach ($r in $results) {
            [void]$sb.AppendLine("・$($r.Meta.Title) ($($r.Meta.RelPath)): $($r.Snippet)")
        }
        return $sb.ToString()
    }

    return "用語 『$Term』 の定義は Wiki 内で見つかりませんでした。"
}

function Invoke-ToolGetLinkedDocs {
    param (
        [string]$RelPath = "",
        [string]$WikiDir = ""
    )
    if ([string]::IsNullOrWhiteSpace($RelPath)) { return @() }

    $targetDir = if (-not [string]::IsNullOrWhiteSpace($WikiDir)) { $WikiDir } else { $script:wikiDir }
    if ([string]::IsNullOrWhiteSpace($targetDir)) { $targetDir = $scriptDir }

    $cleanRel = $RelPath.TrimStart('\', '/').Replace('/', '\')
    $full = Join-Path $targetDir $cleanRel
    if (-not (Test-Path $full)) {
        return @()
    }

    $mdText = Get-Content -Path $full -Raw -Encoding UTF8
    $matches = [regex]::Matches($mdText, '\[([^\]]+)\]\(([^)]+\.md)(?:#[^)]*)?\)')

    if ($matches.Count -eq 0) {
        return @()
    }

    $linkedItems = [System.Collections.Generic.List[PSCustomObject]]::new()
    $baseDir = [System.IO.Path]::GetDirectoryName($cleanRel)

    foreach ($m in $matches) {
        $linkText = $m.Groups[1].Value
        $linkTarget = $m.Groups[2].Value

        $resolvedRel = if ([string]::IsNullOrWhiteSpace($baseDir)) { $linkTarget } else { Join-Path $baseDir $linkTarget }
        $resolvedRel = $resolvedRel.Replace('/', '\')

        $targetFull = Join-Path $targetDir $resolvedRel
        $status = "not_found"
        $title = $linkText

        if (Test-Path $targetFull) {
            $meta = Get-DocumentMetadata -File (Get-Item $targetFull) -RelPath $resolvedRel
            $status = $meta.Status
            $title = $meta.Title
        }

        $linkedItems.Add([PSCustomObject]@{
            LinkText = $linkText
            RelPath  = $resolvedRel
            Title    = $title
            Status   = $status
        })
    }

    return $linkedItems
}

# --- 検索結果ビュー生成関数 (OKF 文脈検索エンジン) ---
function Get-SearchViewHtml {
    param (
        [string]$Query = "",
        [string]$StatusFilter = "active",
        [string]$DomainFilter = ""
    )

    if ([string]::IsNullOrWhiteSpace($StatusFilter)) { $StatusFilter = "active" }
    $stFilterLower = $StatusFilter.ToLower().Trim()

    $keywords = if (-not [string]::IsNullOrWhiteSpace($Query)) {
        @($Query -split '\s+' | Where-Object { $_ -ne "" })
    } else { @() }

    $results = Search-OkfDocs -Query $Query -StatusFilter $StatusFilter -DomainFilter $DomainFilter

    # スコア降順ソート
    $sortedResults = @($results | Sort-Object -Property Score, LastUpdated -Descending)

    $encQuery   = [System.Net.WebUtility]::HtmlEncode($Query)
    $encDomain  = [System.Net.WebUtility]::HtmlEncode($DomainFilter)

    $optActive     = if ($stFilterLower -eq "active")     { "selected" } else { "" }
    $optDraft      = if ($stFilterLower -eq "draft")      { "selected" } else { "" }
    $optDeprecated = if ($stFilterLower -eq "deprecated") { "selected" } else { "" }
    $optAll        = if ($stFilterLower -eq "all")        { "selected" } else { "" }

    $resultsHtmlList = foreach ($r in $sortedResults) {
        $item   = $r.Meta
        $relUri = "/" + [Uri]::EscapeUriString($item.RelPath.Replace('\', '/'))

        $titleHtml = Get-HighlightText -Text $item.Title -Keywords $keywords
        $descHtml  = Get-HighlightText -Text $item.Description -Keywords $keywords
        $snipHtml  = Get-HighlightText -Text $r.Snippet -Keywords $keywords

        $domainEnc = [System.Net.WebUtility]::HtmlEncode($item.Domain)
        $authorEnc = [System.Net.WebUtility]::HtmlEncode($item.Author)
        $lastUpd   = $item.LastUpdated.ToString("yyyy-MM-dd")

        $statusBadge = switch ($item.Status) {
            "draft"      { '<span class="badge badge-draft">📝 Draft</span>' }
            "deprecated" { '<span class="badge badge-deprecated">🗑️ Deprecated</span>' }
            default      { '<span class="badge badge-active">✅ Active</span>' }
        }

        $tagsHtml = ""
        if ($item.Tags -and $item.Tags.Count -gt 0) {
            $badges = foreach ($t in $item.Tags) {
                $encT = [System.Net.WebUtility]::HtmlEncode($t)
                "<span class='tag-badge'>🏷️ $encT</span>"
            }
            $tagsHtml = "<div class='okf-tags' style='margin-top:4px;'>" + ($badges -join " ") + "</div>"
        }

        $scoreHtml = if ($r.Score -gt 0) { "<span style='font-size:12px; color:#6a737d; margin-left:10px;'>(関連度スコア: $($r.Score))</span>" } else { "" }

        @"
<div class="search-item" style="border-bottom: 1px solid #e1e4e8; padding: 14px 0;">
    <h3 style="margin: 0 0 6px 0; font-size: 16px;">
        <a href="$relUri">$titleHtml</a> $statusBadge $scoreHtml
    </h3>
    <div style="font-size: 12px; color: #586069; margin-bottom: 6px;">
        📁 ドメイン: $domainEnc | 📅 最終更新: $lastUpd | 👤 著者: $authorEnc
    </div>
    $tagsHtml
    <p style="margin: 8px 0 0 0; font-size: 13px; color: #444; background: #f8f9fa; padding: 6px 10px; border-left: 3px solid #0366d6; border-radius: 2px;">
        ... $snipHtml ...
    </p>
</div>
"@
    }

    $resultsContent = if ($sortedResults.Count -gt 0) {
        $resultsHtmlList -join "`n"
    } else {
        "<p style='color: #666; margin-top: 20px;'>該当するドキュメントが見つかりませんでした。</p>"
    }

    return @"
<h1>🔍 OKF ナレッジ検索結果 ($($sortedResults.Count) 件)</h1>
<div style="background: #f6f8fa; padding: 16px; border: 1px solid #e1e4e8; border-radius: 6px; margin-bottom: 20px;">
    <form action="/search" method="GET" accept-charset="UTF-8" style="display: flex; flex-wrap: wrap; gap: 10px; align-items: center;">
        <div style="flex: 1; min-width: 200px;">
            <input type="text" name="q" value="$encQuery" placeholder="キーワード (例: PostgreSQL 障害)" style="width: 100%; padding: 6px 10px; font-size: 14px; border: 1px solid #ccc; border-radius: 4px;">
        </div>
        <div>
            <label style="font-size: 12px; font-weight: bold; color: #586069;">ステータス:</label>
            <select name="status" style="padding: 6px 10px; font-size: 13px; border: 1px solid #ccc; border-radius: 4px;">
                <option value="active" $optActive>現行 (Active)</option>
                <option value="draft" $optDraft>下書き (Draft)</option>
                <option value="deprecated" $optDeprecated>非推奨 (Deprecated)</option>
                <option value="all" $optAll>すべて (All)</option>
            </select>
        </div>
        <div>
            <label style="font-size: 12px; font-weight: bold; color: #586069;">ドメイン:</label>
            <input type="text" name="domain" value="$encDomain" placeholder="例: infrastructure" style="padding: 6px 10px; font-size: 13px; border: 1px solid #ccc; border-radius: 4px; width: 140px;">
        </div>
        <div>
            <button type="submit" style="padding: 6px 16px; font-size: 14px; background: #0366d6; color: #fff; border: none; border-radius: 4px; cursor: pointer;">🔍 検索</button>
        </div>
    </form>
</div>
<div class="search-results">
    $resultsContent
</div>
"@
}

function Get-OKFSearchResultsHtml {
    param (
        [string]$query = "",
        [string]$statusFilter = "active",
        [string]$domainFilter = ""
    )
    return Get-SearchViewHtml -Query $query -StatusFilter $statusFilter -DomainFilter $domainFilter
}

# --- UTF-8 URL クエリパラメータ解析関数 ---
function Get-QueryParams {
    param ([Parameter(Mandatory = $true)][System.Net.HttpListenerRequest]$Request)
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
    Add-Type -AssemblyName System.Security
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $enc   = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return "DPAPI:" + [System.Convert]::ToBase64String($enc)
}

function Unprotect-StringAes {
    param ([string]$EncryptedText)
    if ([string]::IsNullOrWhiteSpace($EncryptedText) -or -not $EncryptedText.StartsWith("ENC:")) { return "" }
    try {
        $cipherText = $EncryptedText.Substring(4)
        $cipherBytes = [System.Convert]::FromBase64String($cipherText)
        $salt = [System.Text.Encoding]::UTF8.GetBytes("SimpleWiki-OKF-RAG-2026-Salt")
        $pass = [System.Text.Encoding]::UTF8.GetBytes("SimpleWiki-Portable-Secret-Key-2026")
        $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($pass, $salt, 1000)
        $key = $derive.GetBytes(32)
        $iv  = $derive.GetBytes(16)

        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $key
        $aes.IV  = $iv
        $decryptor = $aes.CreateDecryptor()
        $decBytes = $decryptor.TransformFinalBlock($cipherBytes, 0, $cipherBytes.Length)
        return [System.Text.Encoding]::UTF8.GetString($decBytes)
    } catch {
        Write-Warning "AES 復号に失敗しました: $_"
        return ""
    }
}

function Unprotect-StringDpapi {
    param ([string]$EncryptedText)
    if ([string]::IsNullOrWhiteSpace($EncryptedText) -or -not $EncryptedText.StartsWith("DPAPI:")) { return "" }
    try {
        Add-Type -AssemblyName System.Security
        $cipherText = $EncryptedText.Substring(6)
        $bytes = [System.Convert]::FromBase64String($cipherText)
        $dec = [System.Security.Cryptography.ProtectedData]::Unprotect($bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [System.Text.Encoding]::UTF8.GetString($dec)
    } catch {
        Write-Warning "DPAPI 復号に失敗しました: $_"
        return ""
    }
}

# --- WinRT 日本語形態素解析 ＆ 単語抽出関数 ---
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

function Get-ResolvedSecret {
    param ([string]$SecretValue)
    if ([string]::IsNullOrWhiteSpace($SecretValue)) { return "" }
    if ($SecretValue.StartsWith("ENC:")) {
        return Unprotect-StringAes -EncryptedText $SecretValue
    } elseif ($SecretValue.StartsWith("DPAPI:")) {
        return Unprotect-StringDpapi -EncryptedText $SecretValue
    } elseif ($SecretValue.StartsWith("ENV:")) {
        $envName = $SecretValue.Substring(4).Trim()
        $envVal = [Environment]::GetEnvironmentVariable($envName)
        if ($envVal) { return $envVal } else { return "" }
    }
    return $SecretValue
}

function Get-ConfigJson {
    param ([string]$TargetScriptDir = $scriptDir)
    $configPath = Join-Path $TargetScriptDir "config.json"
    if (-not (Test-Path $configPath)) {
        return [PSCustomObject]@{
            rag = [PSCustomObject]@{
                enabled         = $false
                maxContextDocs  = 3
                maxHistoryTurns = 3
                maxHistoryChars = 4000
                timeoutSec      = 30
            }
        }
    }
    try {
        $raw = Get-Content -Path $configPath -Raw -Encoding UTF8
        return ($raw | ConvertFrom-Json)
    } catch {
        return [PSCustomObject]@{
            rag = [PSCustomObject]@{
                enabled         = $false
                maxContextDocs  = 3
                maxHistoryTurns = 3
                maxHistoryChars = 4000
                timeoutSec      = 30
            }
        }
    }
}

function Invoke-OpenAiChatCompletions {
    param (
        [string]$ApiUrl,
        [string]$ApiKey,
        [string]$Model,
        [string]$SystemPrompt,
        [string]$UserMessage,
        [array]$History = @(),
        [int]$TimeoutSec = 30
    )

    $resolvedKey = Get-ResolvedSecret -SecretValue $ApiKey
    $cleanApiUrl = $ApiUrl.TrimEnd('/')
    $endpointUrl = "$cleanApiUrl/chat/completions"
    if ($cleanApiUrl.EndsWith("/chat/completions")) {
        $endpointUrl = $cleanApiUrl
    }

    $msgList = [System.Collections.Generic.List[PSObject]]::new()
    $msgList.Add(@{ role = "system"; content = $SystemPrompt })

    if ($History -and $History.Count -gt 0) {
        foreach ($h in $History) {
            if ($h -and $h.role -and $h.content) {
                $msgList.Add(@{ role = $h.role.ToString(); content = $h.content.ToString() })
            }
        }
    }
    $msgList.Add(@{ role = "user"; content = $UserMessage })

    $payloadObj = @{
        model       = $Model
        temperature = 0.3
        messages    = $msgList
    }
    $jsonBody = $payloadObj | ConvertTo-Json -Depth 5
    $reqBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

    $webReq = [System.Net.HttpWebRequest]::Create($endpointUrl)
    $webReq.Method = "POST"
    $webReq.ContentType = "application/json; charset=utf-8"
    $webReq.Timeout = $TimeoutSec * 1000
    if (-not [string]::IsNullOrWhiteSpace($resolvedKey)) {
        $webReq.Headers["Authorization"] = "Bearer $resolvedKey"
    }

    try {
        $reqStream = $webReq.GetRequestStream()
        $reqStream.Write($reqBytes, 0, $reqBytes.Length)
        $reqStream.Close()

        $webRes = $webReq.GetResponse()
        try {
            $resStream = $webRes.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($resStream, [System.Text.Encoding]::UTF8)
            $resJson = $reader.ReadToEnd()
            $parsed = $resJson | ConvertFrom-Json
            if ($parsed -and $parsed.choices -and $parsed.choices.Count -gt 0) {
                return $parsed.choices[0].message.content
            }
            throw "LLM から無効なレスポンスが返却されました。"
        } finally {
            $webRes.Close()
        }
    } catch [System.Net.WebException] {
        if ($_.Response) {
            $errStream = $_.Response.GetResponseStream()
            $errReader = New-Object System.IO.StreamReader($errStream, [System.Text.Encoding]::UTF8)
            $errBody = $errReader.ReadToEnd()
            throw "API エラー ($($_.Response.StatusCode)): $errBody"
        }
        throw $_
    }
}

# --- Agentic RAG ReAct ループ実行関数 ---
function Invoke-AgenticRagChat {
    param (
        [string]$ApiUrl,
        [string]$ApiKey,
        [string]$Model,
        [string]$UserMessage,
        [array]$History = @(),
        [string]$WikiDir = "",
        [int]$MaxTurns = 5,
        [int]$MaxDocChars = 2000,
        [int]$TimeoutSec = 30
    )

    $targetDir = if (-not [string]::IsNullOrWhiteSpace($WikiDir)) { $WikiDir } else { $script:wikiDir }
    if ([string]::IsNullOrWhiteSpace($targetDir)) { $targetDir = $scriptDir }

    $thinkingLog = [System.Collections.Generic.List[string]]::new()
    $sourcesList = [System.Collections.Generic.List[PSObject]]::new()
    $visitedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $tools = @(
        @{
            type = "function"
            function = @{
                name = "search_okf"
                description = "OKFスコアリングによりWiki内のActiveドキュメントを検索します。"
                parameters = @{
                    type = "object"
                    properties = @{
                        query = @{ type = "string"; description = "検索キーワード (日本語キーワードをそのまま使用し、勝手に英語翻訳しないでください)" }
                        domain = @{ type = "string"; description = "絞り込みドメイン (原則は空文字列 '' を指定してWiki全域を検索してください)" }
                    }
                    required = @("query")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "lookup_glossary"
                description = "用語集 (glossary.md) またはWiki内の記述から特定用語の定義を調べます。"
                parameters = @{
                    type = "object"
                    properties = @{
                        term = @{ type = "string"; description = "調べたい社内用語" }
                    }
                    required = @("term")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "read_doc"
                description = "指定したドキュメントの本文を取得します (YAMLヘッダー除外)。"
                parameters = @{
                    type = "object"
                    properties = @{
                        relPath = @{ type = "string"; description = "Markdownファイルの相対パス (例: docs/infrastructure/db.md)" }
                    }
                    required = @("relPath")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "get_linked_docs"
                description = "指定ドキュメント内に含まれる他のMarkdownファイルへのハイパーリンク一覧を取得します。"
                parameters = @{
                    type = "object"
                    properties = @{
                        relPath = @{ type = "string"; description = "調査対象のMarkdownファイルパス" }
                    }
                    required = @("relPath")
                }
            }
        }
    )

    $sysPrompt = "あなたは社内Wikiのナレッジを自律調査して回答する Agentic RAG アシスタントです。`n" +
        "【探索ガイドライン】`n" +
        "1. 検索キーワード (query) はユーザーが入力した日本語単語（例: 'エラー', '想定されるエラー'）をそのまま使用し、勝手に英語へ翻訳しないでください。`n" +
        "2. search_okf の domain パラメータは原則として空文字列 '' を指定し、Wiki 全域からドキュメントを検索してください。`n" +
        "3. 必要に応じてツール (search_okf, lookup_glossary, read_doc, get_linked_docs) を呼び出し、情報を深掘りして正確な最終回答を作成してください。`n" +
        "4. 非推奨 (status: deprecated) の記述は避け、常に現行 (active) 情報のみを根拠にしてください。"

    $messages = [System.Collections.Generic.List[PSObject]]::new()
    [void]$messages.Add(@{ role = "system"; content = $sysPrompt })

    if ($History -and $History.Count -gt 0) {
        foreach ($h in $History) {
            if ($h -and $h.role -and $h.content) {
                [void]$messages.Add(@{ role = $h.role.ToString(); content = $h.content.ToString() })
            }
        }
    }
    [void]$messages.Add(@{ role = "user"; content = $UserMessage })

    $resolvedKey = Get-ResolvedSecret -SecretValue $ApiKey
    $cleanApiUrl = $ApiUrl.TrimEnd('/')
    $endpointUrl = "$cleanApiUrl/chat/completions"
    if ($cleanApiUrl.EndsWith("/chat/completions")) {
        $endpointUrl = $cleanApiUrl
    }

    $currentTurn = 0
    $finalAnswer = ""

    while ($currentTurn -lt $MaxTurns) {
        $currentTurn++

        $payloadObj = @{
            model       = $Model
            temperature = 0.2
            messages    = $messages
            tools       = $tools
        }

        $jsonBody = $payloadObj | ConvertTo-Json -Depth 6
        $reqBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

        $webReq = [System.Net.HttpWebRequest]::Create($endpointUrl)
        $webReq.Method = "POST"
        $webReq.ContentType = "application/json; charset=utf-8"
        $webReq.Timeout = $TimeoutSec * 1000
        if (-not [string]::IsNullOrWhiteSpace($resolvedKey)) {
            $webReq.Headers["Authorization"] = "Bearer $resolvedKey"
        }

        $resMsg = $null
        try {
            $reqStream = $webReq.GetRequestStream()
            $reqStream.Write($reqBytes, 0, $reqBytes.Length)
            $reqStream.Close()

            $webRes = $webReq.GetResponse()
            try {
                $resStream = $webRes.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($resStream, [System.Text.Encoding]::UTF8)
                $resJson = $reader.ReadToEnd()
                $parsed = $resJson | ConvertFrom-Json
                if ($parsed -and $parsed.choices -and $parsed.choices.Count -gt 0) {
                    $resMsg = $parsed.choices[0].message
                }
            } finally {
                $webRes.Close()
            }
        } catch {
            [void]$thinkingLog.Add("⚠️ LLM API Tool Calling 通信エラー。Fast モードへフォールバックします。")
            break
        }

        if (-not $resMsg) { break }

        $msgHashtable = @{ role = "assistant" }
        if ($resMsg.content) { $msgHashtable["content"] = $resMsg.content }
        if ($resMsg.tool_calls) { $msgHashtable["tool_calls"] = $resMsg.tool_calls }
        [void]$messages.Add($msgHashtable)

        if ($resMsg.tool_calls -and $resMsg.tool_calls.Count -gt 0) {
            foreach ($toolCall in $resMsg.tool_calls) {
                $callId = $toolCall.id
                $fnName = $toolCall.function.name
                $argsJson = $toolCall.function.arguments
                $argsObj = try { $argsJson | ConvertFrom-Json } catch { @{} }

                $toolResult = ""

                switch ($fnName) {
                    "search_okf" {
                        $q = if ($argsObj.query) { $argsObj.query } else { "" }
                        $d = if ($argsObj.domain) { $argsObj.domain } else { "" }
                        [void]$thinkingLog.Add("🔍 Tool Call: search_okf (query: '$q', domain: '$d')")
                        $searchHits = Search-OkfDocs -Query $q -DomainFilter $d -StatusFilter "active" -WikiDir $targetDir -MaxResults 3
                        if ($searchHits -and $searchHits.Count -gt 0) {
                            foreach ($sh in $searchHits) {
                                if ($sh.Meta -and $sh.Meta.RelPath -and -not $visitedPaths.Contains($sh.Meta.RelPath)) {
                                    [void]$visitedPaths.Add($sh.Meta.RelPath)
                                }
                            }
                            $sb = [System.Text.StringBuilder]::new()
                            foreach ($r in $searchHits) {
                                $meta = $r.Meta
                                [void]$sb.AppendLine("---")
                                [void]$sb.AppendLine("■ タイトル: $($meta.Title) (Path: $($meta.RelPath))")
                                [void]$sb.AppendLine("・ドメイン: $($meta.Domain) | 著者: $($meta.Author) | 更新: $($meta.LastUpdated.ToString('yyyy-MM-dd'))")
                                [void]$sb.AppendLine("・概要: $($meta.Description)")
                                [void]$sb.AppendLine("・スニペット: $($r.Snippet)")
                            }
                            $toolResult = $sb.ToString()
                        } else {
                            $toolResult = "検索結果は見つかりませんでした。"
                        }
                    }
                    "lookup_glossary" {
                        $t = if ($argsObj.term) { $argsObj.term } else { "" }
                        [void]$thinkingLog.Add("📖 Tool Call: lookup_glossary (term: '$t')")
                        $toolResult = Invoke-ToolLookupGlossary -Term $t -WikiDir $targetDir
                    }
                    "read_doc" {
                        $p = if ($argsObj.relPath) { $argsObj.relPath } else { "" }
                        [void]$thinkingLog.Add("📄 Tool Call: read_doc (relPath: '$p')")
                        $toolResult = Invoke-ToolReadDoc -RelPath $p -WikiDir $targetDir -MaxChars $MaxDocChars
                        if ($p -and -not $visitedPaths.Contains($p)) {
                            [void]$visitedPaths.Add($p)
                        }
                    }
                    "get_linked_docs" {
                        $p = if ($argsObj.relPath) { $argsObj.relPath } else { "" }
                        [void]$thinkingLog.Add("🔗 Tool Call: get_linked_docs (relPath: '$p')")
                        $links = Invoke-ToolGetLinkedDocs -RelPath $p -WikiDir $targetDir
                        if ($links -and $links.Count -gt 0) {
                            $linkStrList = foreach ($l in $links) { "・[$($l.LinkText)]($($l.RelPath)) [Status: $($l.Status)]" }
                            $toolResult = "リンク一覧:`n" + ($linkStrList -join "`n")
                        } else {
                            $toolResult = "リンクは見つかりませんでした。"
                        }
                    }
                    default {
                        $toolResult = "未知のツール名: $fnName"
                    }
                }

                [void]$messages.Add(@{
                    role         = "tool"
                    tool_call_id = $callId
                    content      = $toolResult
                })
            }
        } else {
            $finalAnswer = $resMsg.content
            break
        }
    }

    Build-WikiIndex -TargetWikiDir $targetDir | Out-Null
    foreach ($vp in $visitedPaths) {
        $found = $script:WikiIndex | Where-Object { $_.RelPath -eq $vp -or $_.RelPath -like "*$vp*" } | Select-Object -First 1
        if ($found) {
            $relUri = "/" + [Uri]::EscapeUriString($found.RelPath.Replace('\', '/'))
            [void]$sourcesList.Add([PSCustomObject]@{
                title       = $found.Title
                relPath     = $found.RelPath
                relUri      = $relUri
                lastUpdated = $found.LastUpdated.ToString("yyyy-MM-dd")
                author      = $found.Author
                status      = $found.Status
            })
        }
    }

    if ([string]::IsNullOrWhiteSpace($finalAnswer)) {
        [void]$thinkingLog.Add("⏱️ ターン上限 ($MaxTurns) に達したため、収集情報から要約回答を生成します。")
        [void]$messages.Add(@{ role = "user"; content = "※これ以上のツール呼び出しを行わず、ここまでに取得した情報を元に結論をテキストで要約して最終出力してください。該当情報が見つからない場合は『Wiki内に該当する情報が見つかりませんでした』と回答してください。" })

        $payloadObj = @{
            model       = $Model
            temperature = 0.2
            messages    = $messages
        }
        $jsonBody = $payloadObj | ConvertTo-Json -Depth 5
        $reqBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

        try {
            $webReq = [System.Net.HttpWebRequest]::Create($endpointUrl)
            $webReq.Method = "POST"
            $webReq.ContentType = "application/json; charset=utf-8"
            $webReq.Timeout = $TimeoutSec * 1000
            if (-not [string]::IsNullOrWhiteSpace($resolvedKey)) {
                $webReq.Headers["Authorization"] = "Bearer $resolvedKey"
            }

            $reqStream = $webReq.GetRequestStream()
            $reqStream.Write($reqBytes, 0, $reqBytes.Length)
            $reqStream.Close()

            $webRes = $webReq.GetResponse()
            try {
                $resStream = $webRes.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($resStream, [System.Text.Encoding]::UTF8)
                $resJson = $reader.ReadToEnd()
                $parsed = $resJson | ConvertFrom-Json
                if ($parsed -and $parsed.choices -and $parsed.choices.Count -gt 0) {
                    $finalAnswer = $parsed.choices[0].message.content
                }
            } finally {
                $webRes.Close()
            }
        } catch {
            # 通信例外等のキャッチ
        }

        if ([string]::IsNullOrWhiteSpace($finalAnswer)) {
            if ($visitedPaths.Count -gt 0) {
                $finalAnswer = "Wiki 内を自律調査しましたが、質問に直接該当する明確なエラー情報や定義は見つかりませんでした。"
            } else {
                $finalAnswer = "Wiki 内を自律検索しましたが、該当する情報は見つかりませんでした。別の検索キーワードや具体名をお試しください。"
            }
        }
    }

    return [PSCustomObject]@{
        answer      = $finalAnswer
        thinkingLog = $thinkingLog
        sources     = $sourcesList
    }
}

function Get-ChatWidgetHtml {
    $widget = @'
    <!-- Floating Chat Widget -->
    <button id="okfChatBtn" class="chat-widget-btn">🤖 Wiki AI チャット</button>
    <div id="okfChatBox" class="chat-box">
        <div class="chat-header">
            <span>🤖 OKF Wiki AI アシスタント</span>
            <div class="chat-header-actions">
                <button id="okfChatExpandBtn" class="chat-header-expand" title="ウィンドウを拡大/縮小">⛶ 拡大</button>
                <button id="okfChatClearBtn" class="chat-header-clear" title="会話履歴をクリア">🧹 履歴クリア</button>
                <button id="okfChatCloseBtn" class="chat-header-close">✕</button>
            </div>
        </div>
        <div class="chat-mode-selector">
            <span class="mode-label">モード:</span>
            <label><input type="radio" name="okfRagMode" value="fast" checked> ⚡ Fast</label>
            <label><input type="radio" name="okfRagMode" value="agentic"> 🧠 Agentic</label>
        </div>
        <div id="okfChatMessages" class="chat-messages">
            <div class="chat-msg assistant">こんにちは！Wiki内のナレッジを元にお答えします。質問を入力してください。</div>
        </div>
        <div class="chat-input-area">
            <input type="text" id="okfChatInput" placeholder="Wikiに質問..." />
            <button id="okfChatSendBtn">送信</button>
        </div>
    </div>
    <style>
        .chat-widget-btn { position: fixed; bottom: 20px; right: 20px; background: #0366d6; color: #fff; border: none; border-radius: 24px; padding: 10px 18px; font-weight: bold; cursor: pointer; box-shadow: 0 4px 12px rgba(0,0,0,0.15); z-index: 9999; font-size: 13px; display: flex; align-items: center; gap: 6px; }
        .chat-widget-btn:hover { background: #0255b3; }
        .chat-box { position: fixed; bottom: 70px; right: 20px; width: 440px; height: 550px; background: #fff; border: 1px solid #e1e4e8; border-radius: 8px; box-shadow: 0 8px 24px rgba(0,0,0,0.15); display: none; flex-direction: column; z-index: 9999; overflow: hidden; transition: all 0.2s ease-in-out; }
        .chat-box.expanded { width: 85vw; height: 85vh; max-width: 980px; max-height: 850px; bottom: 20px; right: 20px; }
        .chat-header { background: #1b1f23; color: #fff; padding: 10px 14px; font-weight: bold; font-size: 13px; display: flex; justify-content: space-between; align-items: center; }
        .chat-header-actions { display: flex; align-items: center; gap: 6px; }
        .chat-header-expand, .chat-header-clear { background: #343a40; border: 1px solid #495057; color: #f8f9fa; font-size: 11px; padding: 3px 8px; border-radius: 4px; cursor: pointer; }
        .chat-header-expand:hover, .chat-header-clear:hover { background: #495057; }
        .chat-header-close { background: none; border: none; color: #fff; font-size: 16px; cursor: pointer; margin-left: 4px; }
        
        .chat-mode-selector { background: #f1f8ff; border-bottom: 1px solid #c8e1ff; padding: 6px 14px; font-size: 12px; display: flex; align-items: center; gap: 12px; color: #0366d6; font-weight: bold; }
        .chat-mode-selector .mode-label { color: #586069; font-weight: normal; }
        .chat-mode-selector label { cursor: pointer; display: flex; align-items: center; gap: 3px; }

        .chat-messages { flex: 1; padding: 12px; overflow-y: auto; font-size: 13px; display: flex; flex-direction: column; gap: 10px; background: #f8f9fa; }
        .chat-msg { max-width: 90%; padding: 8px 12px; border-radius: 12px; line-height: 1.5; word-break: break-word; }
        .chat-msg.user { align-self: flex-end; background: #0366d6; color: #fff; border-bottom-right-radius: 2px; white-space: pre-wrap; }
        .chat-msg.assistant { align-self: flex-start; background: #fff; color: #24292e; border: 1px solid #e1e4e8; border-bottom-left-radius: 2px; }
        .chat-thinking { margin-bottom: 8px; font-size: 12px; background: #fff8c5; border: 1px solid #ffeef0; border-radius: 6px; padding: 6px 10px; color: #735c0f; }
        .chat-thinking summary { font-weight: bold; cursor: pointer; user-select: none; }
        .chat-thinking ul { margin: 4px 0 0 16px; padding: 0; }
        .chat-thinking li { margin-bottom: 2px; font-family: monospace; font-size: 11px; }

        .chat-sources { margin-top: 8px; font-size: 11px; color: #586069; border-top: 1px dashed #e1e4e8; padding-top: 6px; }
        .chat-msg-actions { margin-top: 6px; display: flex; justify-content: flex-end; border-top: 1px solid #eaecef; padding-top: 4px; }
        .chat-copy-btn { background: none; border: none; color: #0366d6; font-size: 11px; cursor: pointer; padding: 2px 6px; border-radius: 4px; display: inline-flex; align-items: center; gap: 3px; font-weight: bold; }
        .chat-copy-btn:hover { background: #f1f8ff; text-decoration: underline; }
        .chat-input-area { padding: 10px; border-top: 1px solid #e1e4e8; background: #fff; display: flex; gap: 6px; }
        .chat-input-area input { flex: 1; padding: 8px 10px; border: 1px solid #ccc; border-radius: 4px; font-size: 13px; }
        .chat-input-area button { padding: 8px 14px; background: #0366d6; color: #fff; border: none; border-radius: 4px; font-weight: bold; cursor: pointer; }
        .chat-input-area button:disabled { background: #94d1ff; cursor: not-allowed; }
        
        /* Markdown Renderer Styles */
        .chat-table-wrapper { overflow-x: auto; margin: 8px 0; border: 1px solid #e1e4e8; border-radius: 6px; }
        .chat-table { border-collapse: collapse; width: 100%; font-size: 12px; }
        .chat-table th, .chat-table td { border: 1px solid #e1e4e8; padding: 6px 10px; text-align: left; }
        .chat-table th { background: #f6f8fa; font-weight: bold; }
        .chat-table tr:nth-child(even) { background: #f8f9fa; }
        .chat-msg.assistant code { background: #f1f8ff; color: #0366d6; padding: 2px 5px; border-radius: 4px; font-family: monospace; font-size: 12px; }
        .chat-msg.assistant pre { background: #24292e; color: #f6f8fa; padding: 10px; border-radius: 6px; overflow-x: auto; font-size: 12px; margin: 6px 0; }
        .chat-msg.assistant pre code { background: none; color: inherit; padding: 0; }
        .chat-msg.assistant ul, .chat-msg.assistant ol { margin: 6px 0 6px 20px; padding: 0; }
    </style>
    <script>
        document.addEventListener("DOMContentLoaded", function() {
            var btn = document.getElementById("okfChatBtn");
            var box = document.getElementById("okfChatBox");
            var closeBtn = document.getElementById("okfChatCloseBtn");
            var clearBtn = document.getElementById("okfChatClearBtn");
            var expandBtn = document.getElementById("okfChatExpandBtn");
            var sendBtn = document.getElementById("okfChatSendBtn");
            var input = document.getElementById("okfChatInput");
            var msgs = document.getElementById("okfChatMessages");
            var chatHistory = [];

            if (!btn || !box) return;
            btn.addEventListener("click", function() { box.style.display = box.style.display === "flex" ? "none" : "flex"; });
            closeBtn.addEventListener("click", function() { box.style.display = "none"; });

            if (expandBtn) {
                expandBtn.addEventListener("click", function() {
                    box.classList.toggle("expanded");
                    if (box.classList.contains("expanded")) {
                        expandBtn.textContent = "🗗 縮小";
                    } else {
                        expandBtn.textContent = "⛶ 拡大";
                    }
                });
            }

            if (clearBtn) {
                clearBtn.addEventListener("click", function() {
                    chatHistory = [];
                    msgs.innerHTML = '<div class="chat-msg assistant">会話履歴をリセットしました。質問を入力してください。</div>';
                });
            }

            function escapeHtml(str) {
                return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
            }

            function parseInline(str) {
                var s = escapeHtml(str);
                s = s.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
                s = s.replace(/`([^`]+)`/g, "<code>$1</code>");
                s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g, "<a href='$2' target='_blank'>$1</a>");
                return s;
            }

            function renderMarkdown(src) {
                if (!src) return "";
                var html = src;

                var codeBlocks = [];
                html = html.replace(/```([\s\S]*?)```/g, function(match, code) {
                    var placeholder = "___CODEBLOCK_" + codeBlocks.length + "___";
                    codeBlocks.push("<pre><code>" + escapeHtml(code.trim()) + "</code></pre>");
                    return placeholder;
                });

                var tableRegex = /(?:(?:^|\n)\|[^\n]+\|\n\|[\s:\-\|]+\|\n(?:\|[^\n]+\|\n?)+)/g;
                html = html.replace(tableRegex, function(match) {
                    var lines = match.trim().split('\n');
                    if (lines.length < 3) return match;
                    
                    var headerCols = lines[0].split('|').map(function(c) { return c.trim(); }).filter(function(c, i, a) { return i > 0 && i < a.length - 1; });
                    var rows = [];
                    for (var i = 2; i < lines.length; i++) {
                        if (!lines[i].trim()) continue;
                        var cols = lines[i].split('|').map(function(c) { return c.trim(); }).filter(function(c, j, a) { return j > 0 && j < a.length - 1; });
                        rows.push(cols);
                    }

                    var tHtml = "<div class='chat-table-wrapper'><table class='chat-table'><thead><tr>";
                    headerCols.forEach(function(h) { tHtml += "<th>" + parseInline(h) + "</th>"; });
                    tHtml += "</tr></thead><tbody>";
                    rows.forEach(function(r) {
                        tHtml += "<tr>";
                        r.forEach(function(c) { tHtml += "<td>" + parseInline(c) + "</td>"; });
                        tHtml += "</tr>";
                    });
                    tHtml += "</tbody></table></div>";
                    return tHtml;
                });

                var parts = html.split(/(___CODEBLOCK_\d+___|<div class='chat-table-wrapper'>[\s\S]*?<\/div>)/g);
                for (var k = 0; k < parts.length; k++) {
                    if (parts[k].indexOf("___CODEBLOCK_") === 0) {
                        var idx = parseInt(parts[k].replace("___CODEBLOCK_", "").replace("___", ""), 10);
                        parts[k] = codeBlocks[idx];
                    } else if (parts[k].indexOf("<div class='chat-table-wrapper'>") === 0) {
                        // Table Preserved
                    } else {
                        var lines = parts[k].split('\n');
                        var res = [];
                        var inList = false;
                        for (var i = 0; i < lines.length; i++) {
                            var line = lines[i];
                            var listMatch = line.match(/^[\s]*[\-\*]\s+(.*)/);
                            if (listMatch) {
                                if (!inList) { res.push("<ul>"); inList = true; }
                                res.push("<li>" + parseInline(listMatch[1]) + "</li>");
                            } else {
                                if (inList) { res.push("</ul>"); inList = false; }
                                if (line.trim() === "") {
                                    res.push("<br>");
                                } else {
                                    res.push(parseInline(line));
                                }
                            }
                        }
                        if (inList) res.push("</ul>");
                        parts[k] = res.join("");
                    }
                }
                return parts.join("");
            }

            function appendMsg(role, text, sources, thinkingLog) {
                var div = document.createElement("div");
                div.className = "chat-msg " + role;
                if (role === "user") {
                    div.textContent = text;
                } else {
                    var innerHtml = "";
                    if (thinkingLog && thinkingLog.length > 0) {
                        innerHtml += "<details class='chat-thinking'><summary>🧠 Agent 思考プロセス (" + thinkingLog.length + " ステップ)</summary><ul>";
                        thinkingLog.forEach(function(item) {
                            innerHtml += "<li>" + escapeHtml(item) + "</li>";
                        });
                        innerHtml += "</ul></details>";
                    }
                    innerHtml += renderMarkdown(text);
                    div.innerHTML = innerHtml;
                }
                if (sources && sources.length > 0) {
                    var srcDiv = document.createElement("div");
                    srcDiv.className = "chat-sources";
                    srcDiv.innerHTML = "📖 <strong>出典:</strong> " + sources.map(function(s) { return "<a href='" + s.relUri + "' target='_blank'>" + s.title + "</a> (" + s.lastUpdated + ")"; }).join(", ");
                    div.appendChild(srcDiv);
                }
                if (role === "assistant" && text !== "🤔 思考中...") {
                    var actionDiv = document.createElement("div");
                    actionDiv.className = "chat-msg-actions";
                    var copyBtn = document.createElement("button");
                    copyBtn.className = "chat-copy-btn";
                    copyBtn.innerHTML = "📋 コピー";
                    copyBtn.addEventListener("click", function() {
                        var performCopy = function() {
                            copyBtn.innerHTML = "✓ コピー完了";
                            setTimeout(function() { copyBtn.innerHTML = "📋 コピー"; }, 1500);
                        };
                        if (navigator.clipboard && navigator.clipboard.writeText) {
                            navigator.clipboard.writeText(text).then(performCopy).catch(function() {
                                var ta = document.createElement("textarea");
                                ta.value = text;
                                document.body.appendChild(ta);
                                ta.select();
                                document.execCommand("copy");
                                document.body.removeChild(ta);
                                performCopy();
                            });
                        } else {
                            var ta = document.createElement("textarea");
                            ta.value = text;
                            document.body.appendChild(ta);
                            ta.select();
                            document.execCommand("copy");
                            document.body.removeChild(ta);
                            performCopy();
                        }
                    });
                    actionDiv.appendChild(copyBtn);
                    div.appendChild(actionDiv);
                }
                msgs.appendChild(div);
                msgs.scrollTop = msgs.scrollHeight;
            }

            function sendMsg() {
                var q = input.value.trim();
                if (!q) return;

                var modeRadio = document.querySelector('input[name="okfRagMode"]:checked');
                var mode = modeRadio ? modeRadio.value : "fast";

                appendMsg("user", q);
                input.value = "";
                sendBtn.disabled = true;
                appendMsg("assistant", mode === "agentic" ? "🧠 自律深掘り調査中..." : "⚡ 検索・生成中...");

                fetch("/api/chat", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ mode: mode, message: q, history: chatHistory })
                }).then(function(res) { return res.json(); }).then(function(data) {
                    msgs.removeChild(msgs.lastChild);
                    if (data.error) {
                        appendMsg("assistant", "⚠️ エラー: " + data.message);
                    } else {
                        appendMsg("assistant", data.answer, data.sources, data.thinkingLog);
                        chatHistory.push({ role: "user", content: q });
                        chatHistory.push({ role: "assistant", content: data.answer });
                    }
                }).catch(function(err) {
                    msgs.removeChild(msgs.lastChild);
                    appendMsg("assistant", "⚠️ 通信エラーが発生しました。");
                }).finally(function() {
                    sendBtn.disabled = false;
                });
            }

            sendBtn.addEventListener("click", sendMsg);
            input.addEventListener("keypress", function(e) { if (e.key === "Enter") sendMsg(); });
        });
    </script>
'@
    return $widget
}

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

            # 1. API エンドポイント (/api/index.json, /api/chunks.json, /api/chat)
            if ($rawPath -eq "/api/index.json") {
                $jsonStr = Get-ApiIndexJson
                $bytes   = [System.Text.Encoding]::UTF8.GetBytes($jsonStr)
                Write-SafeHttpResponse -Response $response -Bytes $bytes -ContentType "application/json; charset=utf-8"
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
                        $agentRes = Invoke-AgenticRagChat -ApiUrl $config.rag.apiUrl -ApiKey $config.rag.apiKey -Model $config.rag.model -UserMessage $userMsg -History $processedHistory -WikiDir $wikiDir -MaxTurns $maxTurns -MaxDocChars $maxDocChars -TimeoutSec $timeoutSec
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
                $contextDocs = @()
                if ($topScored.Count -gt 0) {
                    $contextDocs = @($topScored | ForEach-Object { $_.Doc })
                } else {
                    $takeCount = [Math]::Min($maxDocs, $activeDocs.Count)
                    $contextDocs = @($activeDocs | Sort-Object LastUpdated -Descending | Select-Object -First $takeCount)
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
            } elseif ($rawPath -eq "/search") {
                $isDynamicView = $true
                $qParam        = $queryParams["q"]
                $stParam       = $queryParams["status"]
                $domParam      = $queryParams["domain"]
                $stValue       = if (-not [string]::IsNullOrWhiteSpace($stParam)) { $stParam } else { "active" }
                $pageTitle     = if ($qParam) { "検索: $qParam" } else { "検索" }
                $bodyContent   = Get-SearchViewHtml -Query $qParam -StatusFilter $stValue -DomainFilter $domParam
            }

            # Markdown ファイルの物理存在チェックと決定
            if (-not $isDynamicView -and ($rawPath -eq "/" -or [string]::IsNullOrEmpty($rawPath))) {
                if (Test-Path (Join-Path $wikiDir "index.md")) {
                    $rawPath = "/index.md"
                } elseif (Test-Path (Join-Path $wikiDir "README.md")) {
                    $rawPath = "/README.md"
                }
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

            # 3. HTML レンダリング (Markdown または動的ビュー)
            if ($isDynamicView -or ((Test-Path $fullPath -PathType Leaf) -and ($fullPath.EndsWith(".md")))) {
                if (-not $isDynamicView) {
                    $mdText   = Get-Content -Path $fullPath -Raw -Encoding UTF8
                    $fileObj  = Get-Item $fullPath
                    $meta     = Get-DocumentMetadata -File $fileObj -RelPath $relPath -MdText $mdText

                    $builder  = New-Object Markdig.MarkdownPipelineBuilder
                    $null     = [Markdig.MarkdownExtensions]::UseAdvancedExtensions($builder)
                    $null     = [Markdig.MarkdownExtensions]::UseYamlFrontMatter($builder)
                    $pipeline = $builder.Build()
                    $renderedHtml = [Markdig.Markdown]::ToHtml($mdText, $pipeline)

                    $okfTopBar   = Get-OkfTopBarHtml -Meta $meta
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
    <script src="/lib/mermaid.min.js"></script>
    <script>
        document.addEventListener("DOMContentLoaded", function() {
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
            } elseif (Test-Path $fullPath -PathType Leaf) {
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

