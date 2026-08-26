# ==============================================================================
#  SimpleWiki HTML ビュー & UI コンポーネント描画モジュール
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================

function Get-SidebarHtml {
    param (
        $currentRelPath,
        [string]$Lang = "ja"
    )

    if ($null -eq $script:SidebarCachedHtml -or [string]::IsNullOrEmpty($script:SidebarCachedHtml)) {
        if ($null -ne $script:WikiIndex -and $script:WikiIndex.Count -gt 0) {
            # インデックス構築済みの場合はインデックスデータから高速にツリー生成（ファイルIO不要）
            $treeNode = [PSCustomObject]@{
                Files      = [System.Collections.Generic.List[PSObject]]::new()
                SubFolders = [ordered]@{}
            }
            foreach ($item in $script:WikiIndex) {
                $rel = $item.RelPath
                $parts = $rel -split '[\\/]'
                $curr = $treeNode
                for ($i = 0; $i -lt $parts.Length - 1; $i++) {
                    $fn = $parts[$i]
                    if (-not $curr.SubFolders.Contains($fn)) {
                        $curr.SubFolders[$fn] = [PSCustomObject]@{
                            Files      = [System.Collections.Generic.List[PSObject]]::new()
                            SubFolders = [ordered]@{}
                        }
                    }
                    $curr = $curr.SubFolders[$fn]
                }
                $fileMock = [PSCustomObject]@{
                    FullName = (Join-Path $wikiDir $rel)
                    BaseName = [System.IO.Path]::GetFileNameWithoutExtension($rel)
                }
                $curr.Files.Add($fileMock)
            }
            $treeHtml = Render-ServerFolderTreeHtml -node $treeNode -currentRelPath "" -wikiDir $wikiDir
            $script:SidebarCachedHtml = $treeHtml
        } elseif ($null -eq $script:SidebarMdFiles -or $script:SidebarMdFiles.Count -eq 0) {
            # インデックス構築中は直下のトップレベルフォルダ/ファイルのみを軽量取得
            $topItems = @(Get-ChildItem -Path $wikiDir -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '^\.(git|lib|tests|dist|\.cache)$' })
            $mdFiles = @($topItems | Where-Object { $_.Extension -eq ".md" } | Sort-Object Name)
            $subDirs = @($topItems | Where-Object { $_.PSIsContainer } | Sort-Object Name)

            $treeNode = [PSCustomObject]@{
                Files      = [System.Collections.Generic.List[PSObject]]::new()
                SubFolders = [ordered]@{}
            }
            foreach ($f in $mdFiles) { $treeNode.Files.Add($f) }
            foreach ($d in $subDirs) {
                $treeNode.SubFolders[$d.Name] = [PSCustomObject]@{
                    Files      = [System.Collections.Generic.List[PSObject]]::new()
                    SubFolders = [ordered]@{}
                }
            }
            $treeHtml = Render-ServerFolderTreeHtml -node $treeNode -currentRelPath "" -wikiDir $wikiDir
            $script:SidebarCachedHtml = $treeHtml
        }
    }

    $clearCacheText = Get-LocalizedStr -Key "sidebar_clear_cache" -Lang $Lang
    $procText       = Get-LocalizedStr -Key "sidebar_processing" -Lang $Lang
    $failText       = Get-LocalizedStr -Key "sidebar_clear_failed" -Lang $Lang
    $errText        = Get-LocalizedStr -Key "sidebar_error" -Lang $Lang

    $refreshButtonHtml = @"
<div style="margin-top: 20px; padding: 10px; border-top: 1px solid #e1e4e8;">
    <button onclick="refreshWikiSidebarCache(this)" style="width: 100%; padding: 6px 12px; font-size: 12px; background: #fff; border: 1px solid #d1d5da; border-radius: 6px; cursor: pointer; color: #586069; display: flex; align-items: center; justify-content: center; gap: 4px;">
        $clearCacheText
    </button>
</div>
<script>
function refreshWikiSidebarCache(btn) {
    btn.disabled = true;
    btn.innerText = "$procText";
    fetch('/api/clear-cache')
        .then(res => res.json())
        .then(data => {
            if (data.success) {
                location.reload();
            } else {
                alert("$failText");
                btn.disabled = false;
                btn.innerText = "$clearCacheText";
            }
        })
        .catch(err => {
            alert("$errText");
            btn.disabled = false;
            btn.innerText = "$clearCacheText";
        });
}
</script>
"@

    return $script:SidebarCachedHtml + $refreshButtonHtml
}

# --- ディレクトリ一覧 HTML 生成関数 ---
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
        [string]$Lang = "ja"
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
    if (-not [string]::IsNullOrWhiteSpace($RelPath)) {
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
        $fullObj = [PSCustomObject]@{
            Title       = $item.Title
            Description = $item.Description
            Author      = $item.Author
            Domain      = $item.Domain
            Tags        = $item.Tags
            LastUpdated = $lastUpdStr
            Status      = $item.Status
            HasYaml     = $item.HasYaml
            RelPath     = $item.RelPath
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

# --- 最近の更新一覧ビュー生成関数 ---
function Get-RecentViewHtml {
    param (
        [string]$Lang = "ja"
    )

    if ($null -eq $script:WikiIndex -or $script:WikiIndex.Count -eq 0) {
        if (-not (Load-WikiIndexCache -TargetWikiDir $wikiDir)) {
            Build-WikiIndex -TargetWikiDir $wikiDir | Out-Null
        }
    }
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

    if ($null -eq $script:WikiIndex -or $script:WikiIndex.Count -eq 0) {
        if (-not (Load-WikiIndexCache -TargetWikiDir $wikiDir)) {
            Build-WikiIndex -TargetWikiDir $wikiDir | Out-Null
        }
    }

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

        $cardsHtml = foreach ($item in $filtered) {
            $relUri = "/" + [Uri]::EscapeUriString($item.RelPath.Replace('\', '/'))
            $title  = [System.Net.WebUtility]::HtmlEncode($item.Title)
            $desc   = [System.Net.WebUtility]::HtmlEncode($item.Description)
            "<div class='search-item'><h3><a href='$relUri'>$title</a></h3><p>$desc</p></div>"
        }

        return @"
<h1>$tagResultsTitle</h1>
<p><a href="/tags">$backToTags</a></p>
<div class="tag-results">
    $($cardsHtml -join "`n")
</div>
"@
    }
}

# --- 品質・メンテナンスダッシュボード生成関数 ---
function Render-DocList {
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

    if ($null -eq $script:WikiIndex -or $script:WikiIndex.Count -eq 0) {
        if (-not (Load-WikiIndexCache -TargetWikiDir $wikiDir)) {
            Build-WikiIndex -TargetWikiDir $wikiDir | Out-Null
        }
    }
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

    function Render-DocList ($docArray, $emptyMsg) {
        $arr = @($docArray)
        if ($arr.Count -eq 0) { return "<p class='empty-msg'>$emptyMsg</p>" }
        $items = foreach ($item in $arr) {
            $relUri  = "/" + [Uri]::EscapeUriString($item.RelPath.Replace('\', '/'))
            $title   = [System.Net.WebUtility]::HtmlEncode($item.Title)
            $lastUpd = $item.LastUpdated.ToString("yyyy-MM-dd")
            "<li><a href='$relUri'>$title</a> <span class='muted'>($lastUpd)</span></li>"
        }
        return "<ul>" + ($items -join "") + "</ul>"
    }

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

    if ($null -eq $script:WikiIndex -or $script:WikiIndex.Count -eq 0) {
        if (-not (Load-WikiIndexCache -TargetWikiDir $wikiDir)) {
            Build-WikiIndex -TargetWikiDir $wikiDir | Out-Null
        }
    }

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
function Render-SettingsSearchCard {
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

# --- システム設定ビュー生成メイン関数 ---
function Get-SettingsViewHtml {
    param (
        [string]$Lang = "ja"
    )

    $data = Get-SettingsViewData -Lang $Lang

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
