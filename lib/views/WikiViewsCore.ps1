# ==============================================================================
#  WikiViewsCore.ps1
#  SimpleWiki - Core View Components
#  Encoding: UTF-8 with BOM
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
        Initialize-WikiIndex -TargetWikiDir $targetWiki
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

function Get-OkfTopBarHtml {
    param (
        [Parameter(Mandatory = $true)]$Meta,
        [string]$RelPath = "",
        [string]$Lang = "ja",
        [bool]$EditorEnabled = $true,
        [switch]$IsExportMode,
        [switch]$IsSingleFileMode,
        [string]$RelToRoot = "."
    )

    if ([string]::IsNullOrWhiteSpace($RelToRoot)) { $RelToRoot = "." }

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
            $tagHref = if ($IsExportMode) {
                if ($IsSingleFileMode) {
                    "#tag=$urlTag"
                } else {
                    "$RelToRoot/tags.html?tag=$urlTag#tag=$urlTag"
                }
            } else {
                "/tags?tag=$urlTag"
            }
            "<a href='$tagHref' class='tag-badge'>🏷️ $encTag</a>"
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
            $supHref = if ($IsExportMode) {
                if ($IsSingleFileMode) {
                    "#" + (Get-SinglePageId -relPath $Meta.SupersededBy)
                } else {
                    $cleanSup = $Meta.SupersededBy.Replace('\', '/').TrimStart('/') -replace '\.md$', '.html'
                    "$RelToRoot/" + [Uri]::EscapeUriString($cleanSup)
                }
            } else {
                "/" + [Uri]::EscapeUriString($Meta.SupersededBy.Replace('\', '/').TrimStart('/'))
            }
            $supersededHtml = "<br><span style='margin-top:4px; display:inline-block;'>$supNotice<a href='$supHref' style='color:#735c0f; font-weight:bold; text-decoration:underline;'>📄 $encSup</a></span>"
        }
        "<div class=""warning-banner"">$warnText$supersededHtml</div>"
    } else { "" }

    $editBtnHtml = ""
    if (-not $IsExportMode -and $EditorEnabled -and -not [string]::IsNullOrWhiteSpace($RelPath)) {
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
        [string]$Lang = "ja",
        [switch]$IsExportMode,
        [switch]$IsSingleFileMode,
        [string]$RelToRoot = "."
    )

    if ([string]::IsNullOrWhiteSpace($RelToRoot)) { $RelToRoot = "." }

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
            $tagHref = if ($IsExportMode) {
                if ($IsSingleFileMode) {
                    "#tag=$urlTag"
                } else {
                    "$RelToRoot/tags.html?tag=$urlTag#tag=$urlTag"
                }
            } else {
                "/tags?tag=$urlTag"
            }
            "<a href='$tagHref' class='tag-badge'>🏷️ $encTag</a>"
        }
        $tagsHtml = "<div class='okf-tags'>" + ($tagBadges -join " ") + "</div>"
    }

    $authorHtml = if (-not [string]::IsNullOrWhiteSpace($author)) {
        $urlAuthor = [Uri]::EscapeDataString($Meta.Author)
        $authorHref = if ($IsExportMode) {
            if ($IsSingleFileMode) {
                "#author=$urlAuthor"
            } else {
                "$RelToRoot/authors.html?name=$urlAuthor#name=$urlAuthor"
            }
        } else {
            "/authors?name=$urlAuthor"
        }
        "<span class='okf-author'>$authorLbl<a href='$authorHref'>$author</a></span>"
    } else { "" }

    $apiHref = if ($IsExportMode) {
        if ($IsSingleFileMode) {
            "api/index.json"
        } else {
            "$RelToRoot/api/index.json"
        }
    } else {
        "/api/index.json"
    }

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
            $relHref = if ($IsExportMode) {
                if ($IsSingleFileMode) {
                    "#" + (Get-SinglePageId -relPath $r)
                } else {
                    $cleanRel = $r.Replace('\', '/').TrimStart('/') -replace '\.md$', '.html'
                    "$RelToRoot/" + [Uri]::EscapeUriString($cleanRel)
                }
            } else {
                "/" + [Uri]::EscapeUriString($r.Replace('\', '/').TrimStart('/'))
            }
            "<a href='$relHref' style='color:#0366d6; text-decoration:none;'>📄 $encRel</a>"
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
        <a href="$apiHref" target="_blank" class="okf-api-link">$apiJsonLbl</a>
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

function Initialize-WikiIndex {
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

function Ensure-WikiIndexLoaded {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param (
        [string]$TargetWikiDir
    )
    Initialize-WikiIndex -TargetWikiDir $TargetWikiDir
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

    $btnNewDoc          = Get-LocalizedStr -Key "btn_new_doc" -Lang $Lang
    $modalNewDocTitle   = Get-LocalizedStr -Key "modal_new_doc_title" -Lang $Lang
    $modalNewDocFolder  = Get-LocalizedStr -Key "modal_new_doc_folder" -Lang $Lang
    $modalNewDocFilename = Get-LocalizedStr -Key "modal_new_doc_filename" -Lang $Lang
    $modalNewDocPageTitle = Get-LocalizedStr -Key "modal_new_doc_page_title" -Lang $Lang
    $modalNewDocSubmit  = Get-LocalizedStr -Key "modal_new_doc_submit" -Lang $Lang
    $modalNewDocExists  = Get-LocalizedStr -Key "modal_new_doc_exists" -Lang $Lang
    $edCancel           = Get-LocalizedStr -Key "editor_cancel_btn" -Lang $Lang

    $modalNewDocExistsJs = ConvertTo-JsString $modalNewDocExists

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
    $navTools     = Get-LocalizedStr -Key "nav_tools" -Lang $Lang
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
<!-- Offline Mermaid.js -->
<script src="/lib/mermaid.min.js"></script>
<style>
    * { box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "BIZ UDPGothic", "Yu Gothic UI", "Meiryo", "Hiragino Sans", sans-serif; margin: 0; padding: 0; display: flex; flex-direction: column; height: 100vh; color: #24292e; background-color: #fff; }
    header.top-header { background: #1b1f23; color: #fff; padding: 10px 20px; display: flex; align-items: center; gap: 16px; flex-shrink: 0; flex-wrap: nowrap; }
    header.top-header .brand { color: #fff; font-weight: bold; font-size: 16px; text-decoration: none; white-space: nowrap; }
    header.top-header nav.top-nav { display: flex; gap: 8px; align-items: center; }
    header.top-header nav.top-nav a { color: #d1d5da; text-decoration: none; font-size: 13px; padding: 4px 8px; border-radius: 4px; white-space: nowrap; }
    header.top-header nav.top-nav a:hover { color: #fff; background: rgba(255,255,255,0.1); }
    header.top-header form.search-form { display: flex; gap: 4px; flex: 1; min-width: 0; max-width: 320px; }
    header.top-header form.search-form input { padding: 4px 8px; font-size: 12px; border: 1px solid #444; border-radius: 4px; background: #2f363d; color: #fff; flex: 1; min-width: 80px; }
    header.top-header form.search-form button { padding: 4px 8px; font-size: 12px; border: none; border-radius: 4px; background: #0366d6; color: #fff; cursor: pointer; white-space: nowrap; }
    .nav-dropdown { position: relative; display: inline-flex; align-items: center; }
    .nav-dropdown-trigger { color: #d1d5da; text-decoration: none; font-size: 13px; padding: 4px 8px; border-radius: 4px; cursor: pointer; background: none; border: none; font-family: inherit; white-space: nowrap; display: inline-flex; align-items: center; gap: 4px; }
    .nav-dropdown-trigger:hover { color: #fff; background: rgba(255,255,255,0.1); }
    .nav-dropdown-menu { display: none; position: absolute; top: 100%; left: 0; margin-top: 4px; background: #2f363d; border: 1px solid #444; border-radius: 6px; min-width: 200px; padding: 4px 0; z-index: 1000; box-shadow: 0 8px 24px rgba(0,0,0,0.4); }
    .nav-dropdown-menu::before { content: ''; position: absolute; top: -10px; left: 0; right: 0; height: 10px; background: transparent; }
    .nav-dropdown:hover .nav-dropdown-menu, .nav-dropdown:focus-within .nav-dropdown-menu { display: block; }
    .nav-dropdown-menu a { display: block; padding: 8px 16px; color: #d1d5da; text-decoration: none; font-size: 13px; white-space: nowrap; }
    .nav-dropdown-menu a:hover { background: rgba(255,255,255,0.1); color: #fff; }
    .nav-dropdown-menu .dropdown-divider { border-top: 1px solid #444; margin: 4px 0; }
    .nav-dropdown-menu .dropdown-item-widget { padding: 8px 16px; }
    .nav-dropdown-menu .dropdown-item-widget select { background: #1b1f23; color: #fff; border: 1px solid #555; border-radius: 4px; padding: 4px 8px; font-size: 12px; cursor: pointer; width: 100%; }
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
        <div class="nav-dropdown">
            <button type="button" class="brand nav-dropdown-trigger">📖 {20} ▾</button>
            <div class="nav-dropdown-menu">
                <a href="/">{3}</a>
                <a href="/recent">{4}</a>
                <a href="/tags">{5}</a>
                <a href="/authors">{7}</a>
            </div>
        </div>
        <form action="/search" method="GET" accept-charset="UTF-8" class="search-form">
            <input type="text" name="q" placeholder="{10}">
            <button type="submit">🔍 {11}</button>
        </form>
        <nav class="top-nav">
            <button type="button" onclick="openNewDocModal()" style="background: #28a745; color: #fff; border: none; padding: 4px 10px; border-radius: 4px; font-size: 12px; font-weight: bold; cursor: pointer; white-space: nowrap;">{34}</button>
            <a href="/stella">{25}</a>
        </nav>
        <div class="nav-dropdown">
            <button class="nav-dropdown-trigger">{33} ▾</button>
            <div class="nav-dropdown-menu">
                <a href="/maintenance">{6}</a>
                <a href="/settings">{19}</a>
                <a href="/api/index.json" target="_blank">{8}</a>
                <div class="dropdown-divider"></div>
                <div class="dropdown-item-widget">
                    <select onchange="switchWikiLanguage(this.value)">
                        {9}
                    </select>
                </div>
            </div>
        </div>
        <button class="shutdown-btn" onclick="shutdownWikiServer()" title="{21}" style="background: #dc3545; color: #fff; border: none; padding: 4px 8px; border-radius: 4px; font-size: 12px; cursor: pointer; font-weight: bold;">✕</button>
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

            // Offline Mermaid Renderer
            if (typeof mermaid !== 'undefined') {
                document.querySelectorAll('pre code.language-mermaid').forEach(function(el) {
                    var pre = el.parentElement;
                    var div = document.createElement('div');
                    div.className = 'mermaid';
                    div.textContent = el.textContent;
                    pre.parentElement.replaceChild(div, pre);
                });
                document.querySelectorAll('pre.mermaid').forEach(function(pre) {
                    var div = document.createElement('div');
                    div.className = 'mermaid';
                    div.textContent = pre.textContent;
                    pre.parentElement.replaceChild(div, pre);
                });
                try {
                    mermaid.initialize({ startOnLoad: false, theme: 'default' });
                    mermaid.run({ nodes: Array.from(document.querySelectorAll('.mermaid:not([data-processed])')) });
                } catch(e) {
                    console.error('Mermaid initialization error:', e);
                }
            }
        });
    </script>

    <!-- New Page Creation Modal -->
    <div id="newDocModal" class="wiki-editor-modal">
        <div class="wiki-editor-container" style="width: 480px; height: auto; max-height: 90vh;">
            <div class="wiki-editor-header">
                <span>{35}</span>
                <button type="button" onclick="closeNewDocModal()" style="background:none; border:none; color:#fff; font-size:16px; cursor:pointer;">✕</button>
            </div>
            <div style="padding: 20px; display: flex; flex-direction: column; gap: 14px;">
                <div class="wiki-form-group">
                    <label for="newDocFolder">{36}</label>
                    <input type="text" id="newDocFolder" value="docs/" placeholder="docs/">
                </div>
                <div class="wiki-form-group">
                    <label for="newDocFileName">{37}</label>
                    <input type="text" id="newDocFileName" placeholder="quickstart.md">
                </div>
                <div class="wiki-form-group">
                    <label for="newDocPageTitle">{38}</label>
                    <input type="text" id="newDocPageTitle" placeholder="クイックスタートガイド">
                </div>
                <div id="newDocError" style="color: #dc3545; font-size: 12px; display: none;"></div>
            </div>
            <div class="wiki-editor-footer" style="justify-content: flex-end; gap: 8px;">
                <button class="wiki-editor-cancel-btn" onclick="closeNewDocModal()">{40}</button>
                <button class="wiki-editor-save-btn" onclick="submitNewDocument()">{39}</button>
            </div>
        </div>
    </div>

    <script>
        function openNewDocModal() {
            document.getElementById("newDocFileName").value = "";
            document.getElementById("newDocPageTitle").value = "";
            document.getElementById("newDocError").style.display = "none";
            document.getElementById("newDocModal").style.display = "flex";
        }

        function closeNewDocModal() {
            document.getElementById("newDocModal").style.display = "none";
        }

        function submitNewDocument() {
            var folder = document.getElementById("newDocFolder").value.trim().replace(/\\/g, '/');
            var filename = document.getElementById("newDocFileName").value.trim();
            var title = document.getElementById("newDocPageTitle").value.trim();
            var errEl = document.getElementById("newDocError");

            if (!filename) {
                errEl.textContent = "ファイル名を入力してください。";
                errEl.style.display = "block";
                return;
            }
            if (!filename.toLowerCase().endsWith(".md")) {
                filename += ".md";
            }

            if (filename.indexOf("..") !== -1 || folder.indexOf("..") !== -1 || /[\\:*?"<>|]/.test(filename)) {
                errEl.textContent = "不正な文字またはパス記号が含まれています。";
                errEl.style.display = "block";
                return;
            }

            if (folder && !folder.endsWith("/")) {
                folder += "/";
            }
            var fullRelPath = (folder + filename).replace(/^\/+/, "");

            fetch("/api/raw?relPath=" + encodeURIComponent(fullRelPath))
                .then(r => {
                    if (r.ok) {
                        errEl.textContent = "{41}";
                        errEl.style.display = "block";
                        return true;
                    }
                    return false;
                })
                .then(exists => {
                    if (exists) return;

                    closeNewDocModal();
                    var dummyBtn = document.createElement("button");
                    dummyBtn.setAttribute("data-relpath", fullRelPath);

                    openWikiEditor(dummyBtn);

                    document.getElementById("metaTitle").value = title || filename.replace(/\.md$/i, "");
                    document.getElementById("metaType").value = "Guide";
                    document.getElementById("metaStatus").value = "draft";
                    document.getElementById("metaVersion").value = "1.0.0";
                    setEditorDateToday();
                    setEditorContent("# " + (title || filename.replace(/\.md$/i, "")) + "\n\n");
                    if (typeof updateSavedSnapshot === "function") {
                        updateSavedSnapshot();
                    }
                })
                .catch(err => {
                    errEl.textContent = "エラーが発生しました: " + err;
                    errEl.style.display = "block";
                });
        }
    </script>

    {222}
</body>
</html>
'@

    $fullHtml = $template.Replace("{0}", $PageTitle).Replace("{1}", $sidebarHtml).Replace("{2}", $BodyContent).Replace("{3}", $navHome).Replace("{4}", $navRecent).Replace("{5}", $navTags).Replace("{6}", $navMaint).Replace("{7}", $navAuthors).Replace("{8}", $navApi).Replace("{9}", $langOptionsStr).Replace("{10}", $searchHolder).Replace("{11}", $searchBtnTxt).Replace("{12}", $docListTitle).Replace("{18}", $Lang).Replace("{19}", $navSettings).Replace("{20}", $navBrand).Replace("{21}", $navShutdown).Replace("{22}", $shutdownConfirmJs).Replace("{23}", $shutdownDoneTitleJs).Replace("{24}", $shutdownDoneDescJs).Replace("{25}", $navStella).Replace("{31}", $searchLoadingTxtJs).Replace("{33}", $navTools).Replace("{34}", $btnNewDoc).Replace("{35}", $modalNewDocTitle).Replace("{36}", $modalNewDocFolder).Replace("{37}", $modalNewDocFilename).Replace("{38}", $modalNewDocPageTitle).Replace("{39}", $modalNewDocSubmit).Replace("{40}", $edCancel).Replace("{41}", $modalNewDocExistsJs).Replace("{222}", $editorModalHtml)

    if (-not [string]::IsNullOrWhiteSpace($chatWidgetHtml)) {
        $fullHtml = $fullHtml.Replace("</body>", "$chatWidgetHtml`n</body>")
    }

    return $fullHtml
}
