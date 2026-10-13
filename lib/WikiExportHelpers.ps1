# ==============================================================================
#  WikiExportHelpers.ps1
#  SimpleWiki Static Export Helper Utilities (Image Resizing & Diagram Conversion)
#  Encoding: UTF-8 with BOM
# ==============================================================================

function Convert-MermaidToSvgMarkup {
    param ([string]$html)

    $pattern = '(?s)<pre(?:\s+class=["\'']mermaid["''])?>(?:<code(?:\s+class=["\'']language-mermaid["''])?>)?(.*?)(?:</code>)?</pre>'
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $fullMatch = $match.Value
        if ($fullMatch -notmatch 'class=["\'']mermaid["\'']' -and $fullMatch -notmatch 'language-mermaid') {
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

    if ($ext -eq ".svg") {
        $b64 = [Convert]::ToBase64String($fileBytes)
        return "data:$mimeType;base64,$b64"
    }

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

    if (-not [string]::IsNullOrWhiteSpace($wikiDir) -and (Test-Path -LiteralPath $wikiDir -PathType Container)) {
        if (Get-Command "Sync-FileTreeNodeOkfOrder" -ErrorAction SilentlyContinue) {
            Sync-FileTreeNodeOkfOrder -targetNode $rootNode -nodePhysicalPath $wikiDir
        }
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

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("<ul>")

    # 1. フォルダの描画 (再帰)
    $sortedFolderNames = if ($node.SubFolders) {
        @($node.SubFolders.Keys | Sort-Object)
    } else { @() }

    foreach ($folderName in $sortedFolderNames) {
        $subNode = $node.SubFolders[$folderName]
        $hasActive = Test-ExportNodeHasActiveFile -node $subNode -currentFile $currentFile
        $openAttr = if ($hasActive -or $IsSingleFileMode) { " open" } else { "" }
        $encodedFolder = [System.Net.WebUtility]::HtmlEncode($folderName)

        $lines.Add("  <li class='nav-folder'>")
        $lines.Add("    <details$openAttr>")
        $lines.Add("      <summary class='folder-title'>&#128193; $encodedFolder</summary>")
        $lines.Add("      " + (Render-ExportFolderTreeHtml -node $subNode -currentFile $currentFile -currentUri $currentUri -IsSingleFileMode:$IsSingleFileMode))
        $lines.Add("    </details>")
        $lines.Add("  </li>")
    }

    # 2. ファイルの描画 (index.md / README.md を先頭に優先ソート)
    $hasCustomOrder = ($node.PSObject.Properties['HasCustomOrder'] -and $node.HasCustomOrder)
    $sortedFiles = if ($node.Files) {
        $idx = 0
        @($node.Files | Sort-Object -Property @{
            Expression = {
                if ($_.BaseName -ieq "index" -or $_.Name -ieq "index.md") { return 0 }
                if ($_.BaseName -ieq "README" -or $_.Name -ieq "readme.md") { return 1 }
                return 2
            }
        }, @{
            Expression = {
                if ($hasCustomOrder) {
                    if ($_.PSObject.Properties['SortOrder'] -and $null -ne $_.SortOrder) {
                        return [int]$_.SortOrder
                    }
                    return $idx++
                } else {
                    return $_.BaseName
                }
            }
        })
    } else { @() }

    foreach ($file in $sortedFiles) {
        $encodedTitle = [System.Net.WebUtility]::HtmlEncode($file.BaseName)

        if ($IsSingleFileMode) {
            $relPath  = $file.FullName.Substring($wikiDir.Length).TrimStart("\", "/")
            $pageId   = Get-SinglePageId -relPath $relPath
            $isActive = ($pageId -eq "index")
            $activeClass = if ($isActive) { " class='active'" } else { "" }
            $lines.Add("  <li class='nav-file'><a href='#$pageId'$activeClass>📄 $encodedTitle</a></li>")
        } else {
            $fileHtmlPath = $file.FullName -replace '\.md$', '.html'
            $fileUri      = New-Object System.Uri($fileHtmlPath)
            $relHref      = $currentUri.MakeRelativeUri($fileUri).ToString()

            $isActive = ($currentFile -and $file.FullName -eq $currentFile.FullName)
            $activeClass = if ($isActive) { " class='active'" } else { "" }

            $lines.Add("  <li class='nav-file'><a href='$relHref'$activeClass>📄 $encodedTitle</a></li>")
        }
    }

    $lines.Add("</ul>")
    return ($lines -join "`n")
}

function Get-ExportSidebarHtml {
    param ($currentFile, $allMdFiles, $wikiDir, [switch]$IsSingleFileMode)

    if ($IsSingleFileMode) {
        $treeNode = Build-FileTreeNode -allMdFiles $allMdFiles -wikiDir $wikiDir
        return Render-ExportFolderTreeHtml -node $treeNode -currentFile $null -currentUri $null -IsSingleFileMode -wikiDir $wikiDir
    } else {
        $currentHtmlPath = $currentFile.FullName -replace '\.md$', '.html'
        $currentUri      = New-Object System.Uri($currentHtmlPath)

        $treeNode = Build-FileTreeNode -allMdFiles $allMdFiles -wikiDir $wikiDir
        return Render-ExportFolderTreeHtml -node $treeNode -currentFile $currentFile -currentUri $currentUri -wikiDir $wikiDir
    }
}

function Get-ExportCssStyle {
    param ([string]$Theme = "Auto")

    $cssVariablesLight = @'
    :root {
        --wiki-bg: #ffffff;
        --wiki-text: #24292e;
        --wiki-sidebar-bg: #f6f8fa;
        --wiki-border: #e1e4e8;
        --wiki-border-light: #eaecef;
        --wiki-link: #0366d6;
        --wiki-link-hover: #0366d6;
        --wiki-link-hover-bg: #f0f3f6;
        --wiki-code-bg: rgba(27,31,35,0.05);
        --wiki-pre-bg: #f6f8fa;
        --wiki-blockquote-border: #dfe2e5;
        --wiki-blockquote-text: #6a737d;
        --wiki-meta-text: #586069;
        --wiki-meta-bg: #f8f9fa;
        --wiki-tag-bg: #e1e4e8;
        --wiki-tag-bg-hover: #0366d6;
        --wiki-tag-text-hover: #ffffff;
        --wiki-card-border: #c8e1ff;
        --wiki-card-bg: #f1f8ff;
        --wiki-glossary-bg: #e8f4fd;
    }
'@

    $cssVariablesDark = @'
    :root {
        --wiki-bg: #0d1117;
        --wiki-text: #c9d1d9;
        --wiki-sidebar-bg: #161b22;
        --wiki-border: #30363d;
        --wiki-border-light: #21262d;
        --wiki-link: #58a6ff;
        --wiki-link-hover: #58a6ff;
        --wiki-link-hover-bg: #21262d;
        --wiki-code-bg: rgba(240,246,252,0.15);
        --wiki-pre-bg: #161b22;
        --wiki-blockquote-border: #30363d;
        --wiki-blockquote-text: #8b949e;
        --wiki-meta-text: #8b949e;
        --wiki-meta-bg: #161b22;
        --wiki-tag-bg: #21262d;
        --wiki-tag-bg-hover: #58a6ff;
        --wiki-tag-text-hover: #ffffff;
        --wiki-card-border: #30363d;
        --wiki-card-bg: #21262d;
        --wiki-glossary-bg: #161b22;
    }
'@

    $commonStyle = ""
    if ($Theme -eq "Light") {
        $commonStyle += $cssVariablesLight + "`n"
    } elseif ($Theme -eq "Dark") {
        $commonStyle += $cssVariablesDark + "`n"
    } else {
        $commonStyle += $cssVariablesLight + "`n@media (prefers-color-scheme: dark) {`n" + ($cssVariablesDark -replace ':root {', '    :root {') + "`n}`n"
    }

    $commonStyle += @'
    * { box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; margin: 0; padding: 0; display: flex; height: 100vh; color: var(--wiki-text); background-color: var(--wiki-bg); }
    nav { width: 260px; background-color: var(--wiki-sidebar-bg); border-right: 1px solid var(--wiki-border); padding: 20px 10px; overflow-y: auto; flex-shrink: 0; }
    nav h2 { font-size: 14px; text-transform: uppercase; color: var(--wiki-meta-text); margin: 0 0 10px 10px; letter-spacing: 0.5px; }
    nav ul { list-style: none; padding: 0; margin: 0; }
    nav ul ul { padding-left: 12px; margin-top: 2px; }
    nav li.nav-folder { margin-top: 4px; margin-bottom: 4px; }
    nav summary.folder-title { font-weight: bold; font-size: 13px; color: var(--wiki-meta-text); padding: 4px 6px; cursor: pointer; user-select: none; }
    nav summary.folder-title:hover { color: var(--wiki-link-hover); }
    nav li.nav-file a { display: block; padding: 4px 8px; color: var(--wiki-link); text-decoration: none; border-radius: 6px; font-size: 14px; word-break: break-all; }
    nav li.nav-file a:hover { background-color: var(--wiki-link-hover-bg); text-decoration: none; }
    nav li.nav-file a.active { background-color: var(--wiki-link); color: #ffffff; font-weight: bold; }
    main { flex: 1; padding: 40px 60px; overflow-y: auto; }
    .markdown-body { max-width: 880px; margin: 0 auto; line-height: 1.6; }
    h1, h2, h3 { border-bottom: 1px solid var(--wiki-border-light); padding-bottom: 0.3em; margin-top: 24px; margin-bottom: 16px; }
    code { background: var(--wiki-code-bg); padding: 0.2em 0.4em; border-radius: 3px; font-family: monospace; }
    pre { background: var(--wiki-pre-bg); padding: 16px; border-radius: 6px; overflow: auto; border: 1px solid var(--wiki-border); }
    pre code { background: transparent; padding: 0; }
    blockquote { border-left: 4px solid var(--wiki-blockquote-border); color: var(--wiki-blockquote-text); margin: 0; padding-left: 1em; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 16px; }
    table th, table td { border: 1px solid var(--wiki-blockquote-border); padding: 8px 13px; }
    table th { background: var(--wiki-pre-bg); }
    img { max-width: 100%; }

    /* OKF Custom Components */
    .okf-top-bar { display: flex; align-items: center; justify-content: space-between; font-size: 12px; color: var(--wiki-meta-text); margin-bottom: 16px; border-bottom: 1px dashed var(--wiki-border); padding-bottom: 8px; }
    .okf-footer-card { background: var(--wiki-meta-bg); border: 1px solid var(--wiki-border); border-radius: 6px; padding: 16px; margin-top: 40px; }
    .okf-footer-header { display: flex; justify-content: space-between; align-items: center; font-size: 13px; font-weight: bold; color: var(--wiki-text); border-bottom: 1px solid var(--wiki-border); padding-bottom: 8px; margin-bottom: 10px; }
    .okf-footer-meta { display: flex; gap: 20px; font-size: 12px; color: var(--wiki-meta-text); margin-top: 10px; }
    .okf-api-link { font-size: 11px; color: var(--wiki-link); text-decoration: none; padding: 2px 8px; background: var(--wiki-tag-bg); border-radius: 12px; }
    .okf-api-link:hover { background: var(--wiki-link-hover); color: #fff; }
    .okf-desc { font-size: 13px; color: var(--wiki-meta-text); margin: 6px 0 10px 0; }
    .okf-tags { display: flex; gap: 6px; flex-wrap: wrap; margin-top: 10px; }
    .tag-badge { background: var(--wiki-tag-bg); color: var(--wiki-link); text-decoration: none; padding: 2px 8px; border-radius: 12px; font-size: 12px; }
    .tag-badge:hover { background: var(--wiki-tag-bg-hover); color: var(--wiki-tag-text-hover); }
    .badge { padding: 3px 8px; border-radius: 12px; font-size: 11px; font-weight: bold; text-transform: uppercase; }
    .badge-active { background: #28a745; color: #fff; }
    .badge-draft { background: #ffc107; color: #212529; }
    .badge-deprecated { background: #dc3545; color: #fff; }
    .warning-banner { background: #fff3cd; border: 1px solid #ffeeba; color: #856404; padding: 12px 16px; border-radius: 6px; margin-bottom: 16px; }

    /* Tags & Glossary Static Views */
    .tag-cloud { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 16px; }
    .tag-cloud-item { background: var(--wiki-card-bg); color: var(--wiki-link); border: 1px solid var(--wiki-card-border); padding: 6px 12px; border-radius: 16px; text-decoration: none; font-size: 13px; font-weight: bold; }
    .tag-cloud-item:hover { background: var(--wiki-link-hover); color: #fff; text-decoration: none; border-color: var(--wiki-link-hover); }
    .tag-count { font-size: 11px; opacity: 0.8; font-weight: normal; }
    .glossary-box { background: var(--wiki-glossary-bg); border-left: 4px solid var(--wiki-link); padding: 14px 18px; border-radius: 6px; margin-bottom: 24px; }
    .glossary-title { font-weight: bold; color: var(--wiki-link); font-size: 15px; margin-bottom: 8px; }
    .glossary-content { font-size: 13px; color: var(--wiki-text); line-height: 1.6; }
    .tag-card, .search-item { border-bottom: 1px solid var(--wiki-border); padding: 12px 0; }
    .tag-card h3, .search-item h3 { margin: 0 0 6px 0; font-size: 16px; }
    .tag-card a, .search-item a { color: var(--wiki-link); text-decoration: none; }
    .tag-card a:hover, .search-item a:hover { text-decoration: underline; }
    .tag-card p, .search-item p { margin: 4px 0 0 0; font-size: 13px; color: var(--wiki-meta-text); }

    /* Single File Inline Tag & Author Filter Banner */
    .single-file-filter-banner { display: none; background: var(--wiki-glossary-bg); border: 1px solid var(--wiki-card-border); color: var(--wiki-link); padding: 10px 16px; border-radius: 6px; margin-bottom: 20px; font-size: 14px; }
    .single-file-filter-banner a { color: var(--wiki-link); font-weight: bold; margin-left: 10px; text-decoration: underline; }

    /* Single page section divider */
    html { scroll-behavior: smooth; }
    .wiki-page { border-bottom: 2px solid var(--wiki-border); padding-bottom: 40px; margin-bottom: 40px; }
    .wiki-page:last-child { border-bottom: none; margin-bottom: 0; padding-bottom: 0; }
'@

    return $commonStyle
}

function Export-WikiApiIndexJson {
    param (
        $AllApiItems,
        [string]$TargetDistDir
    )

    $itemsList = @($AllApiItems)

    $apiEnvelope = [PSCustomObject]@{
        Total       = $itemsList.Count
        Count       = $itemsList.Count
        Offset      = 0
        Limit       = $itemsList.Count
        IsTruncated = $false
        Items       = @($itemsList | ForEach-Object {
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
    $apiDestDir  = Join-Path $TargetDistDir "api"
    if (-not (Test-Path $apiDestDir)) { New-Item -ItemType Directory -Path $apiDestDir -Force | Out-Null }
    [System.IO.File]::WriteAllText((Join-Path $apiDestDir "index.json"), $apiJsonText, [System.Text.Encoding]::UTF8)
    return $apiJsonText
}

function Get-ExportTagsPageHtml {
    param (
        [string]$ApiJsonText,
        [string]$GlossaryJsonText,
        [string]$Template = "",
        [string]$SidebarHtml = "",
        [string]$ExportLang = "ja",
        [string]$DocListTitle = ""
    )

    $tagListTitle       = Get-LocalizedStr -Key "tag_list_title" -Lang $ExportLang
    $tagDocsHeadingTpl  = Get-LocalizedStr -Key "tag_docs_heading" -Lang $ExportLang
    $backToTagsText     = Get-LocalizedStr -Key "back_to_tags" -Lang $ExportLang
    $glossaryTitleTpl   = Get-LocalizedStr -Key "tag_glossary_title" -Lang $ExportLang
    $tagEmptyMsg        = Get-LocalizedStr -Key "tag_empty_msg" -Lang $ExportLang
    $tagNoneRegistered  = Get-LocalizedStr -Key "tag_none_registered" -Lang $ExportLang

    $tagsBodyContent = @"
<div id="tagViewContainer"></div>
<script id="wiki-index-data" type="application/json">
$ApiJsonText
</script>
<script id="wiki-glossary-data" type="application/json">
$GlossaryJsonText
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

    if ([string]::IsNullOrWhiteSpace($Template)) {
        return $tagsBodyContent
    }

    $fullTagsHtml = $Template.Replace("<!-- {{SIMPLEWIKI_PAGE_TITLE}} -->", $tagListTitle).Replace("<!-- {{SIMPLEWIKI_SIDEBAR}} -->", $SidebarHtml).Replace("<!-- {{SIMPLEWIKI_MERMAID}} -->", "").Replace("<!-- {{SIMPLEWIKI_LANG}} -->", $ExportLang).Replace("<!-- {{SIMPLEWIKI_DOC_LIST_TITLE}} -->", $DocListTitle).Replace("<!-- {{SIMPLEWIKI_BODY}} -->", $tagsBodyContent)
    return ($fullTagsHtml -replace "\r?\n", "`r`n")
}

function Get-ExportAuthorsPageHtml {
    param (
        [string]$ApiJsonText,
        [string]$Template = "",
        [string]$SidebarHtml = "",
        [string]$ExportLang = "ja",
        [string]$DocListTitle = ""
    )

    $authorListTitle      = Get-LocalizedStr -Key "author_list_title" -Lang $ExportLang
    $authorDocsHeadingTpl = Get-LocalizedStr -Key "author_docs_heading" -Lang $ExportLang
    $backToAuthorsText    = Get-LocalizedStr -Key "back_to_authors" -Lang $ExportLang
    $authorEmptyMsg       = Get-LocalizedStr -Key "author_empty_msg" -Lang $ExportLang
    $authorNoneRegistered = Get-LocalizedStr -Key "author_none_registered" -Lang $ExportLang

    $authorsBodyContent = @"
<div id="authorViewContainer"></div>
<script id="wiki-index-data" type="application/json">
$ApiJsonText
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

    if ([string]::IsNullOrWhiteSpace($Template)) {
        return $authorsBodyContent
    }

    $fullAuthorsHtml = $Template.Replace("<!-- {{SIMPLEWIKI_PAGE_TITLE}} -->", $authorListTitle).Replace("<!-- {{SIMPLEWIKI_SIDEBAR}} -->", $SidebarHtml).Replace("<!-- {{SIMPLEWIKI_MERMAID}} -->", "").Replace("<!-- {{SIMPLEWIKI_LANG}} -->", $ExportLang).Replace("<!-- {{SIMPLEWIKI_DOC_LIST_TITLE}} -->", $DocListTitle).Replace("<!-- {{SIMPLEWIKI_BODY}} -->", $authorsBodyContent)
    return ($fullAuthorsHtml -replace "\r?\n", "`r`n")
}
