# ==============================================================================
#  Markdig + PowerShell 100% オフライン Wiki 静的 HTML エキスポート機能
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
param (
    [string]$RootFolder = "",
    [string]$OutputDir  = "",
    [Alias("Lang")]
    [string]$Language   = "",
    [switch]$SingleFile,
    [switch]$EmbedImages,
    [switch]$NoEmbedImages,
    [int]$MaxInlineImageSizeKB = 1024,
    [int]$MaxImageDimension = 1600,
    [ValidateSet("Runtime", "Svg")]
    [string]$MermaidMode = "Runtime",
    [switch]$NoApiJson,
    [switch]$NoTagsPage,
    [switch]$NoAuthorsPage
)

$scriptDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
$libDir    = Join-Path $scriptDir "lib"

# --- モジュールのロード (lib/*.ps1) ---
. (Join-Path $libDir "WikiI18n.ps1")
. (Join-Path $libDir "WikiMetadata.ps1")
. (Join-Path $libDir "WikiViews.ps1")
. (Join-Path $libDir "WikiExportHelpers.ps1")

Import-ExternalI18n -TargetScriptDir $scriptDir

$exportLang = $Language
if ([string]::IsNullOrWhiteSpace($exportLang)) {
    $configPath = Join-Path $scriptDir "config.json"
    if (Test-Path $configPath) {
        try {
            $cfg = (Get-Content $configPath -Raw -Encoding UTF8) | ConvertFrom-Json
            if ($cfg -and $cfg.defaultLanguage) { $exportLang = $cfg.defaultLanguage }
            elseif ($cfg -and $cfg.language) { $exportLang = $cfg.language }
        } catch {
            $null = $_ # Suppressed intentionally
        }
    }
}
if ([string]::IsNullOrWhiteSpace($exportLang) -or -not $script:I18n.ContainsKey($exportLang)) {
    $exportLang = "ja"
}

# 入力ルートフォルダの設定 (指定がない場合は markdown_sample フォルダ、存在しない場合は $PSScriptRoot)
$wikiDir = Get-WikiDir -RootFolder $RootFolder -TargetScriptDir $scriptDir

# 出力ディレクトリの設定
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $targetDistDir = Join-Path $scriptDir "dist"
} else {
    $targetDistDir = [System.IO.Path]::GetFullPath($OutputDir)
}

if (-not (Test-Path $targetDistDir)) {
    New-Item -ItemType Directory -Path $targetDistDir -Force | Out-Null
}

$isEmbedImagesMode = ($EmbedImages -or ($SingleFile -and -not $NoEmbedImages))

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  Markdig Wiki 静的 HTML エキスポート開始" -ForegroundColor Green
Write-Host "  入力元:       $wikiDir" -ForegroundColor Yellow
Write-Host "  出力先:       $targetDistDir" -ForegroundColor Cyan
Write-Host "  言語:         $exportLang" -ForegroundColor Cyan
Write-Host "  SingleFile:   $SingleFile" -ForegroundColor Cyan
Write-Host "  EmbedImages:  $isEmbedImagesMode (Max: ${MaxInlineImageSizeKB}KB, MaxDim: ${MaxImageDimension}px)" -ForegroundColor Cyan
Write-Host "  MermaidMode:  $MermaidMode" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Green

# --- 1. Markdig.dll および依存ライブラリのロード ---
$markdigDll = Join-Path $libDir "Markdig.dll"
if (-not (Test-Path $markdigDll)) {
    Write-Error "'lib' フォルダに Markdig.dll が見つかりません:`n$markdigDll"
    exit 1
}

Get-ChildItem -Path $libDir -Filter "*.dll" | ForEach-Object {
    if ($IsWindows -or $env:OS -eq "Windows_NT") { Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue }
    Add-Type -Path $_.FullName
}

function Build-FileTreeNode {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param ($allMdFiles, $wikiDir)

    $rootNode = [PSCustomObject]@{
        Files      = [System.Collections.Generic.List[PSObject]]::new()
        SubFolders = [ordered]@{}
    }

    $normWikiDir = if ($wikiDir) { $wikiDir.Replace('\', '/').TrimEnd('/') } else { "" }
    foreach ($file in $allMdFiles) {
        $normFullName = if ($file.FullName) { $file.FullName.Replace('\', '/') } else { "" }
        $relPath = if ($normWikiDir -and $normFullName.StartsWith($normWikiDir, [System.StringComparison]::OrdinalIgnoreCase)) {
            $normFullName.Substring($normWikiDir.Length).TrimStart('/')
        } else {
            $file.FullName.TrimStart('\', '/')
        }
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

function Test-ExportNodeHasActiveFile {
    param ($node, $currentFile)

    if (-not $currentFile) { return $false }

    foreach ($file in $node.Files) {
        if ($file.FullName -eq $currentFile.FullName) {
            return $true
        }
    }
    foreach ($subFolder in $node.SubFolders.Values) {
        if (Test-ExportNodeHasActiveFile -node $subFolder -currentFile $currentFile) {
            return $true
        }
    }
    return $false
}

function Render-ExportFolderTreeHtml {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param (
        $node,
        $currentFile,
        $currentUri,
        [switch]$IsSingleFileMode
    )

    $html = "<ul>`n"

    # 1. フォルダの描画 (再帰)
    $sortedFolderNames = if ($node.SubFolders) {
        @($node.SubFolders.Keys | Sort-Object)
    } else { @() }

    foreach ($folderName in $sortedFolderNames) {
        $subNode = $node.SubFolders[$folderName]
        $hasActive = Test-ExportNodeHasActiveFile -node $subNode -currentFile $currentFile
        $openAttr = if ($hasActive -or $IsSingleFileMode) { " open" } else { "" }
        $encodedFolder = [System.Net.WebUtility]::HtmlEncode($folderName)

        $html += "  <li class='nav-folder'>`n"
        $html += "    <details$openAttr>`n"
        $html += "      <summary class='folder-title'>&#128193; $encodedFolder</summary>`n"
        $html += "      " + (Render-ExportFolderTreeHtml -node $subNode -currentFile $currentFile -currentUri $currentUri -IsSingleFileMode:$IsSingleFileMode) + "`n"
        $html += "    </details>`n"
        $html += "  </li>`n"
    }

    # 2. ファイルの描画 (index.md / README.md を先頭に優先ソート)
    $sortedFiles = if ($node.Files) {
        @($node.Files | Sort-Object {
            if ($_.BaseName -eq "index") { 0 }
            elseif ($_.BaseName -eq "README") { 1 }
            else { 2 }
        }, BaseName)
    } else { @() }

    foreach ($file in $sortedFiles) {
        $encodedTitle = [System.Net.WebUtility]::HtmlEncode($file.BaseName)

        if ($IsSingleFileMode) {
            $relPath  = $file.FullName.Substring($wikiDir.Length).TrimStart("\", "/")
            $pageId   = Get-SinglePageId -relPath $relPath
            $isActive = ($pageId -eq "index")
            $activeClass = if ($isActive) { " class='active'" } else { "" }
            $html += "  <li class='nav-file'><a href='#$pageId'$activeClass>📄 $encodedTitle</a></li>`n"
        } else {
            $fileHtmlPath = $file.FullName -replace '\.md$', '.html'
            $fileUri      = New-Object System.Uri($fileHtmlPath)
            $relHref      = $currentUri.MakeRelativeUri($fileUri).ToString()

            $isActive = ($currentFile -and $file.FullName -eq $currentFile.FullName)
            $activeClass = if ($isActive) { " class='active'" } else { "" }

            $html += "  <li class='nav-file'><a href='$relHref'$activeClass>📄 $encodedTitle</a></li>`n"
        }
    }

    $html += "</ul>"
    return $html
}

function Get-ExportSidebarHtml {
    param ($currentFile, $allMdFiles, $wikiDir, [switch]$IsSingleFileMode)

    if ($IsSingleFileMode) {
        $treeNode = Build-FileTreeNode -allMdFiles $allMdFiles -wikiDir $wikiDir
        return Render-ExportFolderTreeHtml -node $treeNode -currentFile $null -currentUri $null -IsSingleFileMode
    } else {
        $currentHtmlPath = $currentFile.FullName -replace '\.md$', '.html'
        $currentUri      = New-Object System.Uri($currentHtmlPath)

        $treeNode = Build-FileTreeNode -allMdFiles $allMdFiles -wikiDir $wikiDir
        return Render-ExportFolderTreeHtml -node $treeNode -currentFile $currentFile -currentUri $currentUri
    }
}

# --- 3. マークダウンファイルの抽出 ---
$allMdFiles = Get-ChildItem -Path $wikiDir -Recurse -Filter "*.md" |
    Where-Object { $_.FullName -notmatch '[\\/]\.(git|lib|tests|dist)[\\/]' } |
    Sort-Object FullName

$builder  = New-Object Markdig.MarkdownPipelineBuilder
$null     = [Markdig.MarkdownExtensions]::UseAdvancedExtensions($builder)
$null     = [Markdig.MarkdownExtensions]::UseYamlFrontMatter($builder)
$pipeline = $builder.Build()

$commonStyle = @'
    * { box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; margin: 0; padding: 0; display: flex; height: 100vh; color: #24292e; background-color: #fff; }
    nav { width: 260px; background-color: #f6f8fa; border-right: 1px solid #e1e4e8; padding: 20px 10px; overflow-y: auto; flex-shrink: 0; }
    nav h2 { font-size: 14px; text-transform: uppercase; color: #586069; margin: 0 0 10px 10px; letter-spacing: 0.5px; }
    nav ul { list-style: none; padding: 0; margin: 0; }
    nav ul ul { padding-left: 12px; margin-top: 2px; }
    nav li.nav-folder { margin-top: 4px; margin-bottom: 4px; }
    nav summary.folder-title { font-weight: bold; font-size: 13px; color: #586069; padding: 4px 6px; cursor: pointer; user-select: none; }
    nav summary.folder-title:hover { color: #0366d6; }
    nav li.nav-file a { display: block; padding: 4px 8px; color: #0366d6; text-decoration: none; border-radius: 6px; font-size: 14px; word-break: break-all; }
    nav li.nav-file a:hover { background-color: #f0f3f6; text-decoration: none; }
    nav li.nav-file a.active { background-color: #0366d6; color: #ffffff; font-weight: bold; }
    main { flex: 1; padding: 40px 60px; overflow-y: auto; }
    .markdown-body { max-width: 880px; margin: 0 auto; line-height: 1.6; }
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

    /* Tags & Glossary Static Views */
    .tag-cloud { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 16px; }
    .tag-cloud-item { background: #f1f8ff; color: #0366d6; border: 1px solid #c8e1ff; padding: 6px 12px; border-radius: 16px; text-decoration: none; font-size: 13px; font-weight: bold; }
    .tag-cloud-item:hover { background: #0366d6; color: #fff; text-decoration: none; }
    .tag-count { font-size: 11px; opacity: 0.8; font-weight: normal; }
    .glossary-box { background: #e8f4fd; border-left: 4px solid #0366d6; padding: 14px 18px; border-radius: 6px; margin-bottom: 24px; }
    .glossary-title { font-weight: bold; color: #0366d6; font-size: 15px; margin-bottom: 8px; }
    .glossary-content { font-size: 13px; color: #24292e; line-height: 1.6; }
    .tag-card, .search-item { border-bottom: 1px solid #e1e4e8; padding: 12px 0; }
    .tag-card h3, .search-item h3 { margin: 0 0 6px 0; font-size: 16px; }
    .tag-card a, .search-item a { color: #0366d6; text-decoration: none; }
    .tag-card a:hover, .search-item a:hover { text-decoration: underline; }
    .tag-card p, .search-item p { margin: 4px 0 0 0; font-size: 13px; color: #586069; }

    /* Single File Inline Tag & Author Filter Banner */
    .single-file-filter-banner { display: none; background: #e8f4fd; border: 1px solid #c8e1ff; color: #0366d6; padding: 10px 16px; border-radius: 6px; margin-bottom: 20px; font-size: 14px; }
    .single-file-filter-banner a { color: #0366d6; font-weight: bold; margin-left: 10px; text-decoration: underline; }

    /* Single page section divider */
    html { scroll-behavior: smooth; }
    .wiki-page { border-bottom: 2px solid #e1e4e8; padding-bottom: 40px; margin-bottom: 40px; }
    .wiki-page:last-child { border-bottom: none; margin-bottom: 0; padding-bottom: 0; }
'@

if ($SingleFile) {
    # --- モノリス HTML (アンカーナビゲーション方式) エキスポート ---
    $docListTitle = Get-LocalizedStr -Key "doc_list_title" -Lang $exportLang

    # ドキュメントルートの index.md を最優先（先頭）にソート
    $allMdFiles = @($allMdFiles | Sort-Object {
        $rel = $_.FullName.Substring($wikiDir.Length).TrimStart('\', '/')
        if ($rel -eq 'index.md') { 0 }
        elseif ($rel -eq 'README.md') { 1 }
        else { 2 }
    }, FullName)

    $sidebarHtml  = Get-ExportSidebarHtml -allMdFiles $allMdFiles -wikiDir $wikiDir -IsSingleFileMode

    $pagesHtmlList = [System.Collections.Generic.List[string]]::new()
    $globalImageCache = @{}
    $allApiItems = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($file in $allMdFiles) {
        $relPath  = $file.FullName.Substring($wikiDir.Length).TrimStart("\", "/")
        $pageId   = Get-SinglePageId -relPath $relPath

        $mdText   = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        $meta     = Get-DocumentMetadata -File $file -RelPath $relPath -MdText $mdText
        [void]$allApiItems.Add($meta)

        $bodyHtml = [Markdig.Markdown]::ToHtml($mdText, $pipeline)

        $okfTopBar   = Get-OkfTopBarHtml -Meta $meta -RelPath $relPath -Lang $exportLang -IsExportMode -IsSingleFileMode
        $okfFooter   = Get-OkfFooterCardHtml -Meta $meta -Lang $exportLang -IsExportMode -IsSingleFileMode
        $bodyHtml    = $okfTopBar + $bodyHtml + $okfFooter

        # リンク書き換え (相対 .md / .html リンクを #pageId または #anchorId に変換)
        $fileDirNorm = ([System.IO.Path]::GetDirectoryName($relPath)).Replace('\', '/').TrimEnd('/')

        $linkPattern = 'href=["'']([^"'':#]+?\.(?:md|html))(?:#([^"'']+))?["'']'
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            $targetPath = $match.Groups[1].Value
            $anchorId   = if ($match.Groups[2].Success -and -not [string]::IsNullOrWhiteSpace($match.Groups[2].Value)) { $match.Groups[2].Value } else { "" }

            # フルパスまたは正規化パスの判定
            $combined = if ([string]::IsNullOrWhiteSpace($fileDirNorm)) { $targetPath } else { "$fileDirNorm/$targetPath" }

            # ../ や ./ を解決
            $parts = $combined -split '/'
            $stack = [System.Collections.Generic.List[string]]::new()
            foreach ($p in $parts) {
                if ($p -eq '..') {
                    if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) }
                } elseif ($p -ne '.' -and $p -ne '') {
                    $stack.Add($p)
                }
            }
            $resolvedRelPath = $stack -join '/'
            $targetPageId = Get-SinglePageId -relPath $resolvedRelPath

            $targetHref = if ($anchorId) { "#$anchorId" } else { "#$targetPageId" }
            return "href=""$targetHref"""
        }

        $bodyHtml = [System.Text.RegularExpressions.Regex]::Replace($bodyHtml, $linkPattern, $evaluator)

        # 画像・アセットの相対パス解決 (ルート index.html 基準への正規化 ＆ Base64 埋め込み)
        $assetPattern = '((?:src|href)=["''])([^"'':#]+?\.(?:png|jpe?g|gif|svg|webp|ico|bmp|pdf|zip|mp4|webm))(["''])'
        $assetEvaluator = [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            $prefix    = $match.Groups[1].Value
            $assetPath = $match.Groups[2].Value
            $suffix    = $match.Groups[3].Value

            if ($assetPath.StartsWith('/') -or $assetPath.StartsWith('\')) {
                return $match.Value
            }

            $combined = if ([string]::IsNullOrWhiteSpace($fileDirNorm)) { $assetPath } else { "$fileDirNorm/$assetPath" }
            $parts = $combined -split '[\\/]'
            $stack = [System.Collections.Generic.List[string]]::new()
            foreach ($p in $parts) {
                if ($p -eq '..') {
                    if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) }
                } elseif ($p -ne '.' -and $p -ne '') {
                    $stack.Add($p)
                }
            }
            $resolvedPath = ($stack -join '/').Replace('\', '/')

            # Base64 インライン埋め込み判定 (画像 src 属性の場合)
            if ($isEmbedImagesMode -and $prefix -match '^src=' -and $resolvedPath -match '\.(png|jpe?g|gif|svg|webp|ico|bmp)$') {
                $localAssetFile = Join-Path $wikiDir ($resolvedPath.Replace('/', '\'))
                if (Test-Path -LiteralPath $localAssetFile) {
                    $dataUri = if ($globalImageCache.ContainsKey($localAssetFile)) {
                        $globalImageCache[$localAssetFile]
                    } else {
                        $res = Get-OptimizedImageBase64 -filePath $localAssetFile -maxSizeKB $MaxInlineImageSizeKB -maxDimension $MaxImageDimension
                        $globalImageCache[$localAssetFile] = $res
                        $res
                    }
                    if ($dataUri) {
                        return "$prefix$dataUri$suffix"
                    }
                }
            }

            return "$prefix$resolvedPath$suffix"
        }
        $bodyHtml = [System.Text.RegularExpressions.Regex]::Replace($bodyHtml, $assetPattern, $assetEvaluator)

        if ($MermaidMode -eq "Svg") {
            $bodyHtml = Convert-MermaidToSvgMarkup -html $bodyHtml
        }

        $tagsAttr   = if ($meta.Tags) { [System.Net.WebUtility]::HtmlEncode(($meta.Tags -join ",")) } else { "" }
        $authorAttr = if ($meta.Author) { [System.Net.WebUtility]::HtmlEncode($meta.Author) } else { "" }

        $pageSection = @"
<section class="wiki-page" id="$pageId" data-tags="$tagsAttr" data-author="$authorAttr">
    <div class="markdown-body">
        $bodyHtml
    </div>
</section>
"@
        $pagesHtmlList.Add($pageSection)
    }

    $allPagesContent = $pagesHtmlList -join "`n"

    $mermaidScriptInline = ""
    if ($MermaidMode -eq "Runtime") {
        $scriptMermaid = Join-Path $libDir "mermaid.min.js"
        if (Test-Path $scriptMermaid) {
            $mermaidJsCode = Get-Content -Path $scriptMermaid -Raw -Encoding UTF8
            $mermaidScriptInline = @"
<script>
$mermaidJsCode
</script>
"@
        }
        $mermaidInitScript = @"
<script>
document.addEventListener("DOMContentLoaded", function() {
    if (typeof mermaid === "undefined") return;
    document.querySelectorAll("pre code.language-mermaid").forEach(function(el) {
        var pre = el.parentElement;
        var div = document.createElement("div");
        div.className = "mermaid";
        div.textContent = (el.textContent || "").replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
        pre.replaceWith(div);
    });
    document.querySelectorAll("pre.mermaid").forEach(function(pre) {
        var div = document.createElement("div");
        div.className = "mermaid";
        div.textContent = (pre.textContent || "").replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
        pre.replaceWith(div);
    });
    try {
        mermaid.initialize({ startOnLoad: false, theme: "default" });
        mermaid.run({ nodes: Array.from(document.querySelectorAll(".mermaid:not([data-processed])")) });
    } catch(e) {
        console.error("Mermaid initialization error:", e);
    }
});
</script>
"@
    } else {
        $mermaidInitScript = ""
    }

    $bannerTagTpl    = Get-LocalizedStr -Key "filter_banner_tag" -Lang $exportLang
    $bannerAuthorTpl = Get-LocalizedStr -Key "filter_banner_author" -Lang $exportLang
    $bannerClearText = Get-LocalizedStr -Key "filter_banner_clear" -Lang $exportLang

    $navScript = @"
<script>
function escapeHtml(str) {
    return (str || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function updateActiveNav(hash) {
    if (!hash || hash.indexOf("#tag=") === 0 || hash.indexOf("#author=") === 0) hash = '#index';
    document.querySelectorAll('nav li.nav-file a').forEach(function(a) {
        a.classList.remove('active');
        if (a.getAttribute('href') === hash) {
            a.classList.add('active');
        }
    });
}

function clearFilter() {
    history.pushState("", document.title, window.location.pathname);
    checkHashFilter();
}

function checkHashFilter() {
    var hash = location.hash || "";
    var banner = document.getElementById("singleFileFilterBanner");

    if (hash.indexOf("#tag=") === 0) {
        var tag = decodeURIComponent(hash.substring(5)).trim().toLowerCase();
        var matchCount = 0;
        document.querySelectorAll(".wiki-page").forEach(function(sec) {
            var rawTags = (sec.getAttribute("data-tags") || "").toLowerCase().split(",");
            var tags = rawTags.map(function(t) { return t.trim(); });
            if (tags.indexOf(tag) !== -1) {
                sec.style.display = "";
                matchCount++;
            } else {
                sec.style.display = "none";
            }
        });
        if (banner) {
            var msg = "$bannerTagTpl".replace("{0}", escapeHtml(tag)).replace("{1}", matchCount);
            banner.innerHTML = msg + " <a href='javascript:void(0)' onclick='clearFilter()'>$bannerClearText</a>";
            banner.style.display = "block";
        }
        updateActiveNav("#tag=");
    } else if (hash.indexOf("#author=") === 0) {
        var author = decodeURIComponent(hash.substring(8)).trim().toLowerCase();
        var matchCount = 0;
        document.querySelectorAll(".wiki-page").forEach(function(sec) {
            var a = (sec.getAttribute("data-author") || "").toLowerCase().trim();
            if (a === author) {
                sec.style.display = "";
                matchCount++;
            } else {
                sec.style.display = "none";
            }
        });
        if (banner) {
            var msg = "$bannerAuthorTpl".replace("{0}", escapeHtml(author)).replace("{1}", matchCount);
            banner.innerHTML = msg + " <a href='javascript:void(0)' onclick='clearFilter()'>$bannerClearText</a>";
            banner.style.display = "block";
        }
        updateActiveNav("#author=");
    } else {
        document.querySelectorAll(".wiki-page").forEach(function(sec) {
            sec.style.display = "";
        });
        if (banner) {
            banner.style.display = "none";
        }
        updateActiveNav(hash);
        if (hash && hash.length > 1) {
            var targetEl = document.getElementById(hash.substring(1));
            if (targetEl) {
                setTimeout(function() { targetEl.scrollIntoView(); }, 100);
            }
        }
    }
}

window.addEventListener('hashchange', checkHashFilter);

document.addEventListener("DOMContentLoaded", function() {
    checkHashFilter();

    if ('IntersectionObserver' in window) {
        var observer = new IntersectionObserver(function(entries) {
            entries.forEach(function(entry) {
                if (entry.isIntersecting && !location.hash.startsWith('#tag=') && !location.hash.startsWith('#author=')) {
                    var id = entry.target.id;
                    if (id) {
                        updateActiveNav('#' + id);
                    }
                }
            });
        }, { rootMargin: '0px 0px -70% 0px' });

        document.querySelectorAll('.wiki-page').forEach(function(sec) {
            observer.observe(sec);
        });
    }
});
</script>
"@

    # api/index.json の出力
    if (-not $NoApiJson) {
        $apiEnvelope = [PSCustomObject]@{
            Total       = $allApiItems.Count
            Count       = $allApiItems.Count
            Offset      = 0
            Limit       = $allApiItems.Count
            IsTruncated = $false
            Items       = @($allApiItems | ForEach-Object {
                $lastUpdStr = if ($_.LastUpdated -is [DateTime]) { $_.LastUpdated.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $_.LastUpdated }
                $createdStr = if ($_.CreatedAt -is [DateTime]) { $_.CreatedAt.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $_.CreatedAt }
                $updatedStr = if ($_.UpdatedAt -is [DateTime]) { $_.UpdatedAt.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $_.UpdatedAt }
                [PSCustomObject]@{
                    Title       = $_.Title
                    Description = $_.Description
                    Author      = $_.Author
                    Domain      = $_.Domain
                    Tags        = @($_.Tags)
                    LastUpdated = $lastUpdStr
                    CreatedAt   = $createdStr
                    UpdatedAt   = $updatedStr
                    Status      = $_.Status
                    HasYaml     = $_.HasYaml
                    RelPath     = $_.RelPath
                    Links       = @($_.Links)
                }
            })
        }
        $apiJsonText = $apiEnvelope | ConvertTo-Json -Depth 5
        $apiDestDir  = Join-Path $targetDistDir "api"
        if (-not (Test-Path $apiDestDir)) { New-Item -ItemType Directory -Path $apiDestDir -Force | Out-Null }
        [System.IO.File]::WriteAllText((Join-Path $apiDestDir "index.json"), $apiJsonText, [System.Text.Encoding]::UTF8)
        Write-Host "  [API JSON 出力] -> api/index.json" -ForegroundColor Green
    }

    $monolithHtml = @"
<!DOCTYPE html>
<html lang="$exportLang">
<head>
<meta charset="UTF-8">
<title>SimpleWiki OKF (Single File)</title>
<style>
$commonStyle
</style>
$mermaidScriptInline
</head>
<body>
    <nav>
        <h2>$docListTitle</h2>
        $sidebarHtml
    </nav>
    <main>
        <div id="singleFileFilterBanner" class="single-file-filter-banner"></div>
        $allPagesContent
    </main>
    $mermaidInitScript
    $navScript
</body>
</html>
"@

    $monolithHtml = $monolithHtml -replace "\r?\n", "`r`n"
    $destFile = Join-Path $targetDistDir "index.html"
    [System.IO.File]::WriteAllText($destFile, $monolithHtml, [System.Text.Encoding]::UTF8)
    Write-Host "  [単一ファイル出力] -> index.html" -ForegroundColor Green

} else {
    # --- 標準複数ファイル静的 HTML エキスポート ---
    $template = @"
<!DOCTYPE html>
<html lang="{4}">
<head>
<meta charset="UTF-8">
<title>{0} - SimpleWiki OKF</title>
<style>
$commonStyle
</style>
</head>
<body>
    <nav>
        <h2>{5}</h2>
        {1}
    </nav>
    <main>
        <div class="markdown-body">
            {2}
        </div>
    </main>
    {3}
</body>
</html>
"@

    $globalImageCache = @{}
    $allApiItems = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($file in $allMdFiles) {
        $relPath  = $file.FullName.Substring($wikiDir.Length).TrimStart("\", "/")
        $htmlRel  = $relPath -replace '\.md$', '.html'
        $destFile = Join-Path $targetDistDir $htmlRel

        $destParent = [System.IO.Path]::GetDirectoryName($destFile)
        if (-not (Test-Path $destParent)) {
            New-Item -ItemType Directory -Path $destParent -Force | Out-Null
        }

        $mdText   = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        $meta     = Get-DocumentMetadata -File $file -RelPath $relPath -MdText $mdText
        [void]$allApiItems.Add($meta)

        $bodyHtml = [Markdig.Markdown]::ToHtml($mdText, $pipeline)

        $relToRoot   = Get-RelToRootPath -RelPath $relPath
        $okfTopBar   = Get-OkfTopBarHtml -Meta $meta -RelPath $relPath -Lang $exportLang -IsExportMode -RelToRoot $relToRoot
        $okfFooter   = Get-OkfFooterCardHtml -Meta $meta -Lang $exportLang -IsExportMode -RelToRoot $relToRoot
        $bodyHtml    = $okfTopBar + $bodyHtml + $okfFooter

        # 本文中の .md ハイパーリンクを .html に自動変換
        $bodyHtml = $bodyHtml -replace 'href="([^"]+)\.md"', 'href="$1.html"'
        $bodyHtml = $bodyHtml -replace "href='([^']+)\.md'", "href='$1.html'"

        # 画像の Base64 インライン埋め込み (EmbedImages 有効時)
        if ($isEmbedImagesMode) {
            $fileDirNorm = ([System.IO.Path]::GetDirectoryName($relPath)).Replace('\', '/').TrimEnd('/')
            $assetPattern = '((?:src)=["''])([^"'':#]+?\.(?:png|jpe?g|gif|svg|webp|ico|bmp))(["''])'
            $assetEvaluator = [System.Text.RegularExpressions.MatchEvaluator]{
                param($match)
                $prefix    = $match.Groups[1].Value
                $assetPath = $match.Groups[2].Value
                $suffix    = $match.Groups[3].Value

                if ($assetPath.StartsWith('/') -or $assetPath.StartsWith('\')) {
                    return $match.Value
                }

                $combined = if ([string]::IsNullOrWhiteSpace($fileDirNorm)) { $assetPath } else { "$fileDirNorm/$assetPath" }
                $parts = $combined -split '[\\/]'
                $stack = [System.Collections.Generic.List[string]]::new()
                foreach ($p in $parts) {
                    if ($p -eq '..') {
                        if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) }
                    } elseif ($p -ne '.' -and $p -ne '') {
                        $stack.Add($p)
                    }
                }
                $resolvedPath = ($stack -join '/').Replace('\', '/')
                $localAssetFile = Join-Path $wikiDir ($resolvedPath.Replace('/', '\'))
                if (Test-Path -LiteralPath $localAssetFile) {
                    $dataUri = if ($globalImageCache.ContainsKey($localAssetFile)) {
                        $globalImageCache[$localAssetFile]
                    } else {
                        $res = Get-OptimizedImageBase64 -filePath $localAssetFile -maxSizeKB $MaxInlineImageSizeKB -maxDimension $MaxImageDimension
                        $globalImageCache[$localAssetFile] = $res
                        $res
                    }
                    if ($dataUri) {
                        return "$prefix$dataUri$suffix"
                    }
                }
                return "$prefix$assetPath$suffix"
            }
            $bodyHtml = [System.Text.RegularExpressions.Regex]::Replace($bodyHtml, $assetPattern, $assetEvaluator)
        }

        if ($MermaidMode -eq "Svg") {
            $bodyHtml = Convert-MermaidToSvgMarkup -html $bodyHtml
        }

        $sidebarHtml = Get-ExportSidebarHtml -currentFile $file -allMdFiles $allMdFiles -wikiDir $wikiDir
        $pageTitle   = [System.Net.WebUtility]::HtmlEncode($meta.Title)

        if ($MermaidMode -eq "Runtime") {
            $destUri     = New-Object System.Uri($destFile)
            $mermaidDist = Join-Path $targetDistDir "lib\mermaid.min.js"
            $mermaidUri  = New-Object System.Uri($mermaidDist)
            $relMermaid  = $destUri.MakeRelativeUri($mermaidUri).ToString()

            $mermaidBlock = @"
<script src="$relMermaid"></script>
<script>
    document.addEventListener("DOMContentLoaded", function() {
        document.querySelectorAll("pre code.language-mermaid").forEach(function(el) {
            var pre = el.parentElement;
            var div = document.createElement("div");
            div.className = "mermaid";
            div.textContent = (el.textContent || "").replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
            pre.replaceWith(div);
        });
        document.querySelectorAll("pre.mermaid").forEach(function(pre) {
            var div = document.createElement("div");
            div.className = "mermaid";
            div.textContent = (pre.textContent || "").replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
            pre.replaceWith(div);
        });
        if (typeof mermaid !== "undefined") {
            try {
                mermaid.initialize({ startOnLoad: true, theme: "default" });
            } catch(e) {
                console.error("Mermaid initialization error:", e);
            }
        }
    });
</script>
"@
        } else {
            $mermaidBlock = ""
        }

        $docListTitle = Get-LocalizedStr -Key "doc_list_title" -Lang $exportLang
        $fullHtml = $template.Replace("{0}", $pageTitle).Replace("{1}", $sidebarHtml).Replace("{2}", $bodyHtml).Replace("{3}", $mermaidBlock).Replace("{4}", $exportLang).Replace("{5}", $docListTitle)
        $fullHtml = $fullHtml -replace "\r?\n", "`r`n"

        [System.IO.File]::WriteAllText($destFile, $fullHtml, [System.Text.Encoding]::UTF8)
        Write-Host "  [HTML 変換] $relPath -> $htmlRel" -ForegroundColor Green
    }

    $glossaryPath = Join-Path $wikiDir "glossary.md"
    $glossaryTerms = Get-GlossaryTerms -GlossaryPath $glossaryPath
    $glossaryJsonText = $glossaryTerms | ConvertTo-Json -Depth 3

    # api/index.json の静的ファイル出力
    $apiEnvelope = [PSCustomObject]@{
        Total       = $allApiItems.Count
        Count       = $allApiItems.Count
        Offset      = 0
        Limit       = $allApiItems.Count
        IsTruncated = $false
        Items       = @($allApiItems | ForEach-Object {
            $lastUpdStr = if ($_.LastUpdated -is [DateTime]) { $_.LastUpdated.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $_.LastUpdated }
            $createdStr = if ($_.CreatedAt -is [DateTime]) { $_.CreatedAt.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $_.CreatedAt }
            $updatedStr = if ($_.UpdatedAt -is [DateTime]) { $_.UpdatedAt.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $_.UpdatedAt }
            [PSCustomObject]@{
                Title       = $_.Title
                Description = $_.Description
                Author      = $_.Author
                Domain      = $_.Domain
                Tags        = @($_.Tags)
                LastUpdated = $lastUpdStr
                CreatedAt   = $createdStr
                UpdatedAt   = $updatedStr
                Status      = $_.Status
                HasYaml     = $_.HasYaml
                RelPath     = $_.RelPath
                Links       = @($_.Links)
            }
        })
    }
    $apiJsonText = $apiEnvelope | ConvertTo-Json -Depth 5

    if (-not $NoApiJson) {
        $apiDestDir  = Join-Path $targetDistDir "api"
        if (-not (Test-Path $apiDestDir)) { New-Item -ItemType Directory -Path $apiDestDir -Force | Out-Null }
        [System.IO.File]::WriteAllText((Join-Path $apiDestDir "index.json"), $apiJsonText, [System.Text.Encoding]::UTF8)
        Write-Host "  [API JSON 出力] -> api/index.json" -ForegroundColor Green
    }

    # 1. tags.html 出力
    if (-not $NoTagsPage) {
        $tagsHtmlFile       = Join-Path $targetDistDir "tags.html"
        $dummyCurrentFile   = [PSCustomObject]@{ FullName = Join-Path $wikiDir "tags.md" }
        $sidebarForSub      = Get-ExportSidebarHtml -currentFile $dummyCurrentFile -allMdFiles $allMdFiles -wikiDir $wikiDir
        $tagListTitle       = Get-LocalizedStr -Key "tag_list_title" -Lang $exportLang
        $docListTitle       = Get-LocalizedStr -Key "doc_list_title" -Lang $exportLang
        $tagDocsHeadingTpl  = Get-LocalizedStr -Key "tag_docs_heading" -Lang $exportLang
        $backToTagsText     = Get-LocalizedStr -Key "back_to_tags" -Lang $exportLang
        $glossaryTitleTpl   = Get-LocalizedStr -Key "tag_glossary_title" -Lang $exportLang
        $tagEmptyMsg        = Get-LocalizedStr -Key "tag_empty_msg" -Lang $exportLang
        $tagNoneRegistered  = Get-LocalizedStr -Key "tag_none_registered" -Lang $exportLang

        $tagsBodyContent = @"
<div id="tagViewContainer"></div>
<script id="wiki-index-data" type="application/json">
$apiJsonText
</script>
<script id="wiki-glossary-data" type="application/json">
$glossaryJsonText
</script>
<script>
document.addEventListener("DOMContentLoaded", function() {
    var rawIndex = JSON.parse(document.getElementById("wiki-index-data").textContent || "{}");
    var rawGlossary = JSON.parse(document.getElementById("wiki-glossary-data").textContent || "{}");
    var items = rawIndex.Items || [];

    function getParam() {
        var params = new URLSearchParams(location.search);
        var t = params.get("tag");
        if (!t && location.hash && location.hash.indexOf("#tag=") === 0) {
            t = decodeURIComponent(location.hash.substring(5));
        }
        return t ? t.trim() : "";
    }

    function render() {
        var tag = getParam();
        var container = document.getElementById("tagViewContainer");
        if (!container) return;

        if (tag) {
            var matching = items.filter(function(item) {
                return item.Tags && Array.isArray(item.Tags) && item.Tags.indexOf(tag) !== -1;
            });

            var heading = "$tagDocsHeadingTpl".replace("{0}", escapeHtml(tag)).replace("{1}", matching.length);
            var html = "<h1>" + heading + "</h1>";
            html += "<p><a href='tags.html' onclick='clearTagFilter(event)'>$backToTagsText</a></p>";

            if (rawGlossary[tag]) {
                var glossTitle = "$glossaryTitleTpl".replace("{0}", escapeHtml(tag));
                html += "<div class='glossary-box'><div class='glossary-title'>" + glossTitle + "</div><div class='glossary-content'>" + renderGlossaryText(rawGlossary[tag]) + "</div></div>";
            }

            if (matching.length === 0) {
                html += "<p style='color:#6a737d;'>$tagEmptyMsg</p>";
            } else {
                html += "<div class='tag-results'>";
                matching.forEach(function(item) {
                    var rel = (item.RelPath || "").replace(/\\/g, "/").replace(/\.md$/, ".html");
                    var title = escapeHtml(item.Title || "Untitled");
                    var desc = escapeHtml(item.Description || "");
                    html += "<div class='tag-card'><h3><a href='" + encodeURI(rel) + "'>📄 " + title + "</a></h3><p>" + desc + "</p></div>";
                });
                html += "</div>";
            }
            container.innerHTML = html;
        } else {
            var tagCounts = {};
            items.forEach(function(item) {
                if (item.Tags && Array.isArray(item.Tags)) {
                    item.Tags.forEach(function(t) {
                        if (t) tagCounts[t] = (tagCounts[t] || 0) + 1;
                    });
                }
            });

            var html = "<h1>$tagListTitle</h1><div class='tag-cloud'>";
            var sortedTags = Object.keys(tagCounts).sort();
            if (sortedTags.length === 0) {
                html += "<p style='color:#6a737d;'>$tagNoneRegistered</p>";
            } else {
                sortedTags.forEach(function(t) {
                    html += "<a href='#tag=" + encodeURIComponent(t) + "' class='tag-cloud-item'>🏷️ " + escapeHtml(t) + " <span class='tag-count'>(" + tagCounts[t] + ")</span></a>";
                });
            }
            html += "</div>";
            container.innerHTML = html;
        }
    }

    function escapeHtml(str) {
        return (str || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    }

    function renderGlossaryText(str) {
        return escapeHtml(str).replace(/\r?\n/g, "<br>");
    }

    window.clearTagFilter = function(e) {
        if (e) e.preventDefault();
        history.pushState("", document.title, window.location.pathname);
        render();
    };

    window.addEventListener("hashchange", render);
    render();
});
</script>
"@

        $fullTagsHtml = $template.Replace("{0}", $tagListTitle).Replace("{1}", $sidebarForSub).Replace("{2}", $tagsBodyContent).Replace("{3}", "").Replace("{4}", $exportLang).Replace("{5}", $docListTitle)
        $fullTagsHtml = $fullTagsHtml -replace "\r?\n", "`r`n"
        [System.IO.File]::WriteAllText($tagsHtmlFile, $fullTagsHtml, [System.Text.Encoding]::UTF8)
        Write-Host "  [HTML 変換] tags.html" -ForegroundColor Green
    }

    # 2. authors.html 出力
    if (-not $NoAuthorsPage) {
        $authorsHtmlFile      = Join-Path $targetDistDir "authors.html"
        $authorListTitle      = Get-LocalizedStr -Key "author_list_title" -Lang $exportLang
        $authorDocsHeadingTpl = Get-LocalizedStr -Key "author_docs_heading" -Lang $exportLang
        $backToAuthorsText    = Get-LocalizedStr -Key "back_to_authors" -Lang $exportLang
        $authorEmptyMsg       = Get-LocalizedStr -Key "author_empty_msg" -Lang $exportLang
        $authorNoneRegistered = Get-LocalizedStr -Key "author_none_registered" -Lang $exportLang

        $authorsBodyContent = @"
<div id="authorViewContainer"></div>
<script id="wiki-index-data" type="application/json">
$apiJsonText
</script>
<script>
document.addEventListener("DOMContentLoaded", function() {
    var rawIndex = JSON.parse(document.getElementById("wiki-index-data").textContent || "{}");
    var items = rawIndex.Items || [];

    function getParam() {
        var params = new URLSearchParams(location.search);
        var name = params.get("name");
        if (!name && location.hash && location.hash.indexOf("#name=") === 0) {
            name = decodeURIComponent(location.hash.substring(6));
        }
        return name ? name.trim() : "";
    }

    function render() {
        var author = getParam();
        var container = document.getElementById("authorViewContainer");
        if (!container) return;

        if (author) {
            var matching = items.filter(function(item) {
                return item.Author && item.Author === author;
            });

            var heading = "$authorDocsHeadingTpl".replace("{0}", escapeHtml(author)).replace("{1}", matching.length);
            var html = "<h1>" + heading + "</h1>";
            html += "<p><a href='authors.html' onclick='clearAuthorFilter(event)'>$backToAuthorsText</a></p>";

            if (matching.length === 0) {
                html += "<p style='color:#6a737d;'>$authorEmptyMsg</p>";
            } else {
                html += "<div class='tag-results'>";
                matching.forEach(function(item) {
                    var rel = (item.RelPath || "").replace(/\\/g, "/").replace(/\.md$/, ".html");
                    var title = escapeHtml(item.Title || "Untitled");
                    var desc = escapeHtml(item.Description || "");
                    html += "<div class='tag-card'><h3><a href='" + encodeURI(rel) + "'>📄 " + title + "</a></h3><p>" + desc + "</p></div>";
                });
                html += "</div>";
            }
            container.innerHTML = html;
        } else {
            var authorCounts = {};
            items.forEach(function(item) {
                if (item.Author) {
                    authorCounts[item.Author] = (authorCounts[item.Author] || 0) + 1;
                }
            });

            var html = "<h1>$authorListTitle</h1><ul>";
            var sortedAuthors = Object.keys(authorCounts).sort();
            if (sortedAuthors.length === 0) {
                html += "<p style='color:#6a737d;'>$authorNoneRegistered</p>";
            } else {
                sortedAuthors.forEach(function(a) {
                    html += "<li><a href='#name=" + encodeURIComponent(a) + "'>👤 " + escapeHtml(a) + "</a> <span style='color:#586069;'>(" + authorCounts[a] + ")</span></li>";
                });
            }
            html += "</ul>";
            container.innerHTML = html;
        }
    }

    function escapeHtml(str) {
        return (str || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    }

    window.clearAuthorFilter = function(e) {
        if (e) e.preventDefault();
        history.pushState("", document.title, window.location.pathname);
        render();
    };

    window.addEventListener("hashchange", render);
    render();
});
</script>
"@

        $fullAuthorsHtml = $template.Replace("{0}", $authorListTitle).Replace("{1}", $sidebarForSub).Replace("{2}", $authorsBodyContent).Replace("{3}", "").Replace("{4}", $exportLang).Replace("{5}", $docListTitle)
        $fullAuthorsHtml = $fullAuthorsHtml -replace "\r?\n", "`r`n"
        [System.IO.File]::WriteAllText($authorsHtmlFile, $fullAuthorsHtml, [System.Text.Encoding]::UTF8)
        Write-Host "  [HTML 変換] authors.html" -ForegroundColor Green
    }
}

# --- 4. 静的アセット (画像、CSS、JS 等) のコピー ---
$assetFiles = Get-ChildItem -Path $wikiDir -Recurse |
    Where-Object {
        -not $_.PSIsContainer -and
        $_.Extension -ne ".md" -and
        $_.FullName -notmatch '[\\/]\.(git|lib|tests|dist)[\\/]'
    }

foreach ($asset in $assetFiles) {
    # SingleFile かつ EmbedImages 有効時は、インライン化された画像ファイルのコピーをスキップ
    if ($SingleFile -and $isEmbedImagesMode -and $asset.Extension -match '^\.(png|jpe?g|gif|svg|webp|ico|bmp)$') {
        continue
    }

    $relPath  = $asset.FullName.Substring($wikiDir.Length).TrimStart("\", "/")
    $destFile = Join-Path $targetDistDir $relPath

    $destParent = [System.IO.Path]::GetDirectoryName($destFile)
    if (-not (Test-Path $destParent)) {
        New-Item -ItemType Directory -Path $destParent -Force | Out-Null
    }

    Copy-Item -Path $asset.FullName -Destination $destFile -Force
    Write-Host "  [アセット コピー] $relPath" -ForegroundColor DarkGray
}

if ($isEmbedImagesMode -and $globalImageCache.Count -gt 0) {
    Write-Host "  [画像埋め込み完了] $($globalImageCache.Count) 件の画像を Base64 (Data URI) として HTML 内に集約" -ForegroundColor Green
}

# 100% オフライン用に lib/mermaid.min.js をコピー (Runtime モードかつ非 SingleFile 時)
if ($MermaidMode -eq "Runtime" -and -not $SingleFile) {
    $scriptMermaid = Join-Path $libDir "mermaid.min.js"
    if (Test-Path $scriptMermaid) {
        $distLib = Join-Path $targetDistDir "lib"
        if (-not (Test-Path $distLib)) { New-Item -ItemType Directory -Path $distLib -Force | Out-Null }
        Copy-Item -Path $scriptMermaid -Destination (Join-Path $distLib "mermaid.min.js") -Force
        Write-Host "  [オフライン JS コピー] lib\mermaid.min.js" -ForegroundColor DarkGray
    }
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  エキスポート完了! 静的ファイル出力先:" -ForegroundColor Green
Write-Host "  $targetDistDir" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Green
