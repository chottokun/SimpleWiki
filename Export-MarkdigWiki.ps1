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
    [string]$MermaidMode = "Runtime"
)

$scriptDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
$libDir    = Join-Path $scriptDir "lib"

# --- モジュールのロード (lib/*.ps1) ---
. (Join-Path $libDir "WikiI18n.ps1")
. (Join-Path $libDir "WikiMetadata.ps1")
. (Join-Path $libDir "WikiViews.ps1")

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

function Get-SinglePageId {
    param ([string]$relPath)

    $norm = $relPath.Replace('\', '/').TrimStart('/')
    $clean = $norm -replace '\.md$', '' -replace '\.html$', ''
    if ($clean -eq "index") { return "index" }

    $pageId = $clean -replace '[^a-zA-Z0-9_\-\u4e00-\u9faf\u3040-\u309f\u30a0-\u30ff]', '_'
    if ([string]::IsNullOrWhiteSpace($pageId)) { return "index" }
    return "page_$pageId"
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
            $html += "  <li class='nav-file'><a href='#$pageId' onclick='showPage(&quot;$pageId&quot;); return false;'$activeClass>📄 $encodedTitle</a></li>`n"
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

# Helper to transform mermaid blocks in SVG mode
function Convert-MermaidToSvgMarkup {
    param ([string]$html)

    $pattern = '(?s)<pre(?:\s+class=["'']mermaid["''])?>(?:<code(?:\s+class=["'']language-mermaid["''])?>)?(.*?)(?:</code>)?</pre>'
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        # Verify match contains mermaid class or code tag
        $fullMatch = $match.Value
        if ($fullMatch -notmatch 'class=["'']mermaid["'']' -and $fullMatch -notmatch 'language-mermaid') {
            return $fullMatch
        }

        $code = $match.Groups[1].Value
        $encodedCode = [System.Net.WebUtility]::HtmlEncode($code.Trim())
        return @"
<div class="mermaid-svg" style="border: 1px solid #e1e4e8; border-radius: 6px; padding: 16px; background: #f6f8fa; margin: 16px 0;">
  <svg xmlns="http://www.w3.org/2000/svg" width="100%" height="auto" viewBox="0 0 600 120" style="max-width: 100%;">
    <rect width="100%" height="100%" fill="#f6f8fa" rx="6"/>
    <text x="50%" y="40%" dominant-baseline="middle" text-anchor="middle" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-size="14" font-weight="bold" fill="#24292e">📊 Mermaid Diagram (SVG Static Mode)</text>
    <text x="50%" y="70%" dominant-baseline="middle" text-anchor="middle" font-family="monospace" font-size="12" fill="#586069">$encodedCode</text>
  </svg>
</div>
"@
    }

    return [System.Text.RegularExpressions.Regex]::Replace($html, $pattern, $evaluator)
}

function Get-OptimizedImageBase64 {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param (
        [string]$filePath,
        [int]$maxSizeKB = 1024,
        [int]$maxDimension = 1600
    )

    if (-not (Test-Path -LiteralPath $filePath)) {
        return $null
    }

    $ext = [System.IO.Path]::GetExtension($filePath).ToLowerInvariant()
    $mimeType = switch ($ext) {
        ".svg"  { "image/svg+xml" }
        ".png"  { "image/png" }
        ".jpg"  { "image/jpeg" }
        ".jpeg" { "image/jpeg" }
        ".gif"  { "image/gif" }
        ".webp" { "image/webp" }
        ".bmp"  { "image/bmp" }
        ".ico"  { "image/x-icon" }
        default { "" }
    }

    if ([string]::IsNullOrWhiteSpace($mimeType)) {
        return $null
    }

    $fileInfo  = Get-Item -LiteralPath $filePath
    $fileBytes = [System.IO.File]::ReadAllBytes($filePath)

    # 1. SVG の場合はベクター画像のため、リサイズ不要でそのまま Base64 化
    if ($ext -eq ".svg") {
        $b64 = [Convert]::ToBase64String($fileBytes)
        return "data:$mimeType;base64,$b64"
    }

    # 2. ラスタ画像（PNG, JPG, BMP, GIF, WebP 等）
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

    $fileSizeKB = $fileInfo.Length / 1KB
    $origBmp = $null
    $origWidth = 0
    $origHeight = 0

    try {
        $msIn = New-Object System.IO.MemoryStream(,$fileBytes)
        $origBmp = [System.Drawing.Image]::FromStream($msIn)
        $origWidth = $origBmp.Width
        $origHeight = $origBmp.Height
        $msIn.Dispose()
    } catch {
        $null = $_
        $b64 = [Convert]::ToBase64String($fileBytes)
        return "data:$mimeType;base64,$b64"
    }

    $needsResize = ($origWidth -gt $maxDimension -or $origHeight -gt $maxDimension -or $fileSizeKB -gt $maxSizeKB)

    if (-not $needsResize) {
        if ($origBmp) { $origBmp.Dispose() }
        $b64 = [Convert]::ToBase64String($fileBytes)
        return "data:$mimeType;base64,$b64"
    }

    # 3. 高品質 Bicubic 縮小 ＆ 再圧縮
    try {
        $scale = 1.0
        if ($origWidth -gt $maxDimension -or $origHeight -gt $maxDimension) {
            $scaleW = $maxDimension / [double]$origWidth
            $scaleH = $maxDimension / [double]$origHeight
            $scale = [Math]::Min($scaleW, $scaleH)
        }

        if ($fileSizeKB -gt $maxSizeKB) {
            $sizeRatio = [Math]::Sqrt($maxSizeKB / [double]$fileSizeKB)
            if ($sizeRatio -lt $scale) {
                $scale = [Math]::Max(0.2, $sizeRatio)
            }
        }

        $newWidth  = [Math]::Max(1, [int][Math]::Round($origWidth * $scale))
        $newHeight = [Math]::Max(1, [int][Math]::Round($origHeight * $scale))

        $destBmp = New-Object System.Drawing.Bitmap($newWidth, $newHeight)
        $destGraphics = [System.Drawing.Graphics]::FromImage($destBmp)
        $destGraphics.InterpolationMode   = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $destGraphics.SmoothingMode       = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $destGraphics.PixelOffsetMode     = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $destGraphics.CompositingQuality  = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

        $destRect = New-Object System.Drawing.Rectangle(0, 0, $newWidth, $newHeight)
        $destGraphics.DrawImage($origBmp, $destRect, 0, 0, $origWidth, $origHeight, [System.Drawing.GraphicsUnit]::Pixel)

        $msOut = New-Object System.IO.MemoryStream
        $outMime = $mimeType

        if ($ext -eq ".png") {
            $destBmp.Save($msOut, [System.Drawing.Imaging.ImageFormat]::Png)
            # PNG 保存でまだ上限超過する場合は JPEG に切り替えて品質 80% 圧縮
            if (($msOut.Length / 1KB) -gt $maxSizeKB) {
                $msOut.SetLength(0)
                $encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" } | Select-Object -First 1
                if ($encoder) {
                    $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
                    $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]80)
                    $destBmp.Save($msOut, $encoder, $encoderParams)
                    $outMime = "image/jpeg"
                }
            }
        } else {
            $encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" } | Select-Object -First 1
            if ($encoder) {
                $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
                $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]85)
                $destBmp.Save($msOut, $encoder, $encoderParams)
                $outMime = "image/jpeg"
            } else {
                $destBmp.Save($msOut, [System.Drawing.Imaging.ImageFormat]::Jpeg)
                $outMime = "image/jpeg"
            }
        }

        $compressedBytes = $msOut.ToArray()
        $b64 = [Convert]::ToBase64String($compressedBytes)

        $destGraphics.Dispose()
        $destBmp.Dispose()
        $msOut.Dispose()

        return "data:$outMime;base64,$b64"
    } catch {
        $null = $_
        $b64 = [Convert]::ToBase64String($fileBytes)
        return "data:$mimeType;base64,$b64"
    } finally {
        if ($origBmp) { $origBmp.Dispose() }
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
    .badge { padding: 3px 8px; border-radius: 12px; font-size: 11px; font-weight: bold; text-transform: uppercase; }
    .badge-active { background: #28a745; color: #fff; }
    .badge-draft { background: #ffc107; color: #212529; }
    .badge-deprecated { background: #dc3545; color: #fff; }
    .warning-banner { background: #fff3cd; border: 1px solid #ffeeba; color: #856404; padding: 12px 16px; border-radius: 6px; margin-bottom: 16px; }
'@

if ($SingleFile) {
    # --- モノリス HTML (SPA モード) エキスポート ---
    $docListTitle = Get-LocalizedStr -Key "doc_list_title" -Lang $exportLang
    $sidebarHtml  = Get-ExportSidebarHtml -allMdFiles $allMdFiles -wikiDir $wikiDir -IsSingleFileMode

    $pagesHtmlList = [System.Collections.Generic.List[string]]::new()
    $globalImageCache = @{}

    foreach ($file in $allMdFiles) {
        $relPath  = $file.FullName.Substring($wikiDir.Length).TrimStart("\", "/")
        $pageId   = Get-SinglePageId -relPath $relPath

        $mdText   = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        $meta     = Get-DocumentMetadata -File $file -RelPath $relPath -MdText $mdText
        $bodyHtml = [Markdig.Markdown]::ToHtml($mdText, $pipeline)

        $okfTopBar   = Get-OkfTopBarHtml -Meta $meta -Lang $exportLang
        $okfFooter   = Get-OkfFooterCardHtml -Meta $meta -Lang $exportLang
        $bodyHtml    = $okfTopBar + $bodyHtml + $okfFooter

        # リンク書き換え (相対 .md / .html リンクを #pageId に変換)
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

            $anchorArg = if ($anchorId) { ", '$anchorId'" } else { "" }
            return "href=""#$targetPageId"" onclick=""showPage('$targetPageId'$anchorArg); return false;"""
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

        $displayStyle = if ($pageId -eq "index") { "block" } else { "none" }
        $pageSection = @"
<section class="wiki-page" id="$pageId" style="display: $displayStyle;">
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
        renderMermaidInContainer(document);
    });

    function renderMermaidInContainer(container) {
        if (typeof mermaid === "undefined") return;
        var targets = container.querySelectorAll("pre code.language-mermaid");
        targets.forEach(function(el) {
            var pre = el.parentElement;
            var div = document.createElement("div");
            div.className = "mermaid";
            div.textContent = el.textContent;
            pre.replaceWith(div);
        });
        try {
            mermaid.initialize({ startOnLoad: false, theme: "default" });
            mermaid.run({ querySelector: ".mermaid" });
        } catch(e) {
            console.error("Mermaid initialization error:", e);
        }
    }
</script>
"@
    } else {
        $mermaidInitScript = ""
    }

    $spaScript = @"
<script>
function showPage(pageId, anchorId) {
    // すべてのページコンテナを非表示
    document.querySelectorAll('.wiki-page').forEach(el => {
        el.style.display = 'none';
    });
    // 該当ページを表示
    const target = document.getElementById(pageId);
    if (target) {
        target.style.display = 'block';
        if (anchorId) {
            const anchorEl = document.getElementById(anchorId) || target.querySelector('[id=\"' + anchorId + '\"]');
            if (anchorEl) {
                anchorEl.scrollIntoView();
            } else {
                window.scrollTo(0, 0);
            }
        } else {
            window.scrollTo(0, 0);
        }
    }
    // アクティブなナビゲーションリンクを切り替え
    document.querySelectorAll('nav li.nav-file a').forEach(a => {
        a.classList.remove('active');
        if (a.getAttribute('href') === '#' + pageId) {
            a.classList.add('active');
        }
    });
    // 履歴とハッシュの更新
    const nextHash = anchorId ? '#' + pageId + '_' + anchorId : '#' + pageId;
    if (location.hash !== nextHash) {
        history.pushState(null, '', nextHash);
    }
}

// 起動時およびハッシュ変更時のルーティング
window.addEventListener('popstate', () => {
    const raw = location.hash.replace('#', '') || 'index';
    const parts = raw.split('_');
    const pageId = parts[0] === 'page' ? parts[0] + '_' + parts[1] : parts[0];
    const anchorId = parts.length > (parts[0] === 'page' ? 2 : 1) ? parts.slice(parts[0] === 'page' ? 2 : 1).join('_') : '';
    showPage(pageId, anchorId);
});

window.addEventListener('hashchange', () => {
    const raw = location.hash.replace('#', '') || 'index';
    const parts = raw.split('_');
    const pageId = parts[0] === 'page' ? parts[0] + '_' + parts[1] : parts[0];
    const anchorId = parts.length > (parts[0] === 'page' ? 2 : 1) ? parts.slice(parts[0] === 'page' ? 2 : 1).join('_') : '';
    showPage(pageId, anchorId);
});

document.addEventListener("DOMContentLoaded", () => {
    const raw = location.hash.replace('#', '') || 'index';
    const parts = raw.split('_');
    const pageId = parts[0] === 'page' ? parts[0] + '_' + parts[1] : parts[0];
    const anchorId = parts.length > (parts[0] === 'page' ? 2 : 1) ? parts.slice(parts[0] === 'page' ? 2 : 1).join('_') : '';
    showPage(pageId, anchorId);
});
</script>
"@

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
        $allPagesContent
    </main>
    $mermaidInitScript
    $spaScript
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
            div.textContent = el.textContent;
            pre.replaceWith(div);
        });
        if (typeof mermaid !== "undefined") {
            mermaid.initialize({ startOnLoad: true, theme: "default" });
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
