# ==============================================================================
#  SimpleWiki HTML ビュー & UI コンポーネント描画モジュール
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================

function Get-SidebarHtml {
    param ($currentRelPath)

    if ($null -eq $script:SidebarCachedHtml -or [string]::IsNullOrEmpty($script:SidebarCachedHtml)) {
        if ($null -eq $script:SidebarMdFiles -or $script:SidebarMdFiles.Count -eq 0) {
            $script:SidebarMdFiles = Get-ChildItem -Path $wikiDir -Recurse -Filter "*.md" |
                Where-Object { $_.FullName -notmatch '[\\/]\.(git|lib|tests|dist)[\\/]' } |
                Sort-Object FullName
        }

        $treeNode = Build-ServerFileTreeNode -allMdFiles $script:SidebarMdFiles -wikiDir $wikiDir
        $treeHtml = Render-ServerFolderTreeHtml -node $treeNode -currentRelPath "" -wikiDir $wikiDir

        $refreshButtonHtml = @'
<div style="margin-top: 20px; padding: 10px; border-top: 1px solid #e1e4e8;">
    <button onclick="refreshWikiSidebarCache(this)" style="width: 100%; padding: 6px 12px; font-size: 12px; background: #fff; border: 1px solid #d1d5da; border-radius: 6px; cursor: pointer; color: #586069; display: flex; align-items: center; justify-content: center; gap: 4px;">
        🔄 キャッシュクリア
    </button>
</div>
<script>
function refreshWikiSidebarCache(btn) {
    btn.disabled = true;
    btn.innerText = "⏳ 処理中...";
    fetch('/api/clear-cache')
        .then(res => res.json())
        .then(data => {
            if (data.success) {
                location.reload();
            } else {
                alert("キャッシュクリアに失敗しました。");
                btn.disabled = false;
                btn.innerText = "🔄 キャッシュクリア";
            }
        })
        .catch(err => {
            alert("エラーが発生しました。");
            btn.disabled = false;
            btn.innerText = "🔄 キャッシュクリア";
        });
}
</script>
'@
        $script:SidebarCachedHtml = $treeHtml + $refreshButtonHtml
    }

    return $script:SidebarCachedHtml
}

# --- ディレクトリ一覧 HTML 生成関数 ---
function Get-DirectoryListingHtml {
    param (
        [string]$DirFullPath,
        [string]$RawUrlPath
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
        $html += "<p>このフォルダにはコンテンツがありません。</p>`n"
    } else {
        $totalCount = $subDirs.Count + $mdFiles.Count
        $html += "<p style='color:#586069; font-size:13px;'>$totalCount 件のアイテム</p>`n"
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

    $html += "<div class='dir-listing-notice'>ℹ️ index.md / README.md がないため、フォルダ一覧を表示しています。</div>`n"

    return $html
}

# --- OKF トップバー ＆ フッターカード レンダリング関数 ---
function Get-OkfTopBarHtml {
    param (
        [Parameter(Mandatory = $true)]$Meta,
        [string]$RelPath = ""
    )

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

    $editBtnHtml = ""
    if (-not [string]::IsNullOrWhiteSpace($RelPath)) {
        $safeRel = [System.Net.WebUtility]::HtmlEncode($RelPath.Replace("\", "/"))
        $editBtnHtml = "<button class='edit-doc-btn' data-relpath='$safeRel' onclick='openWikiEditor(this)'>✏️ 編集</button>"
    }

    return @"
$warningBanner
<div class="okf-top-bar">
    <div class="okf-top-left">
        <span class="okf-domain">📁 $domain</span>
        $statusBadge
        $editBtnHtml
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
    param (
        [Parameter(Mandatory = $true)]$Meta,
        [string]$RelPath = ""
    )
    return (Get-OkfTopBarHtml -Meta $Meta -RelPath $RelPath) + (Get-OkfFooterCardHtml -Meta $Meta)
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
            <label style="margin-left: auto; color: #24292e; font-weight: normal; font-size: 12px; cursor: pointer; display: flex; align-items: center; gap: 4px;"><input type="checkbox" id="okfIncludeCurrentPage" checked> 📄 開いているページを含める</label>
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
                    var srcHtml = "📖 <strong>根拠ドキュメント (Markdown):</strong><ul style='margin: 4px 0 0 16px; padding: 0;'>";
                    sources.forEach(function(s) {
                        var dateInfo = s.lastUpdated ? " (" + escapeHtml(s.lastUpdated) + ")" : "";
                        srcHtml += "<li>📄 <a href='" + escapeHtml(s.relUri) + "' target='_blank'>" + escapeHtml(s.title || s.relPath) + "</a>" + dateInfo + "</li>";
                    });
                    srcHtml += "</ul>";
                    srcDiv.innerHTML = srcHtml;
                    div.appendChild(srcDiv);
                } else {
                    var srcDiv = document.createElement("div");
                    srcDiv.className = "chat-sources";
                    srcDiv.innerHTML = "📖 <strong>根拠ドキュメント:</strong> なし (特定のドキュメント参照なし)";
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
                var includeCurrentPage = document.getElementById("okfIncludeCurrentPage") ? document.getElementById("okfIncludeCurrentPage").checked : true;
                var currentPath = decodeURIComponent(location.pathname).replace(/^\//, "");

                appendMsg("user", q);
                input.value = "";
                sendBtn.disabled = true;
                appendMsg("assistant", mode === "agentic" ? "🧠 自律深掘り調査中..." : "⚡ 検索・生成中...");

                fetch("/api/chat", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ mode: mode, message: q, history: chatHistory, includeCurrentPage: includeCurrentPage, currentRelPath: currentPath })
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
