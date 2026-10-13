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
    [switch]$NoAuthorsPage,
    [ValidateSet("Auto", "Light", "Dark")]
    [string]$Theme = "Auto",
    [string]$TemplatePath = "",
    [switch]$DisableRawHtml,
    [switch]$PreserveCodeBlockLinks
)

$scriptDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
$libDir    = Join-Path $scriptDir "lib"

# --- モジュールのロード (lib/*.ps1) ---
. (Join-Path $libDir "WikiI18n.ps1")
. (Join-Path $libDir "WikiMetadata.ps1")
. (Join-Path $libDir "WikiSearch.ps1")
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

# --- 3. マークダウンファイルの抽出 ---
$allMdFiles = Get-ChildItem -Path $wikiDir -Recurse -Filter "*.md" |
    Where-Object { $_.FullName -notmatch '[\\/]\.(git|lib|tests|dist)[\\/]' } |
    Sort-Object FullName

$builder  = New-Object Markdig.MarkdownPipelineBuilder
$null     = [Markdig.MarkdownExtensions]::UseAdvancedExtensions($builder)
$null     = [Markdig.MarkdownExtensions]::UseYamlFrontMatter($builder)
if ($DisableRawHtml) {
    $null = [Markdig.MarkdownExtensions]::DisableHtml($builder)
}
$pipeline = $builder.Build()

$commonStyle = Get-ExportCssStyle -Theme $Theme

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

        $codeBlocks = [System.Collections.ArrayList]::new()
        if ($PreserveCodeBlockLinks) {
            $evaluatorBlock = [System.Text.RegularExpressions.MatchEvaluator] {
                param($match)
                $null = $codeBlocks.Add($match.Value)
                return "<!-- CODEBLOCK_$($codeBlocks.Count - 1) -->"
            }
            $bodyHtml = [System.Text.RegularExpressions.Regex]::Replace($bodyHtml, '(?is)<pre><code.*?>.*?</code></pre>', $evaluatorBlock)
        }

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

        if ($PreserveCodeBlockLinks -and $codeBlocks.Count -gt 0) {
            for ($i = 0; $i -lt $codeBlocks.Count; $i++) {
                $bodyHtml = $bodyHtml.Replace("<!-- CODEBLOCK_${i} -->", $codeBlocks[$i])
            }
        }

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
        $null = Export-WikiApiIndexJson -AllApiItems $allApiItems -TargetDistDir $targetDistDir
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
    if (-not [string]::IsNullOrWhiteSpace($TemplatePath) -and (Test-Path $TemplatePath)) {
        $template = Get-Content -Path $TemplatePath -Raw -Encoding UTF8
    } else {
        $template = @"
<!DOCTYPE html>
<html lang="<!-- {{SIMPLEWIKI_LANG}} -->">
<head>
<meta charset="UTF-8">
<title><!-- {{SIMPLEWIKI_PAGE_TITLE}} --> - SimpleWiki OKF</title>
<style>
$commonStyle
</style>
</head>
<body>
    <nav>
        <h2><!-- {{SIMPLEWIKI_DOC_LIST_TITLE}} --></h2>
        <!-- {{SIMPLEWIKI_SIDEBAR}} -->
    </nav>
    <main>
        <div class="markdown-body">
            <!-- {{SIMPLEWIKI_BODY}} -->
        </div>
    </main>
    <!-- {{SIMPLEWIKI_MERMAID}} -->
</body>
</html>
"@
    }

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

        $codeBlocks = [System.Collections.ArrayList]::new()
        if ($PreserveCodeBlockLinks) {
            $evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
                param($match)
                $null = $codeBlocks.Add($match.Value)
                return "<!-- CODEBLOCK_$($codeBlocks.Count - 1) -->"
            }
            $bodyHtml = [System.Text.RegularExpressions.Regex]::Replace($bodyHtml, '(?is)<pre><code.*?>.*?</code></pre>', $evaluator)
        }

        # 本文中の .md ハイパーリンクを .html に自動変換
        $bodyHtml = $bodyHtml -replace 'href="([^"]+)\.md"', 'href="$1.html"'
        $bodyHtml = $bodyHtml -replace "href='([^']+)\.md'", "href='$1.html'"

        if ($PreserveCodeBlockLinks -and $codeBlocks.Count -gt 0) {
            for ($i = 0; $i -lt $codeBlocks.Count; $i++) {
                $bodyHtml = $bodyHtml.Replace("<!-- CODEBLOCK_${i} -->", $codeBlocks[$i])
            }
        }

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
        $fullHtml = $template.Replace("<!-- {{SIMPLEWIKI_PAGE_TITLE}} -->", $pageTitle).Replace("<!-- {{SIMPLEWIKI_SIDEBAR}} -->", $sidebarHtml).Replace("<!-- {{SIMPLEWIKI_MERMAID}} -->", $mermaidBlock).Replace("<!-- {{SIMPLEWIKI_LANG}} -->", $exportLang).Replace("<!-- {{SIMPLEWIKI_DOC_LIST_TITLE}} -->", $docListTitle).Replace("<!-- {{SIMPLEWIKI_BODY}} -->", $bodyHtml)
        $fullHtml = $fullHtml -replace "\r?\n", "`r`n"

        [System.IO.File]::WriteAllText($destFile, $fullHtml, [System.Text.Encoding]::UTF8)
        Write-Host "  [HTML 変換] $relPath -> $htmlRel" -ForegroundColor Green
    }

    $glossaryPath = Join-Path $wikiDir "glossary.md"
    $glossaryTerms = Get-GlossaryTerms -GlossaryPath $glossaryPath
    $glossaryJsonText = $glossaryTerms | ConvertTo-Json -Depth 3

    $apiJsonText = Export-WikiApiIndexJson -AllApiItems $allApiItems -TargetDistDir $targetDistDir
    if (-not $NoApiJson) {
        Write-Host "  [API JSON 出力] -> api/index.json" -ForegroundColor Green
    } else {
        $apiDestDir = Join-Path $targetDistDir "api"
        if (Test-Path $apiDestDir) { Remove-Item -Path $apiDestDir -Recurse -Force }
    }

    # 1. tags.html 出力
    if (-not $NoTagsPage) {
        $tagsHtmlFile     = Join-Path $targetDistDir "tags.html"
        $dummyCurrentFile = [PSCustomObject]@{ FullName = Join-Path $wikiDir "tags.md" }
        $sidebarForSub    = Get-ExportSidebarHtml -currentFile $dummyCurrentFile -allMdFiles $allMdFiles -wikiDir $wikiDir
        $docListTitle     = Get-LocalizedStr -Key "doc_list_title" -Lang $exportLang

        $fullTagsHtml = Get-ExportTagsPageHtml -ApiJsonText $apiJsonText -GlossaryJsonText $glossaryJsonText -Template $template -SidebarHtml $sidebarForSub -ExportLang $exportLang -DocListTitle $docListTitle
        [System.IO.File]::WriteAllText($tagsHtmlFile, $fullTagsHtml, [System.Text.Encoding]::UTF8)
        Write-Host "  [HTML 変換] tags.html" -ForegroundColor Green
    }

    # 2. authors.html 出力
    if (-not $NoAuthorsPage) {
        $authorsHtmlFile  = Join-Path $targetDistDir "authors.html"
        $dummyCurrentFile = [PSCustomObject]@{ FullName = Join-Path $wikiDir "authors.md" }
        $sidebarForSub    = Get-ExportSidebarHtml -currentFile $dummyCurrentFile -allMdFiles $allMdFiles -wikiDir $wikiDir
        $docListTitle     = Get-LocalizedStr -Key "doc_list_title" -Lang $exportLang

        $fullAuthorsHtml = Get-ExportAuthorsPageHtml -ApiJsonText $apiJsonText -Template $template -SidebarHtml $sidebarForSub -ExportLang $exportLang -DocListTitle $docListTitle
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
