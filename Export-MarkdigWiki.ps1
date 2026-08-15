# ==============================================================================
#  Markdig + PowerShell 100% オフライン Wiki 静的 HTML エキスポート機能
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================
param (
    [string]$RootFolder = "",
    [string]$OutputDir  = "",
    [Alias("Lang")]
    [string]$Language   = ""
)

$scriptDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
$libDir    = Join-Path $scriptDir "lib"

# --- 多言語化 (i18n) 設定 ---
$script:I18n = @{
    "ja" = @{
        "doc_list_title"         = "📄 ドキュメント一覧"
        "edit_doc_btn"           = "✏️ 編集"
        "metadata_card_title"    = "ℹ️ ドキュメント メタデータ (OKF)"
        "metadata_author"        = "👤 著者: "
        "metadata_last_updated"  = "📅 最終更新: "
        "warning_deprecated"     = "⚠️ <strong>警告: 非推奨ドキュメント</strong><br>このドキュメントは非推奨または旧版です。最新の情報を参照してください。"
    }
    "en" = @{
        "doc_list_title"         = "📄 Document List"
        "edit_doc_btn"           = "✏️ Edit"
        "metadata_card_title"    = "ℹ️ Document Metadata (OKF)"
        "metadata_author"        = "👤 Author: "
        "metadata_last_updated"  = "📅 Last Updated: "
        "warning_deprecated"     = "⚠️ <strong>Warning: Deprecated Document</strong><br>This document is deprecated or outdated. Please refer to the latest information."
    }
}

# --- Load and merge optional external localization file (i18n.json) ---
$extI18nPath = Join-Path $scriptDir "i18n.json"
if (Test-Path $extI18nPath) {
    try {
        $rawJson = Get-Content -Path $extI18nPath -Raw -Encoding UTF8
        $extI18n = $rawJson | ConvertFrom-Json
        if ($null -ne $extI18n) {
            foreach ($langKey in $extI18n.psobject.Properties.Name) {
                if (-not $script:I18n.ContainsKey($langKey)) {
                    $script:I18n[$langKey] = @{}
                }
                $langObj = $extI18n.$langKey
                foreach ($prop in $langObj.psobject.Properties) {
                    $script:I18n[$langKey][$prop.Name] = $prop.Value
                }
            }
        }
    } catch {}
}

function Get-LocalizedStr {
    param (
        [string]$Key,
        [string]$Lang = "ja"
    )
    if ($script:I18n.ContainsKey($Lang) -and $script:I18n[$Lang].ContainsKey($Key)) {
        return $script:I18n[$Lang][$Key]
    }
    if ($script:I18n["ja"].ContainsKey($Key)) {
        return $script:I18n["ja"][$Key]
    }
    return $Key
}

$exportLang = $Language
if ([string]::IsNullOrWhiteSpace($exportLang)) {
    $configPath = Join-Path $scriptDir "config.json"
    if (Test-Path $configPath) {
        try {
            $cfg = (Get-Content $configPath -Raw -Encoding UTF8) | ConvertFrom-Json
            if ($cfg -and $cfg.language) { $exportLang = $cfg.language }
        } catch {}
    }
}
if ([string]::IsNullOrWhiteSpace($exportLang) -or -not $script:I18n.ContainsKey($exportLang)) {
    $exportLang = "ja"
}


# 入力ルートフォルダの設定 (指定がない場合は markdown_sample フォルダ、存在しない場合は $PSScriptRoot)
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

# 出力ディレクトリの設定
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $targetDistDir = Join-Path $scriptDir "dist"
} else {
    $targetDistDir = [System.IO.Path]::GetFullPath($OutputDir)
}

if (-not (Test-Path $targetDistDir)) {
    New-Item -ItemType Directory -Path $targetDistDir -Force | Out-Null
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  Markdig Wiki 静的 HTML エキスポート開始" -ForegroundColor Green
Write-Host "  入力元: $wikiDir" -ForegroundColor Yellow
Write-Host "  出力先: $targetDistDir" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Green

# --- 1. Markdig.dll および依存ライブラリのロード ---
$markdigDll = Join-Path $libDir "Markdig.dll"
if (-not (Test-Path $markdigDll)) {
    Write-Error "'lib' フォルダに Markdig.dll が見つかりません:`n$markdigDll"
    exit 1
}

Get-ChildItem -Path $libDir -Filter "*.dll" | ForEach-Object {
    if ($IsWindows -or $env:OS -eq "Windows_NT") {
        Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
    }
    Add-Type -Path $_.FullName
}

# --- 2. 静的 HTML 用サイドバーの自動生成関数 (フォルダ階層対応) ---
function Build-FileTreeNode {
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

function Test-ExportNodeHasActiveFile {
    param ($node, $currentFile)

    foreach ($file in $node.Files) {
        if ($file.FullName -eq $currentFile.FullName) {
            return $true
        }
    }

    foreach ($folderName in $node.SubFolders.Keys) {
        if (Test-ExportNodeHasActiveFile -node $node.SubFolders[$folderName] -currentFile $currentFile) {
            return $true
        }
    }

    return $false
}

function Render-ExportFolderTreeHtml {
    param ($node, $currentFile, $currentUri)

    $html = "<ul>`n"

    foreach ($file in $node.Files) {
        $targetHtmlPath = $file.FullName -replace '\.md$', '.html'
        $targetUri      = New-Object System.Uri($targetHtmlPath)
        $relativeUri    = $currentUri.MakeRelativeUri($targetUri).ToString()
        $title          = [System.Net.WebUtility]::HtmlEncode($file.BaseName)
        $activeClass    = if ($file.FullName -eq $currentFile.FullName) { ' class="active"' } else { '' }

        $html += "  <li class='nav-file'><a href='$relativeUri'$activeClass>$title</a></li>`n"
    }

    foreach ($folderName in $node.SubFolders.Keys) {
        $subNode     = $node.SubFolders[$folderName]
        $encodedName = [System.Net.WebUtility]::HtmlEncode($folderName)
        $subHtml     = Render-ExportFolderTreeHtml -node $subNode -currentFile $currentFile -currentUri $currentUri

        $isOpen   = Test-ExportNodeHasActiveFile -node $subNode -currentFile $currentFile
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

# --- OKF トップバー ＆ フッターカード レンダリング関数 ---
function Get-OkfTopBarHtml {
    param (
        [Parameter(Mandatory = $true)]$Meta,
        [string]$RelPath = "",
        [string]$Lang = "ja"
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
            "<span class='tag-badge'>🏷️ $encTag</span>"
        }
        $tagsHtml = "<div class='okf-tags'>" + ($tagBadges -join " ") + "</div>"
    }

    $warningMsg = Get-LocalizedStr -Key "warning_deprecated" -Lang $Lang
    $warningBanner = if ($Meta.Status -eq "deprecated") {
        "<div class=""warning-banner"">$warningMsg</div>"
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
    param (
        [Parameter(Mandatory = $true)]$Meta,
        [string]$Lang = "ja"
    )

    $desc    = [System.Net.WebUtility]::HtmlEncode($Meta.Description)
    $author  = [System.Net.WebUtility]::HtmlEncode($Meta.Author)
    $lastUpd = $Meta.LastUpdated.ToString("yyyy-MM-dd")

    $tagsHtml = ""
    if ($Meta.Tags -and $Meta.Tags.Count -gt 0) {
        $tagBadges = foreach ($t in $Meta.Tags) {
            $encTag = [System.Net.WebUtility]::HtmlEncode($t)
            "<span class='tag-badge'>🏷️ $encTag</span>"
        }
        $tagsHtml = "<div class='okf-tags'>" + ($tagBadges -join " ") + "</div>"
    }

    $authorLabel     = Get-LocalizedStr -Key "metadata_author" -Lang $Lang
    $lastUpdateLabel = Get-LocalizedStr -Key "metadata_last_updated" -Lang $Lang
    $cardTitleLabel  = Get-LocalizedStr -Key "metadata_card_title" -Lang $Lang

    $authorHtml = if (-not [string]::IsNullOrWhiteSpace($author)) {
        "<span class='okf-author'>$authorLabel$author</span>"
    } else { "" }

    $descHtml = if (-not [string]::IsNullOrWhiteSpace($desc)) {
        "<p class='okf-desc'>$desc</p>"
    } else { "" }

    return @"
<footer class="okf-footer-card">
    <div class="okf-footer-header">
        <span class="okf-footer-title">$cardTitleLabel</span>
    </div>
    $descHtml
    <div class="okf-footer-meta">
        $authorHtml
        <span>$lastUpdateLabel$lastUpd</span>
    </div>
    $tagsHtml
</footer>
"@
}

function Get-OkfCardHtml {
    param (
        [Parameter(Mandatory = $true)]$Meta,
        [string]$Lang = "ja"
    )
    return (Get-OkfTopBarHtml -Meta $Meta -Lang $Lang) + (Get-OkfFooterCardHtml -Meta $Meta -Lang $Lang)
}

function Get-ExportSidebarHtml {
    param ($currentFile, $allMdFiles, $wikiDir)

    $currentHtmlPath = $currentFile.FullName -replace '\.md$', '.html'
    $currentUri      = New-Object System.Uri($currentHtmlPath)

    $treeNode = Build-FileTreeNode -allMdFiles $allMdFiles -wikiDir $wikiDir
    return Render-ExportFolderTreeHtml -node $treeNode -currentFile $currentFile -currentUri $currentUri
}

# --- 3. マークダウンファイルの抽出と HTML 変換 ---
$allMdFiles = Get-ChildItem -Path $wikiDir -Recurse -Filter "*.md" | 
    Where-Object { $_.FullName -notmatch '[\\/]\.(git|lib|tests|dist)[\\/]' } |
    Sort-Object FullName

$builder  = New-Object Markdig.MarkdownPipelineBuilder
$null     = [Markdig.MarkdownExtensions]::UseAdvancedExtensions($builder)
$null     = [Markdig.MarkdownExtensions]::UseYamlFrontMatter($builder)
$pipeline = $builder.Build()

$template = @'
<!DOCTYPE html>
<html lang="{4}">
<head>
<meta charset="UTF-8">
<title>{0} - SimpleWiki OKF</title>
<style>
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
    .okf-card { background: #f8f9fa; border: 1px solid #e1e4e8; border-radius: 8px; padding: 16px; margin-bottom: 24px; }
    .okf-card-header { display: flex; justify-content: space-between; align-items: center; font-size: 13px; color: #586069; font-weight: bold; }
    .okf-desc { font-size: 14px; color: #24292e; margin: 10px 0; }
    .okf-card-footer { display: flex; gap: 20px; font-size: 12px; color: #586069; }
    .okf-tags { margin-top: 10px; display: flex; gap: 6px; flex-wrap: wrap; }
    .tag-badge { background: #e1e4e8; color: #0366d6; padding: 2px 8px; border-radius: 12px; font-size: 12px; }
    .badge { padding: 3px 8px; border-radius: 12px; font-size: 11px; font-weight: bold; text-transform: uppercase; }
    .badge-active { background: #28a745; color: #fff; }
    .badge-draft { background: #ffc107; color: #212529; }
    .badge-deprecated { background: #dc3545; color: #fff; }
    .warning-banner { background: #fff3cd; border: 1px solid #ffeeba; color: #856404; padding: 12px 16px; border-radius: 6px; margin-bottom: 16px; }
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
    <script src="{3}"></script>
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
    $bodyHtml = [Markdig.Markdown]::ToHtml($mdText, $pipeline)

    $okfTopBar   = Get-OkfTopBarHtml -Meta $meta -Lang $exportLang
    $okfFooter   = Get-OkfFooterCardHtml -Meta $meta -Lang $exportLang
    $bodyHtml    = $okfTopBar + $bodyHtml + $okfFooter

    # 本文中の .md ハイパーリンクを .html に自動変換
    $bodyHtml = $bodyHtml -replace 'href="([^"]+)\.md"', 'href="$1.html"'
    $bodyHtml = $bodyHtml -replace "href='([^']+)\.md'", "href='$1.html'"

    $sidebarHtml = Get-ExportSidebarHtml -currentFile $file -allMdFiles $allMdFiles -wikiDir $wikiDir
    $pageTitle   = [System.Net.WebUtility]::HtmlEncode($meta.Title)

    # 現在の出力 HTML から lib/mermaid.min.js への相対パスを計算
    $destUri     = New-Object System.Uri($destFile)
    $mermaidDist = Join-Path $targetDistDir "lib\mermaid.min.js"
    $mermaidUri  = New-Object System.Uri($mermaidDist)
    $relMermaid  = $destUri.MakeRelativeUri($mermaidUri).ToString()

    $docListTitle = Get-LocalizedStr -Key "doc_list_title" -Lang $exportLang
    $fullHtml = $template.Replace("{0}", $pageTitle).Replace("{1}", $sidebarHtml).Replace("{2}", $bodyHtml).Replace("{3}", $relMermaid).Replace("{4}", $exportLang).Replace("{5}", $docListTitle)
    $fullHtml = $fullHtml -replace "\r?\n", "`r`n"

    [System.IO.File]::WriteAllText($destFile, $fullHtml, [System.Text.Encoding]::UTF8)
    Write-Host "  [HTML 変換] $relPath -> $htmlRel" -ForegroundColor Green
}

# --- 4. 静的アセット (画像、CSS、JS 等) のコピー ---
$assetFiles = Get-ChildItem -Path $wikiDir -Recurse | 
    Where-Object { 
        -not $_.PSIsContainer -and 
        $_.Extension -ne ".md" -and 
        $_.FullName -notmatch '[\\/]\.(git|lib|tests|dist)[\\/]' 
    }

foreach ($asset in $assetFiles) {
    $relPath  = $asset.FullName.Substring($wikiDir.Length).TrimStart("\", "/")
    $destFile = Join-Path $targetDistDir $relPath

    $destParent = [System.IO.Path]::GetDirectoryName($destFile)
    if (-not (Test-Path $destParent)) {
        New-Item -ItemType Directory -Path $destParent -Force | Out-Null
    }

    Copy-Item -Path $asset.FullName -Destination $destFile -Force
    Write-Host "  [アセット コピー] $relPath" -ForegroundColor DarkGray
}

# 100% オフライン用に lib/mermaid.min.js をコピー
$scriptMermaid = Join-Path $libDir "mermaid.min.js"
if (Test-Path $scriptMermaid) {
    $distLib = Join-Path $targetDistDir "lib"
    if (-not (Test-Path $distLib)) { New-Item -ItemType Directory -Path $distLib -Force | Out-Null }
    Copy-Item -Path $scriptMermaid -Destination (Join-Path $distLib "mermaid.min.js") -Force
    Write-Host "  [オフライン JS コピー] lib\mermaid.min.js" -ForegroundColor DarkGray
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  エキスポート完了! 静的ファイル出力先:" -ForegroundColor Green
Write-Host "  $targetDistDir" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Green
