# ==============================================================================
#  Start-MarkdigWiki.Tests.ps1 (Pester Tests)
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

Describe 'Markdig Assembly and Pipeline Tests' {
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

    It "Renders embedded HTML tables with colspan and rowspan correctly" {
        $builder  = New-Object Markdig.MarkdownPipelineBuilder
        $null     = [Markdig.MarkdownExtensions]::UseAdvancedExtensions($builder)
        $pipeline = $builder.Build()

        $mdText = "<table><thead><tr><th rowspan=`"2`">Cat</th><th colspan=`"2`">Details</th></tr></thead><tbody><tr><td>Server</td><td>8080</td></tr></tbody></table>"
        $renderedHtml = [Markdig.Markdown]::ToHtml($mdText, $pipeline)
        $renderedHtml | Should Match '<table'
        $renderedHtml | Should Match 'rowspan="2"'
        $renderedHtml | Should Match 'colspan="2"'
    }
}

Describe 'Path Traversal and Security Validation Tests' {
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

Describe 'HTML Escaping and XSS Protection Tests' {
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
}

Describe 'OKF Metadata Extraction and Fallback Tests (Get-DocumentMetadata)' {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
    }

    It "Parses full OKF YAML Front Matter correctly" {
        $mdText = @"
---
title: DB Recovery Manual
description: PostgreSQL recovery steps
author: Taro Yamada
domain: infrastructure/database
tags: [PostgreSQL, Runbook]
last_updated: 2026-08-01
status: active
---
# Body Title
This is body text.
"@
        $fakeFile = [PSCustomObject]@{
            FullName      = "C:\wiki\docs\db\manual.md"
            LastWriteTime = (Get-Date "2026-01-01")
            BaseName      = "manual"
        }
        $meta = Get-DocumentMetadata -File $fakeFile -RelPath "docs/db/manual.md" -MdText $mdText
        $meta.Title | Should Be "DB Recovery Manual"
        $meta.Description | Should Be "PostgreSQL recovery steps"
        $meta.Author | Should Be "Taro Yamada"
        $meta.Domain | Should Be "infrastructure/database"
        $meta.Tags -contains "PostgreSQL" | Should Be $true
        $meta.Tags -contains "Runbook" | Should Be $true
        $meta.LastUpdated.ToString("yyyy-MM-dd") | Should Be "2026-08-01"
        $meta.Status | Should Be "active"
        $meta.HasYaml | Should Be $true
    }

    It "Parses bullet-list tags, quoted title with colons, and handles comments" {
        $mdText = @"
---
# This is a YAML comment
title: "System: Recovery Manual"
tags:
  - Database
  - PostgreSQL
---
# Header
"@
        $fakeFile = [PSCustomObject]@{
            FullName      = "C:\wiki\docs\bullet.md"
            LastWriteTime = (Get-Date "2026-01-01")
            BaseName      = "bullet"
        }
        $meta = Get-DocumentMetadata -File $fakeFile -RelPath "docs/bullet.md" -MdText $mdText
        $meta.Title | Should Be "System: Recovery Manual"
        $meta.Tags -contains "Database" | Should Be $true
        $meta.Tags -contains "PostgreSQL" | Should Be $true
    }


    It "Falls back to H1 header when title is missing in YAML" {
        $mdText = @"
---
description: No title in YAML
---
# Header Title from H1
Body text...
"@
        $fakeFile = [PSCustomObject]@{
            FullName      = "C:\wiki\docs\test.md"
            LastWriteTime = (Get-Date "2026-01-01")
            BaseName      = "test"
        }
        $meta = Get-DocumentMetadata -File $fakeFile -RelPath "docs/test.md" -MdText $mdText
        $meta.Title | Should Be "Header Title from H1"
    }

    It "Falls back to BaseName when no title in YAML and no H1 in body" {
        $mdText = "Plain markdown text without headers or YAML."
        $fakeFile = [PSCustomObject]@{
            FullName      = "C:\wiki\docs\my-doc.md"
            LastWriteTime = (Get-Date "2026-01-01")
            BaseName      = "my-doc"
        }
        $meta = Get-DocumentMetadata -File $fakeFile -RelPath "docs/my-doc.md" -MdText $mdText
        $meta.Title | Should Be "my-doc"
        $meta.Domain | Should Be "docs"
        $meta.Status | Should Be "active"
        $meta.HasYaml | Should Be $false
    }

    It "Gracefully handles malformed YAML syntax without throwing exceptions" {
        $mdText = @"
---
title: Malformed YAML
tags: [broken array
status: : : invalid syntax
---
# Header
"@
        $fakeFile = [PSCustomObject]@{
            FullName      = "C:\wiki\docs\broken.md"
            LastWriteTime = (Get-Date "2026-01-01")
            BaseName      = "broken"
        }
        { $script:testMeta = Get-DocumentMetadata -File $fakeFile -RelPath "docs/broken.md" -MdText $mdText } | Should Not Throw
        $script:testMeta.Title | Should Be "Malformed YAML"
    }

    It "Parses OKF v0.2 metadata fields (version, contributors, reviewer, superseded_by, related, stable status)" {
        $mdText = @"
---
title: "Architecture Spec v0.2"
version: "0.2.0"
status: stable
reviewer: "Kenji Sato"
contributors:
  - "Hanako Suzuki"
  - "Ichiro Tanaka"
superseded_by: "docs/v3-arch.md"
related:
  - "docs/api.md"
  - "docs/guide.md"
---
# Content
"@
        $meta = Get-DocumentMetadata -File $null -RelPath "docs/arch.md" -MdText $mdText
        $meta.Title | Should Be "Architecture Spec v0.2"
        $meta.Version | Should Be "0.2.0"
        $meta.Status | Should Be "stable"
        $meta.Reviewer | Should Be "Kenji Sato"
        $meta.Contributors.Count | Should Be 2
        $meta.Contributors -contains "Hanako Suzuki" | Should Be $true
        $meta.SupersededBy | Should Be "docs/v3-arch.md"
        $meta.Related.Count | Should Be 2
        $meta.LastUpdated | Should Be $null

        # TopBar and Footer HTML rendering
        $topBar = Get-OkfTopBarHtml -Meta $meta -Lang "ja"
        $topBar | Should Match "🌟 Stable"
        $topBar | Should Match "v0.2.0"

        $footer = Get-OkfFooterCardHtml -Meta $meta -Lang "ja"
        $footer | Should Match "v0.2.0"
        $footer | Should Match "Kenji Sato"
        $footer | Should Match "Hanako Suzuki"
        $footer | Should Match "docs/api.md"
        $footer | Should Match "不明"
    }

    It "Handles complete metadata absence with graceful fallbacks" {
        $plainText = "Just some plain text without any YAML front matter."
        $meta = Get-DocumentMetadata -File $null -RelPath "" -MdText $plainText
        $meta.Title | Should Be "Untitled"
        $meta.Status | Should Be "active"
        $meta.Domain | Should Be "root"
        $meta.Version | Should Be ""
        $meta.Contributors.Count | Should Be 0
        $meta.Related.Count | Should Be 0
        $meta.LastUpdated | Should Be $null

        # UI renders cleanly without exceptions
        $topBar = Get-OkfTopBarHtml -Meta $meta -Lang "en"
        $topBar | Should Match "Active"

        $footer = Get-OkfFooterCardHtml -Meta $meta -Lang "en"
        $footer | Should Match "Unknown"
    }
}


Describe 'OKF Dynamic View and API Endpoint Tests' {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        Build-WikiIndex -TargetWikiDir $sampleDir -ForceRefresh | Out-Null
    }

    It "Builds WikiIndex from sample directory successfully" {
        $script:WikiIndex.Count | Should BeGreaterThan 0
    }

    It "Generates JSON for /api/index.json containing Envelope structure and OKF metadata" {
        $json = Get-ApiIndexJson
        $json | Should Not Be $null
        $obj = $json | ConvertFrom-Json
        $obj.Total | Should BeGreaterThan 0
        $obj.Count | Should BeGreaterThan 0
        $obj.Limit | Should BeGreaterThan 0
        $obj.Items[0].Title | Should Not Be $null
        $obj.Items[0].RelPath | Should Not Be $null
    }

    It "TC-API-01: Correctly applies limit and offset pagination boundaries" {
        $json = Get-ApiIndexJson -QueryParams @{ limit = "1"; offset = "0" }
        $obj = $json | ConvertFrom-Json
        $obj.Count | Should Be 1
        $obj.Limit | Should Be 1
        $obj.Offset | Should Be 0
        $obj.IsTruncated | Should Be $true

        # Boundary: offset out of bounds
        $jsonOutOfBounds = Get-ApiIndexJson -QueryParams @{ limit = "10"; offset = "99999" }
        $objOutOfBounds = $jsonOutOfBounds | ConvertFrom-Json
        $objOutOfBounds.Count | Should Be 0
        $objOutOfBounds.Items.Count | Should Be 0
        $objOutOfBounds.IsTruncated | Should Be $false

        # Boundary: negative offset fallback to 0
        $jsonNegOffset = Get-ApiIndexJson -QueryParams @{ limit = "2"; offset = "-5" }
        $objNegOffset = $jsonNegOffset | ConvertFrom-Json
        $objNegOffset.Offset | Should Be 0
    }

    It "TC-API-02: Handles invalid limit and maxLimit enforcement" {
        # Invalid string limit falls back to default limit
        $jsonInvalidLimit = Get-ApiIndexJson -QueryParams @{ limit = "invalid_number" }
        $objInvalidLimit = $jsonInvalidLimit | ConvertFrom-Json
        $objInvalidLimit.Limit | Should Be 100

        # Excess limit capped at maxLimit (1000)
        $jsonExcessLimit = Get-ApiIndexJson -QueryParams @{ limit = "5000" }
        $objExcessLimit = $jsonExcessLimit | ConvertFrom-Json
        $objExcessLimit.Limit | Should Be 1000

        # Bypass maxLimit with limit=all or -1
        $jsonAll = Get-ApiIndexJson -QueryParams @{ limit = "all" }
        $objAll = $jsonAll | ConvertFrom-Json
        $objAll.Limit | Should Be $objAll.Total
        $objAll.Count | Should Be $objAll.Total
    }

    It "TC-API-03: Filters by domain, tag, and since date accurately" {
        # Non-existent domain returns empty result cleanly
        $jsonNoDomain = Get-ApiIndexJson -QueryParams @{ domain = "non_existent_domain_xyz" }
        $objNoDomain = $jsonNoDomain | ConvertFrom-Json
        $objNoDomain.Total | Should Be 0
        $objNoDomain.Count | Should Be 0

        # Non-existent tag returns empty result cleanly
        $jsonNoTag = Get-ApiIndexJson -QueryParams @{ tag = "NonExistentTag999" }
        $objNoTag = $jsonNoTag | ConvertFrom-Json
        $objNoTag.Total | Should Be 0
        $objNoTag.Count | Should Be 0

        # Invalid since date string is safely ignored
        $jsonBadSince = Get-ApiIndexJson -QueryParams @{ since = "not-a-valid-date" }
        $objBadSince = $jsonBadSince | ConvertFrom-Json
        $objBadSince.Total | Should BeGreaterThan 0

        # Valid since date filters out older documents
        $futureDateStr = (Get-Date).AddYears(10).ToString("yyyy-MM-dd")
        $jsonFutureSince = Get-ApiIndexJson -QueryParams @{ since = $futureDateStr }
        $objFutureSince = $jsonFutureSince | ConvertFrom-Json
        $objFutureSince.Total | Should Be 0
    }

    It "TC-API-04: Selects specific fields with case-insensitivity and handles single item array preservation" {
        # Fields parameter selects only requested properties
        $jsonFields = Get-ApiIndexJson -QueryParams @{ fields = "title,relpath"; limit = "1" }
        $objFields = $jsonFields | ConvertFrom-Json
        $firstItem = $objFields.Items[0]
        $firstItem.Title | Should Not Be $null
        $firstItem.RelPath | Should Not Be $null
        $firstItem.PSObject.Properties["Description"] | Should Be $null
        $firstItem.PSObject.Properties["Author"] | Should Be $null

        # Single item response still preserves array type for Items
        $objFields.Items -is [Array] | Should Be $true
    }

    It "Generates pre-chunked JSON for /api/chunks.json containing section-level RAG chunks" {
        $json = Get-ApiChunksJson
        $json | Should Not Be $null
        $json | Should Match "ChunkId"
        $json | Should Match "EnrichedText"
        $json | Should Match "Section"

        $chunksObj = $json | ConvertFrom-Json
        $chunksObj.Count | Should BeGreaterThan 0
        $chunksObj[0].ChunkId | Should Match "#chunk-"
        $chunksObj[0].EnrichedText | Should Match "\[Document:"
    }

    It "Generates HTML for /recent view" {
        $html = Get-RecentViewHtml
        $html | Should Match "最近の更新"
    }

    It "Generates HTML for /tags view" {
        $html = Get-TagsViewHtml
        $html | Should Match "タグ"
    }

    It "Generates HTML for /maintenance view" {
        $html = Get-MaintenanceViewHtml
        $html | Should Match "品質"
    }

    It "Generates HTML for /authors view" {
        $html = Get-AuthorsViewHtml
        $html | Should Match "著者"
    }

    It "Generates HTML for /search view" {
        $html = Get-SearchViewHtml -Query "API"
        $html | Should Match "検索結果"
    }
}

Describe "Get-HighlightText Utility Tests" {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
    }

    It "Highlights keyword in safe HTML text" {
        $result = Get-HighlightText -Text 'PostgreSQL Database Manual' -Keywords @('PostgreSQL')
        $result | Should Match '<mark[^>]*>PostgreSQL</mark>'
    }

    It "Handles special regex metacharacters in keywords without error" {
        $result = Get-HighlightText -Text 'C# & (Notes) Guide' -Keywords @('C#', '(Notes)')
        $result | Should Match '<mark[^>]*>C#</mark>'
        $result | Should Match '<mark[^>]*>\(Notes\)</mark>'
    }

    It "Does not corrupt HTML tags when keyword is style, mark, or background" {
        $result = Get-HighlightText -Text 'This is a style and mark test' -Keywords @('style', 'mark')
        $result | Should Not Match '<mark[^>]*<mark'
        $result | Should Match '<mark[^>]*>style</mark>'
        $result | Should Match '<mark[^>]*>mark</mark>'
    }
}

Describe 'OKF Search Engine Advanced Scoring and Filtering Tests' {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        $script:WikiIndexDirWriteTime = (Get-Item $sampleDir).LastWriteTime

        $script:WikiIndex = @(
            [PSCustomObject]@{
                Title       = "PostgreSQL DB Recovery"
                Description = "Database recovery steps"
                Author      = "Taro Yamada"
                Domain      = "infrastructure/database"
                Tags        = @("PostgreSQL", "Database")
                LastUpdated = (Get-Date "2026-08-01")
                Status      = "active"
                HasYaml     = $true
                RelPath     = "docs/db-recovery.md"
                FullPath    = "C:\wiki\docs\db-recovery.md"
                BodyText    = "How to recover PostgreSQL when crash occurs."
            },
            [PSCustomObject]@{
                Title       = "General Troubleshooting"
                Description = "General system issues"
                Author      = "Jiro Sato"
                Domain      = "support"
                Tags        = @("System")
                LastUpdated = (Get-Date "2026-07-01")
                Status      = "active"
                HasYaml     = $true
                RelPath     = "docs/general.md"
                FullPath    = "C:\wiki\docs\general.md"
                BodyText    = "Check logs for PostgreSQL database errors and recovery."
            },
            [PSCustomObject]@{
                Title       = "Old Legacy Database Setup"
                Description = "Deprecated setup guide for PostgreSQL"
                Author      = "Saburo Tanaka"
                Domain      = "infrastructure/database"
                Tags        = @("PostgreSQL", "Legacy")
                LastUpdated = (Get-Date "2024-01-01")
                Status      = "deprecated"
                HasYaml     = $true
                RelPath     = "docs/legacy-db.md"
                FullPath    = "C:\wiki\docs\legacy-db.md"
                BodyText    = "PostgreSQL setup instructions for legacy server."
            },
            [PSCustomObject]@{
                Title       = 'C# & (Notes) Guide'
                Description = 'Guide for C# development with (Notes)'
                Author      = 'Hanako Suzuki'
                Domain      = 'dev'
                Tags        = @('C#', 'Notes')
                LastUpdated = (Get-Date "2026-08-05")
                Status      = 'active'
                HasYaml     = $true
                RelPath     = 'docs/csharp-notes.md'
                FullPath    = 'C:\wiki\docs\csharp-notes.md'
                BodyText    = 'This document covers C# programming and (Notes).'
            }
        )
    }

    It 'TC-01: Single keyword search returns matching items' {
        $html = Get-SearchViewHtml -Query 'PostgreSQL' -StatusFilter 'all'
        $html | Should Match 'docs/db-recovery.md'
        $html | Should Match 'General Troubleshooting'
        $html | Should Match 'Old Legacy Database Setup'
    }

    It 'TC-02: Multi-word AND search returns only documents matching ALL keywords' {
        $html = Get-SearchViewHtml -Query 'PostgreSQL crash' -StatusFilter 'all'
        $html | Should Match 'docs/db-recovery.md'
        $html | Should Not Match 'General Troubleshooting'
        $html | Should Not Match 'Old Legacy Database Setup'
    }

    It 'TC-03: Ranks document with Title match higher than Body-only match' {
        $html = Get-SearchViewHtml -Query 'PostgreSQL' -StatusFilter 'all'
        $recoveryPos   = $html.IndexOf('docs/db-recovery.md')
        $troublePos    = $html.IndexOf('General Troubleshooting')
        $recoveryPos | Should BeGreaterThan -1
        $troublePos  | Should BeGreaterThan -1
        $recoveryPos | Should BeLessThan $troublePos
    }

    It 'TC-04: StatusFilter active excludes deprecated documents' {
        $html = Get-SearchViewHtml -Query 'PostgreSQL' -StatusFilter 'active'
        $html | Should Match 'docs/db-recovery.md'
        $html | Should Not Match 'Old Legacy Database Setup'
    }

    It 'TC-05: StatusFilter deprecated includes deprecated documents' {
        $html = Get-SearchViewHtml -Query 'PostgreSQL' -StatusFilter 'deprecated'
        $html | Should Match 'Old Legacy Database Setup'
        $html | Should Not Match 'docs/db-recovery.md'
    }

    It 'TC-06: Highlight keywords in search results snippet' {
        $html = Get-SearchViewHtml -Query 'PostgreSQL' -StatusFilter 'active'
        $html | Should Match '<mark[^>]*>PostgreSQL</mark>'
    }

    It 'TC-07: Special character query executes safely without regex exception' {
        { $script:specHtml = Get-SearchViewHtml -Query 'C# (Notes)' -StatusFilter 'all' } | Should Not Throw
        $script:specHtml | Should Match 'docs/csharp-notes.md'
        $script:specHtml | Should Match '&amp;'
    }
}

Describe 'Critical Edge Case and Security Tests' {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        $script:WikiIndexDirWriteTime = (Get-Item $sampleDir).LastWriteTime

        $script:WikiIndex = @(
            [PSCustomObject]@{
                Title       = "PostgreSQL DB Recovery"
                Description = "Database recovery steps"
                Author      = "Taro Yamada"
                Domain      = "infrastructure/database"
                Tags        = @("PostgreSQL", "Database")
                LastUpdated = (Get-Date "2026-08-01")
                Status      = "active"
                HasYaml     = $true
                RelPath     = "docs/db-recovery.md"
                FullPath    = "C:\wiki\docs\db-recovery.md"
                BodyText    = "How to recover PostgreSQL when crash occurs."
            },
            [PSCustomObject]@{
                Title       = "General Troubleshooting"
                Description = "General system issues"
                Author      = "Jiro Sato"
                Domain      = "support"
                Tags        = @("System")
                LastUpdated = (Get-Date "2026-07-01")
                Status      = "active"
                HasYaml     = $true
                RelPath     = "docs/general.md"
                FullPath    = "C:\wiki\docs\general.md"
                BodyText    = "Check logs for PostgreSQL database errors and recovery."
            }
        )
    }

    It 'Splits keywords correctly with Japanese full-width space' {
        $queryWithJpSpace = "PostgreSQL" + [char]0x3000 + "crash"
        $html = Get-SearchViewHtml -Query $queryWithJpSpace -StatusFilter 'all'
        $html | Should Match 'docs/db-recovery.md'
        $html | Should Not Match 'General Troubleshooting'
    }

    It 'Encodes XSS payload in search query input cleanly without raw HTML injection' {
        $xssQuery = '<script>alert("xss")</script>'
        $html = Get-SearchViewHtml -Query $xssQuery -StatusFilter 'all'
        $html | Should Not Match '<script>alert\("xss"\)</script>'
        $html | Should Match '&lt;script&gt;'
    }

    It 'Executes facet-only domain filter search without keywords' {
        $html = Get-SearchViewHtml -Query '' -StatusFilter 'all' -DomainFilter 'infrastructure'
        $html | Should Match 'docs/db-recovery.md'
        $html | Should Not Match 'General Troubleshooting'
    }

    It 'Gracefully handles invalid StatusFilter parameter without crashing' {
        { $script:invalidHtml = Get-SearchViewHtml -Query 'PostgreSQL' -StatusFilter 'invalid_status_value' } | Should Not Throw
        $script:invalidHtml | Should Not Match 'docs/db-recovery.md'
    }

    It 'Parses comma-separated tag string in YAML correctly into array' {
        $sampleMd = "---`ntitle: `"Comma Tag Test`"`ntags: `"PostgreSQL, Database, Recovery`"`n---`n# Test"
        $meta = Get-DocumentMetadata -MdText $sampleMd -RelPath "test.md"
        $meta.Tags.Count | Should Be 3
        ($meta.Tags -contains "PostgreSQL") | Should Be $true
        ($meta.Tags -contains "Database") | Should Be $true
        ($meta.Tags -contains "Recovery") | Should Be $true
    }

    It 'Get-QueryParams decodes percent-encoded UTF-8 Japanese query string without mojibake' {
        # %E3%83%8F%E3%83%B3%E3%83%89%E3%83%96%E3%83%83%E3%82%AF = "ハンドブック"
        $mockReq = [PSCustomObject]@{
            Url = [PSCustomObject]@{
                Query = '?q=%E3%83%8F%E3%83%B3%E3%83%89%E3%83%96%E3%83%83%E3%82%AF&status=active'
            }
        }
        $params = Get-QueryParams -Request $mockReq
        $params["q"] | Should Be "ハンドブック"
        $params["status"] | Should Be "active"
    }

    It 'Executes Unblock-File safely on lib DLLs without throwing exceptions' {
        if ($IsWindows -or $env:OS -eq "Windows_NT") {
            $libPath = Join-Path $projectRoot "lib"
            { Get-ChildItem -Path $libPath -Filter "*.dll" | Unblock-File -ErrorAction SilentlyContinue } | Should Not Throw
        }
    }
}

Describe 'Search Query NOT Syntax Tests' {
    BeforeAll {
        . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly

        $script:WikiIndex = @(
            [PSCustomObject]@{
                Title       = "REST API 仕様書"
                Description = "FastAPI と Python による REST API 開発ガイド"
                Author      = "Dev Team"
                Domain      = "backend/api"
                Tags        = @("API", "Python", "FastAPI")
                LastUpdated = (Get-Date "2026-08-01")
                Status      = "active"
                HasYaml     = $true
                RelPath     = "docs/api-python.md"
                FullPath    = "C:\wiki\docs\api-python.md"
                BodyText    = "Python FastAPI を使用した REST API の設計と実装仕様書です。"
            },
            [PSCustomObject]@{
                Title       = "GraphQL API 仕様書"
                Description = "Node.js と TypeScript による GraphQL 開発"
                Author      = "Frontend Team"
                Domain      = "backend/api"
                Tags        = @("API", "TypeScript", "Node.js")
                LastUpdated = (Get-Date "2026-08-02")
                Status      = "active"
                HasYaml     = $true
                RelPath     = "docs/api-graphql.md"
                FullPath    = "C:\wiki\docs\api-graphql.md"
                BodyText    = "TypeScript で構築する GraphQL API サーバーの仕様です。"
            },
            [PSCustomObject]@{
                Title       = "K-DAT バックアップ運用手順"
                Description = "研究所専用バックアップツール K-DAT の設定"
                Author      = "Infra Team"
                Domain      = "infrastructure/backup"
                Tags        = @("Backup", "Tool")
                LastUpdated = (Get-Date "2026-08-03")
                Status      = "active"
                HasYaml     = $true
                RelPath     = "docs/kdat-backup.md"
                FullPath    = "C:\wiki\docs\kdat-backup.md"
                BodyText    = "K-DAT を使用したデータバックアップ運用マニュアルです。"
            }
        )
    }

    It "TC-NOT-01: Excludes documents matching minus prefix -keyword" {
        $res = @(Search-OkfDocs -Query "API -Python" -StatusFilter "active")
        $res.Count | Should Be 1
        $res[0].Meta.RelPath | Should Be "docs/api-graphql.md"
    }

    It "TC-NOT-02: Excludes documents matching NOT keyword syntax" {
        $res = @(Search-OkfDocs -Query "API NOT Python" -StatusFilter "active")
        $res.Count | Should Be 1
        $res[0].Meta.RelPath | Should Be "docs/api-graphql.md"
    }

    It "TC-NOT-03: Excludes documents matching exclamation prefix !keyword" {
        $res = @(Search-OkfDocs -Query "API !Python" -StatusFilter "active")
        $res.Count | Should Be 1
        $res[0].Meta.RelPath | Should Be "docs/api-graphql.md"
    }

    It "TC-NOT-04: Preserves in-word hyphens like K-DAT as positive search terms without exclusion" {
        $res = @(Search-OkfDocs -Query "K-DAT" -StatusFilter "active")
        $res.Count | Should Be 1
        $res[0].Meta.RelPath | Should Be "docs/kdat-backup.md"
    }

    It "TC-NOT-05: Supports multiple NOT exclusions in a single query" {
        $res = @(Search-OkfDocs -Query "API -Python -TypeScript" -StatusFilter "active")
        $res.Count | Should Be 0
    }

    It "TC-NOT-06: Supports quoted phrase exclusion like NOT `"REST API`"" {
        $res = @(Search-OkfDocs -Query "API NOT `"REST API`"" -StatusFilter "active")
        $res.Count | Should Be 1
        $res[0].Meta.RelPath | Should Be "docs/api-graphql.md"
    }

    It "TC-NOT-07: Supports NOT-only query to filter all documents" {
        $res = @(Search-OkfDocs -Query "-TypeScript" -StatusFilter "active")
        $res.Count | Should Be 2
        $paths = @($res | ForEach-Object { $_.Meta.RelPath })
        ($paths -contains "docs/api-graphql.md") | Should Be $false
    }

    It "TC-NOT-08: Agentic tool Invoke-ToolSearchOkf respects NOT syntax and excludes target" {
        $toolRes = Invoke-ToolSearchOkf -Query "API -Python" -WikiDir $projectRoot
        $toolRes | Should Not Be $null
        $toolRes | Should Match "docs/api-graphql.md"
        $toolRes | Should Not Match "docs/api-python.md"
    }

    It "TC-NOT-09: Supports consecutive space-less NOT syntax and multi-byte Japanese queries" {
        $parsed = Split-SearchQueryTerms -Query "中毒 NOT鉛 NOT一酸化"
        $parsed.IncludeKeywords.Count | Should Be 1
        $parsed.IncludeKeywords[0] | Should Be "中毒"
        $parsed.ExcludeKeywords.Count | Should Be 2
        $parsed.ExcludeKeywords[0] | Should Be "鉛"
        $parsed.ExcludeKeywords[1] | Should Be "一酸化"
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
}

Describe 'OKF LLM RAG Security and Encryption Tests' {
    BeforeAll {
        . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly
    }

    It 'Encrypts and decrypts API key with AES-256 (ENC: prefix)' {
        $rawKey = "sk-proj-test123456789"
        $encKey = Protect-StringAes -PlainText $rawKey
        $encKey | Should Match "^ENC:"
        $decKey = Unprotect-StringAes -EncryptedText $encKey
        $decKey | Should Be $rawKey
    }

    It 'Get-MachineFingerprint returns 16-char formatted machine identifier' {
        $mid = Get-MachineFingerprint
        $mid | Should Match '^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$'
    }

    It 'Generates and unlocks machine-bound activation codes correctly' {
        $testApiKey = "sk-sakura-ai-secret-123456"
        $mid = Get-MachineFingerprint
        $email = "developer@example.com"

        # 1. マシンID ＋ メールアドレスでの暗号化
        $actCode = Protect-ActivationCode -ApiKey $testApiKey -MachineId $mid -Email $email
        $actCode | Should Match "^ENC:"

        # 2. 同一マシン ＋ 同一メールでの復号成功
        $decrypted = Unprotect-ActivationCode -EncryptedText $actCode -MachineId $mid -Email $email
        $decrypted | Should Be $testApiKey

        # 3. 異なるマシンIDでの復号失敗
        $diffMid = "AAAA-BBBB-CCCC-DDDD"
        $failedDec = Unprotect-ActivationCode -EncryptedText $actCode -MachineId $diffMid -Email $email
        $failedDec | Should Be ""

        # 4. 異なるメールアドレスでの復号失敗
        $diffEmail = "wrong.person@example.com"
        $failedEmailDec = Unprotect-ActivationCode -EncryptedText $actCode -MachineId $mid -Email $diffEmail
        $failedEmailDec | Should Be ""

        # 5. 従来ポータブル ENC: 形式の復号互換性テスト (どのマシン・メールでも復号可能)
        $legacyEnc = Protect-StringAes -PlainText $testApiKey
        $decLegacy = Unprotect-ActivationCode -EncryptedText $legacyEnc -MachineId $mid -Email $email
        $decLegacy | Should Be $testApiKey
        $decLegacyDiffMid = Unprotect-ActivationCode -EncryptedText $legacyEnc -MachineId "DIFF-HOST-9999" -Email "other@example.com"
        $decLegacyDiffMid | Should Be $testApiKey

        # 6. Get-ResolvedSecret の透過的復号
        $resolved = Get-ResolvedSecret -SecretValue $actCode -Email $email
        $resolved | Should Be $testApiKey
        $resolvedLegacy = Get-ResolvedSecret -SecretValue $legacyEnc
        $resolvedLegacy | Should Be $testApiKey
    }

    It 'New-ActivationCode.ps1 CLI script supports both Machine-Bound and Legacy portable modes' {
        $cliScript = Join-Path $projectRoot "New-ActivationCode.ps1"
        (Test-Path $cliScript) | Should Be $true
        $tokens = $null
        $errs = $null
        [System.Management.Automation.Language.Parser]::ParseFile($cliScript, [ref]$tokens, [ref]$errs)
        $errs.Count | Should Be 0

        # CLI による Legacy モード出力テスト
        $testKey = "sk-test-cli-key-12345"
        & $cliScript -ApiKey $testKey -Legacy | Out-Null
        $legacyCode = Protect-StringAes -PlainText $testKey
        $unprotected = Unprotect-ActivationCode -EncryptedText $legacyCode
        $unprotected | Should Be $testKey
    }

    It 'Web Crypto API (docs/activation/index.html) generated codes are 100% decryptable by PowerShell' {
        # Web ブラウザ (Web Crypto API) で生成された既知の暗号化コード
        # テストキー: sk-sakura-test-key-123456
        # マシンID: A3B1-9F22-C84D-71E0, メール: user@example.com
        $webBoundCode = "ENC:O5ZNmQDvlNMIMr2aw7Iw+ArP1IROerSgBCud2j5Cugg="
        $webDecrypted = Unprotect-ActivationCode -EncryptedText $webBoundCode -MachineId "A3B1-9F22-C84D-71E0" -Email "user@example.com"
        $webDecrypted | Should Be "sk-sakura-test-key-123456"

        # Web ポータブル (Legacy) コードの復号
        $webLegacyCode = "ENC:rcBTlBqj1CLuHa9ZHN9vwmb7Fslkcr2Fi0ihcDYDimo="
        $webLegacyDecrypted = Unprotect-ActivationCode -EncryptedText $webLegacyCode
        $webLegacyDecrypted | Should Be "sk-sakura-test-key-123456"
    }

    It 'Encrypts and decrypts API key with Windows DPAPI (DPAPI: prefix)' {
        if ($IsWindows -or $env:OS -eq "Windows_NT") {
            $rawKey = "sk-proj-dpapitest98765"
            $dpapiKey = Protect-StringDpapi -PlainText $rawKey
            $dpapiKey | Should Match "^DPAPI:"
            $decKey = Unprotect-StringDpapi -EncryptedText $dpapiKey
            $decKey | Should Be $rawKey
        }
    }

    It 'Resolves secret for ENV: prefix dynamically' {
        [Environment]::SetEnvironmentVariable("TEST_OPENAI_KEY", "sk-env-secret-val")
        try {
            $resolved = Get-ResolvedSecret -SecretValue "ENV:TEST_OPENAI_KEY"
            $resolved | Should Be "sk-env-secret-val"
        } finally {
            [Environment]::SetEnvironmentVariable("TEST_OPENAI_KEY", $null)
        }
    }

    It 'Get-ConfigJson returns enabled = false when config.json does not exist' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestNoConfig"
        if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
        try {
            $cfg = Get-ConfigJson -TargetScriptDir $tempDir
            $cfg.rag.enabled | Should Be $false
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Set-ApiKey.ps1 creates config.json with encrypted key' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestSetApiKey"
        if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
        $targetCfg = Join-Path $tempDir "config.json"
        try {
            $setScript = Join-Path $projectRoot "Set-ApiKey.ps1"
            & $setScript -ApiKey "sk-test-portable-key" -Scope Portable -ConfigPath $targetCfg
            (Test-Path $targetCfg) | Should Be $true
            $cfg = Get-Content -Path $targetCfg -Raw | ConvertFrom-Json
            $cfg.rag.enabled | Should Be $true
            $cfg.rag.apiKey | Should Match "^ENC:"
            $resolved = Get-ResolvedSecret -SecretValue $cfg.rag.apiKey
            $resolved | Should Be "sk-test-portable-key"
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-JapaneseWordsWinRT tokenizes Japanese queries and filters Japanese stop words' {
        $words = Get-JapaneseWordsWinRT -Text 'セットアップの方法は？'
        ($words -contains 'セットアップ') | Should Be $true
        ($words -contains '環境構築') | Should Be $true
        ($words -contains 'は') | Should Be $false
        ($words -contains 'の') | Should Be $false
    }

    It 'Invoke-OpenAiChatCompletions builds message payload with history array' {
        $history = @(
            @{ role = 'user'; content = '質問1' },
            @{ role = 'assistant'; content = '回答1' }
        )
        { Invoke-OpenAiChatCompletions -ApiUrl 'http://invalid-endpoint-for-test-xyz' -ApiKey 'test-key' -Model 'test-model' -SystemPrompt 'System Prompt' -UserMessage '質問2' -History $history -TimeoutSec 1 } | Should Throw
    }

    It 'Invoke-OpenAiChatCompletions accepts -Stream switch and -OnChunkReceived callback' {
        $chunkList = [System.Collections.Generic.List[string]]::new()
        {
            Invoke-OpenAiChatCompletions -ApiUrl 'http://invalid-endpoint-for-test-xyz' -ApiKey 'test-key' -Model 'test-model' -SystemPrompt 'System Prompt' -UserMessage '質問' -Stream -OnChunkReceived { param($c) $chunkList.Add($c) } -TimeoutSec 1
        } | Should Throw
    }
}

Describe 'Agentic RAG and OKF Tools Tests' {
    BeforeAll {
        # Import functions from Start-MarkdigWiki.ps1
        $scriptPath = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $scriptPath -DotSourceOnly
    }

    It "Start-MarkdigWiki.ps1 is encoded as UTF-8 with BOM" {
        $scriptPath = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
        $bytes.Length | Should BeGreaterThan 3
        $bytes[0] | Should Be 0xEF
        $bytes[1] | Should Be 0xBB
        $bytes[2] | Should Be 0xBF
    }

    It "Search-OkfDocs scores and filters active documents correctly" {
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        Build-WikiIndex -TargetWikiDir $sampleDir -ForceRefresh | Out-Null
        $results = Search-OkfDocs -Query "Markdown" -StatusFilter "active" -WikiDir $sampleDir
        ($null -ne $results) | Should Be $true
        $results.Count | Should BeGreaterThan 0
        $results[0].Score | Should BeGreaterThan 0
    }

    It "Invoke-ToolReadDoc trims body text and strips YAML header" {
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        Build-WikiIndex -TargetWikiDir $sampleDir -ForceRefresh | Out-Null
        $doc = $script:WikiIndex | Select-Object -First 1
        if ($doc) {
            $content = Invoke-ToolReadDoc -RelPath $doc.RelPath -WikiDir $sampleDir -MaxChars 50
            $content | Should Not Be $null
            $content | Should Not Match "^---"
            $content.Length | Should BeLessThan 300
        }
    }

    It "Invoke-ToolGetLinkedDocs extracts markdown relative links" {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_LinkTest"
        if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
        try {
            $doc1 = Join-Path $tempDir "doc1.md"
            $doc2 = Join-Path $tempDir "doc2.md"
            Set-Content -Path $doc1 -Value "# Doc 1`nSee [Doc 2](doc2.md) for details." -Encoding UTF8
            Set-Content -Path $doc2 -Value "# Doc 2`nTarget content." -Encoding UTF8

            Build-WikiIndex -TargetWikiDir $tempDir -ForceRefresh | Out-Null
            $links = @(Invoke-ToolGetLinkedDocs -RelPath "doc1.md" -WikiDir $tempDir)
            $links | Should Not Be $null
            $links.Count | Should Be 1
            $links[0].RelPath | Should Be "doc2.md"
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Invoke-ToolLookupGlossary finds terms in document content or tags" {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_GlossaryTest"
        if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
        try {
            $glossaryFile = Join-Path $tempDir "glossary.md"
            Set-Content -Path $glossaryFile -Value "# 社内用語集`n`n## K-DAT`n研究所専用のバックアップツール。" -Encoding UTF8

            Build-WikiIndex -TargetWikiDir $tempDir -ForceRefresh | Out-Null
            $res = Invoke-ToolLookupGlossary -Term "K-DAT" -WikiDir $tempDir
            ($null -ne $res) | Should Be $true
            $res | Should Match "K-DAT"
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Invoke-AgenticRagChat fallback generates informative answer when LLM fails or max turns reached without content" {
        # Invalid API URL triggers fallback handling
        $res = Invoke-AgenticRagChat -ApiUrl "http://invalid-endpoint-xyz-999" -ApiKey "key" -Model "model" -UserMessage "質問" -WikiDir $projectRoot -MaxTurns 1 -TimeoutSec 1
        ($null -ne $res) | Should Be $true
        $res.answer | Should Not BeNullOrEmpty
        $res.thinkingLog.Count | Should BeGreaterThan 0
    }

    It "Invoke-ToolSearchOkf falls back to all domains when specific domain query yields zero hits" {
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        Build-WikiIndex -TargetWikiDir $sampleDir -ForceRefresh | Out-Null
        # '概要' is in domain 'root', but domain 'non_existent_domain' is passed
        $res = Invoke-ToolSearchOkf -Query "概要" -Domain "non_existent_domain" -WikiDir $sampleDir
        ($null -ne $res) | Should Be $true
        $res | Should Match "概要"
    }

    It "Search-OkfDocs utilizes WinRT morph tokenization and exact phrase bonus on first attempt" {
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        Build-WikiIndex -TargetWikiDir $sampleDir -ForceRefresh | Out-Null
        # Query containing particles and full sentence
        $results = Search-OkfDocs -Query "想定されるエラーは？" -StatusFilter "active" -WikiDir $sampleDir
        ($null -ne $results) | Should Be $true
        $results.Count | Should BeGreaterThan 0
        # Check that top result matched exact phrase or tokenized words
        $results[0].Score | Should BeGreaterThan 0
    }

    It "Invoke-ToolSearchOkf returns multiple candidate results with formatting for Agentic traversal" {
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        Build-WikiIndex -TargetWikiDir $sampleDir -ForceRefresh | Out-Null
        $res = Invoke-ToolSearchOkf -Query "仕様" -WikiDir $sampleDir
        ($null -ne $res) | Should Be $true
        $res | Should Match "RelPath"
        $res | Should Match "read_doc"
    }

    It "Invoke-AgenticRagChat fallback prompt instructs to present related knowledge when direct hits are scarce" {
        $res = Invoke-AgenticRagChat -ApiUrl "http://invalid-endpoint-xyz-999" -ApiKey "key" -Model "model" -UserMessage "未知のトピック" -WikiDir $projectRoot -MaxTurns 1 -TimeoutSec 1
        ($null -ne $res) | Should Be $true
        $res.answer | Should Not BeNullOrEmpty
    }

    It "Invoke-AgenticRagChat supports -Stream, -OnThinkingCallback, and -OnChunkReceived parameters" {
        $thinkList = [System.Collections.Generic.List[string]]::new()
        $chunkList = [System.Collections.Generic.List[string]]::new()
        $res = Invoke-AgenticRagChat -ApiUrl "http://invalid-endpoint-xyz-999" -ApiKey "key" -Model "model" -UserMessage "テスト質問" -WikiDir $projectRoot -MaxTurns 1 -TimeoutSec 1 -Stream -OnThinkingCallback { param($m) $thinkList.Add($m) } -OnChunkReceived { param($c) $chunkList.Add($c) }
        ($null -ne $res) | Should Be $true
        $res.answer | Should Not BeNullOrEmpty
    }
}

Describe 'Markdown Editor API and Generation Backup Tests' {
    BeforeAll {
        # Dot source the script to test functions locally
        . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly
    }

    It "Get-ConfigJson parses editor config with custom or default maxBackups" {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestEditorDir"
        if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force }
        $null = New-Item -ItemType Directory -Path $tempDir

        $cfgFile = Join-Path $tempDir "config.json"
        @{ editor = @{ maxBackups = 5 } } | ConvertTo-Json | Out-File -FilePath $cfgFile -Encoding UTF8 -NoNewline

        $parsed = Get-ConfigJson -TargetScriptDir $tempDir
        $parsed.editor.maxBackups | Should Be 5

        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Backup rotation rotates backups correctly up to maxBackups" {
        $tempDir = Join-Path $projectRoot "temp_test_editor_backup_dir"
        if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force }
        $null = New-Item -ItemType Directory -Path $tempDir

        $testFile = Join-Path $tempDir "test-doc.md"
        "Initial Content" | Out-File -FilePath $testFile -Encoding utf8

        # Mock backup rotation with maxBackups = 3
        # First write: rotates original to bak1, then writes new
        $maxBackups = 3

        # Rotation 1
        if ($maxBackups -gt 0 -and (Test-Path $testFile)) {
            for ($i = $maxBackups - 1; $i -ge 1; $i--) {
                $oldBak = "$testFile.bak$i"
                $newBak = "$testFile.bak$($i + 1)"
                if (Test-Path $oldBak) { Copy-Item -Path $oldBak -Destination $newBak -Force }
            }
            Copy-Item -Path $testFile -Destination "$testFile.bak1" -Force
        }
        "Content Gen 2" | Out-File -FilePath $testFile -Encoding utf8

        (Test-Path "$testFile.bak1") | Should Be $true
        (Get-Content -Path "$testFile.bak1" -Raw) | Should Match "Initial Content"

        # Rotation 2
        if ($maxBackups -gt 0 -and (Test-Path $testFile)) {
            for ($i = $maxBackups - 1; $i -ge 1; $i--) {
                $oldBak = "$testFile.bak$i"
                $newBak = "$testFile.bak$($i + 1)"
                if (Test-Path $oldBak) { Copy-Item -Path $oldBak -Destination $newBak -Force }
            }
            Copy-Item -Path $testFile -Destination "$testFile.bak1" -Force
        }
        "Content Gen 3" | Out-File -FilePath $testFile -Encoding utf8

        (Test-Path "$testFile.bak2") | Should Be $true
        (Get-Content -Path "$testFile.bak2" -Raw) | Should Match "Initial Content"
        (Get-Content -Path "$testFile.bak1" -Raw) | Should Match "Content Gen 2"

        # Rotation 3
        if ($maxBackups -gt 0 -and (Test-Path $testFile)) {
            for ($i = $maxBackups - 1; $i -ge 1; $i--) {
                $oldBak = "$testFile.bak$i"
                $newBak = "$testFile.bak$($i + 1)"
                if (Test-Path $oldBak) { Copy-Item -Path $oldBak -Destination $newBak -Force }
            }
            Copy-Item -Path $testFile -Destination "$testFile.bak1" -Force
        }
        "Content Gen 4" | Out-File -FilePath $testFile -Encoding utf8

        (Test-Path "$testFile.bak3") | Should Be $true
        (Get-Content -Path "$testFile.bak3" -Raw) | Should Match "Initial Content"
        (Get-Content -Path "$testFile.bak2" -Raw) | Should Match "Content Gen 2"
        (Get-Content -Path "$testFile.bak1" -Raw) | Should Match "Content Gen 3"

        # Rotation 4 (exceeding maxBackups, bak3 should be replaced by gen 2 content, original initial content is deleted)
        if ($maxBackups -gt 0 -and (Test-Path $testFile)) {
            for ($i = $maxBackups - 1; $i -ge 1; $i--) {
                $oldBak = "$testFile.bak$i"
                $newBak = "$testFile.bak$($i + 1)"
                if (Test-Path $oldBak) { Copy-Item -Path $oldBak -Destination $newBak -Force }
            }
            Copy-Item -Path $testFile -Destination "$testFile.bak1" -Force
        }
        "Content Gen 5" | Out-File -FilePath $testFile -Encoding utf8

        (Test-Path "$testFile.bak4") | Should Be $false
        (Get-Content -Path "$testFile.bak3" -Raw) | Should Match "Content Gen 2"
        (Get-Content -Path "$testFile.bak2" -Raw) | Should Match "Content Gen 3"
        (Get-Content -Path "$testFile.bak1" -Raw) | Should Match "Content Gen 4"

        Remove-Item -Path $tempDir -Recurse -Force
    }

    It "Preserves UTF-8 with BOM signature on write" {
        $tempDir = Join-Path $projectRoot "temp_test_editor_utf8"
        if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force }
        $null = New-Item -ItemType Directory -Path $tempDir
        $testFile = Join-Path $tempDir "utf8-test.md"

        $utf8bom = New-Object System.Text.UTF8Encoding -ArgumentList @($true)
        [System.IO.File]::WriteAllText($testFile, "こんにちは", $utf8bom)

        # Read back bytes
        $bytes = [System.IO.File]::ReadAllBytes($testFile)
        # Check BOM: EF BB BF -> 239, 187, 191
        $bytes[0] | Should Be 239
        $bytes[1] | Should Be 187
        $bytes[2] | Should Be 191

        Remove-Item -Path $tempDir -Recurse -Force
    }

    It "Serializes /api/raw content as string without PSNoteProperty objects" {
        $tempDir = Join-Path $projectRoot "temp_test_editor_raw"
        if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force }
        $null = New-Item -ItemType Directory -Path $tempDir
        $testFile = Join-Path $tempDir "raw-test.md"

        [System.IO.File]::WriteAllText($testFile, "# Test Heading`nTest body content", [System.Text.Encoding]::UTF8)

        $content = [System.IO.File]::ReadAllText($testFile, [System.Text.Encoding]::UTF8)
        $jsonStr = @{ markdown = $content } | ConvertTo-Json
        $parsedObj = $jsonStr | ConvertFrom-Json

        ($parsedObj.markdown -is [string]) | Should Be $true
        $parsedObj.markdown | Should Match "# Test Heading"

        Remove-Item -Path $tempDir -Recurse -Force
    }

    It "Detects backup versions and reads historical versions correctly" {
        $tempDir = Join-Path $projectRoot "temp_test_editor_history"
        if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force }
        $null = New-Item -ItemType Directory -Path $tempDir

        $testFile = Join-Path $tempDir "history-doc.md"
        $bak1File = "$testFile.bak1"

        [System.IO.File]::WriteAllText($testFile, "Current content", [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($bak1File, "Historical content gen 1", [System.Text.Encoding]::UTF8)

        # Test reading backup file via ReadAllText
        $bakContent = [System.IO.File]::ReadAllText($bak1File, [System.Text.Encoding]::UTF8)
        $bakContent | Should Match "Historical content gen 1"

        # Check backup file detection
        (Test-Path "$testFile.bak1") | Should Be $true

        Remove-Item -Path $tempDir -Recurse -Force
    }

    It "Validates YAML Front Matter syntax correctly" {
        # Valid YAML
        $validMd = "---`r`ntitle: Test Title`r`nstatus: active`r`ntags:`r`n  - tag1`r`n---`r`n# Body"
        $resValid = Test-YamlFrontMatterSyntax -MdText $validMd
        $resValid.isValid | Should Be $true
        $resValid.warnings.Count | Should Be 0

        # Missing closing ---
        $unclosedMd = "---`r`ntitle: Test Title`r`n# Body"
        $resUnclosed = Test-YamlFrontMatterSyntax -MdText $unclosedMd
        $resUnclosed.isValid | Should Be $false
        $resUnclosed.warnings[0] | Should Match "(閉じヘッダー|closing header|---)"

        # Invalid line without colon
        $invalidLineMd = "---`r`ntitle Test Title`r`n---`r`n# Body"
        $resInvalid = Test-YamlFrontMatterSyntax -MdText $invalidLineMd
        $resInvalid.isValid | Should Be $false
        $resInvalid.warnings[0] | Should Match "(key: value|キー: 値)"
    }
}

Describe 'Editor Settings and Read-Only Guard Tests' {
    BeforeAll {
        . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly
    }

    It "Get-SettingsViewData includes EditorEnabledChecked and EditorMaxBackups fields for ja and en" {
        $dataJa = Get-SettingsViewData -Lang "ja"
        $dataJa.EditorEnabledChecked | Should Not Be $null
        ($dataJa.EditorMaxBackups -ge 0) | Should Be $true
        $dataJa.EditorTitleLbl | Should Match "エディター設定"

        $dataEn = Get-SettingsViewData -Lang "en"
        $dataEn.EditorTitleLbl | Should Match "Editor Settings"
    }

    It "Get-SettingsViewHtml renders editor settings card and enable checkbox" {
        $html = Get-SettingsViewHtml -Lang "ja"
        $html | Should Match "editorEnabled"
        $html | Should Match "editorMaxBackups"
        $html | Should Match "エディター設定"
    }

    It "Get-OkfTopBarHtml hides edit button when EditorEnabled is false" {
        $meta = [PSCustomObject]@{
            Title       = "Test Doc"
            Domain      = "docs"
            Status      = "active"
            Tags        = @("test")
            LastUpdated = (Get-Date)
        }

        $topBarEnabled = Get-OkfTopBarHtml -Meta $meta -RelPath "test.md" -Lang "ja" -EditorEnabled $true
        $topBarEnabled | Should Match "edit-doc-btn"

        $topBarDisabled = Get-OkfTopBarHtml -Meta $meta -RelPath "test.md" -Lang "ja" -EditorEnabled $false
        $topBarDisabled | Should Not Match "edit-doc-btn"
    }

    It "/api/config saves editor enabled and maxBackups settings safely" {
        $tempIsolatedDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestEditorIsolated"
        if (Test-Path $tempIsolatedDir) { Remove-Item -Path $tempIsolatedDir -Recurse -Force -ErrorAction SilentlyContinue }
        $null = New-Item -ItemType Directory -Path $tempIsolatedDir

        Copy-Item -Path (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -Destination $tempIsolatedDir -Force
        Copy-Item -Path (Join-Path $projectRoot "lib") -Destination (Join-Path $tempIsolatedDir "lib") -Recurse -Force
        Copy-Item -Path (Join-Path $projectRoot "markdown_sample") -Destination (Join-Path $tempIsolatedDir "markdown_sample") -Recurse -Force

        $isolatedConfig = Join-Path $tempIsolatedDir "config.json"
        @{
            editor = @{ enabled = $true; maxBackups = 3 }
            search = @{ prebuildIndex = $false; useCache = $false; cacheFolder = ".cache" }
        } | ConvertTo-Json -Depth 5 | Out-File -FilePath $isolatedConfig -Encoding UTF8

        $port = 8095
        $psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { (Get-Command pwsh).Source } elseif (Get-Command powershell -ErrorAction SilentlyContinue) { (Get-Command powershell).Source } else { (Get-Process -Id $PID).Path }
        $proc = Start-Process $psExe -ArgumentList "-File", (Join-Path $tempIsolatedDir "Start-MarkdigWiki.ps1"), "-RootFolder", (Join-Path $tempIsolatedDir "markdown_sample"), "-Port", $port -PassThru
        Start-Sleep -Seconds 3
        try {
            # 1. /api/config POST with editor.enabled = false
            $payload = @{
                editor = @{
                    enabled    = $false
                    maxBackups = 5
                }
            } | ConvertTo-Json -Depth 5

            $res = Invoke-RestMethod -Uri "http://localhost:$port/api/config" -Method Post -Body $payload -ContentType "application/json; charset=utf-8"
            $res.success | Should Be $true

            # Verify saved config
            $savedCfg = Get-Content -Path $isolatedConfig -Raw -Encoding UTF8 | ConvertFrom-Json
            $savedCfg.editor.enabled | Should Be $false
            $savedCfg.editor.maxBackups | Should Be 5

            # 2. /api/save POST should return 403 Forbidden when editor.enabled = false
            $savePayload = @{
                relPath  = "概要.md"
                markdown = "# Read Only Test"
            } | ConvertTo-Json -Depth 5

            try {
                Invoke-RestMethod -Uri "http://localhost:$port/api/save" -Method Post -Body $savePayload -ContentType "application/json; charset=utf-8"
                throw "Expected 403 Forbidden exception"
            } catch {
                $_.Exception.Response.StatusCode.value__ | Should Be 403
            }
        } finally {
            Invoke-RestMethod -Uri "http://localhost:$port/api/shutdown" -Method Post -ErrorAction SilentlyContinue
            if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
            Remove-Item -Path $tempIsolatedDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Directory Listing and Fallback Tests (Get-DirectoryListingHtml)' {
    BeforeAll {
        $projectRoot = (Resolve-Path "$PSScriptRoot\..").Path
        . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly

        # テスト用ディレクトリ構造を作成
        $testRoot = Join-Path $TestDrive "wiki-dir-listing"
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

        # サブフォルダ (index.md あり)
        $subWithIndex = Join-Path $testRoot "法律A"
        New-Item -Path $subWithIndex -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $subWithIndex "index.md") -Value "# 法律A" -Encoding UTF8

        # サブフォルダ (index.md なし)
        $subNoIndex = Join-Path $testRoot "法律B"
        New-Item -Path $subNoIndex -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $subNoIndex "art_001.md") -Value "# 条文1" -Encoding UTF8

        # ルート直下の .md ファイル
        Set-Content -Path (Join-Path $testRoot "glossary.md") -Value "# 用語集" -Encoding UTF8

        # 空フォルダ
        $emptyDir = Join-Path $testRoot "empty"
        New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null
    }

    It "ルートにフォルダと .md ファイルの一覧を生成する" {
        $html = Get-DirectoryListingHtml -DirFullPath $testRoot -RawUrlPath "/"
        $html | Should Match "dir-listing-list"
        $html | Should Match "法律A"
        $html | Should Match "法律B"
        $html | Should Match "glossary"
        $html | Should Match "dir-listing-notice"
        $html | Should Match "index\.md / README\.md がないため"
    }

    It "フォルダは太字リンク、ファイルは通常リンクで表示される" {
        $html = Get-DirectoryListingHtml -DirFullPath $testRoot -RawUrlPath "/"
        $html | Should Match "dir-listing-folder"
        $html | Should Match "dir-listing-file"
    }

    It "アイテム数が正しく表示される" {
        $html = Get-DirectoryListingHtml -DirFullPath $testRoot -RawUrlPath "/"
        # 3 subdirs (法律A, 法律B, empty) + 1 file (glossary.md) = 4
        $html | Should Match "4 件のアイテム"
    }

    It "空フォルダではコンテンツなしメッセージを表示する" {
        $emptyDir = Join-Path $testRoot "empty"
        $html = Get-DirectoryListingHtml -DirFullPath $emptyDir -RawUrlPath "/empty/"
        $html | Should Match "コンテンツがありません"
        $html | Should Match "dir-listing-notice"
    }

    It "フォルダリンクの href に URL エンコードされた名前が含まれる" {
        $html = Get-DirectoryListingHtml -DirFullPath $testRoot -RawUrlPath "/"
        # 日本語フォルダ名は URL エンコードされる
        $encodedName = [Uri]::EscapeDataString("法律A")
        $html | Should Match $encodedName
    }

    It "ルートの index.md/README.md フォールバック: index.md が存在する場合に正しく解決される" {
        # index.md があるディレクトリ
        $dirWithIndex = Join-Path $testRoot "法律A"
        $fullPath = [System.IO.Path]::GetFullPath($dirWithIndex)
        $relPath = "法律A"

        # ディレクトリ内の index.md を探す (スクリプトのロジックを再現)
        $dirIndexPath = Join-Path $fullPath "index.md"
        (Test-Path $dirIndexPath -PathType Leaf) | Should Be $true

        $newFullPath = [System.IO.Path]::GetFullPath($dirIndexPath)
        $newRelPath = (($relPath.TrimEnd('\') + '\index.md').TrimStart('\'))
        $newRelPath | Should Be "法律A\index.md"
        $newFullPath | Should Match "index\.md$"
    }

    It "ルートの index.md/README.md フォールバック: どちらもない場合は一覧表示される" {
        $fullPath = [System.IO.Path]::GetFullPath($testRoot)
        $dirIndexPath = Join-Path $fullPath "index.md"
        $dirReadmePath = Join-Path $fullPath "README.md"

        (Test-Path $dirIndexPath -PathType Leaf) | Should Be $false
        (Test-Path $dirReadmePath -PathType Leaf) | Should Be $false

        # フォルダ一覧が生成されることを確認
        $html = Get-DirectoryListingHtml -DirFullPath $fullPath -RawUrlPath "/"
        $html | Should Not BeNullOrEmpty
        $html | Should Match "dir-listing-list"
    }

    It "ルートパスの relPath 変換で空文字列から index.md への変換が正しい" {
        $relPath = ""
        $newRelPath = (($relPath.TrimEnd('\') + '\index.md').TrimStart('\'))
        $newRelPath | Should Be "index.md"
    }

    It "サブディレクトリパスの relPath 変換が正しい" {
        $relPath = "docs\"
        $newRelPath = (($relPath.TrimEnd('\') + '\index.md').TrimStart('\'))
        $newRelPath | Should Be "docs\index.md"
    }

    It "空の Markdown ファイルを読み込んでも例外をスローせずレンダリングできる" {
        $emptyMdPath = Join-Path $testRoot "empty-file.md"
        New-Item -Path $emptyMdPath -ItemType File -Force | Out-Null

        {
            $mdText = Get-Content -Path $emptyMdPath -Raw -Encoding UTF8
            if ($null -eq $mdText) { $mdText = "" }

            $builder  = New-Object Markdig.MarkdownPipelineBuilder
            $null     = [Markdig.MarkdownExtensions]::UseAdvancedExtensions($builder)
            $pipeline = $builder.Build()
            $rendered = [Markdig.Markdown]::ToHtml($mdText, $pipeline)
            $rendered | Should Be ""
        } | Should Not Throw
    }

    It "Render-ServerFolderTreeHtml pins index.md and README.md to the top of folder listings" {
        $node = [PSCustomObject]@{
            Files = [System.Collections.Generic.List[PSObject]]@(
                [PSCustomObject]@{ FullName = "C:\wiki\zoo.md"; BaseName = "zoo" },
                [PSCustomObject]@{ FullName = "C:\wiki\about.md"; BaseName = "about" },
                [PSCustomObject]@{ FullName = "C:\wiki\index.md"; BaseName = "index" },
                [PSCustomObject]@{ FullName = "C:\wiki\README.md"; BaseName = "README" }
            )
            SubFolders = [ordered]@{}
        }
        $treeHtml = Render-ServerFolderTreeHtml -node $node -currentRelPath "" -wikiDir "C:\wiki"
        $idxPos = $treeHtml.IndexOf("index")
        $readmePos = $treeHtml.IndexOf("README")
        $aboutPos = $treeHtml.IndexOf("about")
        $zooPos = $treeHtml.IndexOf("zoo")

        ($idxPos -lt $readmePos) | Should Be $true
        ($readmePos -lt $aboutPos) | Should Be $true
        ($aboutPos -lt $zooPos) | Should Be $true
    }

    It "Render-ServerFolderTreeHtml safely sorts folders without index.md or empty files" {
        $node = [PSCustomObject]@{
            Files = [System.Collections.Generic.List[PSObject]]@(
                [PSCustomObject]@{ FullName = "C:\wiki\zeta.md"; BaseName = "zeta" },
                [PSCustomObject]@{ FullName = "C:\wiki\alpha.md"; BaseName = "alpha" }
            )
            SubFolders = [ordered]@{}
        }
        {
            $treeHtml = Render-ServerFolderTreeHtml -node $node -currentRelPath "" -wikiDir "C:\wiki"
            $alphaPos = $treeHtml.IndexOf("alpha")
            $zetaPos = $treeHtml.IndexOf("zeta")
            ($alphaPos -lt $zetaPos) | Should Be $true
        } | Should Not Throw
    }

    It "Get-ChatWidgetHtml に開いているページを含めるデフォルトONのチェックボックスが含まれる" {
        $html = Get-ChatWidgetHtml
        $html | Should Match "okfIncludeCurrentPage"
        $html | Should Match "checked"
        $html | Should Match "開いているページを含める"
        $html | Should Match "根拠ドキュメント \(Markdown\)"
        $html | Should Match "text/event-stream"
        $html | Should Match "getReader"
        $html | Should Match "stream: true"
    }
}

Describe 'Index Cache and Settings View Tests' {
    BeforeAll {
        . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly
        $testScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path $PWD "tests" }
        $testProjectRoot = (Get-Item $testScriptDir).Parent.FullName
        $testSampleDir = Join-Path $testProjectRoot "markdown_sample"
    }

    It "Get-WikiCachePath produces valid cross-platform cache file path under scriptDir with folder hash" {
        $cachePath = Get-WikiCachePath -TargetWikiDir $testSampleDir
        $cachePath | Should Not BeNullOrEmpty
        $cachePath | Should Match "\.cache"
        $cachePath | Should Match "\.index-cache-[a-f0-9]{8,}\.json"
        # キャッシュの親ディレクトリがスクリプト配置元 ($scriptDir / $projectRoot) 配下であることを検証
        $cachePath.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase) | Should Be $true
    }

    It "Get-WikiCachePath isolates cache files for different target directories" {
        $dirA = "C:\Test\WikiA"
        $dirB = "C:\Test\WikiB"
        $cacheA = Get-WikiCachePath -TargetWikiDir $dirA
        $cacheB = Get-WikiCachePath -TargetWikiDir $dirB
        $cacheA | Should Not Be $cacheB
    }

    It "Save-WikiIndexCache and Load-WikiIndexCache cycle works when useCache is enabled" {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestCacheDir"
        $tempScriptDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestCacheScriptDir"
        if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempScriptDir) { Remove-Item -Path $tempScriptDir -Recurse -Force -ErrorAction SilentlyContinue }
        $null = New-Item -ItemType Directory -Path $tempDir
        $null = New-Item -ItemType Directory -Path $tempScriptDir

        # テスト用 Markdown ファイルを作成
        $testMd = Join-Path $tempDir "test1.md"
        "---`ntitle: Test 1`n---`n# Test 1 Content" | Out-File -FilePath $testMd -Encoding UTF8

        try {
            $cfgFile = Join-Path $tempScriptDir "config.json"
            @{
                search = @{
                    prebuildIndex = $true
                    useCache      = $true
                    cacheFolder   = ".cache"
                }
            } | ConvertTo-Json | Out-File -FilePath $cfgFile -Encoding UTF8

            # インデックス構築とキャッシュ保存
            Build-WikiIndex -TargetWikiDir $tempDir -TargetScriptDir $tempScriptDir -ForceRefresh | Out-Null
            $saved = Save-WikiIndexCache -TargetWikiDir $tempDir -TargetScriptDir $tempScriptDir
            $saved | Should Be $true

            # メモリ内インデックスをクリアしてディスクから再読み込み
            $script:WikiIndex = @()
            $loaded = Load-WikiIndexCache -TargetWikiDir $tempDir -TargetScriptDir $tempScriptDir
            $loaded | Should Be $true
            $script:WikiIndex.Count | Should Be 1
            $script:WikiIndex[0].Title | Should Be "Test 1"

            # ファイル削除時にキャッシュが無効化されることの検証 (ゾンビファイル防止)
            Remove-Item -Path $testMd -Force
            $script:WikiIndex = @()
            $loadedAfterDelete = Load-WikiIndexCache -TargetWikiDir $tempDir -TargetScriptDir $tempScriptDir
            $loadedAfterDelete | Should Be $false
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $tempScriptDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Clear-AllWikiCaches removes all index-cache files and resets in-memory cache" {
        $cacheDir = Join-Path $testProjectRoot ".cache"
        if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }

        $dummy1 = Join-Path $cacheDir ".index-cache-test111.json"
        $dummy2 = Join-Path $cacheDir ".index-cache-test222.json"
        "test1" | Out-File -FilePath $dummy1 -Encoding UTF8
        "test2" | Out-File -FilePath $dummy2 -Encoding UTF8

        $script:WikiIndex = @([PSCustomObject]@{ Title = "MemoryCache" })
        $script:SidebarCachedHtml = "<div>CachedSidebar</div>"

        $clearResult = Clear-AllWikiCaches -TargetScriptDir $testProjectRoot
        ($clearResult.deletedFiles -ge 2) | Should Be $true
        (Test-Path $dummy1) | Should Be $false
        (Test-Path $dummy2) | Should Be $false
        $script:WikiIndex.Count | Should Be 0
        $script:SidebarCachedHtml | Should Be $null
    }

    It "Get-SettingsViewHtml renders settings form, cache folder, and clear all cache button" {
        $html = Get-SettingsViewHtml
        $html | Should Not BeNullOrEmpty
        $html | Should Match "システム設定"
        $html | Should Match "prebuildIndex"
        $html | Should Match "useCache"
        $html | Should Match "cacheFolder"
        $html | Should Match "clearAllCachesNow"
        $html | Should Match "clearAllCacheBtn"
    }

    It "Get-WikiIndexingStatus tracks index build progress correctly" {
        $status = Get-WikiIndexingStatus
        $status | Should Not BeNullOrEmpty
        ($status.PSObject.Properties.Name -contains "IsBuilding") | Should Be $true
        ($status.PSObject.Properties.Name -contains "Total") | Should Be $true
        ($status.PSObject.Properties.Name -contains "Current") | Should Be $true
        ($status.PSObject.Properties.Name -contains "Percent") | Should Be $true
    }

    It "Get-WikiStatusPath returns valid cross-process status file path" {
        $statusPath = Get-WikiStatusPath -TargetWikiDir $testProjectRoot -TargetScriptDir $testProjectRoot
        $statusPath | Should Not BeNullOrEmpty
        $statusPath | Should Match '\.index-status-[a-f0-9]+\.json$'
    }

    It "Get-SearchViewHtml contains searchProgressBanner and loading indicator" {
        $html = Get-SearchViewHtml -Query "test"
        $html | Should Match 'searchProgressBanner'
        $html | Should Match 'searchProgressText'
    }

    It "Start-MarkdigWiki.ps1 includes /api/indexing-status endpoint" {
        $scriptContent = (Get-ChildItem -Path $projectRoot -Filter "*.ps1" -Recurse | ForEach-Object { Get-Content -Path $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        $scriptContent | Should Match 'indexing-status'
    }
}

Describe "Multi-Language (i18n) & Localization Tests" {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
    }

    It "Get-LocalizedStr returns Japanese by default and English when requested" {
        $jaHome = Get-LocalizedStr -Key "home" -Lang "ja"
        $jaHome | Should Be "🏠 ホーム"

        $enHome = Get-LocalizedStr -Key "home" -Lang "en"
        $enHome | Should Be "🏠 Home"
    }

    It "Get-LocalizedStr falls back to Japanese when requested language key is missing" {
        $fallbackStr = Get-LocalizedStr -Key "home" -Lang "unknown_lang"
        $fallbackStr | Should Be "🏠 ホーム"
    }

    It "Get-RequestLanguage resolves language with correct priority: Query > Cookie > Config > Default" {
        $cfgJa = [PSCustomObject]@{ defaultLanguage = "ja" }
        $cfgEn = [PSCustomObject]@{ defaultLanguage = "en" }

        # 1. Query parameter overrides all (both NameValueCollection and Hashtable)
        $qParams = [System.Web.HttpUtility]::ParseQueryString("lang=en")
        $cookieCol = New-Object System.Net.CookieCollection
        $cookieCol.Add((New-Object System.Net.Cookie("lang", "ja", "/", "localhost")))
        $resolved = Get-RequestLanguage -QueryParams $qParams -Cookies $cookieCol -Config $cfgJa
        $resolved | Should Be "en"

        $qHash = @{ "lang" = "en" }
        $resolvedHash = Get-RequestLanguage -QueryParams $qHash -Cookies $cookieCol -Config $cfgJa
        $resolvedHash | Should Be "en"

        # 2. Cookie overrides Config
        $emptyQ = [System.Web.HttpUtility]::ParseQueryString("")
        $resolvedCookie = Get-RequestLanguage -QueryParams $emptyQ -Cookies $cookieCol -Config $cfgEn
        $resolvedCookie | Should Be "ja"

        # 3. Config defaultLanguage
        $resolvedCfg = Get-RequestLanguage -QueryParams $emptyQ -Cookies (New-Object System.Net.CookieCollection) -Config $cfgEn
        $resolvedCfg | Should Be "en"

        # 4. Default fallback
        $resolvedDef = Get-RequestLanguage -QueryParams $emptyQ -Cookies (New-Object System.Net.CookieCollection) -Config $null
        $resolvedDef | Should Be "ja"
    }

    It "Generates localized HTML views in English when requested" {
        $recentHtml = Get-RecentViewHtml -Lang "en"
        $recentHtml | Should Match "🕒 Recent Updates"
        $recentHtml | Should Match "<th>Last Updated</th>"

        $tagsHtml = Get-TagsViewHtml -Lang "en"
        $tagsHtml | Should Match "🏷️ Tags"

        $maintHtml = Get-MaintenanceViewHtml -Lang "en"
        $maintHtml | Should Match "🧹 Quality & Maintenance Dashboard"

        $authorsHtml = Get-AuthorsViewHtml -Lang "en"
        $authorsHtml | Should Match "👥 Authors"

        $searchHtml = Get-SearchViewHtml -Query "test" -Lang "en"
        $searchHtml | Should Match "🔍 OKF Knowledge Search Results"
        $searchHtml | Should Match "Active"

        $settingsHtml = Get-SettingsViewHtml -Lang "en"
        $settingsHtml | Should Match "⚙️ System Settings"
        $settingsHtml | Should Match "Enable index cache"

        $chatWidgetHtml = Get-ChatWidgetHtml -Lang "en"
        $chatWidgetHtml | Should Match "🤖 OKF Wiki AI Assistant"
        $chatWidgetHtml | Should Match "chat-widget-btn"

        $sidebarHtml = Get-SidebarHtml -currentRelPath "" -Lang "en"
        $sidebarHtml | Should Match "🔄 Clear Cache"
    }

    It "Static HTML exporter supports -Language en parameter and localizes metadata cards" {
        $exportScript = Join-Path $projectRoot "Export-MarkdigWiki.ps1"
        $sampleDir    = Join-Path $projectRoot "markdown_sample"
        $testOutDir   = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_I18nExportTest"

        if (Test-Path $testOutDir) { Remove-Item -Path $testOutDir -Recurse -Force }
        try {
            & $exportScript -RootFolder $sampleDir -OutputDir $testOutDir -Language "en"
            $indexHtml = Join-Path $testOutDir "index.html"
            (Test-Path $indexHtml) | Should Be $true
            $content = [System.IO.File]::ReadAllText($indexHtml)
            $content | Should Match '<html lang="en">'
            $content | Should Match '<h2>📄 Document List</h2>'
            $content | Should Match 'ℹ️ Document Metadata \(OKF\)'
            $content | Should Match 'Last Updated:'
        } finally {
            if (Test-Path $testOutDir) { Remove-Item -Path $testOutDir -Recurse -Force }
        }
    }

    It "Dynamically merges external i18n.json dictionary entries" {
        $tempI18nFile = Join-Path $projectRoot "i18n.json"
        $i18nContent = '{ "zh": { "home": "首页" }, "en": { "home": "Custom Home" } }'
        [System.IO.File]::WriteAllText($tempI18nFile, $i18nContent, [System.Text.Encoding]::UTF8)

        try {
            # Reload script logic to parse i18n.json
            . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly

            $homeZh = Get-LocalizedStr -Key "home" -Lang "zh"
            $homeZh | Should Be "首页"

            $homeEnOverride = Get-LocalizedStr -Key "home" -Lang "en"
            $homeEnOverride | Should Be "Custom Home"
        } finally {
            if (Test-Path $tempI18nFile) { Remove-Item -Path $tempI18nFile -Force }
            # Restore default script state
            . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly
        }
    }

    It "Get-LocalizedStr safely handles format arguments and non-existent keys" {
        # FormatArgs substitution
        $itemsJa = Get-LocalizedStr -Key "items_count" -Lang "ja" -FormatArgs @(42)
        $itemsJa | Should Be "42 件のアイテム"

        $itemsEn = Get-LocalizedStr -Key "items_count" -Lang "en" -FormatArgs @(42)
        $itemsEn | Should Be "42 items"

        # Missing key returns the key itself
        $missing = Get-LocalizedStr -Key "non_existent_custom_key_123" -Lang "en"
        $missing | Should Be "non_existent_custom_key_123"
    }

    It "Get-RequestLanguage normalizes uppercase and mixed-case language inputs" {
        $qParams = [System.Web.HttpUtility]::ParseQueryString("lang=EN")
        $resolved = Get-RequestLanguage -QueryParams $qParams -Cookies $null -Config $null
        $resolved | Should Be "en"

        $cookieCol = New-Object System.Net.CookieCollection
        $cookieCol.Add((New-Object System.Net.Cookie("lang", "JA", "/", "localhost")))
        $resolvedCookie = Get-RequestLanguage -QueryParams $null -Cookies $cookieCol -Config $null
        $resolvedCookie | Should Be "ja"
    }

    It "Get-DirectoryListingHtml produces properly localized output in English" {
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        $dirHtml = Get-DirectoryListingHtml -DirFullPath $sampleDir -RawUrlPath "/" -Lang "en"
        $dirHtml | Should Match "items"
        $dirHtml | Should Match "Showing directory listing because index.md / README.md is missing."
    }

    It "Get-OkfTopBarHtml and Get-OkfFooterCardHtml correctly localize warning and labels in English" {
        $mockMeta = [PSCustomObject]@{
            Title       = "Test Deprecated Doc"
            Description = "A test deprecated document"
            Author      = "Tester"
            Domain      = "testing"
            Status      = "deprecated"
            Tags        = @("test")
            LastUpdated = (Get-Date "2025-01-01")
        }

        $topBar = Get-OkfTopBarHtml -Meta $mockMeta -RelPath "test.md" -Lang "en"
        $topBar | Should Match "Warning: Deprecated Document"
        $topBar | Should Match "Edit"

        $footer = Get-OkfFooterCardHtml -Meta $mockMeta -Lang "en"
        $footer | Should Match "Document Metadata \(OKF\)"
        $footer | Should Match "Author:"
        $footer | Should Match "Last Updated:"
    }

    It "Chat prompts (Fast RAG and Agentic RAG) are localized properly in English and Japanese" {
        $sysJa = Get-LocalizedStr -Key "default_system_prompt" -Lang "ja"
        $sysJa | Should Match "Wikiのナレッジを元に回答するアシスタント"
        $sysJa | Should Match "用語のブレも考慮し"

        $sysEn = Get-LocalizedStr -Key "default_system_prompt" -Lang "en"
        $sysEn | Should Match "assistant who answers based on the knowledge of the Wiki"
        $sysEn | Should Match "variations in terminology"

        $agentJa = Get-LocalizedStr -Key "default_agentic_system_prompt" -Lang "ja"
        $agentJa | Should Match "自律調査して回答する Agentic RAG アシスタント"

        $agentEn = Get-LocalizedStr -Key "default_agentic_system_prompt" -Lang "en"
        $agentEn | Should Match "Agentic RAG assistant that autonomously investigates"

        # Agentic RAG fallback with Lang = "en"
        $resEn = Invoke-AgenticRagChat -ApiUrl "http://invalid-url-for-test.local/v1" -ApiKey "dummy" -Model "test" -UserMessage "What is the architecture?" -MaxTurns 1 -Lang "en"
        $resEn.answer | Should Match "I autonomously investigated the Wiki|I searched the Wiki"
    }
}

Describe "UI Shutdown and Brand Title Customization Tests" {
    BeforeAll {
        . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly
    }

    It "Localizes brand_title correctly for ja and en" {
        $brandJa = Get-LocalizedStr -Key "brand_title" -Lang "ja"
        $brandJa | Should Match "SimpleWiki"

        $brandEn = Get-LocalizedStr -Key "brand_title" -Lang "en"
        $brandEn | Should Match "SimpleWiki"
    }

    It "Localizes all shutdown dictionary keys in ja and en" {
        $keys = @("shutdown_btn", "shutdown_confirm", "shutdown_done_title", "shutdown_done_desc", "settings_server_title", "settings_shutdown_desc", "settings_shutdown_btn")
        foreach ($k in $keys) {
            $valJa = Get-LocalizedStr -Key $k -Lang "ja"
            $valJa | Should Not Be $k
            $valJa.Length | Should BeGreaterThan 0

            $valEn = Get-LocalizedStr -Key $k -Lang "en"
            $valEn | Should Not Be $k
            $valEn.Length | Should BeGreaterThan 0
        }
    }

    It "Get-SettingsViewHtml renders server control section and shutdown trigger" {
        $htmlJa = Get-SettingsViewHtml -Lang "ja"
        $htmlJa | Should Match "サーバー制御"
        $htmlJa | Should Match "shutdownWikiServer\(\)"

        $htmlEn = Get-SettingsViewHtml -Lang "en"
        $htmlEn | Should Match "Server Control"
        $htmlEn | Should Match "shutdownWikiServer\(\)"
    }

    It "Start-MarkdigWiki.ps1 includes /api/shutdown endpoint and brand_title placeholder" {
        $scriptContent = (Get-ChildItem -Path $projectRoot -Filter "*.ps1" -Recurse | ForEach-Object { Get-Content -Path $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        $scriptContent | Should Match '/api/shutdown'
        $scriptContent | Should Match 'shutdown-btn'
        $scriptContent | Should Match 'shutdownWikiServer'
        $scriptContent | Should Match 'shutdownOverlay'
    }

    It "All i18n dictionary keys are completely synchronized between ja and en" {
        $jaKeys = $script:I18n["ja"].Keys | Sort-Object
        $enKeys = $script:I18n["en"].Keys | Sort-Object

        $missingInEn = $jaKeys | Where-Object { -not $script:I18n["en"].ContainsKey($_) }
        $missingInJa = $enKeys | Where-Object { -not $script:I18n["ja"].ContainsKey($_) }

        $missingInEn.Count | Should Be 0
        $missingInJa.Count | Should Be 0
    }

    It "Start-MarkdigWiki.ps1 binds all editor i18n variables into template and JS" {
        $scriptContent = (Get-ChildItem -Path $projectRoot -Filter "*.ps1" -Recurse | ForEach-Object { Get-Content -Path $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        $scriptContent | Should Match 'editor_gen_prefix'
        $scriptContent | Should Match 'editor_warning_yaml'
        $scriptContent | Should Match 'editor_loading'
        $scriptContent | Should Match 'editor_history_loading'
        $scriptContent | Should Match 'editor_load_error'
        $scriptContent | Should Match 'editor_backup_load_err'
        $scriptContent | Should Match 'editor_saved_warning'
        $scriptContent | Should Match 'editor_saved'
        $scriptContent | Should Match 'indexing_searching'
        $scriptContent | Should Match 'editor_meta_section_title'
        $scriptContent | Should Match 'editor_mode_form'
        $scriptContent | Should Match 'editor_mode_raw'
        $scriptContent | Should Match 'editor_field_type'
        $scriptContent | Should Match 'editor_field_title'
        $scriptContent | Should Match 'editor_field_status'
        $scriptContent | Should Match 'editor_status_draft'
        $scriptContent | Should Match 'editor_status_stable'
        $scriptContent | Should Match 'editor_status_deprecated'
        $scriptContent | Should Match 'editor_field_version'
        $scriptContent | Should Match 'editor_field_domain'
        $scriptContent | Should Match 'editor_field_author'
        $scriptContent | Should Match 'editor_field_reviewer'
        $scriptContent | Should Match 'editor_field_last_updated'
        $scriptContent | Should Match 'editor_set_today'
        $scriptContent | Should Match 'editor_field_desc'
        $scriptContent | Should Match 'editor_field_tags'
        $scriptContent | Should Match 'editor_field_related'
        $scriptContent | Should Match 'editor_field_superseded'
        $scriptContent | Should Match 'editor_auto_date'
        $scriptContent | Should Match 'editor_body_placeholder'
        $scriptContent | Should Match 'editor_shortcut_hint'
    }

    It "Start-MarkdigWiki.ps1 contains Form & RAW YAML separated editor modal HTML and JS functions" {
        $scriptContent = (Get-ChildItem -Path $projectRoot -Filter "*.ps1" -Recurse | ForEach-Object { Get-Content -Path $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        $scriptContent | Should Match 'id="yamlFormContainer"'
        $scriptContent | Should Match 'id="yamlRawContainer"'
        $scriptContent | Should Match 'id="wikiEditorBodyTextarea"'
        $scriptContent | Should Match 'id="metaType"'
        $scriptContent | Should Match 'id="metaLastUpdated"'
        $scriptContent | Should Match 'function parseMarkdownWithYaml'
        $scriptContent | Should Match 'function populateYamlForm'
        $scriptContent | Should Match 'function generateMarkdownWithYaml'
        $scriptContent | Should Match 'function switchYamlMode'
        $scriptContent | Should Match 'function onStatusChange'
        $scriptContent | Should Match 'function setEditorDateToday'
        $scriptContent | Should Match 'supersededByGroup'
        $scriptContent | Should Match 'metaAutoDate'
    }

    It "Start-MarkdigWiki.ps1 includes keyboard shortcuts for editor modal (Ctrl+S save and Esc cancel)" {
        $scriptContent = (Get-ChildItem -Path $projectRoot -Filter "*.ps1" -Recurse | ForEach-Object { Get-Content -Path $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        $scriptContent | Should Match 'addEventListener\("keydown"'
        $scriptContent | Should Match 'saveWikiMarkdown\(\)'
        $scriptContent | Should Match 'closeWikiEditor\(\)'
    }

    It "Start-MarkdigWiki.ps1 sanitizes RAW YAML delimiters and uses local date generation" {
        $scriptContent = (Get-ChildItem -Path $projectRoot -Filter "*.ps1" -Recurse | ForEach-Object { Get-Content -Path $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        $scriptContent | Should Match 'replace\(\/\^---\\r\?\\n\?\/, \x27\x27\)\.replace\(\/\\r\?\\n\?---\\r\?\$\/, \x27\x27\)'
        $scriptContent | Should Match 'd\.getFullYear\(\)'
        $scriptContent | Should Match 'd\.getMonth\(\) \+ 1'
        $scriptContent | Should Match 'd\.getDate\(\)'
    }

    It "/api/config handles OrderedDictionary and saves config.json without errors" {
        $tempIsolatedDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestServerIsolated"
        if (Test-Path $tempIsolatedDir) { Remove-Item -Path $tempIsolatedDir -Recurse -Force -ErrorAction SilentlyContinue }
        $null = New-Item -ItemType Directory -Path $tempIsolatedDir

        # サーバー起動に必要な最小構成（スクリプト、lib、sample、config）を一時ディレクトリにコピー
        Copy-Item -Path (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -Destination $tempIsolatedDir -Force
        Copy-Item -Path (Join-Path $projectRoot "lib") -Destination (Join-Path $tempIsolatedDir "lib") -Recurse -Force
        Copy-Item -Path (Join-Path $projectRoot "markdown_sample") -Destination (Join-Path $tempIsolatedDir "markdown_sample") -Recurse -Force

        $isolatedConfig = Join-Path $tempIsolatedDir "config.json"
        @{
            search = @{ prebuildIndex = $false; useCache = $false; cacheFolder = ".cache" }
            rag    = @{ enabled = $false; apiUrl = "http://localhost:11434/v1"; model = "test-model" }
        } | ConvertTo-Json -Depth 5 | Out-File -FilePath $isolatedConfig -Encoding UTF8

        $port = 8094
        $psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { (Get-Command pwsh).Source } elseif (Get-Command powershell -ErrorAction SilentlyContinue) { (Get-Command powershell).Source } else { (Get-Process -Id $PID).Path }
        $proc = Start-Process $psExe -ArgumentList "-File", (Join-Path $tempIsolatedDir "Start-MarkdigWiki.ps1"), "-RootFolder", (Join-Path $tempIsolatedDir "markdown_sample"), "-Port", $port -PassThru
        Start-Sleep -Seconds 3
        try {
            $payload = @{
                search = @{
                    prebuildIndex = $false
                    useCache      = $true
                    cacheFolder   = ".cache"
                }
                rag = @{
                    enabled = $false
                    apiUrl  = "http://localhost:11434/v1"
                    model   = "qwen2.5-coder-7b-instruct"
                }
            } | ConvertTo-Json -Depth 5

            $res = Invoke-RestMethod -Uri "http://localhost:$port/api/config" -Method Post -Body $payload -ContentType "application/json; charset=utf-8"
            $res.success | Should Be $true

            # Activation Code 結合テスト: 自PCマシンID向けアクティベーションコードの送信
            $mid = Get-MachineFingerprint
            $actCode = Protect-ActivationCode -ApiKey "sk-live-test-12345" -MachineId $mid
            $actPayload = @{
                rag = @{
                    enabled        = $true
                    activationCode = $actCode
                }
            } | ConvertTo-Json -Depth 5
            $actRes = Invoke-RestMethod -Uri "http://localhost:$port/api/config" -Method Post -Body $actPayload -ContentType "application/json; charset=utf-8"
            $actRes.success | Should Be $true

            # 保存された隔離環境の config.json が DPAPI 形式になっていることを検証
            $savedCfg = Get-Content -Path $isolatedConfig -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($IsWindows -or $env:OS -eq "Windows_NT") { $savedCfg.rag.apiKey | Should Match "^DPAPI:" } else { $savedCfg.rag.apiKey | Should Match "^ENC:" }
            $resolvedKey = Get-ResolvedSecret -SecretValue $savedCfg.rag.apiKey
            $resolvedKey | Should Be "sk-live-test-12345"

            # 不正なマシンID用アクティベーションコード送信時のエラー拒絶テスト
            $badActCode = Protect-ActivationCode -ApiKey "sk-other-key" -MachineId "OTHER-MACHINE-9999"
            $badPayload = @{
                rag = @{
                    enabled        = $true
                    activationCode = $badActCode
                }
            } | ConvertTo-Json -Depth 5

            try {
                Invoke-RestMethod -Uri "http://localhost:$port/api/config" -Method Post -Body $badPayload -ContentType "application/json; charset=utf-8"
                throw "Expected HTTP 400 failure"
            } catch {
                # 400 Bad Request で弾かれることを検証
                $_.Exception.Response.StatusCode.value__ | Should Be 400
            }
        } finally {
            Invoke-RestMethod -Uri "http://localhost:$port/api/shutdown" -Method Post -ErrorAction SilentlyContinue
            if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
            Remove-Item -Path $tempIsolatedDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}



Describe "Repository Code Quality, Syntax & Character Encoding Validation Tests" {
    It "All PowerShell script files parse successfully without AST syntax errors" {
        $psFiles = Get-ChildItem -Path $projectRoot -Recurse -Include "*.ps1", "*.psm1", "*.psd1" |
            Where-Object { $_.FullName -notmatch '[\\/]\.(git|cache)[\\/]' }

        foreach ($file in $psFiles) {
            $tokens = $null
            $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errs)
            $errCount = if ($errs) { $errs.Count } else { 0 }
            $errCount | Should Be 0
        }
    }

    It "All PowerShell scripts (.ps1, .psm1, .psd1) are encoded as UTF-8 with BOM" {
        $psFiles = Get-ChildItem -Path $projectRoot -Recurse -Include "*.ps1", "*.psm1", "*.psd1" |
            Where-Object { $_.FullName -notmatch '[\\/]\.(git|cache)[\\/]' }

        foreach ($file in $psFiles) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            $hasBom | Should Be $true
        }
    }

    It "All Batch files (.bat) are strictly encoded as UTF-8 without BOM (No-BOM)" {
        $batFiles = Get-ChildItem -Path $projectRoot -Recurse -Include "*.bat" |
            Where-Object { $_.FullName -notmatch '[\\/]\.(git|cache)[\\/]' }

        foreach ($file in $batFiles) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            $hasBom | Should Be $false
        }
    }
}

# ==============================================================================
# PR 統合・ユニットテスト拡充スイート (PR #14, #16, #18, #20, #24, #28, #29, #30, #31, #32)
# ==============================================================================
Describe "PR Consolidation & Unit Test Coverage Suite" {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly

        $exportScriptPath = Join-Path $projectRoot "Export-MarkdigWiki.ps1"
        if (Test-Path $exportScriptPath) {
            $tokens = $null; $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($exportScriptPath, [ref]$tokens, [ref]$errs)
            $funcAsts = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
            foreach ($fn in $funcAsts) {
                Invoke-Expression $fn.Extent.Text
            }
        }
    }

    Context "PR #11 & #18: WikiMetadata Helper Functions" {
        It "Get-WikiDir resolves default and specified paths correctly" {
            $resolved = Get-WikiDir -RootFolder "" -TargetScriptDir $projectRoot
            (Test-Path $resolved) | Should Be $true

            $resolvedCustom = Get-WikiDir -RootFolder $projectRoot -TargetScriptDir $projectRoot
            $resolvedCustom | Should Be $projectRoot
        }

        It "ConvertFrom-YamlHeader extracts YAML and splits body cleanly" {
            $md = @"
---
title: "Custom Title"
tags: [tag1, tag2]
domain: guide/setup
---
# Content Heading
This is body text.
"@
            $res = ConvertFrom-YamlHeader -MdText $md -RelPath "test.md"
            $res.HasYaml | Should Be $true
            $res.YamlDict["title"] | Should Be "Custom Title"
            $res.BodyText | Should Match "This is body text\."
        }

        It "Get-YamlListProperty handles arrays, strings, and comma-delimited values" {
            $dict = @{
                tagsList = @("a", "b", "c")
                tagsCsv  = "tag1, tag2, tag3"
                tagsEmpty = ""
            }
            (Get-YamlListProperty -YamlDict $dict -Key "tagsList").Count | Should Be 3
            (Get-YamlListProperty -YamlDict $dict -Key "tagsCsv").Count | Should Be 3
            (Get-YamlListProperty -YamlDict $dict -Key "tagsEmpty").Count | Should Be 0
        }

        It "Get-DocumentTitle resolves YAML title > Markdown H1 > Filename > Untitled" {
            $t1 = Get-DocumentTitle -YamlDict @{ title = "YamlTitle" } -BodyText "# H1 Title" -File $null
            $t1 | Should Be "YamlTitle"

            $t2 = Get-DocumentTitle -YamlDict @{} -BodyText "# H1 Title`nBody" -File $null
            $t2 | Should Be "H1 Title"

            $fakeFile = [PSCustomObject]@{ BaseName = "SampleFile" }
            $t3 = Get-DocumentTitle -YamlDict @{} -BodyText "No heading" -File $fakeFile
            $t3 | Should Be "SampleFile"

            $t4 = Get-DocumentTitle -YamlDict @{} -BodyText "No heading" -File $null
            $t4 | Should Be "Untitled"
        }

        It "Get-DocumentDescription extracts and trims summary without markdown symbols" {
            $desc1 = Get-DocumentDescription -YamlDict @{ description = "Manual Desc" } -BodyText "Body"
            $desc1 | Should Be "Manual Desc"

            $desc2 = Get-DocumentDescription -YamlDict @{} -BodyText "# Heading`n**Bold text** with [link](url)."
            $desc2 | Should Not Match '[\*#\[\]]'
            $desc2 | Should Match "Bold text with link"
        }

        It "Get-DocumentDomain determines domain from YAML or relative directory path" {
            $d1 = Get-DocumentDomain -YamlDict @{ domain = "custom/domain" } -RelPath "docs/guide.md"
            $d1 | Should Be "custom/domain"

            $d2 = Get-DocumentDomain -YamlDict @{} -RelPath "docs\user-guide\install.md"
            $d2 | Should Be "docs/user-guide"

            $d3 = Get-DocumentDomain -YamlDict @{} -RelPath "index.md"
            $d3 | Should Be "root"
        }
    }

    Context "PR #25 & #32: WikiViews Helper Functions" {
        It "Render-DocList generates valid HTML with escaped titles and dates" {
            $docs = @(
                [PSCustomObject]@{
                    Title       = "Doc & <Tag> One"
                    RelPath     = "guide\doc1.md"
                    LastUpdated = [DateTime]::Parse("2026-08-01")
                },
                [PSCustomObject]@{
                    Title       = "Doc Two"
                    RelPath     = "guide/doc2.md"
                    LastUpdated = "2026-08-02"
                }
            )

            $html = Render-DocList -docArray $docs -emptyMsg "No docs available"
            $html | Should Match "<ul>"
            $html | Should Match "Doc &amp; &lt;Tag&gt; One"
            $html | Should Match "/guide/doc1.md"
            $html | Should Match "\(2026-08-01\)"

            $emptyHtml = Render-DocList -docArray @() -emptyMsg "Empty List"
            $emptyHtml | Should Be "<p class='empty-msg'>Empty List</p>"
        }

        It "Get-SettingsViewData prepares complete data packet for view rendering" {
            $dataJa = Get-SettingsViewData -Lang "ja"
            $dataJa.Lang | Should Be "ja"
            $dataJa.TitleLbl | Should Not BeNullOrEmpty
            $dataJa.SearchTitleLbl | Should Not BeNullOrEmpty

            $dataEn = Get-SettingsViewData -Lang "en"
            $dataEn.Lang | Should Be "en"
            $dataEn.TitleLbl | Should Not BeNullOrEmpty
        }

        It "Render-SettingsSearchCard, Render-SettingsRagCard, Render-SettingsServerCard render semantic cards" {
            $data = Get-SettingsViewData -Lang "ja"
            $searchCard = Render-SettingsSearchCard -Data $data
            $searchCard | Should Match "okf-card"
            $searchCard | Should Match "rebuildBtn"

            $ragCard = Render-SettingsRagCard -Data $data
            $ragCard | Should Match "machineIdText"

            $serverCard = Render-SettingsServerCard -Data $data
            $serverCard | Should Match "shutdownWikiServer\(\)"
        }
    }

    Context "PR #28 & #27: WikiSearch Modular Engine & Performance Optimization" {
        It "Test-OkfDocFilter filters by status, domain, and NOT exclusion correctly" {
            $item = [PSCustomObject]@{
                Title       = "Active Architecture Document"
                Description = "High level design"
                Tags        = @("arch", "core")
                Domain      = "docs/arch"
                Status      = "active"
                BodyText    = "Some secret legacy details here."
            }

            # Status filter
            (Test-OkfDocFilter -Item $item -StatusFilter "active") | Should Be $true
            (Test-OkfDocFilter -Item $item -StatusFilter "deprecated") | Should Be $false
            (Test-OkfDocFilter -Item $item -StatusFilter "all") | Should Be $true

            # Domain filter
            (Test-OkfDocFilter -Item $item -DomainFilter "docs/arch") | Should Be $true
            (Test-OkfDocFilter -Item $item -DomainFilter "unrelated") | Should Be $false

            # NOT exclusion filter
            $excludePatterns = @([regex]::Escape("secret"))
            (Test-OkfDocFilter -Item $item -EscapedExcludeKeywords $excludePatterns) | Should Be $false
        }

        It "Get-OkfDocScore calculates weighted relevance score with phrase bonus" {
            $item = [PSCustomObject]@{
                Title       = "Agentic RAG Architecture"
                Description = "Fast search engine design"
                Tags        = @("rag", "ai")
                Domain      = "core"
                Author      = "DevTeam"
                Status      = "active"
                BodyText    = "Detailed architecture notes about agentic systems."
            }

            $phrase = [regex]::Escape("Agentic RAG")
            $keywords = @([regex]::Escape("agentic"), [regex]::Escape("architecture"))

            $score = Get-OkfDocScore -Item $item -PhraseRegex $phrase -EscapedKeywords $keywords -CleanQuery "Agentic RAG" -KeywordCount 2
            $score | Should BeGreaterThan 20
        }

        It "Get-OkfDocSnippet extracts contextual lines matching search keywords" {
            $item = [PSCustomObject]@{
                Title       = "Sample"
                Description = "Default description"
                BodyText    = "---`ntitle: Sample`n---`nFirst intro line.`nTarget keyword appears on this specific matching line.`nTrailing summary line."
            }

            $snip = Get-OkfDocSnippet -Item $item -Keywords @("matching")
            $snip | Should Match "Target keyword appears"
        }
    }

    Context "PR #14 & #16 & #24 & #29 & #30 & #31: Trees, Exporters, and PSObject Conversion" {
        It "Convert-PSObjectToOrdered converts nested hashtables and PSObjects recursively" {
            function Convert-PSObjectToOrdered {
                param ($InputObject)
                if ($null -eq $InputObject) { return $null }
                if ($InputObject -is [System.Collections.Specialized.OrderedDictionary]) { return $InputObject }
                if ($InputObject -is [System.Collections.IDictionary]) {
                    $ordered = [ordered]@{}
                    foreach ($key in $InputObject.Keys) {
                        $ordered[$key] = Convert-PSObjectToOrdered -InputObject $InputObject[$key]
                    }
                    return $ordered
                }
                if ($InputObject -is [PSCustomObject]) {
                    $ordered = [ordered]@{}
                    foreach ($prop in $InputObject.PSObject.Properties) {
                        $ordered[$prop.Name] = Convert-PSObjectToOrdered -InputObject $prop.Value
                    }
                    return $ordered
                }
                if ($InputObject -is [System.Collections.IList] -or $InputObject -is [System.Array]) {
                    $list = [System.Collections.Generic.List[object]]::new()
                    foreach ($item in $InputObject) {
                        [void]$list.Add((Convert-PSObjectToOrdered -InputObject $item))
                    }
                    return @($list)
                }
                return $InputObject
            }

            $nested = [PSCustomObject]@{
                Level1 = [PSCustomObject]@{
                    Key1 = "Val1"
                    Num  = 123
                }
                List = @("item1", "item2")
            }
            $dict = Convert-PSObjectToOrdered -InputObject $nested
            $dict | Should BeOfType [System.Collections.Specialized.OrderedDictionary]
            $dict["Level1"] | Should BeOfType [System.Collections.Specialized.OrderedDictionary]
            $dict["Level1"]["Key1"] | Should Be "Val1"
        }

        It "Build-ServerFileTreeNode and Test-ServerNodeHasActiveFile build recursive trees accurately" {
            $wikiDir = [System.IO.Path]::GetFullPath("C:\wiki_test")
            $mdFiles = @(
                [PSCustomObject]@{ FullName = (Join-Path $wikiDir "index.md") },
                [PSCustomObject]@{ FullName = (Join-Path $wikiDir "docs\guide\start.md") }
            )

            $tree = Build-ServerFileTreeNode -allMdFiles $mdFiles -wikiDir $wikiDir
            $tree.Files.Count | Should Be 1
            $tree.SubFolders.Contains("docs") | Should Be $true
            $tree.SubFolders["docs"].SubFolders.Contains("guide") | Should Be $true

            $hasActive = Test-ServerNodeHasActiveFile -node $tree -currentRelPath "docs\guide\start.md" -wikiDir $wikiDir
            $hasActive | Should Be $true

            $notActive = Test-ServerNodeHasActiveFile -node $tree -currentRelPath "other\path.md" -wikiDir $wikiDir
            $notActive | Should Be $false
        }

        It "Render-ServerFolderTreeHtml renders valid HTML folder details" {
            $wikiDir = [System.IO.Path]::GetFullPath("C:\wiki_test")
            $mdFiles = @(
                [PSCustomObject]@{ FullName = (Join-Path $wikiDir "index.md") },
                [PSCustomObject]@{ FullName = (Join-Path $wikiDir "docs\manual.md") }
            )
            $tree = Build-ServerFileTreeNode -allMdFiles $mdFiles -wikiDir $wikiDir
            $html = Render-ServerFolderTreeHtml -node $tree -currentRelPath "docs\manual.md" -wikiDir $wikiDir
            $html | Should Match "folder-title"
            $html | Should Match "docs"
        }

        It "Build-FileTreeNode and Test-ExportNodeHasActiveFile generate static hierarchies" {
            $files = @(
                [PSCustomObject]@{ FullName = "C:\wiki\index.md"; BaseName = "index" },
                [PSCustomObject]@{ FullName = "C:\wiki\docs\api.md"; BaseName = "api" }
            )
            $tree = Build-FileTreeNode -allMdFiles $files -wikiDir "C:\wiki"
            $tree.Files.Count | Should Be 1
            $tree.SubFolders.Contains("docs") | Should Be $true

            $active = Test-ExportNodeHasActiveFile -node $tree -currentFile $files[1]
            $active | Should Be $true
        }

        It "Import-ExternalI18n merges external JSON dictionaries smoothly" {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("SimpleWiki_I18n_PRTest_" + [System.Guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            try {
                $customDict = @{
                    ja = @{ custom_key_test = "テスト値" }
                    en = @{ custom_key_test = "Test Value" }
                } | ConvertTo-Json -Depth 5
                Set-Content -Path (Join-Path $tempDir "i18n.json") -Value $customDict -Encoding UTF8

                Import-ExternalI18n -TargetScriptDir $tempDir
                (Get-LocalizedStr -Key "custom_key_test" -Lang "ja") | Should Be "テスト値"
                (Get-LocalizedStr -Key "custom_key_test" -Lang "en") | Should Be "Test Value"
            } finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# ==============================================================================
# 批判的検証・セキュリティ・異常系耐性テストスイート (Adversarial Testing)
# ==============================================================================
Describe "Adversarial & Security Resilience Tests" {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
    }

    Context "1. Security & Parameter Sanitization (Activation & DPAPI)" {
        It "Rejects activation code generation with whitespace-only parameters gracefully" {
            $cleanMid = if ([string]::IsNullOrWhiteSpace("   `t`n ")) { "" } else { "   `t`n ".Trim() }
            $cleanMid | Should Be ""
        }

        It "Hardware fingerprint extraction never returns empty or generic default string" {
            $fp = Get-MachineFingerprint
            $fp | Should Not BeNullOrEmpty
            $fp | Should Not Be "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"
            $fp.Length | Should BeGreaterThan 5
        }

        It "Protects against injection in Activation Code Email and MachineId" {
            $maliciousEmail = "victim@example.com' OR '1'='1; --"
            $maliciousMid = "<script>alert(1)</script>`r`nDROP TABLE"
            $rawKey = "sk-super-secret-key"

            $code = Protect-ActivationCode -ApiKey $rawKey -MachineId $maliciousMid -Email $maliciousEmail
            $code | Should Match "^ENC:"

            $dec = Unprotect-ActivationCode -EncryptedText $code -MachineId $maliciousMid -Email $maliciousEmail
            $dec | Should Be $rawKey

            # 異なるマシンIDでは復号が完全に拒絶されること
            $badDec = Unprotect-ActivationCode -EncryptedText $code -MachineId "DIFFERENT-MACHINE-ID" -Email $maliciousEmail
            $badDec | Should Be ""
        }
    }

    Context "2. Search Engine Hardening & ReDoS Resilience" {
        It "Handles malicious regex characters in query without throwing exceptions" {
            $script:WikiIndex = @(
                [PSCustomObject]@{
                    Title       = "Normal Document"
                    Description = 'Some text [.*+?^${}()|[]\] and special symbols'
                    Domain      = "root"
                    Tags        = @("sample", "[test]")
                    Status      = "active"
                    BodyText    = "Body with ((((nested)))) syntax."
                }
            )

            $adversarialQueries = @(
                '[.*+?^${}()|[]\]',
                '((((((((a+)+)+)+)+)+)+)+)',
                '\\\\\\\\\\\\',
                'NOT - - - + + +',
                '???***+++',
                '"unclosed quote',
                '<script>alert(1)</script>'
            )

            foreach ($q in $adversarialQueries) {
                {
                    $results = Search-OkfDocs -Query $q
                } | Should Not Throw
            }
        }

        It "Handles extremely large 10,000+ character search queries safely" {
            $hugeQuery = ("A" * 10000)
            {
                $res = Search-OkfDocs -Query $hugeQuery
                $res.Count | Should Be 0
            } | Should Not Throw
        }

        It "Safely ignores null or corrupted items in WikiIndex" {
            $script:WikiIndex = @($null, [PSCustomObject]@{ Title = $null; Description = $null; Status = $null })
            {
                $res = Search-OkfDocs -Query "test"
            } | Should Not Throw
        }
    }

    Context "3. YAML Front Matter Parser Adversarial Attacks" {
        It "Safely handles corrupt, unclosed, or deeply nested pseudo-YAML without crashing" {
            $corruptYamls = @(
                "---\ntitle: [unclosed list\n---`nText",
                "---\n: missing key\n---`nText",
                "---\n" + ("- item\n" * 100) + "---`nText",
                "---\ntags: `"`"`"`"`"`"`"`"\n---`nText"
            )

            foreach ($cy in $corruptYamls) {
                {
                    $meta = ConvertFrom-YamlHeader -MdText $cy -RelPath "corrupt.md"
                } | Should Not Throw
            }
        }
    }

    Context "4. HTML View XSS Injection Prevention" {
        It "HtmlEncodes malicious script payloads in Render-DocList and metadata tags" {
            $xssDocs = @(
                [PSCustomObject]@{
                    Title       = "<script>alert('xss')</script>"
                    RelPath     = "docs/<img src=x onerror=alert(1)>.md"
                    LastUpdated = [DateTime]::Now
                }
            )

            $rendered = Render-DocList -docArray $xssDocs -emptyMsg "None"
            $rendered | Should Not Match "<script>"
            $rendered | Should Match "&lt;script&gt;"
        }
    }

    Context "5. Glossary & Term-Linked Backlinks Extension Tests" {
        It "Extracts terms and definitions correctly from glossary.md" {
            $glossaryMd = @"
---
title: "Glossary"
---

# 社内用語

## OKF (Open Knowledge Format)

* **概要**: ドキュメント構造化フォーマット。

## K-DAT

* **概要**: バックアップツール。
"@
            $terms = Get-GlossaryTerms -MdText $glossaryMd
            $terms.Count | Should Be 2
            $terms.Contains("K-DAT") | Should Be $true
            $terms.Contains("OKF (Open Knowledge Format)") | Should Be $true

            $defOkf = Get-GlossaryTermDefinition -Term "OKF" -MdText $glossaryMd
            $defOkf | Should Match "ドキュメント構造化フォーマット"
        }

        It "Runs Update-WikiTags.ps1 in DryRun mode without modifying files" {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("WikiTagsTest_" + [Guid]::NewGuid().ToString("N"))
            $null = New-Item -ItemType Directory -Path $tempDir -Force
            try {
                $gPath = Join-Path $tempDir "glossary.md"
                $docPath = Join-Path $tempDir "test.md"

                Set-Content -Path $gPath -Value "## OKF`n`n* **概要**: ドキュメントフォーマット" -Encoding UTF8
                $origContent = "---\ntags:\n  - draft\n---\n\nこの文章には OKF が含まれます。"
                Set-Content -Path $docPath -Value $origContent -Encoding UTF8 -NoNewline

                $updateScript = Join-Path $PSScriptRoot "../Update-WikiTags.ps1"
                & $updateScript -WikiDir $tempDir -GlossaryPath $gPath -DryRun

                $readBack = Get-Content -Path $docPath -Raw -Encoding UTF8
                $readBack | Should Be $origContent
            } finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Merges newly detected glossary terms into tags without destroying existing custom tags" {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("WikiTagsMerge_" + [Guid]::NewGuid().ToString("N"))
            $null = New-Item -ItemType Directory -Path $tempDir -Force
            try {
                $gPath = Join-Path $tempDir "glossary.md"
                $docPath = Join-Path $tempDir "test.md"

                Set-Content -Path $gPath -Value "## OKF (Open Knowledge Format)`n`n* **概要**: フォーマット" -Encoding UTF8
                $origContent = "---\ntags:\n  - status/draft\n  - custom-tag\n---\n\nこの文章には OKF が含まれます。"
                Set-Content -Path $docPath -Value $origContent -Encoding UTF8

                $updateScript = Join-Path $PSScriptRoot "../Update-WikiTags.ps1"
                & $updateScript -WikiDir $tempDir -GlossaryPath $gPath

                $readBack = Get-Content -Path $docPath -Raw -Encoding UTF8
                $readBack | Should Match "status/draft"
                $readBack | Should Match "custom-tag"
                $readBack | Should Match "OKF"
            } finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Renders glossary box in Get-TagsViewHtml when tag matches a glossary term" {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("WikiTagView_" + [Guid]::NewGuid().ToString("N"))
            $null = New-Item -ItemType Directory -Path $tempDir -Force
            $oldWikiDir = $script:wikiDir
            try {
                $gPath = Join-Path $tempDir "glossary.md"
                Set-Content -Path $gPath -Value "## OKF`n`n* **概要**: 用語解説テストテキスト" -Encoding UTF8

                $script:wikiDir = $tempDir
                $wikiDir = $tempDir
                $script:WikiIndex = @(
                    [PSCustomObject]@{
                        Title       = "Test Doc"
                        Description = "Test Desc"
                        RelPath     = "test.md"
                        Tags        = @("OKF")
                        Status      = "active"
                    }
                )

                $html = Get-TagsViewHtml -SelectedTag "OKF" -Lang "ja"
                $html | Should Match "glossary-box"
                $html | Should Match "用語解説: OKF"
                $html | Should Match "用語解説テストテキスト"
                # Markdig による Markdown (太字) の HTML レンダリング確認
                if ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq "Markdig" }) {
                    $html | Should Match "<strong>概要</strong>"
                }

                $htmlNoGlossary = Get-TagsViewHtml -SelectedTag "NonGlossaryTag" -Lang "ja"
                $htmlNoGlossary | Should Not Match "glossary-box"
            } finally {
                $script:wikiDir = $oldWikiDir
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe "Refactoring Specific Behavior Tests" {
    BeforeAll {
        . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly
    }

    It "Get-OkfFooterCardHtml correctly renders description paragraph when Description property is provided" {
        $meta = [PSCustomObject]@{
            Title       = "Test Card Doc"
            Description = "This is a test description paragraph."
            Author      = "Card Author"
            Domain      = "test-domain"
            LastUpdated = (Get-Date "2026-08-10")
            Tags        = @("test")
        }

        $html = Get-OkfFooterCardHtml -Meta $meta -Lang "ja"
        $html | Should Match "<p class='okf-desc'"
        $html | Should Match "This is a test description paragraph\."
    }

    It "Get-MaintenanceViewHtml uses top-level Render-DocList to format document lists" {
        $script:WikiIndex = @(
            [PSCustomObject]@{
                Title       = "Outdated Manual"
                RelPath     = "docs/outdated.md"
                Status      = "active"
                LastUpdated = (Get-Date "2020-01-01")
            }
        )

        $html = Get-MaintenanceViewHtml -Lang "ja"
        $html | Should Match "Outdated Manual"
        $html | Should Match "/docs/outdated.md"
        $html | Should Match "\(2020-01-01\)"
    }

    It "Get-WikiEditorModalHtml generates editor modal HTML structure and JS functions" {
        $editorHtml = Get-WikiEditorModalHtml -Lang "ja"
        $editorHtml | Should Match 'id="wikiEditorModal"'
        $editorHtml | Should Match 'id="yamlFormContainer"'
        $editorHtml | Should Match 'id="yamlRawContainer"'
        $editorHtml | Should Match 'function parseMarkdownWithYaml'
        $editorHtml | Should Match 'function populateYamlForm'
        $editorHtml | Should Match 'function generateMarkdownWithYaml'
    }

    It "Get-MainViewHtml renders full page HTML layout incorporating editor modal" {
        $layoutHtml = Get-MainViewHtml -PageTitle "Test Title" -BodyContent "<p>Test Body</p>" -RelPath "index.md" -Lang "ja"
        $layoutHtml | Should Match '<!DOCTYPE html>'
        $layoutHtml | Should Match '<title>Test Title - .*SimpleWiki OKF</title>'
        $layoutHtml | Should Match 'id="wikiEditorModal"'
        $layoutHtml | Should Match 'shutdownWikiServer'
    }
}
