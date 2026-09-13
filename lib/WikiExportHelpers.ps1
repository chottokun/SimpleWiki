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
        return Render-ExportFolderTreeHtml -node $treeNode -currentFile $null -currentUri $null -IsSingleFileMode
    } else {
        $currentHtmlPath = $currentFile.FullName -replace '\.md$', '.html'
        $currentUri      = New-Object System.Uri($currentHtmlPath)

        $treeNode = Build-FileTreeNode -allMdFiles $allMdFiles -wikiDir $wikiDir
        return Render-ExportFolderTreeHtml -node $treeNode -currentFile $currentFile -currentUri $currentUri
    }
}
