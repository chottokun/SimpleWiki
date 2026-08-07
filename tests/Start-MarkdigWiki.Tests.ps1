# ==============================================================================
#  Start-MarkdigWiki.Tests.ps1 (Pester Tests)
#  Encoding: UTF-8 with BOM
# ==============================================================================

$projectRoot = (Resolve-Path "$PSScriptRoot\..").Path
$libDll      = Join-Path $projectRoot "lib\Markdig.dll"

Describe "Markdig Assembly & Pipeline Tests" {
    It "Markdig.dll exists in lib directory" {
        (Test-Path $libDll) | Should Be $true
    }

    It "Markdig assembly loads and builds Advanced Extensions pipeline" {
        $libDir = Join-Path $projectRoot "lib"
        Get-ChildItem -Path $libDir -Filter "*.dll" | ForEach-Object {
            Add-Type -Path $_.FullName
        }
        $builder  = New-Object Markdig.MarkdownPipelineBuilder
        $null     = [Markdig.MarkdownExtensions]::UseAdvancedExtensions($builder)
        $pipeline = $builder.Build()
        $pipeline | Should Not Be $null

        $html = [Markdig.Markdown]::ToHtml("# Hello World`n- [x] Task completed", $pipeline)
        $html | Should Match "Hello World"
        $html | Should Match "task-list-item"
    }
}

Describe "Path Traversal & Security Validation Tests" {
    BeforeAll {
        $wikiDir     = $projectRoot
        $fullWikiDir = $wikiDir.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    }

    It "Valid relative path inside wikiDir is allowed" {
        $filePath  = Join-Path $wikiDir "index.md"
        $fullPath  = [System.IO.Path]::GetFullPath($filePath)
        $isAllowed = $fullPath.StartsWith($fullWikiDir, [System.StringComparison]::OrdinalIgnoreCase)
        $isAllowed | Should Be $true
    }

    It "Path traversal attempting to access external directory is blocked" {
        $filePath  = Join-Path $wikiDir "..\..\Windows\System32\drivers\etc\hosts"
        $fullPath  = [System.IO.Path]::GetFullPath($filePath)
        $isAllowed = $fullPath.StartsWith($fullWikiDir, [System.StringComparison]::OrdinalIgnoreCase)
        $isAllowed | Should Be $false
    }
}

Describe "HTML Escaping & XSS Protection Tests" {
    It "XSS script in 404 path is HTML encoded" {
        $rawPath  = "/<script>alert('xss')</script>"
        $safePath = [System.Net.WebUtility]::HtmlEncode($rawPath)
        $safePath | Should Not Match "<script>"
        $safePath | Should Match "&lt;script&gt;"
    }

    It "Special characters in page title are HTML encoded" {
        $baseName  = "<Test & Document>"
        $safeTitle = [System.Net.WebUtility]::HtmlEncode($baseName)
        $safeTitle | Should Be "&lt;Test &amp; Document&gt;"
    }
}

Describe "Static HTML Export Tests (Export-MarkdigWiki.ps1)" {
    BeforeAll {
        $testExportDir = Join-Path $env:TEMP "SimpleWiki_TestExport"
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

        $htmlContent | Should Match "%E6%A6%82%E8%A6%81.html"
        $htmlContent | Should Match "docs/%E8%A9%B3%E7%B4%B0%E4%BB%95%E6%A7%98.html"
    }

    It "Generates relative URI links for subfolder pages without leading slash" {
        $subHtmlPath    = Join-Path $testExportDir "docs\詳細仕様.html"
        $subHtmlContent = [System.IO.File]::ReadAllText($subHtmlPath)

        $subHtmlContent | Should Match "href='../index.html'"
        $subHtmlContent | Should Match "href='../%E6%A6%82%E8%A6%81.html'"
    }
}
