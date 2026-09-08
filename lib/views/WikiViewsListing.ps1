# ==============================================================================
#  WikiViewsListing.ps1
#  SimpleWiki - Listing & API Views
#  Encoding: UTF-8 with BOM
# ==============================================================================

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

        $tagsArr = if ($item.Tags) { @($item.Tags) } else { @() }
        $linksArr = if ($item.Links) { @($item.Links) } else { @() }

        $fullObj = [PSCustomObject]@{
            Title       = $item.Title
            Description = $item.Description
            Author      = $item.Author
            Domain      = $item.Domain
            Tags        = @($tagsArr)
            LastUpdated = $lastUpdStr
            CreatedAt   = $createdStr
            UpdatedAt   = $updatedStr
            Status      = $item.Status
            HasYaml     = $item.HasYaml
            RelPath     = $item.RelPath
            Links       = @($linksArr)
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

function Get-GlossaryBoxHtml {
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

function Render-GlossaryBoxHtml {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param (
        [string]$Term,
        [string]$TargetWikiDir
    )
    return Get-GlossaryBoxHtml -Term $Term -TargetWikiDir $TargetWikiDir
}

function Get-RecentViewHtml {
    param (
        [string]$Lang = "ja"
    )

    Initialize-WikiIndex -TargetWikiDir $wikiDir
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

function Get-TagsViewHtml {
    param (
        [string]$SelectedTag = "",
        [string]$Lang = "ja"
    )

    Initialize-WikiIndex -TargetWikiDir $wikiDir

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

function Get-DocListHtml {
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

function Render-DocList {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param (
        $docArray,
        [string]$emptyMsg
    )
    return Get-DocListHtml -docArray $docArray -emptyMsg $emptyMsg
}

function Get-AuthorsViewHtml {
    param (
        [string]$SelectedAuthor = "",
        [string]$Lang = "ja"
    )

    Initialize-WikiIndex -TargetWikiDir $wikiDir

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
