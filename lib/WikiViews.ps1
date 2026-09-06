# ==============================================================================
#  SimpleWiki HTML ビュー & UI コンポーネント描画モジュール
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================

function Get-SidebarHtml {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSReviewUnusedParameter", "")]
    param (
        $currentRelPath,
        [string]$Lang = "ja"
    )

    $targetWiki = if ($wikiDir) { $wikiDir } elseif ($script:wikiDir) { $script:wikiDir } else { $PWD.Path }

    # Ensure index is loaded (from memory, disk cache, or synchronous build)
    if ($null -eq $script:WikiIndex -or $script:WikiIndex.Count -eq 0) {
        Ensure-WikiIndexLoaded -TargetWikiDir $targetWiki
    }

    # Retrieve tree: from index if available, otherwise full recursive scan from disk
    $treeNode = $null
    if ($null -ne $script:CachedSidebarTree -and $null -ne $script:WikiIndex -and $script:WikiIndex.Count -gt 0 -and $script:CachedSidebarTreeLastScan -eq $script:WikiIndexLastScan) {
        $treeNode = $script:CachedSidebarTree
    } else {
        if ($null -ne $script:WikiIndex -and $script:WikiIndex.Count -gt 0) {
            $treeNode = Build-ServerFileTreeNode -allMdFiles $script:WikiIndex -wikiDir $targetWiki
            $script:CachedSidebarTree = $treeNode
            $script:CachedSidebarTreeLastScan = $script:WikiIndexLastScan
        } else {
            $treeNode = Build-ServerFileTreeNode -wikiDir $targetWiki
        }
    }

    $treeHtml = Render-ServerFolderTreeHtml -node $treeNode -currentRelPath $currentRelPath -wikiDir $targetWiki

    return $treeHtml
}
function Get-DirectoryListingHtml {
    param (
        [string]$DirFullPath,
        [string]$RawUrlPath,
        [string]$Lang = "ja"
    )

    $cleanUrl = $RawUrlPath.TrimEnd("/")

    $css = @'
<style>
    .dir-listing-list { list-style: none; padding: 0; margin: 0; display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 6px; }
    .dir-listing-list li { padding: 8px 12px; border: 1px solid #e1e4e8; border-radius: 6px; transition: background 0.15s, border-color 0.15s; }
    .dir-listing-list li:hover { background: #f6f8fa; border-color: #0366d6; }
    .dir-listing-list li a { text-decoration: none; color: #0366d6; font-size: 14px; display: block; word-break: break-all; }
    .dir-listing-folder a { font-weight: 600; }
    .dir-listing-notice { margin-top: 24px; padding: 12px 16px; background: #fffbdd; border: 1px solid #f9c513; border-radius: 6px; font-size: 13px; color: #735c0f; }
</style>
'@

    $html = $css + "`n"

    $subDirs = Get-ChildItem -LiteralPath $DirFullPath -Directory -ErrorAction SilentlyContinue | Sort-Object Name
    $mdFiles = Get-ChildItem -LiteralPath $DirFullPath -Filter "*.md" -File -ErrorAction SilentlyContinue | Sort-Object Name

    if ($subDirs.Count -eq 0 -and $mdFiles.Count -eq 0) {
        $noContentText = Get-LocalizedStr -Key "no_content" -Lang $Lang
        $html += "<p>$noContentText</p>`n"
    } else {
        $totalCount = $subDirs.Count + $mdFiles.Count
        $itemsCountText = Get-LocalizedStr -Key "items_count" -Lang $Lang -FormatArgs @($totalCount)
        $html += "<p style='color:#586069; font-size:13px;'>$itemsCountText</p>`n"
        $html += "<ul class='dir-listing-list'>`n"

        foreach ($dir in $subDirs) {
            $encodedName = [System.Net.WebUtility]::HtmlEncode($dir.Name)
            $urlName     = [Uri]::EscapeDataString($dir.Name)
            $href        = "$cleanUrl/$urlName/"
            $html += "  <li class='dir-listing-folder'><a href='$href'>📁 $encodedName</a></li>`n"
        }

        foreach ($file in $mdFiles) {
            $encodedName = [System.Net.WebUtility]::HtmlEncode($file.BaseName)
            $urlName     = [Uri]::EscapeDataString($file.Name)
            $href        = "$cleanUrl/$urlName"
            $html += "  <li class='dir-listing-file'><a href='$href'>📄 $encodedName</a></li>`n"
        }

        $html += "</ul>`n"
    }

    $noIndexWarningText = Get-LocalizedStr -Key "no_index_warning" -Lang $Lang
    $html += "<div class='dir-listing-notice'>$noIndexWarningText</div>`n"

    return $html
}

# --- OKF トップバー ＆ フッターカード レンダリング関数 ---
function Get-OkfTopBarHtml {
    param (
        [Parameter(Mandatory = $true)]$Meta,
        [string]$RelPath = "",
        [string]$Lang = "ja",
        [bool]$EditorEnabled = $true
    )

    $domain = [System.Net.WebUtility]::HtmlEncode($Meta.Domain)
    $statusBadge = switch ($Meta.Status) {
        "draft"       { '<span class="badge badge-draft">📝 Draft</span>' }
        "wip"         { '<span class="badge badge-draft">📝 WIP</span>' }
        "review"      { '<span class="badge badge-draft" style="background:#fff3cd; color:#856404; border-color:#ffeeba;">🔍 Review</span>' }
        "in-review"   { '<span class="badge badge-draft" style="background:#fff3cd; color:#856404; border-color:#ffeeba;">🔍 Review</span>' }
        "deprecated"  { '<span class="badge badge-deprecated">🗑️ Deprecated</span>' }
        "archived"    { '<span class="badge badge-deprecated" style="background:#fbe9e7; color:#c62828; border-color:#ffccbc;">📦 Archived</span>' }
        "obsolete"    { '<span class="badge badge-deprecated">🗑️ Obsolete</span>' }
        "stable"      { '<span class="badge badge-active" style="background:#e8f4fd; color:#0366d6; border-color:#c8e1ff;">🌟 Stable</span>' }
        default       { '<span class="badge badge-active">✅ Active</span>' }
    }

    $verBadge = if ($Meta.Version -and -not [string]::IsNullOrWhiteSpace($Meta.Version)) {
        $encVer = [System.Net.WebUtility]::HtmlEncode($Meta.Version)
        "<span class='badge badge-active' style='background:#e1e4e8; color:#24292e; border:none; font-weight:normal;'>v$encVer</span>"
    } else { "" }

    $tagsHtml = ""
    if ($Meta.Tags -and $Meta.Tags.Count -gt 0) {
        $tagBadges = foreach ($t in $Meta.Tags) {
            $encTag = [System.Net.WebUtility]::HtmlEncode($t)
            $urlTag = [Uri]::EscapeDataString($t)
            "<a href='/tags?tag=$urlTag' class='tag-badge'>🏷️ $encTag</a>"
        }
        $tagsHtml = "<div class='okf-tags'>" + ($tagBadges -join " ") + "</div>"
    }

    $isDep = ($Meta.Status -in @("deprecated", "archived", "obsolete"))
    $warningBanner = if ($isDep) {
        $warnText = Get-LocalizedStr -Key "warning_deprecated" -Lang $Lang
        $supersededHtml = ""
        if ($Meta.SupersededBy -and -not [string]::IsNullOrWhiteSpace($Meta.SupersededBy)) {
            $supNotice = Get-LocalizedStr -Key "superseded_by_notice" -Lang $Lang
            $encSup = [System.Net.WebUtility]::HtmlEncode($Meta.SupersededBy)
            $urlSup = "/" + [Uri]::EscapeUriString($Meta.SupersededBy.Replace('\', '/').TrimStart('/'))
            $supersededHtml = "<br><span style='margin-top:4px; display:inline-block;'>$supNotice<a href='$urlSup' style='color:#735c0f; font-weight:bold; text-decoration:underline;'>📄 $encSup</a></span>"
        }
        "<div class=""warning-banner"">$warnText$supersededHtml</div>"
    } else { "" }

    $editBtnHtml = ""
    if ($EditorEnabled -and -not [string]::IsNullOrWhiteSpace($RelPath)) {
        $safeRel = [System.Net.WebUtility]::HtmlEncode($RelPath.Replace("\", "/"))
        $editBtnText = Get-LocalizedStr -Key "edit_doc_btn" -Lang $Lang
        $editBtnHtml = "<button class='edit-doc-btn' data-relpath='$safeRel' onclick='openWikiEditor(this)'>$editBtnText</button>"
    }

    return @"
$warningBanner
<div class="okf-top-bar">
    <div class="okf-top-left">
        <span class="okf-domain">📁 $domain</span>
        $statusBadge
        $verBadge
        $editBtnHtml
    </div>
    $tagsHtml
</div>
"@
}

function Get-OkfFooterCardHtml {
    param (
        [Parameter(Mandatory = $true)]$Meta,
        [string]$Lang = "ja"
    )

    $desc    = [System.Net.WebUtility]::HtmlEncode($Meta.Description)
    $author  = [System.Net.WebUtility]::HtmlEncode($Meta.Author)

    $lastUpd = if ($Meta.LastUpdated -and $Meta.LastUpdated -ne [DateTime]::MinValue) {
        $Meta.LastUpdated.ToString("yyyy-MM-dd")
    } else {
        Get-LocalizedStr -Key "unknown" -Lang $Lang
    }

    $cardTitle   = Get-LocalizedStr -Key "metadata_card_title" -Lang $Lang
    $authorLbl   = Get-LocalizedStr -Key "metadata_author" -Lang $Lang
    $lastUpdLbl  = Get-LocalizedStr -Key "metadata_last_updated" -Lang $Lang
    $apiJsonLbl  = Get-LocalizedStr -Key "api_json" -Lang $Lang
    $verLbl      = Get-LocalizedStr -Key "metadata_version" -Lang $Lang
    $revLbl      = Get-LocalizedStr -Key "metadata_reviewer" -Lang $Lang
    $contribLbl  = Get-LocalizedStr -Key "metadata_contributors" -Lang $Lang
    $relatedLbl  = Get-LocalizedStr -Key "metadata_related" -Lang $Lang

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
        "<span class='okf-author'>$authorLbl<a href='/authors?name=$urlAuthor'>$author</a></span>"
    } else { "" }

    $versionHtml = if ($Meta.Version -and -not [string]::IsNullOrWhiteSpace($Meta.Version)) {
        $encV = [System.Net.WebUtility]::HtmlEncode($Meta.Version)
        "<span>$verLbl<strong>v$encV</strong></span>"
    } else { "" }

    $reviewerHtml = if ($Meta.Reviewer -and -not [string]::IsNullOrWhiteSpace($Meta.Reviewer)) {
        $encR = [System.Net.WebUtility]::HtmlEncode($Meta.Reviewer)
        "<span>$revLbl$encR</span>"
    } else { "" }

    $contributorsHtml = if ($Meta.Contributors -and $Meta.Contributors.Count -gt 0) {
        $cList = ($Meta.Contributors | ForEach-Object { [System.Net.WebUtility]::HtmlEncode($_) }) -join ", "
        "<span>$contribLbl$cList</span>"
    } else { "" }

    $relatedHtml = if ($Meta.Related -and $Meta.Related.Count -gt 0) {
        $rLinks = foreach ($r in $Meta.Related) {
            $encRel = [System.Net.WebUtility]::HtmlEncode($r)
            $urlRel = "/" + [Uri]::EscapeUriString($r.Replace('\', '/').TrimStart('/'))
            "<a href='$urlRel' style='color:#0366d6; text-decoration:none;'>📄 $encRel</a>"
        }
        "<div style='margin-top:8px; font-size:12px; color:#586069;'>$relatedLbl" + ($rLinks -join " &nbsp;|&nbsp; ") + "</div>"
    } else { "" }

    $descHtml = if (-not [string]::IsNullOrWhiteSpace($desc)) {
        "<p class='okf-desc'>$desc</p>"
    } else { "" }

    return @"
<footer class="okf-footer-card">
    <div class="okf-footer-header">
        <span class="okf-footer-title">$cardTitle</span>
        <a href="/api/index.json" target="_blank" class="okf-api-link">$apiJsonLbl</a>
    </div>
    $descHtml
    <div class="okf-footer-meta" style="display:flex; flex-wrap:wrap; gap:16px;">
        $authorHtml
        $versionHtml
        $reviewerHtml
        $contributorsHtml
        <span>$lastUpdLbl$lastUpd</span>
    </div>
    $relatedHtml
    $tagsHtml
</footer>
"@
}


# --- 機械可読 API JSON 生成関数 (AI エージェント / LLM 用) ---
function Get-ApiIndexJson {
    param (
        [hashtable]$QueryParams = @{}
    )
    Build-WikiIndex -TargetWikiDir $wikiDir | Out-Null
    $config = Get-ConfigJson -TargetScriptDir $scriptDir

    $defaultLimit = if ($config.api -and $config.api.defaultLimit) { [int]$config.api.defaultLimit } else { 100 }
    $maxLimit     = if ($config.api -and $config.api.maxLimit) { [int]$config.api.maxLimit } else { 1000 }

    $filteredItems = $script:WikiIndex

    # 1. フィルタリング (Domain)
    if ($QueryParams.ContainsKey("domain") -and -not [string]::IsNullOrWhiteSpace($QueryParams["domain"])) {
        $targetDomain = $QueryParams["domain"].Trim()
        $filteredItems = $filteredItems | Where-Object { $_.Domain -eq $targetDomain -or $_.Domain.StartsWith($targetDomain) }
    }

    # 2. フィルタリング (Tag)
    if ($QueryParams.ContainsKey("tag") -and -not [string]::IsNullOrWhiteSpace($QueryParams["tag"])) {
        $targetTag = $QueryParams["tag"].Trim()
        $filteredItems = $filteredItems | Where-Object { $_.Tags -and ($_.Tags -contains $targetTag) }
    }

    # 3. フィルタリング (Since: YYYY-MM-DD or ISO 8601)
    if ($QueryParams.ContainsKey("since") -and -not [string]::IsNullOrWhiteSpace($QueryParams["since"])) {
        $sinceParsed = [DateTime]::MinValue
        if ([DateTime]::TryParse($QueryParams["since"], [ref]$sinceParsed)) {
            $filteredItems = $filteredItems | Where-Object { $_.LastUpdated -ge $sinceParsed }
        }
    }

    $total = ($filteredItems | Measure-Object).Count

    # 4. ページネーション (Offset & Limit)
    $offset = 0
    if ($QueryParams.ContainsKey("offset")) {
        [int]::TryParse($QueryParams["offset"], [ref]$offset) | Out-Null
        if ($offset -lt 0) { $offset = 0 }
    }

    $limit = $defaultLimit
    if ($QueryParams.ContainsKey("limit")) {
        $rawLimit = $QueryParams["limit"]
        if ($rawLimit -eq "all" -or $rawLimit -eq "-1") {
            $limit = $total
        } else {
            [int]::TryParse($rawLimit, [ref]$limit) | Out-Null
            if ($limit -le 0) { $limit = $defaultLimit }
        }
    }

    if ($limit -gt $maxLimit -and ($QueryParams["limit"] -ne "all" -and $QueryParams["limit"] -ne "-1")) {
        $limit = $maxLimit
    }

    $slicedItems = if ($total -gt 0 -and $offset -lt $total) {
        $countToTake = [Math]::Min($limit, $total - $offset)
        $filteredItems[$offset..($offset + $countToTake - 1)]
    } else {
        @()
    }

    # 5. フィールド指定 (Fields: カンマ区切り)
    $fields = $null
    if ($QueryParams.ContainsKey("fields") -and -not [string]::IsNullOrWhiteSpace($QueryParams["fields"])) {
        $fields = ($QueryParams["fields"] -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    $exportItems = @(foreach ($item in $slicedItems) {
        $lastUpdStr = if ($item.LastUpdated -is [DateTime]) { $item.LastUpdated.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $item.LastUpdated }
        $createdStr = if ($item.CreatedAt -is [DateTime]) { $item.CreatedAt.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $item.CreatedAt }
        $updatedStr = if ($item.UpdatedAt -is [DateTime]) { $item.UpdatedAt.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $item.UpdatedAt }

        $fullObj = [PSCustomObject]@{
            Title       = $item.Title
            Description = $item.Description
            Author      = $item.Author
            Domain      = $item.Domain
            Tags        = $item.Tags
            LastUpdated = $lastUpdStr
            CreatedAt   = $createdStr
            UpdatedAt   = $updatedStr
            Status      = $item.Status
            HasYaml     = $item.HasYaml
            RelPath     = $item.RelPath
            Links       = $item.Links
            X           = if ($null -ne $item.X) { [int]$item.X } else { 0 }
            Y           = if ($null -ne $item.Y) { [int]$item.Y } else { 0 }
        }

        if ($fields -and $fields.Count -gt 0) {
            $selectedObj = [ordered]@{}
            foreach ($f in $fields) {
                $prop = $fullObj.psobject.Properties | Where-Object { $_.Name -eq $f } | Select-Object -First 1
                if ($prop) {
                    $selectedObj[$prop.Name] = $prop.Value
                }
            }
            [PSCustomObject]$selectedObj
        } else {
            $fullObj
        }
    })

    $itemCount = $exportItems.Count
    $isTruncated = ($offset + $itemCount) -lt $total

    $envelope = [PSCustomObject]@{
        Total       = $total
        Count       = $itemCount
        Offset      = $offset
        Limit       = $limit
        IsTruncated = $isTruncated
        Items       = $exportItems
    }

    return ($envelope | ConvertTo-Json -Depth 5)
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

# --- インデックス読み込み & 用語解説ヘルパー関数 ---
function Ensure-WikiIndexLoaded {
    param (
        [string]$TargetWikiDir
    )
    $dir = if (-not [string]::IsNullOrWhiteSpace($TargetWikiDir)) { $TargetWikiDir } elseif ($wikiDir) { $wikiDir } elseif ($script:wikiDir) { $script:wikiDir } else { $PWD.Path }
    if ($null -eq $script:WikiIndex -or $script:WikiIndex.Count -eq 0) {
        if (-not (Load-WikiIndexCache -TargetWikiDir $dir)) {
            Build-WikiIndex -TargetWikiDir $dir | Out-Null
        }
    }
}

function Render-GlossaryBoxHtml {
    param (
        [string]$Term,
        [string]$TargetWikiDir
    )
    if ([string]::IsNullOrWhiteSpace($Term)) {
        return ""
    }

    $targetWiki = if (-not [string]::IsNullOrWhiteSpace($TargetWikiDir)) { $TargetWikiDir } elseif ($wikiDir) { $wikiDir } elseif ($script:wikiDir) { $script:wikiDir } else { $PWD.Path }
    $gPath = Join-Path $targetWiki "glossary.md"
    if (-not (Test-Path $gPath) -and $scriptDir) {
        $gPath = Join-Path $scriptDir "markdown_sample/glossary.md"
    }

    $defText = Get-GlossaryTermDefinition -Term $Term -GlossaryPath $gPath
    if ([string]::IsNullOrWhiteSpace($defText)) {
        return ""
    }

    $formattedDef = ""
    if ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq "Markdig" }) {
        try {
            $builder = New-Object Markdig.MarkdownPipelineBuilder
            $null = [Markdig.MarkdownExtensions]::UseAdvancedExtensions($builder)
            $pipeline = $builder.Build()
            $formattedDef = [Markdig.Markdown]::ToHtml($defText, $pipeline)
        } catch {
            $formattedDef = ($defText -split '\r?\n' | ForEach-Object { [System.Net.WebUtility]::HtmlEncode($_) }) -join "<br>"
        }
    } else {
        $formattedDef = ($defText -split '\r?\n' | ForEach-Object { [System.Net.WebUtility]::HtmlEncode($_) }) -join "<br>"
    }

    $encTag = [System.Net.WebUtility]::HtmlEncode($Term)
    return @"
<div class="glossary-box" style="background: #e8f4fd; border-left: 4px solid #0366d6; padding: 14px 18px; border-radius: 6px; margin-bottom: 24px;">
    <div style="font-weight: bold; color: #0366d6; font-size: 15px; margin-bottom: 8px;">📖 用語解説: $encTag</div>
    <div class="glossary-content" style="font-size: 13px; color: #24292e; line-height: 1.6;">
        $formattedDef
    </div>
</div>
"@
}

# --- 最近の更新一覧ビュー生成関数 ---
function Get-RecentViewHtml {
    param (
        [string]$Lang = "ja"
    )

    Ensure-WikiIndexLoaded -TargetWikiDir $wikiDir
    $sorted = $script:WikiIndex | Sort-Object LastUpdated -Descending

    $titleLbl   = Get-LocalizedStr -Key "recent_updates_title" -Lang $Lang
    $descLbl    = Get-LocalizedStr -Key "recent_updates_desc" -Lang $Lang
    $colLastUpd = Get-LocalizedStr -Key "table_col_last_updated" -Lang $Lang
    $colTitle   = Get-LocalizedStr -Key "table_col_title" -Lang $Lang
    $colDomain  = Get-LocalizedStr -Key "table_col_domain" -Lang $Lang
    $colAuthor  = Get-LocalizedStr -Key "table_col_author" -Lang $Lang
    $colStatus  = Get-LocalizedStr -Key "table_col_status" -Lang $Lang

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
<h1>$titleLbl</h1>
<p>$descLbl</p>
<table class="okf-table">
    <thead>
        <tr><th>$colLastUpd</th><th>$colTitle</th><th>$colDomain</th><th>$colAuthor</th><th>$colStatus</th></tr>
    </thead>
    <tbody>
        $($rowsHtml -join "`n")
    </tbody>
</table>
"@
}

# --- タグ目録 & 絞り込みビュー生成関数 ---
function Get-TagsViewHtml {
    param (
        [string]$SelectedTag = "",
        [string]$Lang = "ja"
    )

    Ensure-WikiIndexLoaded -TargetWikiDir $wikiDir

    if ([string]::IsNullOrWhiteSpace($SelectedTag)) {
        $tagListTitle = Get-LocalizedStr -Key "tag_list_title" -Lang $Lang
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
<h1>$tagListTitle</h1>
<div class="tag-cloud">
    $($cloudHtml -join " ")
</div>
"@
    } else {
        $filtered = @($script:WikiIndex | Where-Object { $_.Tags -contains $SelectedTag })
        $encTag   = [System.Net.WebUtility]::HtmlEncode($SelectedTag)
        $tagResultsTitle = Get-LocalizedStr -Key "tag_results_title" -Lang $Lang -FormatArgs @($encTag)
        $backToTags      = Get-LocalizedStr -Key "back_to_tags" -Lang $Lang

        $glossaryBoxHtml = Render-GlossaryBoxHtml -Term $SelectedTag -TargetWikiDir $wikiDir

        $cardsHtml = foreach ($item in $filtered) {
            $relUri = "/" + [Uri]::EscapeUriString($item.RelPath.Replace('\', '/'))
            $title  = [System.Net.WebUtility]::HtmlEncode($item.Title)
            $desc   = [System.Net.WebUtility]::HtmlEncode($item.Description)
            "<div class='search-item'><h3><a href='$relUri'>$title</a></h3><p>$desc</p></div>"
        }

        return @"
<h1>$tagResultsTitle</h1>
<p><a href="/tags">$backToTags</a></p>
$glossaryBoxHtml
<div class="tag-results">
    $($cardsHtml -join "`n")
</div>
"@
    }
}

# --- 品質・メンテナンスダッシュボード生成関数 ---
function Render-DocList {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param (
        $docArray,
        [string]$emptyMsg
    )
    if ($null -eq $docArray) { return "<p class='empty-msg'>$emptyMsg</p>" }
    $arr = @($docArray)
    if ($arr.Count -eq 0) { return "<p class='empty-msg'>$emptyMsg</p>" }
    $items = foreach ($item in $arr) {
        if ($null -eq $item) { continue }
        $relUri  = "/" + [Uri]::EscapeUriString($item.RelPath.Replace('\', '/'))
        $title   = [System.Net.WebUtility]::HtmlEncode($item.Title)
        $lastUpd = if ($item.LastUpdated -is [DateTime]) { $item.LastUpdated.ToString("yyyy-MM-dd") } else { $item.LastUpdated }
        "<li><a href='$relUri'>$title</a> <span class='muted'>($lastUpd)</span></li>"
    }
    if (-not $items -or $items.Count -eq 0) { return "<p class='empty-msg'>$emptyMsg</p>" }
    return "<ul>" + ($items -join "") + "</ul>"
}

function Get-MaintenanceViewHtml {
    param (
        [string]$Lang = "ja"
    )

    Ensure-WikiIndexLoaded -TargetWikiDir $wikiDir
    $now = Get-Date

    $staleDocs      = @($script:WikiIndex | Where-Object { $_.Status -eq "active" -and ($now - $_.LastUpdated).TotalDays -ge 365 })
    $draftDocs      = @($script:WikiIndex | Where-Object { $_.Status -eq "draft" })
    $deprecatedDocs = @($script:WikiIndex | Where-Object { $_.Status -eq "deprecated" })

    $maintTitle   = Get-LocalizedStr -Key "maint_dashboard_title" -Lang $Lang
    $maintDesc    = Get-LocalizedStr -Key "maint_dashboard_desc" -Lang $Lang
    $maintStale   = Get-LocalizedStr -Key "maint_stale_docs" -Lang $Lang
    $maintDraft   = Get-LocalizedStr -Key "maint_drafts" -Lang $Lang
    $maintDep     = Get-LocalizedStr -Key "maint_deprecated" -Lang $Lang
    $maintNoDocs  = Get-LocalizedStr -Key "maint_no_docs" -Lang $Lang

    return @"
<h1>$maintTitle</h1>
<p>$maintDesc</p>

<div class="maint-section warning-box">
    <h2>$maintStale</h2>
    $(Render-DocList $staleDocs $maintNoDocs)
</div>

<div class="maint-section info-box">
    <h2>$maintDraft</h2>
    $(Render-DocList $draftDocs $maintNoDocs)
</div>

<div class="maint-section danger-box">
    <h2>$maintDep</h2>
    $(Render-DocList $deprecatedDocs $maintNoDocs)
</div>
"@
}

# --- 著者一覧ビュー生成関数 ---
function Get-AuthorsViewHtml {
    param (
        [string]$SelectedAuthor = "",
        [string]$Lang = "ja"
    )

    Ensure-WikiIndexLoaded -TargetWikiDir $wikiDir

    if ([string]::IsNullOrWhiteSpace($SelectedAuthor)) {
        $authorListTitle = Get-LocalizedStr -Key "author_list_title" -Lang $Lang
        $authors = @($script:WikiIndex | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Author) } | Group-Object Author)

        $listHtml = foreach ($g in ($authors | Sort-Object Name)) {
            $encAuthor = [System.Net.WebUtility]::HtmlEncode($g.Name)
            $urlAuthor = [Uri]::EscapeDataString($g.Name)
            $count     = $g.Count
            $itemsText = Get-LocalizedStr -Key "items_count" -Lang $Lang -FormatArgs @($count)
            "<li><a href='/authors?name=$urlAuthor'>👤 $encAuthor</a> <span class='muted'>($itemsText)</span></li>"
        }

        return @"
<h1>$authorListTitle</h1>
<ul>
    $($listHtml -join "`n")
</ul>
"@
    } else {
        $filtered  = @($script:WikiIndex | Where-Object { $_.Author -eq $SelectedAuthor })
        $encAuthor = [System.Net.WebUtility]::HtmlEncode($SelectedAuthor)
        $authorResTitle = Get-LocalizedStr -Key "author_results_title" -Lang $Lang -FormatArgs @($encAuthor)
        $backToAuthors  = Get-LocalizedStr -Key "back_to_authors" -Lang $Lang

        $itemsHtml = foreach ($item in $filtered) {
            $relUri = "/" + [Uri]::EscapeUriString($item.RelPath.Replace('\', '/'))
            $title  = [System.Net.WebUtility]::HtmlEncode($item.Title)
            "<li><a href='$relUri'>$title</a></li>"
        }

        return @"
<h1>$authorResTitle</h1>
<p><a href="/authors">$backToAuthors</a></p>
<ul>
    $($itemsHtml -join "`n")
</ul>
"@
    }
}

# --- 検索ビュー生成関数 ---
function Get-SearchViewHtml {
    param (
        [string]$Query = "",
        [string]$StatusFilter = "active",
        [string]$DomainFilter = "",
        [string]$Lang = "ja"
    )

    if ([string]::IsNullOrWhiteSpace($StatusFilter)) { $StatusFilter = "active" }
    $stFilterLower = $StatusFilter.ToLower().Trim()

    $parsedQuery = Split-SearchQueryTerms -Query $Query
    $keywords = if ($parsedQuery.IncludeKeywords -and $parsedQuery.IncludeKeywords.Count -gt 0) {
        @($parsedQuery.IncludeKeywords)
    } elseif (-not [string]::IsNullOrWhiteSpace($parsedQuery.CleanQuery)) {
        @($parsedQuery.CleanQuery -split '\s+' | Where-Object { $_ -ne "" })
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

    $searchScoreLbl  = Get-LocalizedStr -Key "search_score" -Lang $Lang
    $domainPrefixLbl = Get-LocalizedStr -Key "search_domain_prefix" -Lang $Lang
    $authorPrefixLbl = Get-LocalizedStr -Key "metadata_author" -Lang $Lang
    $lastUpdPrefixLbl = Get-LocalizedStr -Key "metadata_last_updated" -Lang $Lang

    $resultsHtmlList = foreach ($r in $sortedResults) {
        $item   = $r.Meta
        $relUri = "/" + [Uri]::EscapeUriString($item.RelPath.Replace('\', '/'))

        $titleHtml = Get-HighlightText -Text $item.Title -Keywords $keywords
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
                if ($t -isnot [string] -or [string]::IsNullOrWhiteSpace($t)) { continue }
                $encT = [System.Net.WebUtility]::HtmlEncode([string]$t)
                "<span class='tag-badge'>🏷️ $encT</span>"
            }
            $tagsHtml = "<div class='okf-tags' style='margin-top:4px;'>" + ($badges -join " ") + "</div>"
        }

        $scoreHtml = if ($r.Score -gt 0) {
            $scoreText = [string]::Format($searchScoreLbl, $r.Score)
            "<span style='font-size:12px; color:#6a737d; margin-left:10px;'>$scoreText</span>"
        } else { "" }

        @"
<div class="search-item" style="border-bottom: 1px solid #e1e4e8; padding: 14px 0;">
    <h3 style="margin: 0 0 6px 0; font-size: 16px;">
        <a href="$relUri">$titleHtml</a> $statusBadge $scoreHtml
    </h3>
    <div style="font-size: 12px; color: #586069; margin-bottom: 6px;">
        $domainPrefixLbl$domainEnc | $lastUpdPrefixLbl$lastUpd | $authorPrefixLbl$authorEnc
    </div>
    $tagsHtml
    <p style="margin: 8px 0 0 0; font-size: 13px; color: #444; background: #f8f9fa; padding: 6px 10px; border-left: 3px solid #0366d6; border-radius: 2px;">
        ... $snipHtml ...
    </p>
</div>
"@
    }

    $resultsTitleLbl = Get-LocalizedStr -Key "search_results_title" -Lang $Lang -FormatArgs @($sortedResults.Count)
    $keyHolderLbl    = Get-LocalizedStr -Key "search_keyword_label" -Lang $Lang
    $statusLbl       = Get-LocalizedStr -Key "search_status_label" -Lang $Lang
    $stActiveLbl     = Get-LocalizedStr -Key "search_status_active" -Lang $Lang
    $stDraftLbl      = Get-LocalizedStr -Key "search_status_draft" -Lang $Lang
    $stDepLbl        = Get-LocalizedStr -Key "search_status_dep" -Lang $Lang
    $stAllLbl        = Get-LocalizedStr -Key "search_status_all" -Lang $Lang
    $domainLbl       = Get-LocalizedStr -Key "search_domain_label" -Lang $Lang
    $domainHolderLbl = Get-LocalizedStr -Key "search_domain_placeholder" -Lang $Lang
    $searchBtnLbl    = Get-LocalizedStr -Key "search_btn" -Lang $Lang
    $noResultsLbl    = Get-LocalizedStr -Key "search_no_results" -Lang $Lang
    $indexingSearchingJs = Get-LocalizedStr -Key "indexing_searching" -Lang $Lang

    $resultsContent = if ($sortedResults.Count -gt 0) {
        $resultsHtmlList -join "`n"
    } else {
        "<p style='color: #666; margin-top: 20px;'>$noResultsLbl</p>"
    }

    return @"
<h1>$resultsTitleLbl</h1>
<div style="background: #f6f8fa; padding: 16px; border: 1px solid #e1e4e8; border-radius: 6px; margin-bottom: 20px;">
    <form action="/search" method="GET" accept-charset="UTF-8" style="display: flex; flex-wrap: wrap; gap: 10px; align-items: center;">
        <div style="flex: 1; min-width: 200px;">
            <input type="text" name="q" value="$encQuery" placeholder="$keyHolderLbl" style="width: 100%; padding: 6px 10px; font-size: 14px; border: 1px solid #ccc; border-radius: 4px;">
        </div>
        <div>
            <label style="font-size: 12px; font-weight: bold; color: #586069;">$statusLbl</label>
            <select name="status" style="padding: 6px 10px; font-size: 13px; border: 1px solid #ccc; border-radius: 4px;">
                <option value="active" $optActive>$stActiveLbl</option>
                <option value="draft" $optDraft>$stDraftLbl</option>
                <option value="deprecated" $optDeprecated>$stDepLbl</option>
                <option value="all" $optAll>$stAllLbl</option>
            </select>
        </div>
        <div>
            <label style="font-size: 12px; font-weight: bold; color: #586069;">$domainLbl</label>
            <input type="text" name="domain" value="$encDomain" placeholder="$domainHolderLbl" style="padding: 6px 10px; font-size: 13px; border: 1px solid #ccc; border-radius: 4px; width: 140px;">
        </div>
        <div>
            <button type="submit" id="searchSubmitBtn" style="padding: 6px 16px; font-size: 14px; background: #0366d6; color: #fff; border: none; border-radius: 4px; cursor: pointer;">🔍 $searchBtnLbl</button>
        </div>
    </form>
    <div id="searchProgressBanner" style="display: none; margin-top: 12px; padding: 8px 12px; background: #e8f4fd; border: 1px solid #c8e1ff; border-radius: 4px; color: #0366d6; font-size: 13px; align-items: center; gap: 8px;">
        <span class="indexing-spinner" style="display:inline-block; width:14px; height:14px; border:2px solid #0366d6; border-top-color:transparent; border-radius:50%; animation:spin 0.8s linear infinite;"></span>
        <span id="searchProgressText">$indexingSearchingJs</span>
    </div>
</div>
<script>
(function() {
    var form = document.querySelector('form[action="/search"]');
    if (form) {
        form.addEventListener('submit', function() {
            var btn = document.getElementById('searchSubmitBtn');
            var banner = document.getElementById('searchProgressBanner');
            if (btn) { btn.disabled = true; }
            if (banner) { banner.style.display = 'flex'; }
        });
    }
})();
</script>
<div class="search-results">
    $resultsContent
</div>
"@
}

function Get-ChatWidgetHtml {
    param (
        [string]$Lang = "ja"
    )

    $btnTitle       = Get-LocalizedStr -Key "chat_widget_btn" -Lang $Lang
    $headerTitle    = Get-LocalizedStr -Key "chat_header_title" -Lang $Lang
    $expandTitle    = Get-LocalizedStr -Key "chat_expand" -Lang $Lang
    $collapseTitle  = Get-LocalizedStr -Key "chat_collapse" -Lang $Lang
    $clearTitle     = Get-LocalizedStr -Key "chat_clear_history" -Lang $Lang
    $modeLbl        = Get-LocalizedStr -Key "chat_mode_label" -Lang $Lang
    $inclCurrLbl    = Get-LocalizedStr -Key "chat_include_current" -Lang $Lang
    $welcomeMsg     = Get-LocalizedStr -Key "chat_welcome_msg" -Lang $Lang
    $inputHolder    = Get-LocalizedStr -Key "chat_input_placeholder" -Lang $Lang
    $sendBtnLbl     = Get-LocalizedStr -Key "chat_send_btn" -Lang $Lang
    $resetHistoryJs = Get-LocalizedStr -Key "chat_reset_history" -Lang $Lang
    $thinkFastJs    = Get-LocalizedStr -Key "chat_thinking_fast" -Lang $Lang
    $thinkAgentJs   = Get-LocalizedStr -Key "chat_thinking_agent" -Lang $Lang
    $commErrorJs    = Get-LocalizedStr -Key "chat_comm_error" -Lang $Lang
    $errorPrefixJs  = Get-LocalizedStr -Key "chat_error_prefix" -Lang $Lang
    $agentThinkJs   = Get-LocalizedStr -Key "chat_agent_thinking" -Lang $Lang
    $sourceDocsJs   = Get-LocalizedStr -Key "chat_source_docs" -Lang $Lang
    $sourceEmptyJs  = Get-LocalizedStr -Key "chat_source_empty" -Lang $Lang
    $copyBtnJs      = Get-LocalizedStr -Key "chat_copy_btn" -Lang $Lang
    $copyDoneJs     = Get-LocalizedStr -Key "chat_copy_completed" -Lang $Lang

    $widget = @"
    <!-- Floating Chat Widget -->
    <button id="okfChatBtn" class="chat-widget-btn">$btnTitle</button>
    <div id="okfChatBox" class="chat-box">
        <div class="chat-header">
            <span>$headerTitle</span>
            <div class="chat-header-actions">
                <button id="okfChatExpandBtn" class="chat-header-expand" title="ウィンドウを拡大/縮小">$expandTitle</button>
                <button id="okfChatClearBtn" class="chat-header-clear" title="会話履歴をクリア">$clearTitle</button>
                <button id="okfChatCloseBtn" class="chat-header-close">✕</button>
            </div>
        </div>
        <div class="chat-mode-selector">
            <span class="mode-label">$modeLbl</span>
            <label><input type="radio" name="okfRagMode" value="fast" checked> ⚡ Fast</label>
            <label><input type="radio" name="okfRagMode" value="agentic"> 🧠 Agentic</label>
            <label style="margin-left: auto; color: #24292e; font-weight: normal; font-size: 12px; cursor: pointer; display: flex; align-items: center; gap: 4px;"><input type="checkbox" id="okfIncludeCurrentPage" checked> $inclCurrLbl</label>
        </div>
        <div id="okfChatMessages" class="chat-messages">
            <div class="chat-msg assistant">$welcomeMsg</div>
        </div>
        <div class="chat-input-area">
            <input type="text" id="okfChatInput" placeholder="$inputHolder" />
            <button id="okfChatSendBtn">$sendBtnLbl</button>
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
                        expandBtn.textContent = "$collapseTitle";
                    } else {
                        expandBtn.textContent = "$expandTitle";
                    }
                });
            }

            if (clearBtn) {
                clearBtn.addEventListener("click", function() {
                    chatHistory = [];
                    msgs.innerHTML = '<div class="chat-msg assistant">$resetHistoryJs</div>';
                });
            }

            function escapeHtml(str) {
                return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
            }

            function parseInline(str) {
                var s = escapeHtml(str);
                s = s.replace(/\*\*([^*]+)\*\*/g, "<strong>`$1</strong>");
                s = s.replace(/`([^`]+)`/g, "<code>`$1</code>");
                s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g, "<a href='`$2' target='_blank'>`$1</a>");
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
                        // Restore code blocks inside table cells if any
                        parts[k] = parts[k].replace(/___CODEBLOCK_(\d+)___/g, function(m, num) {
                            return codeBlocks[parseInt(num, 10)] || m;
                        });
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
                var finalHtml = parts.join("");
                // Safety net: ensure any remaining placeholder is replaced
                finalHtml = finalHtml.replace(/___CODEBLOCK_(\d+)___/g, function(m, num) {
                    return codeBlocks[parseInt(num, 10)] || m;
                });
                return finalHtml;
            }

            function createAssistantMsgBox() {
                var div = document.createElement("div");
                div.className = "chat-msg assistant";
                div.innerHTML = "<details class='chat-thinking' style='display:none;'><summary></summary><ul></ul></details>" +
                                "<div class='chat-content'></div>" +
                                "<div class='chat-sources' style='display:none;'></div>" +
                                "<div class='chat-msg-actions' style='display:none;'></div>";
                msgs.appendChild(div);
                msgs.scrollTop = msgs.scrollHeight;
                return {
                    root: div,
                    thinking: div.querySelector(".chat-thinking"),
                    thinkingSummary: div.querySelector(".chat-thinking summary"),
                    thinkingUl: div.querySelector(".chat-thinking ul"),
                    content: div.querySelector(".chat-content"),
                    sources: div.querySelector(".chat-sources"),
                    actions: div.querySelector(".chat-msg-actions")
                };
            }

            function finalizeAssistantMsg(box, answerText, sources, thinkingLogs) {
                if (thinkingLogs && thinkingLogs.length > 0) {
                    box.thinking.style.display = "block";
                    box.thinkingSummary.textContent = "$agentThinkJs".replace("{0}", thinkingLogs.length);
                    box.thinkingUl.innerHTML = "";
                    thinkingLogs.forEach(function(item) {
                        var li = document.createElement("li");
                        li.textContent = item;
                        box.thinkingUl.appendChild(li);
                    });
                }
                box.content.innerHTML = renderMarkdown(answerText);
                if (sources && sources.length > 0) {
                    var srcHtml = "$sourceDocsJs<ul style='margin: 4px 0 0 16px; padding: 0;'>";
                    sources.forEach(function(s) {
                        var dateInfo = s.lastUpdated ? " (" + escapeHtml(s.lastUpdated) + ")" : "";
                        srcHtml += "<li>📄 <a href='" + escapeHtml(s.relUri) + "' target='_blank'>" + escapeHtml(s.title || s.relPath) + "</a>" + dateInfo + "</li>";
                    });
                    srcHtml += "</ul>";
                    box.sources.innerHTML = srcHtml;
                    box.sources.style.display = "block";
                } else {
                    box.sources.innerHTML = "$sourceEmptyJs";
                    box.sources.style.display = "block";
                }

                var copyBtn = document.createElement("button");
                copyBtn.className = "chat-copy-btn";
                copyBtn.innerHTML = "$copyBtnJs";
                copyBtn.addEventListener("click", function() {
                    var performCopy = function() {
                        copyBtn.innerHTML = "$copyDoneJs";
                        setTimeout(function() { copyBtn.innerHTML = "$copyBtnJs"; }, 1500);
                    };
                    if (navigator.clipboard && navigator.clipboard.writeText) {
                        navigator.clipboard.writeText(answerText).then(performCopy).catch(function() {
                            var ta = document.createElement("textarea");
                            ta.value = answerText;
                            document.body.appendChild(ta);
                            ta.select();
                            document.execCommand("copy");
                            document.body.removeChild(ta);
                            performCopy();
                        });
                    } else {
                        var ta = document.createElement("textarea");
                        ta.value = answerText;
                        document.body.appendChild(ta);
                        ta.select();
                        document.execCommand("copy");
                        document.body.removeChild(ta);
                        performCopy();
                    }
                });
                box.actions.innerHTML = "";
                box.actions.appendChild(copyBtn);
                box.actions.style.display = "flex";
                msgs.scrollTop = msgs.scrollHeight;
            }

            function appendMsg(role, text, sources, thinkingLog) {
                var div = document.createElement("div");
                div.className = "chat-msg " + role;
                if (role === "user") {
                    div.textContent = text;
                    msgs.appendChild(div);
                    msgs.scrollTop = msgs.scrollHeight;
                } else {
                    var box = createAssistantMsgBox();
                    finalizeAssistantMsg(box, text, sources, thinkingLog);
                }
            }

            function sendMsg() {
                var q = input.value.trim();
                if (!q) return;

                var modeRadio = document.querySelector('input[name="okfRagMode"]:checked');
                var mode = modeRadio ? modeRadio.value : "fast";
                var includeCurrentPage = document.getElementById("okfIncludeCurrentPage") ? document.getElementById("okfIncludeCurrentPage").checked : true;
                var currentPath = decodeURIComponent(location.pathname).replace(/^\//, "");

                appendMsg("user", q);
                input.value = "";
                sendBtn.disabled = true;

                var assistantBox = createAssistantMsgBox();
                assistantBox.content.textContent = (mode === "agentic" ? "$thinkAgentJs" : "$thinkFastJs");

                var thinkingLogs = [];
                var fullAnswer = "";

                fetch("/api/chat", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ mode: mode, message: q, history: chatHistory, includeCurrentPage: includeCurrentPage, currentRelPath: currentPath, lang: "$Lang", stream: true })
                }).then(function(res) {
                    var contentType = res.headers.get("content-type") || "";

                    if (contentType.indexOf("text/event-stream") !== -1 && res.body && res.body.getReader) {
                        // --- SSE ストリーム処理 ---
                        var reader = res.body.getReader();
                        var decoder = new TextDecoder("utf-8");
                        var streamBuffer = "";
                        var hasStartedToken = false;

                        function readStream() {
                            return reader.read().then(function(result) {
                                if (result.done) {
                                    return;
                                }
                                streamBuffer += decoder.decode(result.value, { stream: true });
                                var lines = streamBuffer.split("\n\n");
                                streamBuffer = lines.pop(); // 未完結のチャンクをバッファに残す

                                for (var i = 0; i < lines.length; i++) {
                                    var line = lines[i].trim();
                                    if (line.indexOf("data: ") === 0) {
                                        var jsonStr = line.substring(6).trim();
                                        if (jsonStr === "[DONE]") continue;
                                        try {
                                            var ev = JSON.parse(jsonStr);
                                            if (ev.type === "thinking") {
                                                thinkingLogs.push(ev.content);
                                                assistantBox.thinking.style.display = "block";
                                                assistantBox.thinkingSummary.textContent = "$agentThinkJs".replace("{0}", thinkingLogs.length);
                                                var li = document.createElement("li");
                                                li.textContent = ev.content;
                                                assistantBox.thinkingUl.appendChild(li);
                                                msgs.scrollTop = msgs.scrollHeight;
                                            } else if (ev.type === "token") {
                                                if (!hasStartedToken) {
                                                    hasStartedToken = true;
                                                    assistantBox.content.innerHTML = "";
                                                }
                                                fullAnswer += ev.content;
                                                assistantBox.content.innerHTML = renderMarkdown(fullAnswer);
                                                msgs.scrollTop = msgs.scrollHeight;
                                            } else if (ev.type === "done") {
                                                var finalAnswerText = ev.answer || fullAnswer;
                                                finalizeAssistantMsg(assistantBox, finalAnswerText, ev.sources, ev.thinkingLog || thinkingLogs);
                                                chatHistory.push({ role: "user", content: q });
                                                chatHistory.push({ role: "assistant", content: finalAnswerText });
                                            } else if (ev.type === "error") {
                                                assistantBox.content.innerHTML = "<span style='color:#cb2431;'>$errorPrefixJs" + escapeHtml(ev.message || "Unknown error") + "</span>";
                                            }
                                        } catch(e) { }
                                    }
                                }
                                return readStream();
                            });
                        }
                        return readStream();
                    } else {
                        // --- 一括 JSON フォールバック処理 ---
                        return res.json().then(function(data) {
                            if (data.error) {
                                assistantBox.content.innerHTML = "<span style='color:#cb2431;'>$errorPrefixJs" + escapeHtml(data.message || data.error) + "</span>";
                            } else {
                                finalizeAssistantMsg(assistantBox, data.answer, data.sources, data.thinkingLog);
                                chatHistory.push({ role: "user", content: q });
                                chatHistory.push({ role: "assistant", content: data.answer });
                            }
                        });
                    }
                }).catch(function(err) {
                    assistantBox.content.innerHTML = "<span style='color:#cb2431;'>$commErrorJs</span>";
                }).finally(function() {
                    sendBtn.disabled = false;
                });
            }

            sendBtn.addEventListener("click", sendMsg);
            input.addEventListener("keypress", function(e) { if (e.key === "Enter") sendMsg(); });
        });
    </script>
"@
    return $widget
}

# --- システム設定データ取得・準備関数 ---
function Get-SettingsViewData {
    param (
        [string]$Lang = "ja"
    )

    $config = Get-ConfigJson -TargetScriptDir $scriptDir

    $editorEnabledChecked = if ($config.editor -and $null -ne $config.editor.enabled) {
        if ($config.editor.enabled -eq $true) { "checked" } else { "" }
    } else { "checked" }
    $editorType           = if ($config.editor -and $config.editor.type) { [string]$config.editor.type } else { "toastui" }
    $editorMaxBackups     = if ($config.editor -and $null -ne $config.editor.maxBackups) { [int]$config.editor.maxBackups } else { 3 }

    $prebuildChecked   = if ($config.search -and $config.search.prebuildIndex -eq $true) { "checked" } else { "" }
    $useCacheChecked   = if ($config.search -and $config.search.useCache -eq $true) { "checked" } else { "" }
    $cacheFolder       = if ($config.search -and -not [string]::IsNullOrWhiteSpace($config.search.cacheFolder)) { [System.Net.WebUtility]::HtmlEncode($config.search.cacheFolder) } else { ".cache" }

    $localMachineId    = Get-MachineFingerprint
    $ragEnabledChecked = if ($config.rag -and $config.rag.enabled -eq $true) { "checked" } else { "" }
    $apiUrl            = if ($config.rag -and $config.rag.apiUrl) { [System.Net.WebUtility]::HtmlEncode($config.rag.apiUrl) } else { "http://localhost:11434/v1" }
    $model             = if ($config.rag -and $config.rag.model) { [System.Net.WebUtility]::HtmlEncode($config.rag.model) } else { "qwen2.5-coder-7b-instruct" }
    $userEmail         = if ($config.rag -and $config.rag.userEmail) { [System.Net.WebUtility]::HtmlEncode($config.rag.userEmail) } else { "" }

    $cachedCount = if ($null -ne $script:WikiIndex) { $script:WikiIndex.Count } else { 0 }
    $notRunText  = Get-LocalizedStr -Key "settings_not_run" -Lang $Lang
    $lastScanStr = if ($script:WikiIndexLastScan -and $script:WikiIndexLastScan -gt [DateTime]::MinValue) { $script:WikiIndexLastScan.ToString("yyyy-MM-dd HH:mm:ss") } else { $notRunText }

    $rawIndexingInProg = Get-LocalizedStr -Key "indexing_in_progress" -Lang $Lang -FormatArgs @("__INDEX_CURR__", "__INDEX_TOTAL__")

    return [PSCustomObject]@{
        Lang              = $Lang
        EditorEnabledChecked = $editorEnabledChecked
        EditorType           = $editorType
        EditorMaxBackups     = $editorMaxBackups
        PrebuildChecked   = $prebuildChecked
        UseCacheChecked   = $useCacheChecked
        CacheFolder       = $cacheFolder
        LocalMachineId    = $localMachineId
        RagEnabledChecked = $ragEnabledChecked
        ApiUrl            = $apiUrl
        Model             = $model
        UserEmail         = $userEmail

        TitleLbl          = Get-LocalizedStr -Key "settings_title" -Lang $Lang
        DescLbl           = Get-LocalizedStr -Key "settings_desc" -Lang $Lang
        EditorTitleLbl    = Get-LocalizedStr -Key "settings_editor_title" -Lang $Lang
        EditorEnableLbl   = Get-LocalizedStr -Key "settings_editor_enable" -Lang $Lang
        EditorDescLbl     = Get-LocalizedStr -Key "settings_editor_desc" -Lang $Lang
        EditorTypeLbl     = Get-LocalizedStr -Key "settings_editor_type" -Lang $Lang
        EditorTypeDescLbl = Get-LocalizedStr -Key "settings_editor_type_desc" -Lang $Lang
        EditorTypeToastUiLbl  = Get-LocalizedStr -Key "settings_editor_type_toastui" -Lang $Lang
        EditorTypeTextAreaLbl = Get-LocalizedStr -Key "settings_editor_type_textarea" -Lang $Lang
        EditorMaxBackupsLbl = Get-LocalizedStr -Key "settings_editor_max_backups" -Lang $Lang
        SearchTitleLbl    = Get-LocalizedStr -Key "settings_search_title" -Lang $Lang
        PrebuildLbl       = Get-LocalizedStr -Key "settings_prebuild_label" -Lang $Lang
        DefOffLbl         = Get-LocalizedStr -Key "settings_default_off" -Lang $Lang
        PrebuildDesc      = Get-LocalizedStr -Key "settings_prebuild_desc" -Lang $Lang
        CacheLbl          = Get-LocalizedStr -Key "settings_cache_label" -Lang $Lang
        CacheDesc         = Get-LocalizedStr -Key "settings_cache_desc" -Lang $Lang
        CacheFoldLbl      = Get-LocalizedStr -Key "settings_cache_folder" -Lang $Lang
        CachedStatLbl     = Get-LocalizedStr -Key "settings_cached_status" -Lang $Lang -FormatArgs @($cachedCount, $lastScanStr)
        RebuildBtnLbl     = Get-LocalizedStr -Key "settings_rebuild_btn" -Lang $Lang
        RagTitleLbl       = Get-LocalizedStr -Key "settings_rag_title" -Lang $Lang
        RagEnableLbl      = Get-LocalizedStr -Key "settings_rag_enable" -Lang $Lang
        MachineIdLbl      = Get-LocalizedStr -Key "settings_machine_id" -Lang $Lang
        CopyMachineLbl    = Get-LocalizedStr -Key "settings_copy_machine_id" -Lang $Lang
        CopiedLbl         = Get-LocalizedStr -Key "settings_copied" -Lang $Lang
        ActCodeLbl        = Get-LocalizedStr -Key "settings_act_code" -Lang $Lang
        ActHolderLbl      = Get-LocalizedStr -Key "settings_act_code_holder" -Lang $Lang
        ActDescLbl        = Get-LocalizedStr -Key "settings_act_desc" -Lang $Lang
        ApiUrlLbl         = Get-LocalizedStr -Key "settings_api_url" -Lang $Lang
        ModelLbl          = Get-LocalizedStr -Key "settings_model" -Lang $Lang
        SaveBtnLbl        = Get-LocalizedStr -Key "settings_save_btn" -Lang $Lang
        ServerTitleLbl    = Get-LocalizedStr -Key "settings_server_title" -Lang $Lang
        ServerDescLbl     = Get-LocalizedStr -Key "settings_shutdown_desc" -Lang $Lang
        ShutdownBtnLbl    = Get-LocalizedStr -Key "settings_shutdown_btn" -Lang $Lang
        SavedSuccessJs    = ConvertTo-JsString (Get-LocalizedStr -Key "settings_saved_success" -Lang $Lang)
        SavedErrorJs      = ConvertTo-JsString (Get-LocalizedStr -Key "settings_saved_error" -Lang $Lang)
        CommErrorJs       = ConvertTo-JsString (Get-LocalizedStr -Key "settings_comm_error" -Lang $Lang)
        RebuildRunJs      = ConvertTo-JsString (Get-LocalizedStr -Key "settings_rebuild_running" -Lang $Lang)
        RebuildStartJs    = ConvertTo-JsString (Get-LocalizedStr -Key "settings_rebuild_start" -Lang $Lang)
        RebuildFailJs     = ConvertTo-JsString (Get-LocalizedStr -Key "settings_rebuild_failed" -Lang $Lang)
        ClearAllBtnLbl    = Get-LocalizedStr -Key "settings_clear_all_cache" -Lang $Lang
        ClearAllDesc      = Get-LocalizedStr -Key "settings_clear_all_desc" -Lang $Lang
        ClearAllConfJs    = ConvertTo-JsString (Get-LocalizedStr -Key "settings_clear_all_confirm" -Lang $Lang)
        ClearAllRunJs     = ConvertTo-JsString (Get-LocalizedStr -Key "settings_clear_all_running" -Lang $Lang)
        ClearAllFailJs    = ConvertTo-JsString (Get-LocalizedStr -Key "settings_clear_all_failed" -Lang $Lang)
        IndexingInProgJs  = ConvertTo-JsString $rawIndexingInProg
    }
}

# --- システム設定 UI コンポーネント描画サブ関数 ---
function Render-SettingsEditorCard {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param ([PSCustomObject]$Data)

    $selToastUi  = if ($Data.EditorType -eq "toastui") { "selected" } else { "" }
    $selTextarea = if ($Data.EditorType -eq "textarea") { "selected" } else { "" }

    return @"
        <div class="okf-card">
            <div class="okf-card-header">$($Data.EditorTitleLbl)</div>
            <div style="margin-top: 15px; display: flex; flex-direction: column; gap: 12px;">
                <label style="display: flex; align-items: center; gap: 10px; cursor: pointer;">
                    <input type="checkbox" id="editorEnabled" name="editorEnabled" $($Data.EditorEnabledChecked)>
                    <span><strong>$($Data.EditorEnableLbl)</strong></span>
                </label>
                <div style="font-size: 13px; color: #586069; margin-left: 24px;">
                    $($Data.EditorDescLbl)
                </div>

                <div style="margin-left: 24px; margin-top: 5px;">
                    <label for="editorType" style="font-size: 13px; font-weight: bold;">$($Data.EditorTypeLbl)</label><br>
                    <select id="editorType" name="editorType" style="padding: 6px; border: 1px solid #ccc; border-radius: 4px; margin-top: 4px; font-size: 13px;">
                        <option value="toastui" $selToastUi>$($Data.EditorTypeToastUiLbl)</option>
                        <option value="textarea" $selTextarea>$($Data.EditorTypeTextAreaLbl)</option>
                    </select>
                    <div style="font-size: 12px; color: #666; margin-top: 2px;">$($Data.EditorTypeDescLbl)</div>
                </div>

                <div style="margin-left: 24px; margin-top: 5px;">
                    <label for="editorMaxBackups" style="font-size: 13px; font-weight: bold;">$($Data.EditorMaxBackupsLbl)</label><br>
                    <input type="number" id="editorMaxBackups" name="editorMaxBackups" value="$($Data.EditorMaxBackups)" min="0" max="100" style="width: 120px; padding: 6px; border: 1px solid #ccc; border-radius: 4px; margin-top: 4px;" required>
                </div>
            </div>
        </div>
"@
}

function Render-SettingsSearchCard {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param ([PSCustomObject]$Data)

    return @"
        <div class="okf-card">
            <div class="okf-card-header">$($Data.SearchTitleLbl)</div>
            <div style="margin-top: 15px; display: flex; flex-direction: column; gap: 12px;">
                <label style="display: flex; align-items: center; gap: 10px; cursor: pointer;">
                    <input type="checkbox" id="prebuildIndex" name="prebuildIndex" $($Data.PrebuildChecked)>
                    <span><strong>$($Data.PrebuildLbl)</strong> $($Data.DefOffLbl)</span>
                </label>
                <div style="font-size: 13px; color: #586069; margin-left: 24px;">
                    $($Data.PrebuildDesc)
                </div>

                <label style="display: flex; align-items: center; gap: 10px; cursor: pointer; margin-top: 8px;">
                    <input type="checkbox" id="useCache" name="useCache" $($Data.UseCacheChecked)>
                    <span><strong>$($Data.CacheLbl)</strong> $($Data.DefOffLbl)</span>
                </label>
                <div style="font-size: 13px; color: #586069; margin-left: 24px;">
                    $($Data.CacheDesc)
                </div>

                <div style="margin-left: 24px; margin-top: 5px;">
                    <label for="cacheFolder" style="font-size: 13px; font-weight: bold;">$($Data.CacheFoldLbl)</label><br>
                    <input type="text" id="cacheFolder" name="cacheFolder" value="$($Data.CacheFolder)" style="width: 250px; padding: 6px; border: 1px solid #ccc; border-radius: 4px; margin-top: 4px;" required>
                </div>
            </div>

            <div style="margin-top: 15px; padding-top: 15px; border-top: 1px solid #eaecef; font-size: 13px; color: #586069; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px;">
                <div>
                    <strong>$($Data.CachedStatLbl)</strong>
                </div>
                <div style="display: flex; gap: 8px;">
                    <button type="button" id="clearAllCacheBtn" onclick="clearAllCachesNow()" style="padding: 6px 12px; background: #fff; color: #d73a49; border: 1px solid #d1d5da; border-radius: 4px; cursor: pointer; font-weight: bold; display: inline-flex; align-items: center; gap: 4px;">
                        $($Data.ClearAllBtnLbl)
                    </button>
                    <button type="button" id="rebuildBtn" onclick="rebuildIndexNow()" style="padding: 6px 12px; background: #6c757d; color: white; border: none; border-radius: 4px; cursor: pointer; font-weight: bold;">
                        $($Data.RebuildBtnLbl)
                    </button>
                </div>
            </div>
            <div style="font-size: 12px; color: #6a737d; margin-top: 8px;">
                $($Data.ClearAllDesc)
            </div>
        </div>
"@
}

function Render-SettingsRagCard {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param ([PSCustomObject]$Data)

    return @"
        <div class="okf-card">
            <div class="okf-card-header">$($Data.RagTitleLbl)</div>
            <div style="margin-top: 15px; display: flex; flex-direction: column; gap: 14px;">
                <label style="display: flex; align-items: center; gap: 10px; cursor: pointer;">
                    <input type="checkbox" id="ragEnabled" name="ragEnabled" $($Data.RagEnabledChecked)>
                    <span><strong>$($Data.RagEnableLbl)</strong></span>
                </label>

                <!-- マシン ID 表示 ＆ コピー -->
                <div style="background: #f6f8fa; border: 1px solid #e1e4e8; border-radius: 6px; padding: 12px; margin-left: 24px;">
                    <div style="font-size: 12px; font-weight: bold; color: #586069; margin-bottom: 6px;">$($Data.MachineIdLbl)</div>
                    <div style="display: flex; align-items: center; gap: 10px;">
                        <code id="machineIdText" style="font-family: monospace; font-size: 14px; font-weight: bold; background: #fff; border: 1px solid #d1d5da; padding: 6px 12px; border-radius: 4px; color: #0366d6;">$($Data.LocalMachineId)</code>
                        <button type="button" onclick="copyMachineId(this)" style="padding: 6px 12px; font-size: 12px; background: #fff; border: 1px solid #d1d5da; border-radius: 4px; cursor: pointer; color: #24292e;">
                            $($Data.CopyMachineLbl)
                        </button>
                    </div>
                </div>

                <!-- アクティベーションコード入力欄 -->
                <div style="margin-left: 24px;">
                    <label for="activationCode" style="font-size: 13px; font-weight: bold;">$($Data.ActCodeLbl)</label><br>
                    <input type="text" id="activationCode" name="activationCode" placeholder="$($Data.ActHolderLbl)" style="width: 100%; max-width: 500px; padding: 7px 10px; font-family: monospace; font-size: 13px; border: 1px solid #ccc; border-radius: 4px; margin-top: 4px;">
                    <div style="font-size: 12px; color: #586069; margin-top: 4px;">
                        $($Data.ActDescLbl)
                    </div>
                </div>

                <div style="margin-left: 24px;">
                    <label for="userEmail" style="font-size: 13px; font-weight: bold;">メールアドレス (登録時に入力した場合のみ):</label><br>
                    <input type="email" id="userEmail" name="userEmail" value="$($Data.UserEmail)" placeholder="user@example.com" style="width: 100%; max-width: 350px; padding: 6px 10px; font-size: 13px; border: 1px solid #ccc; border-radius: 4px; margin-top: 4px;">
                </div>

                <div style="margin-left: 24px; display: flex; flex-direction: column; gap: 10px; margin-top: 4px;">
                    <div>
                        <label for="apiUrl" style="font-size: 13px; font-weight: bold;">$($Data.ApiUrlLbl)</label><br>
                        <input type="text" id="apiUrl" name="apiUrl" value="$($Data.ApiUrl)" style="width: 100%; max-width: 400px; padding: 6px; border: 1px solid #ccc; border-radius: 4px; margin-top: 4px;">
                    </div>
                    <div>
                        <label for="model" style="font-size: 13px; font-weight: bold;">$($Data.ModelLbl)</label><br>
                        <input type="text" id="model" name="model" value="$($Data.Model)" style="width: 100%; max-width: 400px; padding: 6px; border: 1px solid #ccc; border-radius: 4px; margin-top: 4px;">
                    </div>
                </div>
            </div>
        </div>
"@
}

function Render-SettingsServerCard {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param ([PSCustomObject]$Data)

    return @"
    <div class="okf-card" style="margin-top: 30px; border-color: #f5c6cb;">
        <div class="okf-card-header" style="color: #721c24;">$($Data.ServerTitleLbl)</div>
        <div style="margin-top: 12px; font-size: 13px; color: #586069;">
            $($Data.ServerDescLbl)
        </div>
        <div style="margin-top: 15px;">
            <button type="button" onclick="shutdownWikiServer()" style="padding: 8px 18px; background: #dc3545; color: white; border: none; border-radius: 6px; font-size: 13px; font-weight: bold; cursor: pointer;">
                $($Data.ShutdownBtnLbl)
            </button>
        </div>
    </div>
"@
}

function Render-SettingsScript {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param ([PSCustomObject]$Data)

    return @"
<script>
function copyMachineId(btn) {
    var mid = document.getElementById('machineIdText').innerText.trim();
    if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(mid).then(function() {
            var orig = btn.innerText;
            btn.innerText = '$($Data.CopiedLbl)';
            setTimeout(function() { btn.innerText = orig; }, 2000);
        });
    }
}
var toastTimer = null;
function showToast(msg, isError, duration) {
    var toast = document.getElementById('settingsToast');
    var toastMsg = document.getElementById('settingsToastMsg');
    if (toastTimer) {
        clearTimeout(toastTimer);
        toastTimer = null;
    }
    toast.style.display = 'block';
    toast.style.borderColor = isError ? '#dc3545' : '#28a745';
    toastMsg.style.color = isError ? '#721c24' : '#155724';
    toastMsg.innerText = msg;
    var dur = (typeof duration === 'number') ? duration : 4000;
    if (dur > 0) {
        toastTimer = setTimeout(function() {
            toast.style.display = 'none';
            toastTimer = null;
        }, dur);
    }
}

function saveSettings(e) {
    e.preventDefault();
    var saveBtn = document.getElementById('saveBtn');
    saveBtn.disabled = true;
    saveBtn.innerText = '...';

    var actCodeInput = document.getElementById('activationCode');
    var userEmailInput = document.getElementById('userEmail');

    var payload = {
        editor: {
            enabled: document.getElementById('editorEnabled').checked,
            type: document.getElementById('editorType').value,
            maxBackups: parseInt(document.getElementById('editorMaxBackups').value, 10) || 0
        },
        search: {
            prebuildIndex: document.getElementById('prebuildIndex').checked,
            useCache: document.getElementById('useCache').checked,
            cacheFolder: document.getElementById('cacheFolder').value.trim()
        },
        rag: {
            enabled: document.getElementById('ragEnabled').checked,
            apiUrl: document.getElementById('apiUrl').value.trim(),
            model: document.getElementById('model').value.trim(),
            userEmail: userEmailInput ? userEmailInput.value.trim() : ""
        }
    };
    if (actCodeInput && actCodeInput.value.trim()) {
        payload.rag.activationCode = actCodeInput.value.trim();
    }

    fetch('/api/config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    })
    .then(function(res) { return res.json(); })
    .then(function(data) {
        saveBtn.disabled = false;
        saveBtn.innerText = '$($Data.SaveBtnLbl)';
        if (data.success) {
            showToast('$($Data.SavedSuccessJs)', false);
        } else {
            showToast('$($Data.SavedErrorJs)' + (data.message || ''), true);
        }
    })
    .catch(function(err) {
        saveBtn.disabled = false;
        saveBtn.innerText = '$($Data.SaveBtnLbl)';
        showToast('$($Data.CommErrorJs)', true);
    });
}

function rebuildIndexNow() {
    var rebuildBtn = document.getElementById('rebuildBtn');
    if (rebuildBtn) {
        rebuildBtn.disabled = true;
        rebuildBtn.innerText = '$($Data.RebuildRunJs)';
    }
    showToast('$($Data.RebuildStartJs)', false, 0);

    var pollTimer = setInterval(function() {
        fetch('/api/indexing-status')
        .then(function(r) { return r.json(); })
        .then(function(st) {
            if (st && st.IsBuilding && st.Total > 0) {
                var txt = '$($Data.IndexingInProgJs)'.replace('__INDEX_CURR__', st.Current).replace('__INDEX_TOTAL__', st.Total);
                showToast(txt, false, 0);
            }
        })
        .catch(function() {});
    }, 400);

    fetch('/api/config?action=rebuild_index', { method: 'POST' })
    .then(function(res) { return res.json(); })
    .then(function(data) {
        clearInterval(pollTimer);
        if (rebuildBtn) {
            rebuildBtn.disabled = false;
            rebuildBtn.innerText = '$($Data.RebuildBtnLbl)';
        }
        if (data.success) {
            showToast('✅ ' + data.message, false, 3000);
            setTimeout(function() { location.reload(); }, 1200);
        } else {
            showToast('$($Data.RebuildFailJs)' + (data.message || ''), true, 5000);
        }
    })
    .catch(function(err) {
        clearInterval(pollTimer);
        if (rebuildBtn) {
            rebuildBtn.disabled = false;
            rebuildBtn.innerText = '$($Data.RebuildBtnLbl)';
        }
        showToast('$($Data.CommErrorJs)', true, 5000);
    });
}

function clearAllCachesNow() {
    if (!confirm('$($Data.ClearAllConfJs)')) {
        return;
    }
    var clearBtn = document.getElementById('clearAllCacheBtn');
    if (clearBtn) {
        clearBtn.disabled = true;
        clearBtn.innerText = '$($Data.ClearAllRunJs)';
    }
    showToast('$($Data.ClearAllRunJs)', false, 0);

    fetch('/api/config?action=clear_all_caches', { method: 'POST' })
    .then(function(res) { return res.json(); })
    .then(function(data) {
        if (clearBtn) {
            clearBtn.disabled = false;
            clearBtn.innerText = '$($Data.ClearAllBtnLbl)';
        }
        if (data.success) {
            showToast('✅ ' + data.message, false, 3000);
            setTimeout(function() { location.reload(); }, 1200);
        } else {
            showToast('$($Data.ClearAllFailJs)' + (data.message || ''), true, 5000);
        }
    })
    .catch(function(err) {
        if (clearBtn) {
            clearBtn.disabled = false;
            clearBtn.innerText = '$($Data.ClearAllBtnLbl)';
        }
        showToast('$($Data.CommErrorJs)', true, 5000);
    });
}
</script>
"@
}

# --- コントロールパネル ＆ ステラビュー ＆ タイムライン描画関数 ---

function Get-StellaControlPanelHtml {
    param (
        [string]$ActiveView = "stella",
        [string]$Lang = "ja"
    )

    Ensure-WikiIndexLoaded -TargetWikiDir $wikiDir

    $navStella    = Get-LocalizedStr -Key "stella_view_nav" -Lang $Lang
    $searchHolder = Get-LocalizedStr -Key "stella_search_holder" -Lang $Lang

    $stAll        = Get-LocalizedStr -Key "stella_status_all" -Lang $Lang
    $stActive     = Get-LocalizedStr -Key "stella_status_active" -Lang $Lang
    $stDraft      = Get-LocalizedStr -Key "stella_status_draft" -Lang $Lang
    $stDep        = Get-LocalizedStr -Key "stella_status_deprecated" -Lang $Lang
    $stArch       = Get-LocalizedStr -Key "stella_status_archived" -Lang $Lang
    $tagAll       = Get-LocalizedStr -Key "stella_tag_all" -Lang $Lang
    $resetBtnTxt  = Get-LocalizedStr -Key "stella_btn_reset" -Lang $Lang

    $preset3dTxt  = Get-LocalizedStr -Key "stella_preset_3d" -Lang $Lang
    $presetTopTxt = Get-LocalizedStr -Key "stella_preset_top" -Lang $Lang
    $presetTlTxt  = Get-LocalizedStr -Key "stella_preset_timeline" -Lang $Lang

    $allTags = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($item in $script:WikiIndex) {
        if ($item.Tags) {
            foreach ($t in $item.Tags) {
                if ($t -is [string] -and -not [string]::IsNullOrWhiteSpace($t)) { [void]$allTags.Add($t.Trim()) }
            }
        }
    }

    $tagOptions = foreach ($t in ($allTags | Sort-Object)) {
        $encT = [System.Net.WebUtility]::HtmlEncode($t)
        "<option value='$encT'>🏷️ $encT</option>"
    }
    $tagOptionsStr = $tagOptions -join ""

    return @"
<div class="stella-control-panel">
    <div class="stella-control-left">
        <span style="font-weight: bold; color: #58a6ff; font-size: 13px; margin-right: 4px;">$navStella</span>
        <div class="stella-preset-group">
            <button class="stella-preset-btn active" data-preset="3d" onclick="setStellaPreset('3d')" title="$preset3dTxt">$preset3dTxt</button>
            <button class="stella-preset-btn" data-preset="top" onclick="setStellaPreset('top')" title="$presetTopTxt">$presetTopTxt</button>
            <button class="stella-preset-btn" data-preset="timeline" onclick="setStellaPreset('timeline')" title="$presetTlTxt">$presetTlTxt</button>
        </div>
        <button class="stella-reset-btn" onclick="resetStellaView()" title="$resetBtnTxt">$resetBtnTxt</button>
    </div>
    <div class="stella-control-center">
        <input type="text" id="stellaSearchInput" placeholder="$searchHolder" class="stella-input">
        <select id="stellaStatusSelect" class="stella-select">
            <option value="all">$stAll</option>
            <option value="active">$stActive</option>
            <option value="draft">$stDraft</option>
            <option value="deprecated">$stDep</option>
            <option value="archived">$stArch</option>
        </select>
        <select id="stellaTagSelect" class="stella-select">
            <option value="all">$tagAll</option>
            $tagOptionsStr
        </select>
    </div>
</div>
<style>
    .stella-control-panel { display: flex; align-items: center; justify-content: space-between; background: #161b22; padding: 10px 16px; border-radius: 8px; border: 1px solid #30363d; margin-bottom: 20px; gap: 12px; flex-wrap: wrap; }
    .stella-control-left, .stella-control-center { display: flex; align-items: center; gap: 8px; }
    .stella-preset-group { display: inline-flex; border-radius: 6px; overflow: hidden; border: 1px solid #30363d; }
    .stella-preset-btn { background: #21262d; color: #8b949e; border: none; border-right: 1px solid #30363d; padding: 6px 12px; font-size: 12px; font-weight: bold; cursor: pointer; transition: all 0.2s; }
    .stella-preset-btn:last-child { border-right: none; }
    .stella-preset-btn:hover { background: #30363d; color: #c9d1d9; }
    .stella-preset-btn.active { background: #1f6feb; color: #ffffff; }
    .stella-reset-btn { color: #8b949e; background: #21262d; border: 1px solid #30363d; padding: 6px 12px; border-radius: 6px; font-size: 12px; font-weight: bold; cursor: pointer; transition: all 0.2s; }
    .stella-reset-btn:hover { color: #58a6ff; background: #30363d; border-color: #58a6ff; }
    .stella-input, .stella-select { background: #0d1117; border: 1px solid #30363d; color: #c9d1d9; font-size: 12px; padding: 6px 10px; border-radius: 6px; outline: none; }
    .stella-input { width: 200px; }
    .stella-input:focus, .stella-select:focus { border-color: #58a6ff; }
</style>
"@
}

function Get-StellaViewHtml {
    param (
        [string]$Lang = "ja"
    )

    Ensure-WikiIndexLoaded -TargetWikiDir $wikiDir
    $controlPanelHtml = Get-StellaControlPanelHtml -ActiveView "stella" -Lang $Lang

    $previewTitle   = Get-LocalizedStr -Key "stella_preview_title" -Lang $Lang
    $openDocTxt     = Get-LocalizedStr -Key "search_btn" -Lang $Lang
    $navStellaTitle = Get-LocalizedStr -Key "stella_view_nav" -Lang $Lang
    $helpDrag       = Get-LocalizedStr -Key "stella_help_drag" -Lang $Lang
    $helpWheel      = Get-LocalizedStr -Key "stella_help_zoom" -Lang $Lang
    $helpClick      = Get-LocalizedStr -Key "stella_help_click" -Lang $Lang
    $connectedTitle = Get-LocalizedStr -Key "stella_connected_nodes" -Lang $Lang
    $timePastTxt    = Get-LocalizedStr -Key "stella_time_past" -Lang $Lang
    $timePresTxt    = Get-LocalizedStr -Key "stella_time_present" -Lang $Lang

    # Index items serialization
    $indexJson = Get-ApiIndexJson -QueryParams @{ limit = "all" }

    return @"
$controlPanelHtml

<div class="stella-container" style="position: relative; width: 100%; height: calc(100vh - 180px); min-height: 580px; background: radial-gradient(circle at 50% 50%, #0d131f 0%, #06090e 100%); border-radius: 8px; border: 1px solid #30363d; overflow: hidden; display: flex; user-select: none;">
    <!-- Graphical Operation Guide Overlay -->
    <div class="stella-help-overlay" style="position: absolute; top: 12px; left: 12px; background: rgba(22, 27, 34, 0.88); backdrop-filter: blur(6px); padding: 10px 14px; border-radius: 8px; border: 1px solid #30363d; color: #8b949e; font-size: 11px; z-index: 50; pointer-events: none; line-height: 1.6; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
        <div style="font-weight: bold; color: #58a6ff; margin-bottom: 4px; display: flex; align-items: center; gap: 6px;">$navStellaTitle</div>
        <div>$helpDrag</div>
        <div>$helpWheel</div>
        <div>$helpClick</div>
    </div>

    <!-- Time Axis HUD Indicator -->
    <div id="stellaTimeHud" style="position: absolute; bottom: 12px; left: 12px; background: rgba(22, 27, 34, 0.82); backdrop-filter: blur(4px); padding: 6px 12px; border-radius: 6px; border: 1px solid #30363d; color: #8b949e; font-size: 11px; z-index: 50; pointer-events: none; display: flex; align-items: center; gap: 8px;">
        <span>⏳ 時間軸 (Z):</span>
        <span style="color: #79c0ff;">◀ $timePastTxt</span>
        <span style="color: #30363d;">──────────</span>
        <span style="color: #58a6ff; font-weight: bold;">$timePresTxt ▶</span>
    </div>

    <svg id="stellaCanvas" style="width: 100%; height: 100%; cursor: grab;" viewBox="0 0 1000 800">
        <g id="stellaLinksGroup"></g>
        <g id="stellaNodesGroup"></g>
    </svg>

    <!-- Slide-in preview pane -->
    <div id="stellaSlidePane" class="stella-slidein-pane" style="position: absolute; top: 0; right: -380px; width: 360px; height: 100%; background: #161b22; border-left: 1px solid #30363d; padding: 20px; box-shadow: -4px 0 16px rgba(0,0,0,0.5); transition: right 0.3s ease; color: #c9d1d9; overflow-y: auto; z-index: 100; box-sizing: border-box;">
        <button onclick="closeStellaPane()" style="position: absolute; top: 12px; right: 12px; background: none; border: none; color: #8b949e; font-size: 18px; cursor: pointer;">✕</button>
        <h3 id="stellaPaneTitle" style="margin-top: 0; font-size: 16px; color: #58a6ff; word-break: break-all;">$previewTitle</h3>
        <div id="stellaPaneMeta" style="font-size: 12px; color: #8b949e; margin-bottom: 12px; display: flex; flex-wrap: wrap; gap: 8px; align-items: center;"></div>
        <p id="stellaPaneDesc" style="font-size: 13px; line-height: 1.5; color: #8b949e; background: #0d1117; padding: 10px; border-radius: 6px; border: 1px solid #21262d; margin-bottom: 12px;"></p>

        <!-- Connected Stars (Metadata Affinity) -->
        <div id="stellaConnectedSection" style="margin-top: 14px; border-top: 1px solid #21262d; padding-top: 12px;">
            <div style="font-size: 12px; font-weight: bold; color: #58a6ff; margin-bottom: 8px;">$connectedTitle</div>
            <div id="stellaConnectedList" style="display: flex; flex-direction: column; gap: 6px; font-size: 12px;"></div>
        </div>

        <div style="margin-top: 18px;">
            <a id="stellaPaneLink" href="#" style="display: inline-block; padding: 8px 16px; background: #1f6feb; color: #fff; text-decoration: none; border-radius: 6px; font-size: 12px; font-weight: bold;">📄 $openDocTxt</a>
        </div>
    </div>
</div>

<script>
(function() {
    var rawData = $indexJson;
    var rawItems = (rawData && rawData.Items) ? rawData.Items : [];

    var nodes = rawItems.map(function(item) {
        var rel = item.RelPath || item.relPath || "";
        return {
            relPath: rel,
            title: item.Title || item.title || "Untitled",
            description: item.Description || item.description || "",
            status: (item.Status || item.status || "active").toLowerCase(),
            tags: item.Tags || item.tags || [],
            domain: item.Domain || item.domain || "root",
            lastUpdated: item.LastUpdated || item.lastUpdated || "",
            related: item.Related || item.related || [],
            links: item.Links || item.links || [],
            x: item.X !== undefined ? item.X : 500,
            y: item.Y !== undefined ? item.Y : 400,
            z: item.Z !== undefined ? item.Z : 0,
            screenX: 500,
            screenY: 400,
            projZ: 0,
            scale: 1,
            el: null,
            circleEl: null,
            textEl: null
        };
    });

    var svg = document.getElementById("stellaCanvas");
    var gLinks = document.getElementById("stellaLinksGroup");
    var gNodes = document.getElementById("stellaNodesGroup");
    var pane = document.getElementById("stellaSlidePane");

    // 3D カメラ状態変数 (Z軸 = 時間軸)
    var rotX = 0.38;       // ピッチ角 (上下)
    var rotY = 0.45;       // ヨー角 (左右)
    var panX = 0, panY = 0; // 平行移動
    var zoom = 1.0;        // ズーム倍率
    var centerWorldX = 500, centerWorldY = 400;

    // キャンバス基準サイズ
    if (nodes.length > 0) {
        var sumX = 0, sumY = 0;
        nodes.forEach(function(n) { sumX += n.x; sumY += n.y; });
        centerWorldX = sumX / nodes.length;
        centerWorldY = sumY / nodes.length;
    }

    var selectedNode = null;
    var allEdges = [];
    var fov = 950;
    var camDist = 1100;

    // 3D 透視投影関数 (Perspective 3D Projection)
    function project3D(wx, wy, wz) {
        var x0 = wx - centerWorldX;
        var y0 = wy - centerWorldY;
        var z0 = wz;

        // 1. Yaw (Y軸回転: 左右)
        var cosY = Math.cos(rotY), sinY = Math.sin(rotY);
        var x1 = x0 * cosY + z0 * sinY;
        var z1 = -x0 * sinY + z0 * cosY;

        // 2. Pitch (X軸回転: 上下)
        var cosX = Math.cos(rotX), sinX = Math.sin(rotX);
        var y2 = y0 * cosX - z1 * sinX;
        var z2 = y0 * sinX + z1 * cosX;

        // 3. 透視投影 (Perspective Projection)
        var depth = camDist + z2;
        if (depth < 80) depth = 80;
        var k = (fov / depth) * zoom;

        return {
            x: 500 + panX + (x1 * k),
            y: 400 + panY + (y2 * k),
            z: z2,
            k: k
        };
    }

    // 3D 空間位置の全体更新
    function update3DPositions() {
        // 1. ノードの画面投影
        nodes.forEach(function(n) {
            var p = project3D(n.x, n.y, n.z);
            n.screenX = p.x;
            n.screenY = p.y;
            n.projZ = p.z;
            n.scale = p.k;

            if (n.el) {
                n.el.setAttribute("transform", "translate(" + p.x.toFixed(1) + "," + p.y.toFixed(1) + ")");
                var isHub = (n.tags && n.tags.length >= 4);
                var baseR = isHub ? 8 : 6;
                var currentR = Math.max(3, Math.min(18, baseR * Math.pow(p.k, 0.85)));
                n.circleEl.setAttribute("r", currentR.toFixed(1));

                var depthFade = Math.max(0.2, Math.min(1.0, 0.35 + (0.65 * (p.k / Math.max(0.1, zoom)))));
                n.circleEl.setAttribute("opacity", (selectedNode ? n.circleEl.getAttribute("opacity") : depthFade.toFixed(2)));

                if (n.textEl && !selectedNode) {
                    var textAlpha = (p.k < 0.7 && !isHub) ? "0.15" : depthFade.toFixed(2);
                    n.textEl.style.opacity = textAlpha;
                    var fontSize = Math.max(9, Math.min(14, 11 * p.k));
                    n.textEl.setAttribute("font-size", fontSize.toFixed(1) + "px");
                    n.textEl.setAttribute("x", (currentR + 5).toFixed(1));
                }
            }
        });

        // 2. 星座線の画面投影
        allEdges.forEach(function(e) {
            if (e.lineEl) {
                e.lineEl.setAttribute("x1", e.source.screenX.toFixed(1));
                e.lineEl.setAttribute("y1", e.source.screenY.toFixed(1));
                e.lineEl.setAttribute("x2", e.target.screenX.toFixed(1));
                e.lineEl.setAttribute("y2", e.target.screenY.toFixed(1));
            }
        });

        // 3. Z-Sorting (Painter's Algorithm: 奥にある星から順に DOM を再配置)
        var sortedNodes = nodes.slice().sort(function(a, b) { return a.projZ - b.projZ; });
        sortedNodes.forEach(function(n) {
            if (n.el && n.el.parentNode === gNodes) {
                gNodes.appendChild(n.el);
            }
        });
    }

    // 視点プリセット切り替え (Smooth Tweening Animation)
    var animId = null;
    function tweenCameraTo(targetRotX, targetRotY, targetPanX, targetPanY, targetZoom) {
        if (animId) cancelAnimationFrame(animId);
        var sRotX = rotX, sRotY = rotY;
        var sPanX = panX, sPanY = panY;
        var sZoom = zoom;
        var startTime = performance.now();
        var duration = 550;

        function step(now) {
            var progress = Math.min(1, (now - startTime) / duration);
            var ease = progress < 0.5 ? 4 * progress * progress * progress : 1 - Math.pow(-2 * progress + 2, 3) / 2;

            rotX = sRotX + (targetRotX - sRotX) * ease;
            rotY = sRotY + (targetRotY - sRotY) * ease;
            panX = sPanX + (targetPanX - sPanX) * ease;
            panY = sPanY + (targetPanY - sPanY) * ease;
            zoom = sZoom + (targetZoom - sZoom) * ease;

            update3DPositions();

            if (progress < 1) {
                animId = requestAnimationFrame(step);
            } else {
                animId = null;
            }
        }
        animId = requestAnimationFrame(step);
    }

    window.setStellaPreset = function(mode) {
        var buttons = document.querySelectorAll(".stella-preset-btn");
        buttons.forEach(function(b) {
            b.classList.toggle("active", b.dataset.preset === mode);
        });

        if (mode === "3d") {
            tweenCameraTo(0.38, 0.45, 0, 0, 1.0);
        } else if (mode === "top") {
            tweenCameraTo(0.0, 0.0, 0, 0, 1.0);
        } else if (mode === "timeline") {
            tweenCameraTo(0.0, 1.57079, 0, 0, 0.95);
        }
    };

    window.resetStellaView = function() {
        window.setStellaPreset("3d");
        applyFilter();
        closeStellaPane();
    };

    function renderCanvas() {
        gLinks.innerHTML = "";
        gNodes.innerHTML = "";
        allEdges = [];

        var nodeCount = nodes.length;
        for (var i = 0; i < nodeCount; i++) {
            for (var j = i + 1; j < nodeCount; j++) {
                var n1 = nodes[i];
                var n2 = nodes[j];

                var sharedTags = [];
                if (n1.tags && n2.tags) {
                    n1.tags.forEach(function(t) {
                        if (typeof t === "string" && t.trim() !== "" && n2.tags.indexOf(t) !== -1 && sharedTags.indexOf(t) === -1) {
                            sharedTags.push(t);
                        }
                    });
                }

                var isRelated = false;
                var r1 = n1.relPath.replace(/\\/g, '/').toLowerCase();
                var r2 = n2.relPath.replace(/\\/g, '/').toLowerCase();
                if (n1.related) {
                    n1.related.forEach(function(rel) {
                        if (typeof rel === "string" && (rel.toLowerCase() === r2 || rel.toLowerCase() === n2.relPath.toLowerCase())) { isRelated = true; }
                    });
                }
                if (n2.related) {
                    n2.related.forEach(function(rel) {
                        if (typeof rel === "string" && (rel.toLowerCase() === r1 || rel.toLowerCase() === n1.relPath.toLowerCase())) { isRelated = true; }
                    });
                }

                if (sharedTags.length > 0 || isRelated) {
                    allEdges.push({
                        source: n1,
                        target: n2,
                        sharedTags: sharedTags,
                        isRelated: isRelated,
                        weight: (isRelated ? 6 : 0) + (sharedTags.length * 2),
                        lineEl: null
                    });
                }
            }
        }

        // 次数制限 k-NN フィルタ (毛糸玉防止)
        var nodeEdgeCount = {};
        var backboneEdgeMap = {};
        var sortedEdges = allEdges.slice().sort(function(a, b) { return b.weight - a.weight; });

        sortedEdges.forEach(function(e) {
            var sKey = e.source.relPath;
            var tKey = e.target.relPath;
            var countS = nodeEdgeCount[sKey] || 0;
            var countT = nodeEdgeCount[tKey] || 0;

            if (e.isRelated || (countS < 4 && countT < 4)) {
                var edgeId = sKey < tKey ? sKey + '|' + tKey : tKey + '|' + sKey;
                backboneEdgeMap[edgeId] = true;
                nodeEdgeCount[sKey] = countS + 1;
                nodeEdgeCount[tKey] = countT + 1;
            }
        });

        // 星座線の DOM 生成
        allEdges.forEach(function(e) {
            var sKey = e.source.relPath;
            var tKey = e.target.relPath;
            var edgeId = sKey < tKey ? sKey + '|' + tKey : tKey + '|' + sKey;
            var isBackbone = !!backboneEdgeMap[edgeId];

            var line = document.createElementNS("http://www.w3.org/2000/svg", "line");
            var strokeColor = e.isRelated ? "rgba(138, 180, 248, 0.55)" : (e.sharedTags.length > 1 ? "rgba(88, 166, 255, 0.4)" : "rgba(88, 166, 255, 0.2)");
            var strokeWidth = e.isRelated ? "2.2" : (e.sharedTags.length > 1 ? "1.6" : "1.1");
            line.setAttribute("stroke", strokeColor);
            line.setAttribute("stroke-width", strokeWidth);
            if (!e.isRelated && e.sharedTags.length === 1) {
                line.setAttribute("stroke-dasharray", "4,3");
            }
            line.dataset.isBackbone = isBackbone ? "true" : "false";
            line.dataset.isRelated = e.isRelated ? "true" : "false";
            line.dataset.sharedCount = e.sharedTags.length;

            if (!isBackbone) {
                line.style.display = "none";
            }

            e.lineEl = line;
            gLinks.appendChild(line);
        });

        // 星ノードの DOM 生成
        nodes.forEach(function(n) {
            var g = document.createElementNS("http://www.w3.org/2000/svg", "g");
            g.setAttribute("class", "stella-node");
            g.dataset.relpath = n.relPath;
            var isHub = (n.tags && n.tags.length >= 4);
            g.dataset.isHub = isHub ? "true" : "false";
            g.style.cursor = "pointer";

            var dotColor = (n.status === 'stable' || n.status === 'active') ? '#58a6ff' : (n.status === 'draft' ? '#d29922' : '#f85149');

            var circle = document.createElementNS("http://www.w3.org/2000/svg", "circle");
            circle.setAttribute("r", isHub ? "8" : "6");
            circle.setAttribute("fill", dotColor);
            circle.setAttribute("opacity", "0.85");
            circle.setAttribute("class", "stella-dot");
            circle.style.transition = "fill 0.2s ease, r 0.2s ease";

            var text = document.createElementNS("http://www.w3.org/2000/svg", "text");
            text.setAttribute("x", (isHub ? 13 : 11).toString());
            text.setAttribute("y", "4");
            text.setAttribute("fill", "#c9d1d9");
            text.setAttribute("font-size", "11px");
            text.setAttribute("font-weight", isHub ? "bold" : "500");
            text.setAttribute("opacity", "0.85");
            text.textContent = n.title;

            g.appendChild(circle);
            g.appendChild(text);

            n.el = g;
            n.circleEl = circle;
            n.textEl = text;

            g.addEventListener("click", function(e) {
                e.stopPropagation();
                flyToNode(n);
                highlightConstellation(n);
                openStellaPane(n);
            });

            gNodes.appendChild(g);
        });

        update3DPositions();
    }

    // マウスドラッグによる 3D Orbit 回転 & パン
    var isDragging = false;
    var isPanMode = false;
    var lastMouseX = 0, lastMouseY = 0;

    svg.addEventListener("mousedown", function(e) {
        if (e.button !== 0 && e.button !== 2) return;
        isDragging = true;
        isPanMode = (e.shiftKey || e.button === 2);
        lastMouseX = e.clientX;
        lastMouseY = e.clientY;
        svg.style.cursor = isPanMode ? "move" : "grabbing";
        e.preventDefault();
    });

    window.addEventListener("mousemove", function(e) {
        if (!isDragging) return;
        var dx = e.clientX - lastMouseX;
        var dy = e.clientY - lastMouseY;
        lastMouseX = e.clientX;
        lastMouseY = e.clientY;

        if (isPanMode) {
            panX += dx;
            panY += dy;
        } else {
            rotY += dx * 0.006;
            rotX -= dy * 0.006;
            // ピッチ角をクランプ (-85度〜+85度)
            rotX = Math.max(-1.48, Math.min(1.48, rotX));
        }

        update3DPositions();
    });

    window.addEventListener("mouseup", function() {
        if (isDragging) {
            isDragging = false;
            svg.style.cursor = "grab";
        }
    });

    svg.addEventListener("contextmenu", function(e) {
        e.preventDefault();
    });

    // マウスホイールによるズーム
    svg.addEventListener("wheel", function(e) {
        e.preventDefault();
        var factor = e.deltaY < 0 ? 1.12 : 0.89;
        zoom = Math.max(0.35, Math.min(3.2, zoom * factor));
        update3DPositions();
    }, { passive: false });

    function flyToNode(n) {
        selectedNode = n;
        // 選択ノードが中央に来るように panX, panY を計算
        var p = project3D(n.x, n.y, n.z);
        var targetPanX = panX + (500 - p.x);
        var targetPanY = panY + (400 - p.y);
        tweenCameraTo(rotX, rotY, targetPanX, targetPanY, 1.25);
    }

    window.flyToRelPath = function(rel) {
        var target = nodes.filter(function(n) { return n.relPath === rel; })[0];
        if (target) {
            flyToNode(target);
            highlightConstellation(target);
            openStellaPane(target);
        }
    };

    // 星座発光 (Constellation Lighting)
    function highlightConstellation(centerNode) {
        var connectedRels = {};
        connectedRels[centerNode.relPath] = true;

        allEdges.forEach(function(e) {
            if (e.source.relPath === centerNode.relPath) { connectedRels[e.target.relPath] = true; }
            if (e.target.relPath === centerNode.relPath) { connectedRels[e.source.relPath] = true; }
        });

        // ノード発光
        nodes.forEach(function(n) {
            if (n.relPath === centerNode.relPath) {
                n.circleEl.setAttribute("fill", "#58a6ff");
                n.circleEl.setAttribute("opacity", "1");
                if (n.textEl) { n.textEl.style.opacity = "1"; n.textEl.setAttribute("font-weight", "bold"); }
            } else if (connectedRels[n.relPath]) {
                n.circleEl.setAttribute("fill", "#79c0ff");
                n.circleEl.setAttribute("opacity", "1");
                if (n.textEl) { n.textEl.style.opacity = "0.95"; }
            } else {
                n.circleEl.setAttribute("opacity", "0.18");
                if (n.textEl) { n.textEl.style.opacity = "0.12"; }
            }
        });

        // 星座線発光
        allEdges.forEach(function(e) {
            if (e.lineEl) {
                var s = e.source.relPath;
                var t = e.target.relPath;
                var isConn = (s === centerNode.relPath || t === centerNode.relPath);

                if (isConn) {
                    e.lineEl.style.display = "block";
                    e.lineEl.setAttribute("stroke", "rgba(88, 166, 255, 0.95)");
                    e.lineEl.setAttribute("stroke-width", "2.8");
                    e.lineEl.style.filter = "drop-shadow(0 0 5px #388bfd)";
                } else {
                    var isBackbone = e.lineEl.dataset.isBackbone === "true";
                    if (isBackbone) {
                        e.lineEl.style.display = "block";
                        e.lineEl.setAttribute("stroke", "rgba(88, 166, 255, 0.08)");
                        e.lineEl.setAttribute("stroke-width", "1");
                        e.lineEl.style.filter = "none";
                    } else {
                        e.lineEl.style.display = "none";
                    }
                }
            }
        });
    }

    function openStellaPane(n) {
        document.getElementById("stellaPaneTitle").textContent = n.title;
        var statusBadge = "<span style='padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: bold; background: " + (n.status === 'active' || n.status === 'stable' ? '#238636' : n.status === 'draft' ? '#d29922' : '#f85149') + "; color: #fff;'>" + n.status.toUpperCase() + "</span>";
        var domainBadge = "<span style='padding: 2px 8px; border-radius: 10px; font-size: 11px; background: #21262d; color: #8b949e; border: 1px solid #30363d;'>📁 " + (n.domain || "root") + "</span>";
        var dateStr = n.lastUpdated ? n.lastUpdated.substring(0, 10) : "";
        document.getElementById("stellaPaneMeta").innerHTML = statusBadge + " " + domainBadge + " <span>📅 " + dateStr + "</span>";
        document.getElementById("stellaPaneDesc").textContent = n.description || "概要はありません。";
        document.getElementById("stellaPaneLink").href = "/" + encodeURIComponent(n.relPath.replace(/\\/g, '/')).replace(/%2F/g, '/');

        var connectedListEl = document.getElementById("stellaConnectedList");
        var connectedItems = [];
        allEdges.forEach(function(e) {
            var other = null;
            if (e.source.relPath === n.relPath) other = e.target;
            else if (e.target.relPath === n.relPath) other = e.source;

            if (other) {
                var reason = e.isRelated ? "🔗 関連指定" : ("🏷️ " + e.sharedTags.join(", "));
                connectedItems.push("<div onclick=\"flyToRelPath('" + other.relPath.replace(/'/g, "\\'") + "')\" style='cursor: pointer; padding: 6px 10px; background: #0d1117; border-radius: 6px; border: 1px solid #21262d; display: flex; justify-content: space-between; align-items: center; transition: all 0.2s;' onmouseover=\"this.style.borderColor='#58a6ff'\" onmouseout=\"this.style.borderColor='#21262d'\"><span style='color: #c9d1d9; font-weight: 500;'>🌟 " + other.title + "</span><span style='color: #8b949e; font-size: 11px;'>" + reason + "</span></div>");
            }
        });

        if (connectedItems.length > 0) {
            connectedListEl.innerHTML = connectedItems.join("");
            document.getElementById("stellaConnectedSection").style.display = "block";
        } else {
            connectedListEl.innerHTML = "<span style='color: #6e7681; font-size: 11px;'>関連する星はありません</span>";
        }

        pane.style.right = "0px";
    }

    window.closeStellaPane = function() {
        pane.style.right = "-380px";
        if (selectedNode) {
            selectedNode = null;
            applyFilter();
        }
    };

    function applyFilter() {
        var query = (document.getElementById("stellaSearchInput").value || "").toLowerCase().trim();
        var statusVal = document.getElementById("stellaStatusSelect").value;
        var tagVal = document.getElementById("stellaTagSelect").value;

        var matchingRels = {};
        nodes.forEach(function(n) {
            var matchQ = !query || (n.title.toLowerCase().indexOf(query) !== -1 || n.description.toLowerCase().indexOf(query) !== -1);
            var matchS = statusVal === "all" || n.status === statusVal || (statusVal === "active" && n.status === "stable");
            var matchT = tagVal === "all" || (n.tags && n.tags.indexOf(tagVal) !== -1);

            if (matchQ && matchS && matchT && (query || statusVal !== "all" || tagVal !== "all")) {
                matchingRels[n.relPath] = true;
            }
        });

        var isActiveFilter = (query !== "" || statusVal !== "all" || tagVal !== "all");

        nodes.forEach(function(n) {
            var isHub = (n.tags && n.tags.length >= 4);
            if (!isActiveFilter) {
                var dotColor = (n.status === 'stable' || n.status === 'active') ? '#58a6ff' : (n.status === 'draft' ? '#d29922' : '#f85149');
                n.circleEl.setAttribute("fill", dotColor);
            } else if (matchingRels[n.relPath]) {
                n.circleEl.setAttribute("fill", "#388bfd");
                n.circleEl.setAttribute("opacity", "1");
                if (n.textEl) n.textEl.style.opacity = "1";
            } else {
                n.circleEl.setAttribute("fill", "#21262d");
                n.circleEl.setAttribute("opacity", "0.2");
                if (n.textEl) n.textEl.style.opacity = "0.15";
            }
        });

        allEdges.forEach(function(e) {
            if (e.lineEl) {
                var s = e.source.relPath;
                var t = e.target.relPath;
                var isBackbone = e.lineEl.dataset.isBackbone === "true";
                e.lineEl.style.filter = "none";

                if (isActiveFilter) {
                    if (matchingRels[s] && matchingRels[t]) {
                        e.lineEl.style.display = "block";
                        e.lineEl.setAttribute("stroke", "rgba(56, 139, 253, 0.85)");
                        e.lineEl.setAttribute("stroke-width", "2.2");
                    } else {
                        e.lineEl.style.display = "none";
                    }
                } else {
                    if (isBackbone) {
                        e.lineEl.style.display = "block";
                        var isRelated = e.lineEl.dataset.isRelated === "true";
                        var sharedCount = parseInt(e.lineEl.dataset.sharedCount || "0", 10);
                        e.lineEl.setAttribute("stroke", isRelated ? "rgba(138, 180, 248, 0.55)" : (sharedCount > 1 ? "rgba(88, 166, 255, 0.4)" : "rgba(88, 166, 255, 0.2)"));
                        e.lineEl.setAttribute("stroke-width", isRelated ? "2.2" : (sharedCount > 1 ? "1.6" : "1.1"));
                    } else {
                        e.lineEl.style.display = "none";
                    }
                }
            }
        });

        update3DPositions();
    }

    document.getElementById("stellaSearchInput").addEventListener("input", applyFilter);
    document.getElementById("stellaStatusSelect").addEventListener("change", applyFilter);
    document.getElementById("stellaTagSelect").addEventListener("change", applyFilter);

    renderCanvas();
})();
</script>
"@
}

# --- システム設定ビュー生成メイン関数 ---
function Get-SettingsViewHtml {
    param (
        [string]$Lang = "ja"
    )

    $data = Get-SettingsViewData -Lang $Lang

    $editorCardHtml = Render-SettingsEditorCard -Data $data
    $searchCardHtml = Render-SettingsSearchCard -Data $data
    $ragCardHtml    = Render-SettingsRagCard -Data $data
    $serverCardHtml = Render-SettingsServerCard -Data $data
    $scriptHtml     = Render-SettingsScript -Data $data

    return @"
<div class="settings-container">
    <h2>$($data.TitleLbl)</h2>
    <p>$($data.DescLbl)</p>

    <div id="settingsToast" class="okf-card" style="display:none; border-left: 4px solid #28a745; margin-bottom: 20px;">
        <span id="settingsToastMsg" style="font-weight: bold;"></span>
    </div>

    <form id="settingsForm" onsubmit="saveSettings(event)" style="display: flex; flex-direction: column; gap: 20px;">
$editorCardHtml

$searchCardHtml

$ragCardHtml

        <div>
            <button type="submit" id="saveBtn" style="padding: 10px 24px; background: #28a745; color: white; border: none; border-radius: 6px; font-size: 15px; font-weight: bold; cursor: pointer;">
                $($data.SaveBtnLbl)
            </button>
        </div>
    </form>

$serverCardHtml
</div>

$scriptHtml
"@
}

# --- 完全レイアウト & エディタモーダル描画メイン関数 ---
function Get-MainViewHtml {
    param (
        [string]$PageTitle = "",
        [string]$BodyContent = "",
        [string]$RelPath = "",
        [string]$Lang = "ja",
        $Config = $null
    )

    $sidebarHtml     = Get-SidebarHtml -currentRelPath $RelPath -Lang $Lang
    $editorModalHtml = Get-WikiEditorModalHtml -Lang $Lang

    $chatWidgetHtml = ""
    if ($Config -and $Config.rag -and $Config.rag.enabled) {
        $chatWidgetHtml = Get-ChatWidgetHtml -Lang $Lang
    }

    $navBrand     = Get-LocalizedStr -Key "brand_title" -Lang $Lang
    $navShutdown  = Get-LocalizedStr -Key "shutdown_btn" -Lang $Lang
    $shutdownConfirmJs = ConvertTo-JsString (Get-LocalizedStr -Key "shutdown_confirm" -Lang $Lang)
    $shutdownDoneTitleJs = ConvertTo-JsString (Get-LocalizedStr -Key "shutdown_done_title" -Lang $Lang)
    $shutdownDoneDescJs = ConvertTo-JsString (Get-LocalizedStr -Key "shutdown_done_desc" -Lang $Lang)

    $navHome      = Get-LocalizedStr -Key "home" -Lang $Lang
    $navRecent    = Get-LocalizedStr -Key "recent_updates" -Lang $Lang
    $navTags      = Get-LocalizedStr -Key "tags" -Lang $Lang
    $navMaint     = Get-LocalizedStr -Key "maintenance" -Lang $Lang
    $navAuthors   = Get-LocalizedStr -Key "authors" -Lang $Lang
    $navSettings  = Get-LocalizedStr -Key "settings" -Lang $Lang
    $navApi       = Get-LocalizedStr -Key "api_json" -Lang $Lang
    $navStella    = Get-LocalizedStr -Key "stella_view_nav" -Lang $Lang
    $searchHolder = Get-LocalizedStr -Key "search_placeholder" -Lang $Lang
    $searchBtnTxt = Get-LocalizedStr -Key "search_btn" -Lang $Lang
    $docListTitle = Get-LocalizedStr -Key "doc_list_title" -Lang $Lang

    $langOptionsHtml = foreach ($k in ($script:I18n.Keys | Sort-Object)) {
        $sel = if ($k -eq $Lang) { "selected" } else { "" }
        $label = switch ($k) {
            "ja" { "日本語 (JP)" }
            "en" { "English (EN)" }
            default { $k.ToUpper() }
        }
        "<option value='$k' $sel>$label</option>"
    }
    $langOptionsStr = $langOptionsHtml -join ""

    $searchLoadingTxtJs = ConvertTo-JsString (Get-LocalizedStr -Key "indexing_searching" -Lang $Lang)

    $template = @'
<!DOCTYPE html>
<html lang="{18}">
<head>
<meta charset="UTF-8">
<title>{0} - {20} OKF</title>
<!-- TOAST UI Editor CDN Assets -->
<link rel="stylesheet" href="https://uicdn.toast.com/editor/latest/toastui-editor.min.css" />
<script src="https://uicdn.toast.com/editor/latest/toastui-editor-all.min.js"></script>
<style>
    * { box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "BIZ UDPGothic", "Yu Gothic UI", "Meiryo", "Hiragino Sans", sans-serif; margin: 0; padding: 0; display: flex; flex-direction: column; height: 100vh; color: #24292e; background-color: #fff; }
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
    nav.sidebar li.nav-file.active > a { background-color: #0366d6; color: #ffffff !important; font-weight: bold; }
    main.main-content { flex: 1; padding: 30px 40px; overflow-y: auto; background-color: #fff; }
    main.main-content h1 { font-size: 24px; margin-top: 0; border-bottom: 1px solid #e1e4e8; padding-bottom: 8px; color: #24292e; }
    main.main-content h2 { font-size: 20px; border-bottom: 1px solid #e1e4e8; padding-bottom: 6px; color: #24292e; margin-top: 24px; }
    main.main-content p { line-height: 1.6; color: #24292e; }
    main.main-content code { background-color: #f6f8fa; padding: 2px 6px; border-radius: 3px; font-family: "Cascadia Mono", "Cascadia Code", SFMono-Regular, Consolas, "BIZ UDGothic", "Yu Gothic", "Meiryo", monospace; font-size: 85%; }
    main.main-content pre { background-color: #f6f8fa; padding: 16px; border-radius: 6px; overflow: auto; line-height: 1.45; }
    main.main-content pre code { background-color: transparent; padding: 0; }
    main.main-content table { border-collapse: collapse; width: 100%; margin: 15px 0; }
    main.main-content table th, main.main-content table td { border: 1px solid #dfe2e5; padding: 6px 13px; }
    main.main-content table th { background-color: #f6f8fa; font-weight: bold; }
    main.main-content table tr:nth-child(2n) { background-color: #f8f9fa; }
    main.main-content blockquote { padding: 0 1em; color: #6a737d; border-left: 0.25em solid #dfe2e5; margin: 0 0 16px 0; }
    .badge { display: inline-block; padding: 2px 8px; font-size: 11px; font-weight: bold; border-radius: 12px; margin-left: 8px; vertical-align: middle; }
    .badge-active { background-color: #dcffe4; color: #155724; border: 1px solid #c3e6cb; }
    .badge-draft { background-color: #fff3cd; color: #856404; border: 1px solid #ffeeba; }
    .badge-deprecated { background-color: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
    .okf-top-bar { display: flex; justify-content: space-between; align-items: center; background: #f6f8fa; padding: 8px 12px; border-radius: 6px; margin-bottom: 20px; border: 1px solid #e1e4e8; }
    .okf-domain { font-size: 12px; color: #586069; font-weight: bold; }
    .okf-tags { display: flex; gap: 6px; }
    .tag-badge { background: #e1e4e8; color: #0366d6; font-size: 11px; padding: 2px 8px; border-radius: 10px; text-decoration: none; }
    .tag-badge:hover { background: #0366d6; color: #fff; }
    .okf-footer-card { margin-top: 40px; padding: 16px; background: #f6f8fa; border: 1px solid #e1e4e8; border-radius: 6px; font-size: 13px; }
    .okf-footer-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; border-bottom: 1px solid #e1e4e8; padding-bottom: 6px; }
    .okf-footer-title { font-weight: bold; color: #24292e; }
    .okf-api-link { font-size: 11px; color: #0366d6; text-decoration: none; }
    .okf-api-link:hover { text-decoration: underline; }
    .okf-footer-meta span { color: #586069; margin-right: 15px; }
    .warning-banner { background-color: #fff3cd; color: #856404; padding: 10px 15px; border-radius: 6px; border: 1px solid #ffeeba; margin-bottom: 20px; font-size: 13px; }
    .edit-doc-btn { background: #28a745; color: #fff; border: none; padding: 4px 10px; border-radius: 4px; font-size: 12px; font-weight: bold; cursor: pointer; margin-left: 10px; }
    .edit-doc-btn:hover { background: #218838; }
    .wiki-editor-modal { display: none; position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; background: rgba(0,0,0,0.5); z-index: 10000; justify-content: center; align-items: center; padding: 16px; box-sizing: border-box; }
    .wiki-editor-modal.fullscreen { padding: 0; }
    .wiki-editor-container { background: #fff; width: 92vw; max-width: 1040px; height: 90vh; max-height: calc(100vh - 32px); border-radius: 8px; display: flex; flex-direction: column; overflow: hidden; box-shadow: 0 10px 30px rgba(0,0,0,0.3); transition: width 0.2s ease, height 0.2s ease; }
    .wiki-editor-container.fullscreen { width: 100vw; height: 100vh; max-width: none; max-height: none; border-radius: 0; }
    .wiki-editor-header { background: #1b1f23; color: #fff; padding: 10px 18px; display: flex; justify-content: space-between; align-items: center; font-weight: bold; flex-shrink: 0; }
    .wiki-meta-accordion { background: #f6f8fa; border-bottom: 1px solid #e1e4e8; flex-shrink: 0; }
    .wiki-meta-header { padding: 8px 16px; display: flex; justify-content: space-between; align-items: center; cursor: pointer; user-select: none; }
    .wiki-meta-header:hover { background: #eef1f4; }
    .wiki-meta-toggle-btn { background: #e1e4e8; border: none; padding: 3px 10px; font-size: 11px; border-radius: 4px; cursor: pointer; color: #24292e; }
    .wiki-meta-toggle-btn.active { background: #0366d6; color: #fff; font-weight: bold; }
    .wiki-meta-body { max-height: 240px; overflow-y: auto; }
    .wiki-meta-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 8px; padding: 10px 16px; }
    .wiki-form-group { display: flex; flex-direction: column; gap: 3px; }
    .wiki-form-group.full-width { grid-column: 1 / -1; }
    .wiki-form-group label { font-size: 11px; font-weight: bold; color: #586069; }
    .wiki-form-group input, .wiki-form-group select { padding: 3px 6px; font-size: 12px; border: 1px solid #ccc; border-radius: 4px; }
    .wiki-raw-yaml-textarea { width: 100%; height: 120px; font-family: "Cascadia Mono", "Cascadia Code", Consolas, "BIZ UDGothic", "Yu Gothic", "Meiryo", monospace; font-size: 12px; padding: 8px; border: 1px solid #ccc; border-radius: 4px; box-sizing: border-box; }
    .wiki-editor-textarea { flex: 1; min-height: 0; padding: 16px; font-family: "Cascadia Mono", "Cascadia Code", Consolas, "BIZ UDGothic", "Yu Gothic", "Meiryo", monospace; font-size: 13px; line-height: 1.5; border: none; resize: none; outline: none; }
    .wiki-editor-footer { background: #f6f8fa; padding: 8px 18px; border-top: 1px solid #e1e4e8; display: flex; justify-content: space-between; align-items: center; flex-shrink: 0; }
    .wiki-editor-cancel-btn { background: #6c757d; color: #fff; border: none; padding: 6px 14px; border-radius: 4px; cursor: pointer; font-size: 13px; }
    .wiki-editor-save-btn { background: #28a745; color: #fff; border: none; padding: 6px 16px; border-radius: 4px; cursor: pointer; font-size: 13px; font-weight: bold; }
    .shutdown-overlay { display: none; position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; background: rgba(0,0,0,0.85); color: #fff; z-index: 20000; flex-direction: column; justify-content: center; align-items: center; text-align: center; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "BIZ UDPGothic", "Yu Gothic UI", "Meiryo", "Hiragino Sans", sans-serif; }
    @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }

    /* TOAST UI Editor Typography Override for Optimal Japanese Rendering */
    .toastui-editor-defaultUI,
    .toastui-editor-contents,
    .toastui-editor-contents p,
    .toastui-editor-contents h1,
    .toastui-editor-contents h2,
    .toastui-editor-contents h3,
    .toastui-editor-contents h4,
    .toastui-editor-contents h5,
    .toastui-editor-contents h6,
    .toastui-editor-contents table,
    .toastui-editor-contents li,
    .ProseMirror {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "BIZ UDPGothic", "Yu Gothic UI", "Meiryo", "Hiragino Sans", sans-serif !important;
    }
    .toastui-editor-contents code,
    .toastui-editor-contents pre,
    .toastui-editor-contents pre code,
    .toastui-editor-md-container textarea,
    .toastui-editor-md-container .ProseMirror {
        font-family: "Cascadia Mono", "Cascadia Code", Consolas, "BIZ UDGothic", "Yu Gothic", "Meiryo", monospace !important;
    }
</style>
</head>
<body>
    <header class="top-header">
        <a href="/" class="brand">📖 {20}</a>
        <nav class="top-nav">
            <a href="/">{3}</a>
            <a href="/stella">{25}</a>
            <a href="/recent">{4}</a>
            <a href="/tags">{5}</a>
            <a href="/maintenance">{6}</a>
            <a href="/authors">{7}</a>
            <a href="/settings">{19}</a>
            <a href="/api/index.json" target="_blank">{8}</a>
            <select onchange="switchWikiLanguage(this.value)" style="background: #2f363d; color: #fff; border: 1px solid #444; border-radius: 4px; padding: 2px 6px; font-size: 12px; cursor: pointer;">
                {9}
            </select>
            <button class="shutdown-btn" onclick="shutdownWikiServer()" title="{21}" style="background: #dc3545; color: #fff; border: none; padding: 4px 8px; border-radius: 4px; font-size: 12px; cursor: pointer; font-weight: bold;">✕ {21}</button>
        </nav>
        <form action="/search" method="GET" accept-charset="UTF-8" class="search-form">
            <input type="text" name="q" placeholder="{10}">
            <button type="submit">🔍 {11}</button>
        </form>
    </header>

    <div class="layout-container">
        <nav class="sidebar">
            <h2>{12}</h2>
            {1}
        </nav>
        <main class="main-content">
            {2}
        </main>
    </div>

    <!-- UI Shutdown Overlay -->
    <div id="shutdownOverlay" class="shutdown-overlay">
        <h2 id="shutdownTitle" style="font-size: 24px; margin-bottom: 12px;">サーバーをシャットダウン中...</h2>
        <p id="shutdownDesc" style="font-size: 14px; color: #ccc;">画面を閉じてキーボードの処理を完了できます。</p>
    </div>

    <script>
        function shutdownWikiServer() {
            if (!confirm("{22}")) { return; }
            var overlay = document.getElementById('shutdownOverlay');
            if (overlay) { overlay.style.display = 'flex'; }

            fetch('/api/shutdown', { method: 'POST' })
                .then(function(r) { return r.json(); })
                .then(function(data) {
                    if (document.getElementById('shutdownTitle')) {
                        document.getElementById('shutdownTitle').innerText = "{23}";
                    }
                    if (document.getElementById('shutdownDesc')) {
                        document.getElementById('shutdownDesc').innerText = "{24}";
                    }
                })
                .catch(function(err) {
                    if (document.getElementById('shutdownTitle')) {
                        document.getElementById('shutdownTitle').innerText = "{23}";
                    }
                });
        }

        document.addEventListener('DOMContentLoaded', function() {
            var searchLoadingTxt = "{31}";
            document.querySelectorAll('form[action="/search"]').forEach(function(f) {
                f.addEventListener('submit', function() {
                    var btn = f.querySelector('button[type="submit"]');
                    if (btn) {
                        btn.disabled = true;
                        btn.innerHTML = '<span style="display:inline-block; width:12px; height:12px; border:2px solid #fff; border-top-color:transparent; border-radius:50%; animation:spin 0.8s linear infinite; vertical-align:middle; margin-right:6px;"></span> ' + (searchLoadingTxt || btn.textContent || '');
                    }
                    var banner = document.getElementById('searchProgressBanner');
                    if (banner) {
                        banner.style.display = 'flex';
                    }
                });
            });
        });
    </script>

    {222}
</body>
</html>
'@

    $fullHtml = $template.Replace("{0}", $PageTitle).Replace("{1}", $sidebarHtml).Replace("{2}", $BodyContent).Replace("{3}", $navHome).Replace("{4}", $navRecent).Replace("{5}", $navTags).Replace("{6}", $navMaint).Replace("{7}", $navAuthors).Replace("{8}", $navApi).Replace("{9}", $langOptionsStr).Replace("{10}", $searchHolder).Replace("{11}", $searchBtnTxt).Replace("{12}", $docListTitle).Replace("{18}", $Lang).Replace("{19}", $navSettings).Replace("{20}", $navBrand).Replace("{21}", $navShutdown).Replace("{22}", $shutdownConfirmJs).Replace("{23}", $shutdownDoneTitleJs).Replace("{24}", $shutdownDoneDescJs).Replace("{25}", $navStella).Replace("{31}", $searchLoadingTxtJs).Replace("{222}", $editorModalHtml)

    if (-not [string]::IsNullOrWhiteSpace($chatWidgetHtml)) {
        $fullHtml = $fullHtml.Replace("</body>", "$chatWidgetHtml`n</body>")
    }

    return $fullHtml
}
