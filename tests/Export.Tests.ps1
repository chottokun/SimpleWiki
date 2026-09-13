# ==============================================================================
#  Export.Tests.ps1
#  Encoding: UTF-8 with BOM
# ==============================================================================

[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingInvokeExpression", "")]
param()

if (-not $script:projectRoot) {
    $script:projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}
$projectRoot = $script:projectRoot
$libDll      = Join-Path $projectRoot "lib\Markdig.dll"

Describe "Static HTML Export Tests (Export-MarkdigWiki.ps1)" {
    BeforeAll {
        $testExportDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestExport"
        if (Test-Path $testExportDir) { Remove-Item -Path $testExportDir -Recurse -Force }
    }

    AfterAll {
        if (Test-Path $testExportDir) { Remove-Item -Path $testExportDir -Recurse -Force }
    }

    It "Exports static HTML files to target directory" {
        $exportScript = Join-Path $projectRoot "Export-MarkdigWiki.ps1"
        $sampleDir    = Join-Path $projectRoot "markdown_sample"
        & $exportScript -RootFolder $sampleDir -OutputDir $testExportDir

        (Test-Path (Join-Path $testExportDir "index.html")) | Should Be $true
        (Test-Path (Join-Path $testExportDir "概要.html")) | Should Be $true
        (Test-Path (Join-Path $testExportDir "docs\詳細仕様.html")) | Should Be $true
    }

    It "Converts .md hyperlinks to .html in exported files" {
        $indexHtmlPath = Join-Path $testExportDir "index.html"
        $htmlContent   = [System.IO.File]::ReadAllText($indexHtmlPath)

        $htmlContent | Should Match "(%E6%A6%82%E8%A6%81|概要)\.html"
        $htmlContent | Should Match "docs/(%E8%A9%B3%E7%B4%B0%E4%BB%95%E6%A7%98|詳細仕様)\.html"
    }

    It "Generates relative URI links for subfolder pages without leading slash" {
        $subHtmlPath    = Join-Path $testExportDir "docs\詳細仕様.html"
        $subHtmlContent = [System.IO.File]::ReadAllText($subHtmlPath)

        $subHtmlContent | Should Match "href='../index.html'"
        $subHtmlContent | Should Match "href='../(%E6%A6%82%E8%A6%81|概要)\.html'"
    }

    It "Generates nested tree structure for subfolder pages in sidebar" {
        $subHtmlPath    = Join-Path $testExportDir "docs\詳細仕様.html"
        $subHtmlContent = [System.IO.File]::ReadAllText($subHtmlPath)

        $subHtmlContent | Should Match "<li class='nav-folder'>"
        # アクティブな親フォルダ docs は open
        $subHtmlContent | Should Match "<details open>\s*<summary class='folder-title'>.*?\s*docs</summary>"
        # アクティブでないフォルダ guides は open なし
        $subHtmlContent | Should Match "<details>\s*<summary class='folder-title'>.*?\s*guides</summary>"
    }

    It "Embeds OKF top bar and footer card in exported static HTML files" {
        $indexHtmlPath = Join-Path $testExportDir "index.html"
        $htmlContent   = [System.IO.File]::ReadAllText($indexHtmlPath)

        $htmlContent | Should Match "class=""okf-top-bar"""
        $htmlContent | Should Match "class=""okf-footer-card"""
    }

    It "Multi-file export generates static api/index.json, tags.html, and authors.html with relative tag and API links" {
        $apiJsonPath = Join-Path (Join-Path $testExportDir "api") "index.json"
        (Test-Path $apiJsonPath) | Should Be $true
        $apiJsonText = [System.IO.File]::ReadAllText($apiJsonPath)
        $apiJsonText | Should Match '"Total":'
        $apiJsonText | Should Match '"Items":'

        $tagsHtmlPath = Join-Path $testExportDir "tags.html"
        (Test-Path $tagsHtmlPath) | Should Be $true
        $tagsHtmlContent = [System.IO.File]::ReadAllText($tagsHtmlPath)
        $tagsHtmlContent | Should Match 'id="tagViewContainer"'
        $tagsHtmlContent | Should Match 'id="wiki-index-data"'

        $authorsHtmlPath = Join-Path $testExportDir "authors.html"
        (Test-Path $authorsHtmlPath) | Should Be $true
        $authorsHtmlContent = [System.IO.File]::ReadAllText($authorsHtmlPath)
        $authorsHtmlContent | Should Match 'id="authorViewContainer"'

        # Check subfolder document has relative tag, author, and API links
        $subHtmlPath = Join-Path $testExportDir "docs\api\REST-API.html"
        if (Test-Path $subHtmlPath) {
            $subContent = [System.IO.File]::ReadAllText($subHtmlPath)
            $subContent | Should Match 'href=[''"]\.\./\.\./tags\.html\?tag='
            $subContent | Should Match 'href=[''"]\.\./\.\./authors\.html\?name='
            $subContent | Should Match 'href=[''"]\.\./\.\./api/index\.json["'']'
        }
    }

    It "Static export with -Language en localizes tags.html and authors.html UI text" {
        $enExportDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestEnExport"
        if (Test-Path $enExportDir) { Remove-Item -Path $enExportDir -Recurse -Force }

        try {
            $exportScript = Join-Path $projectRoot "Export-MarkdigWiki.ps1"
            $sampleDir    = Join-Path $projectRoot "markdown_sample"
            & $exportScript -RootFolder $sampleDir -OutputDir $enExportDir -Language "en"

            $tagsPath = Join-Path $enExportDir "tags.html"
            (Test-Path $tagsPath) | Should Be $true
            $tagsContent = [System.IO.File]::ReadAllText($tagsPath)
            $tagsContent | Should Match 'Back to all tags'
            $tagsContent | Should Match 'Documents tagged'

            $authorsPath = Join-Path $enExportDir "authors.html"
            (Test-Path $authorsPath) | Should Be $true
            $authorsContent = [System.IO.File]::ReadAllText($authorsPath)
            $authorsContent | Should Match 'Back to all authors'
            $authorsContent | Should Match 'Documents by'
        } finally {
            if (Test-Path $enExportDir) { Remove-Item -Path $enExportDir -Recurse -Force }
        }
    }

    It "Multi-file export respects -NoApiJson, -NoTagsPage, and -NoAuthorsPage switches" {
        $noOptDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestNoOptExport"
        if (Test-Path $noOptDir) { Remove-Item -Path $noOptDir -Recurse -Force }

        try {
            $exportScript = Join-Path $projectRoot "Export-MarkdigWiki.ps1"
            $sampleDir    = Join-Path $projectRoot "markdown_sample"
            & $exportScript -RootFolder $sampleDir -OutputDir $noOptDir -NoApiJson -NoTagsPage -NoAuthorsPage

            (Test-Path (Join-Path $noOptDir "index.html")) | Should Be $true
            (Test-Path (Join-Path (Join-Path $noOptDir "api") "index.json")) | Should Be $false
            (Test-Path (Join-Path $noOptDir "tags.html")) | Should Be $false
            (Test-Path (Join-Path $noOptDir "authors.html")) | Should Be $false
        } finally {
            if (Test-Path $noOptDir) { Remove-Item -Path $noOptDir -Recurse -Force }
        }
    }

    It "Defines CSS style block cleanly without duplication" {
        $indexHtmlPath = Join-Path $testExportDir "index.html"
        $htmlContent   = [System.IO.File]::ReadAllText($indexHtmlPath)

        $styleMatches = [regex]::Matches($htmlContent, '<style>')
        $styleMatches.Count | Should Be 1
    }

    It "-SingleFile switch exports monolith HTML with anchor navigation and Base64 embedded images by default" {
        $singleExportDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestSingleFileExport"
        if (Test-Path $singleExportDir) { Remove-Item -Path $singleExportDir -Recurse -Force }

        try {
            $exportScript = Join-Path $projectRoot "Export-MarkdigWiki.ps1"
            $sampleDir    = Join-Path $projectRoot "markdown_sample"
            & $exportScript -RootFolder $sampleDir -OutputDir $singleExportDir -SingleFile -MermaidMode "Runtime"

            $indexPath = Join-Path $singleExportDir "index.html"
            (Test-Path $indexPath) | Should Be $true

            $htmlContent = [System.IO.File]::ReadAllText($indexPath)
            # Verify single page sections exist and are not hidden
            $htmlContent | Should Match '<section class="wiki-page" id="index"'
            $htmlContent | Should Match '<section class="wiki-page" id="page_'
            $htmlContent | Should Not Match '<section[^>]*class="wiki-page"[^>]*style="[^"]*display:\s*none'

            # Verify links rewritten to anchor hash fragments
            $htmlContent | Should Match 'href="#index"'

            # Verify navigation JavaScript functions are present
            $htmlContent | Should Match 'function updateActiveNav'
            $htmlContent | Should Match 'window\.addEventListener\(''hashchange'''

            # Verify inlined mermaid.min.js is present in Runtime mode
            $htmlContent | Should Match 'mermaid\.initialize'

            # Verify images are embedded as Base64 Data URIs by default
            $htmlContent | Should Match 'src="data:image/png;base64,'
            $htmlContent | Should Match 'src="data:image/svg\+xml;base64,'
            $htmlContent | Should Not Match 'src="\.\./\.\./images/'
            $htmlContent | Should Not Match 'src="\.\./images/'

            # Verify static api/index.json exists and single file contains filter banner
            $singleApiJson = Join-Path (Join-Path $singleExportDir "api") "index.json"
            (Test-Path $singleApiJson) | Should Be $true

            $htmlContent | Should Match 'id="singleFileFilterBanner"'
            $htmlContent | Should Match 'data-tags='
            $htmlContent | Should Match 'href=.*#tag='
            $htmlContent | Should Match 'href=.*api/index\.json'

            # Verify physical images folder was not copied (pure self-contained HTML)
            $imagesDir = Join-Path $singleExportDir "images"
            (Test-Path $imagesDir) | Should Be $false
        } finally {
            if (Test-Path $singleExportDir) { Remove-Item -Path $singleExportDir -Recurse -Force }
        }
    }

    It "-SingleFile with -NoEmbedImages preserves relative paths and copies asset directory" {
        $noEmbedDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestNoEmbedExport"
        if (Test-Path $noEmbedDir) { Remove-Item -Path $noEmbedDir -Recurse -Force }

        try {
            $exportScript = Join-Path $projectRoot "Export-MarkdigWiki.ps1"
            $sampleDir    = Join-Path $projectRoot "markdown_sample"
            & $exportScript -RootFolder $sampleDir -OutputDir $noEmbedDir -SingleFile -NoEmbedImages -MermaidMode "Runtime"

            $indexPath = Join-Path $noEmbedDir "index.html"
            (Test-Path $indexPath) | Should Be $true

            $htmlContent = [System.IO.File]::ReadAllText($indexPath)
            # Relative image paths normalized to root
            $htmlContent | Should Match 'src="images/ui-header\.png"'
            $htmlContent | Should Match 'src="images/ui-viewer-header\.png"'

            # External images folder is preserved
            $imagesDir = Join-Path $noEmbedDir "images"
            (Test-Path $imagesDir) | Should Be $true
        } finally {
            if (Test-Path $noEmbedDir) { Remove-Item -Path $noEmbedDir -Recurse -Force }
        }
    }

    It "Get-OptimizedImageBase64 resizes large images and converts images to Data URIs" {
        $exportHelpers = Join-Path $projectRoot "lib\WikiExportHelpers.ps1"
        . $exportHelpers
        $svgPath       = Join-Path $projectRoot "markdown_sample\images\architecture.svg"
        $pngPath       = Join-Path $projectRoot "markdown_sample\images\ui-header.png"

        # 1. Test SVG
        $svgUri = Get-OptimizedImageBase64 -filePath $svgPath
        $svgUri | Should Match '^data:image/svg\+xml;base64,'

        # 2. Test PNG
        $pngUri = Get-OptimizedImageBase64 -filePath $pngPath
        $pngUri | Should Match '^data:image/png;base64,'

        # 3. Test Large Image Resize (maxDimension 800) if GDI+ is available
        $canTestGdi = $false
        try {
            Add-Type -AssemblyName System.Drawing -ErrorAction Stop
            $testBmp = New-Object System.Drawing.Bitmap 10, 10
            $testBmp.Dispose()
            $canTestGdi = $true
        } catch {
            $null = $_ # Suppressed intentionally
        }

        if ($canTestGdi) {
            $tempLargeBmpPath = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_LargeTestImage.png"
            try {
                $largeBmp = New-Object System.Drawing.Bitmap 2400, 1800
                $g = [System.Drawing.Graphics]::FromImage($largeBmp)
                $g.Clear([System.Drawing.Color]::Blue)
                $g.Dispose()
                $largeBmp.Save($tempLargeBmpPath, [System.Drawing.Imaging.ImageFormat]::Png)
                $largeBmp.Dispose()

                $resizedUri = Get-OptimizedImageBase64 -filePath $tempLargeBmpPath -maxDimension 800
                $resizedUri | Should Match '^data:image/(?:png|jpeg);base64,'

                # Decode resized image and verify dimension
                $b64Data = $resizedUri -replace '^data:image/(?:png|jpeg);base64,', ''
                $bytes = [Convert]::FromBase64String($b64Data)
                $ms = New-Object System.IO.MemoryStream(,$bytes)
                $decodedImg = [System.Drawing.Image]::FromStream($ms)
                ($decodedImg.Width -le 800) | Should Be $true
                ($decodedImg.Height -le 800) | Should Be $true
                $decodedImg.Dispose()
                $ms.Dispose()
            } finally {
                if (Test-Path $tempLargeBmpPath) { Remove-Item -Path $tempLargeBmpPath -Force }
            }
        }
    }

    It "-MermaidMode Svg mode transforms mermaid code blocks and omits mermaid.min.js" {
        $svgExportDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestSvgExport"
        if (Test-Path $svgExportDir) { Remove-Item -Path $svgExportDir -Recurse -Force }

        try {
            $exportScript = Join-Path $projectRoot "Export-MarkdigWiki.ps1"
            $sampleDir    = Join-Path $projectRoot "markdown_sample"
            & $exportScript -RootFolder $sampleDir -OutputDir $svgExportDir -MermaidMode "Svg"

            # Check that mermaid.min.js was NOT copied to output directory
            $mermaidLibPath = Join-Path (Join-Path $svgExportDir "lib") "mermaid.min.js"
            (Test-Path $mermaidLibPath) | Should Be $false

            # Check that mermaid code blocks were converted to SVG containers in HTML files
            $specHtmlPath = Join-Path (Join-Path $svgExportDir "docs") "詳細仕様.html"
            (Test-Path $specHtmlPath) | Should Be $true
            if (Test-Path $specHtmlPath) {
                $htmlContent = [System.IO.File]::ReadAllText($specHtmlPath)
                $htmlContent | Should Match 'class="mermaid-svg"'
                $htmlContent | Should Match '<svg '
                $htmlContent | Should Not Match '<script src=".*?mermaid.min.js">'
            }
        } finally {
            if (Test-Path $svgExportDir) { Remove-Item -Path $svgExportDir -Recurse -Force }
        }
    }
}

Describe "Convert-MermaidToSvgMarkup Unit Tests" {
    BeforeAll {
        $exportHelpers = Join-Path $projectRoot "lib\WikiExportHelpers.ps1"
        . $exportHelpers
    }

    It "Converts <pre class='mermaid'> into SVG markup block" {
        $inputHtml = '<pre class="mermaid">graph TD;&#10;A--&gt;B;</pre>'
        $result = Convert-MermaidToSvgMarkup -html $inputHtml

        $result | Should Match '<div class="mermaid-svg"'
        $result | Should Match '<svg '
        $result | Should Match 'Mermaid Diagram \(SVG Static Mode\)'
        $result | Should Match 'graph TD;'
    }

    It "Converts <pre><code class='language-mermaid'> into SVG markup block" {
        $inputHtml = '<pre><code class="language-mermaid">graph LR;&#10;X--&gt;Y;</code></pre>'
        $result = Convert-MermaidToSvgMarkup -html $inputHtml

        $result | Should Match '<div class="mermaid-svg"'
        $result | Should Match '<svg '
        $result | Should Match 'graph LR;'
    }

    It "Encodes special characters (HTML entities) in Mermaid code" {
        $inputHtml = '<pre class="mermaid">A & B < C > D</pre>'
        $result = Convert-MermaidToSvgMarkup -html $inputHtml

        $result | Should Match 'A &amp; B &lt; C &gt; D'
    }

    It "Leaves non-Mermaid pre code blocks unchanged" {
        $inputHtml = '<pre><code class="language-bash">echo "Hello World"</code></pre>'
        $result = Convert-MermaidToSvgMarkup -html $inputHtml

        $result | Should Be $inputHtml
    }

    It "Converts multiple Mermaid blocks while leaving non-Mermaid blocks untouched" {
        $inputHtml = @"
<p>Intro</p>
<pre class="mermaid">graph TD; A-->B;</pre>
<pre><code class="language-bash">echo 123</code></pre>
<pre><code class="language-mermaid">sequenceDiagram; Alice->>Bob: Hi;</code></pre>
"@
        $result = Convert-MermaidToSvgMarkup -html $inputHtml

        $matches = [regex]::Matches($result, '<div class="mermaid-svg"')
        $matches.Count | Should Be 2
        $result | Should Match '<pre><code class="language-bash">echo 123</code></pre>'
    }

    It "Returns original HTML string when no Mermaid blocks exist or when given empty string" {
        $inputHtml = '<p>No mermaid diagram here</p>'
        (Convert-MermaidToSvgMarkup -html $inputHtml) | Should Be $inputHtml
        (Convert-MermaidToSvgMarkup -html "") | Should Be ""
    }
}


Describe 'Export-GUI.ps1 GUI Component and Syntax Validation' {
    It 'Export-GUI.ps1 file exists and passes AST syntax parsing' {
        $guiScript = Join-Path $projectRoot "Export-GUI.ps1"
        (Test-Path $guiScript) | Should Be $true

        $errs = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseFile($guiScript, [ref]$tokens, [ref]$errs)
        $errs.Count | Should Be 0
    }

    It 'Export-GUI.bat exists and references Export-GUI.ps1' {
        $guiBat = Join-Path $projectRoot "Export-GUI.bat"
        (Test-Path $guiBat) | Should Be $true
        $content = Get-Content -Path $guiBat -Raw
        $content | Should Match "Export-GUI\.ps1"
    }

    It 'Export-GUI.ps1 contains controls for SingleFile, MermaidMode, EmbedImages, Language, and Feature Toggles' {
        $guiScript = Join-Path $projectRoot "Export-GUI.ps1"
        $content   = Get-Content -Path $guiScript -Raw
        $content | Should Match 'chkSingleFile'
        $content | Should Match 'cmbMermaid'
        $content | Should Match 'chkEmbedImages'
        $content | Should Match 'cmbLang'
        $content | Should Match 'chkApiJson'
        $content | Should Match 'chkTagsPage'
        $content | Should Match 'chkAuthorsPage'
        $content | Should Match 'NoApiJson'
        $content | Should Match 'NoTagsPage'
        $content | Should Match 'NoAuthorsPage'
        $content | Should Match 'cmbTheme'
        $content | Should Match 'chkDisableRawHtml'
        $content | Should Match 'chkPreserveCodeBlock'
    }
}

Describe "Static Export Tree and Navigation Helper Unit Tests" {
    BeforeAll {
        . (Join-Path $projectRoot "lib\WikiMetadata.ps1")
        . (Join-Path $projectRoot "lib\WikiExportHelpers.ps1")

        $script:dummyBaseDir = Join-Path $projectRoot "markdown_sample"
        $script:dummyFile1Path = Join-Path $script:dummyBaseDir "index.md"
        $script:dummyFile2Path = Join-Path (Join-Path $script:dummyBaseDir "docs") "guide.md"
        $script:dummyHtml2Path = Join-Path (Join-Path $script:dummyBaseDir "docs") "guide.html"
    }

    It "Build-FileTreeNode creates hierarchical folder structure from markdown file list" {
        $dummyFiles = @(
            [PSCustomObject]@{ FullName = $script:dummyFile1Path; BaseName = "index" },
            [PSCustomObject]@{ FullName = $script:dummyFile2Path; BaseName = "guide" }
        )
        $treeNode = Build-FileTreeNode -allMdFiles $dummyFiles -wikiDir $script:dummyBaseDir
        $treeNode.Files.Count | Should Be 1
        $treeNode.SubFolders.Contains("docs") | Should Be $true
        $treeNode.SubFolders["docs"].Files.Count | Should Be 1
    }

    It "Test-ExportNodeHasActiveFile identifies if active file exists in node tree" {
        $dummyFile1 = [PSCustomObject]@{ FullName = $script:dummyFile1Path; BaseName = "index" }
        $dummyFile2 = [PSCustomObject]@{ FullName = $script:dummyFile2Path; BaseName = "guide" }
        $treeNode = Build-FileTreeNode -allMdFiles @($dummyFile1, $dummyFile2) -wikiDir $script:dummyBaseDir

        (Test-ExportNodeHasActiveFile -node $treeNode.SubFolders["docs"] -currentFile $dummyFile2) | Should Be $true
        (Test-ExportNodeHasActiveFile -node $treeNode.SubFolders["docs"] -currentFile $dummyFile1) | Should Be $false
    }

    It "Render-ExportFolderTreeHtml renders HTML list with details and active file highlights" {
        $dummyFile1 = [PSCustomObject]@{ FullName = $script:dummyFile1Path; BaseName = "index" }
        $dummyFile2 = [PSCustomObject]@{ FullName = $script:dummyFile2Path; BaseName = "guide" }
        $treeNode = Build-FileTreeNode -allMdFiles @($dummyFile1, $dummyFile2) -wikiDir $script:dummyBaseDir
        $currentUri = New-Object System.Uri($script:dummyHtml2Path)

        $html = Render-ExportFolderTreeHtml -node $treeNode -currentFile $dummyFile2 -currentUri $currentUri
        $html | Should Match "<li class='nav-folder'>"
        $html | Should Match "<details open>"
        $html | Should Match "class='active'"
    }

    It "Get-ExportSidebarHtml builds sidebar tree HTML for single file mode and multi-file mode" {
        $dummyFile1 = [PSCustomObject]@{ FullName = $script:dummyFile1Path; BaseName = "index" }
        $dummyFiles = @($dummyFile1)

        $htmlSingle = Get-ExportSidebarHtml -currentFile $null -allMdFiles $dummyFiles -wikiDir $script:dummyBaseDir -IsSingleFileMode
        $htmlSingle | Should Match "href='#index'"

        $htmlMulti = Get-ExportSidebarHtml -currentFile $dummyFile1 -allMdFiles $dummyFiles -wikiDir $script:dummyBaseDir
        $htmlMulti | Should Match "class='active'"
    }
}

Describe "Static HTML Export Template and HTML Safety Options" {
    BeforeAll {
        $script:testExportDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestExportSafety"
        if (Test-Path $script:testExportDir) { Remove-Item -Path $script:testExportDir -Recurse -Force }
        New-Item -ItemType Directory -Path $script:testExportDir -Force | Out-Null
        
        $script:dummySampleDir = Join-Path $script:testExportDir "dummy_wiki"
        New-Item -ItemType Directory -Path $script:dummySampleDir -Force | Out-Null
        
        $script:exportScript = Join-Path $projectRoot "Export-MarkdigWiki.ps1"
    }
    AfterAll {
        if (Test-Path $script:testExportDir) { Remove-Item -Path $script:testExportDir -Recurse -Force }
    }
    
    BeforeEach {
        if (Test-Path (Join-Path $script:testExportDir "out")) { Remove-Item -Path (Join-Path $script:testExportDir "out") -Recurse -Force }
        New-Item -ItemType Directory -Path (Join-Path $script:testExportDir "out") -Force | Out-Null
        if (Test-Path $script:dummySampleDir) { Remove-Item -Path $script:dummySampleDir\* -Recurse -Force }
    }

    It "-DisableRawHtml prevents <script> tags from passing through" {
        $mdPath = Join-Path $script:dummySampleDir "test.md"
        [System.IO.File]::WriteAllText($mdPath, "<script>alert(1);</script>", [System.Text.Encoding]::UTF8)
        
        & $script:exportScript -RootFolder $script:dummySampleDir -OutputDir (Join-Path $script:testExportDir "out") -DisableRawHtml
        
        $htmlPath = Join-Path (Join-Path $script:testExportDir "out") "test.html"
        $html = [System.IO.File]::ReadAllText($htmlPath)
        $html | Should Not Match "<script>alert\(1\);</script>"
    }

    It "-Theme outputs correct CSS classes (Light, Dark, Auto)" {
        $mdPath = Join-Path $script:dummySampleDir "test.md"
        [System.IO.File]::WriteAllText($mdPath, "test content", [System.Text.Encoding]::UTF8)
        
        # Light
        & $script:exportScript -RootFolder $script:dummySampleDir -OutputDir (Join-Path $script:testExportDir "out") -Theme Light
        $htmlPath = Join-Path (Join-Path $script:testExportDir "out") "test.html"
        $htmlLight = [System.IO.File]::ReadAllText($htmlPath)
        $htmlLight | Should Match '--wiki-bg: #ffffff;'
        $htmlLight | Should Not Match '@media \(prefers-color-scheme: dark\)'
        
        # Dark
        & $script:exportScript -RootFolder $script:dummySampleDir -OutputDir (Join-Path $script:testExportDir "out") -Theme Dark
        $htmlDark = [System.IO.File]::ReadAllText($htmlPath)
        $htmlDark | Should Match '--wiki-bg: #0d1117;'
        $htmlDark | Should Not Match '@media \(prefers-color-scheme: dark\)'
        
        # Auto
        & $script:exportScript -RootFolder $script:dummySampleDir -OutputDir (Join-Path $script:testExportDir "out") -Theme Auto
        $htmlAuto = [System.IO.File]::ReadAllText($htmlPath)
        $htmlAuto | Should Match '--wiki-bg: #ffffff;'
        $htmlAuto | Should Match '@media \(prefers-color-scheme: dark\)'
    }

    It "-TemplatePath utilizes custom template" {
        $mdPath = Join-Path $script:dummySampleDir "test.md"
        [System.IO.File]::WriteAllText($mdPath, "test content", [System.Text.Encoding]::UTF8)
        
        $tplPath = Join-Path $script:testExportDir "custom.html"
        [System.IO.File]::WriteAllText($tplPath, "CUSTOM_TEMPLATE_START<!-- {{SIMPLEWIKI_BODY}} -->CUSTOM_TEMPLATE_END", [System.Text.Encoding]::UTF8)
        
        & $script:exportScript -RootFolder $script:dummySampleDir -OutputDir (Join-Path $script:testExportDir "out") -TemplatePath $tplPath
        $htmlPath = Join-Path (Join-Path $script:testExportDir "out") "test.html"
        $html = [System.IO.File]::ReadAllText($htmlPath)
        $html | Should Match "CUSTOM_TEMPLATE_START"
        $html | Should Match "CUSTOM_TEMPLATE_END"
        $html | Should Match "<p>test content</p>"
    }
    
    It "-PreserveCodeBlockLinks does not mutate links in code blocks" {
        $mdPath = Join-Path $script:dummySampleDir "test.md"
        $mdContent = @"
<pre><code class="html">
href="tutorial.md"
</code></pre>

[Normal Link](tutorial.md)
"@
        [System.IO.File]::WriteAllText($mdPath, $mdContent, [System.Text.Encoding]::UTF8)
        
        & $script:exportScript -RootFolder $script:dummySampleDir -OutputDir (Join-Path $script:testExportDir "out") -PreserveCodeBlockLinks
        
        $htmlPath = Join-Path (Join-Path $script:testExportDir "out") "test.html"
        $html = [System.IO.File]::ReadAllText($htmlPath)
        
        $html | Should Match 'href="tutorial.md"'
        $html | Should Match 'href="tutorial.html"'
    }

    It "Formats like {0} in markdown body do not cause substitution errors" {
        $mdPath = Join-Path $script:dummySampleDir "test.md"
        $mdContent = "String format test {0} and {1}"
        [System.IO.File]::WriteAllText($mdPath, $mdContent, [System.Text.Encoding]::UTF8)
        
        & $script:exportScript -RootFolder $script:dummySampleDir -OutputDir (Join-Path $script:testExportDir "out")
        
        $htmlPath = Join-Path (Join-Path $script:testExportDir "out") "test.html"
        $html = [System.IO.File]::ReadAllText($htmlPath)
        
        $html | Should Match 'String format test \{0\} and \{1\}'
    }
}
