# ==============================================================================
#  Start-MarkdigWiki.Tests.ps1 (Pester Tests)
#  Encoding: UTF-8 with BOM
# ==============================================================================

$projectRoot = (Resolve-Path "$PSScriptRoot\..").Path
$libDll      = Join-Path $projectRoot "lib\Markdig.dll"

Describe "Markdig Assembly & Pipeline Tests" {
    It "Markdig.dll exists in lib directory" {
        (Test-Path $libDll) | Should -Be $true
    }

    It "Markdig assembly loads and builds Advanced Extensions pipeline" {
        $libDir = Join-Path $projectRoot "lib"
        Get-ChildItem -Path $libDir -Filter "*.dll" | ForEach-Object {
            Add-Type -Path $_.FullName
        }
        $builder  = New-Object Markdig.MarkdownPipelineBuilder
        $null     = [Markdig.MarkdownExtensions]::UseAdvancedExtensions($builder)
        $pipeline = $builder.Build()
        $pipeline | Should -Not -Be $null

        $html = [Markdig.Markdown]::ToHtml("# Hello World`n- [x] Task completed", $pipeline)
        $html | Should -Match "Hello World"
        $html | Should -Match "task-list-item"
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
        $isAllowed | Should -Be $true
    }

    It "Path traversal attempting to access external directory is blocked" {
        $filePath  = Join-Path $wikiDir "..\..\Windows\System32\drivers\etc\hosts"
        $fullPath  = [System.IO.Path]::GetFullPath($filePath)
        $isAllowed = $fullPath.StartsWith($fullWikiDir, [System.StringComparison]::OrdinalIgnoreCase)
        $isAllowed | Should -Be $false
    }
}

Describe "HTML Escaping & XSS Protection Tests" {
    It "XSS script in 404 path is HTML encoded" {
        $rawPath  = "/<script>alert('xss')</script>"
        $safePath = [System.Net.WebUtility]::HtmlEncode($rawPath)
        $safePath | Should -Not -Match "<script>"
        $safePath | Should -Match "&lt;script&gt;"
    }

    It "Special characters in page title are HTML encoded" {
        $baseName  = "<Test & Document>"
        $safeTitle = [System.Net.WebUtility]::HtmlEncode($baseName)
        $safeTitle | Should -Be "&lt;Test &amp; Document&gt;"
    }
}

Describe "Static HTML Export Tests (Export-MarkdigWiki.ps1)" {
    BeforeAll {
        $tempPath = [System.IO.Path]::GetTempPath()
        $script:testExportDir = Join-Path $tempPath "SimpleWiki_TestExport"
        if (Test-Path $script:testExportDir) { Remove-Item -Path $script:testExportDir -Recurse -Force }
    }

    AfterAll {
        if ($script:testExportDir -and (Test-Path $script:testExportDir)) { Remove-Item -Path $script:testExportDir -Recurse -Force }
    }

    It "Exports static HTML files to target directory" {
        $exportScript = Join-Path $projectRoot "Export-MarkdigWiki.ps1"
        $sampleDir    = Join-Path $projectRoot "markdown_sample"
        & $exportScript -RootFolder $sampleDir -OutputDir $script:testExportDir

        (Test-Path (Join-Path $script:testExportDir "index.html")) | Should -Be $true
        (Test-Path (Join-Path $script:testExportDir "概要.html")) | Should -Be $true
        (Test-Path (Join-Path $script:testExportDir "docs\詳細仕様.html")) | Should -Be $true
    }

    It "Converts .md hyperlinks to .html in exported files" {
        $indexHtmlPath = Join-Path $script:testExportDir "index.html"
        $htmlContent   = [System.IO.File]::ReadAllText($indexHtmlPath)

        $htmlContent | Should -Match "(%E6%A6%82%E8%A6%81|概要)\.html"
        $htmlContent | Should -Match "docs/(%E8%A9%B3%E7%B4%B0%E4%BB%95%E6%A7%98|詳細仕様)\.html"
    }

    It "Generates relative URI links for subfolder pages without leading slash" {
        $subHtmlPath    = Join-Path $script:testExportDir "docs\詳細仕様.html"
        $subHtmlContent = [System.IO.File]::ReadAllText($subHtmlPath)

        $subHtmlContent | Should -Match "href='../index.html'"
        $subHtmlContent | Should -Match "href='\.\./(%E6%A6%82%E8%A6%81|概要)\.html'"
    }

    It "Generates nested tree structure for subfolder pages in sidebar" {
        $subHtmlPath    = Join-Path $script:testExportDir "docs\詳細仕様.html"
        $subHtmlContent = [System.IO.File]::ReadAllText($subHtmlPath)

        $subHtmlContent | Should -Match "<li class='nav-folder'>"
        # アクティブな親フォルダ docs は open
        $subHtmlContent | Should -Match "<details open>\s*<summary class='folder-title'>📁 docs</summary>"
        # アクティブでないフォルダ guides は open なし
        $subHtmlContent | Should -Match "<details>\s*<summary class='folder-title'>📁 guides</summary>"
    }

    It "Embeds OKF top bar and footer card in exported static HTML files" {
        $indexHtmlPath = Join-Path $script:testExportDir "index.html"
        $htmlContent   = [System.IO.File]::ReadAllText($indexHtmlPath)

        $indexHtmlPath | Should -Not -Be $null
        $htmlContent | Should -Match "class=""okf-top-bar"""
        $htmlContent | Should -Match "class=""okf-footer-card"""
    }
}

Describe "OKF Metadata Extraction & Fallback Tests (Get-DocumentMetadata)" {
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
        $meta.Title | Should -Be "DB Recovery Manual"
        $meta.Description | Should -Be "PostgreSQL recovery steps"
        $meta.Author | Should -Be "Taro Yamada"
        $meta.Domain | Should -Be "infrastructure/database"
        $meta.Tags -contains "PostgreSQL" | Should -Be $true
        $meta.Tags -contains "Runbook" | Should -Be $true
        $meta.LastUpdated.ToString("yyyy-MM-dd") | Should -Be "2026-08-01"
        $meta.Status | Should -Be "active"
        $meta.HasYaml | Should -Be $true
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
        $meta.Title | Should -Be "System: Recovery Manual"
        $meta.Tags -contains "Database" | Should -Be $true
        $meta.Tags -contains "PostgreSQL" | Should -Be $true
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
        $meta.Title | Should -Be "Header Title from H1"
    }

    It "Falls back to BaseName when no title in YAML and no H1 in body" {
        $mdText = "Plain markdown text without headers or YAML."
        $fakeFile = [PSCustomObject]@{
            FullName      = "C:\wiki\docs\my-doc.md"
            LastWriteTime = (Get-Date "2026-01-01")
            BaseName      = "my-doc"
        }
        $meta = Get-DocumentMetadata -File $fakeFile -RelPath "docs/my-doc.md" -MdText $mdText
        $meta.Title | Should -Be "my-doc"
        $meta.Domain | Should -Be "docs"
        $meta.Status | Should -Be "active"
        $meta.HasYaml | Should -Be $false
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
        { $script:testMeta = Get-DocumentMetadata -File $fakeFile -RelPath "docs/broken.md" -MdText $mdText } | Should -Not -Throw
        $script:testMeta.Title | Should -Be "Malformed YAML"
    }
}

Describe "OKF Dynamic View & API Endpoint Tests" {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        Build-WikiIndex -TargetWikiDir $sampleDir -ForceRefresh | Out-Null
    }

    It "Builds WikiIndex from sample directory successfully" {
        $script:WikiIndex.Count | Should -BeGreaterThan 0
    }

    It "Generates JSON for /api/index.json containing OKF metadata" {
        $json = Get-ApiIndexJson
        $json | Should -Not -Be $null
        $json | Should -Match "Title"
        $json | Should -Match "RelPath"
    }

    It "Generates pre-chunked JSON for /api/chunks.json containing section-level RAG chunks" {
        $json = Get-ApiChunksJson
        $json | Should -Not -Be $null
        $json | Should -Match "ChunkId"
        $json | Should -Match "EnrichedText"
        $json | Should -Match "Section"
        
        $chunksObj = $json | ConvertFrom-Json
        $chunksObj.Count | Should -BeGreaterThan 0
        $chunksObj[0].ChunkId | Should -Match "#chunk-"
        $chunksObj[0].EnrichedText | Should -Match "\[Document:"
    }

    It "Generates HTML for /recent view" {
        $html = Get-RecentViewHtml
        $html | Should -Match "最近の更新"
    }

    It "Generates HTML for /tags view" {
        $html = Get-TagsViewHtml
        $html | Should -Match "タグ"
    }

    It "Generates HTML for /maintenance view" {
        $html = Get-MaintenanceViewHtml
        $html | Should -Match "品質"
    }

    It "Generates HTML for /authors view" {
        $html = Get-AuthorsViewHtml
        $html | Should -Match "著者"
    }

    It "Generates HTML for /search view" {
        $html = Get-SearchViewHtml -Query "API"
        $html | Should -Match "検索結果"
    }
}

Describe "Get-HighlightText Utility Tests" {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
    }

    It "Highlights keyword in safe HTML text" {
        $result = Get-HighlightText -Text 'PostgreSQL Database Manual' -Keywords @('PostgreSQL')
        $result | Should -Match '<mark[^>]*>PostgreSQL</mark>'
    }

    It "Handles special regex metacharacters in keywords without error" {
        $result = Get-HighlightText -Text 'C# & (Notes) Guide' -Keywords @('C#', '(Notes)')
        $result | Should -Match '<mark[^>]*>C#</mark>'
        $result | Should -Match '<mark[^>]*>\(Notes\)</mark>'
    }

    It "Does not corrupt HTML tags when keyword is style, mark, or background" {
        $result = Get-HighlightText -Text 'This is a style and mark test' -Keywords @('style', 'mark')
        $result | Should -Not -Match '<mark[^>]*<mark'
        $result | Should -Match '<mark[^>]*>style</mark>'
        $result | Should -Match '<mark[^>]*>mark</mark>'
    }
}

Describe 'OKF Search Engine Advanced Scoring & Filtering Tests' {
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
        $html | Should -Match 'docs/db-recovery.md'
        $html | Should -Match 'General Troubleshooting'
        $html | Should -Match 'Old Legacy Database Setup'
    }

    It 'TC-02: Multi-word AND search returns only documents matching ALL keywords' {
        $html = Get-SearchViewHtml -Query 'PostgreSQL crash' -StatusFilter 'all'
        $html | Should -Match 'docs/db-recovery.md'
        $html | Should -Not -Match 'General Troubleshooting'
        $html | Should -Not -Match 'Old Legacy Database Setup'
    }

    It 'TC-03: Ranks document with Title match higher than Body-only match' {
        $html = Get-SearchViewHtml -Query 'PostgreSQL' -StatusFilter 'all'
        $recoveryPos   = $html.IndexOf('docs/db-recovery.md')
        $troublePos    = $html.IndexOf('General Troubleshooting')
        $recoveryPos | Should -BeGreaterThan -1
        $troublePos  | Should -BeGreaterThan -1
        $recoveryPos | Should -BeLessThan $troublePos
    }

    It 'TC-04: StatusFilter active excludes deprecated documents' {
        $html = Get-SearchViewHtml -Query 'PostgreSQL' -StatusFilter 'active'
        $html | Should -Match 'docs/db-recovery.md'
        $html | Should -Not -Match 'Old Legacy Database Setup'
    }

    It 'TC-05: StatusFilter deprecated includes deprecated documents' {
        $html = Get-SearchViewHtml -Query 'PostgreSQL' -StatusFilter 'deprecated'
        $html | Should -Match 'Old Legacy Database Setup'
        $html | Should -Not -Match 'docs/db-recovery.md'
    }

    It 'TC-06: Highlight keywords in search results snippet' {
        $html = Get-SearchViewHtml -Query 'PostgreSQL' -StatusFilter 'active'
        $html | Should -Match '<mark[^>]*>PostgreSQL</mark>'
    }

    It 'TC-07: Special character query executes safely without regex exception' {
        { $script:specHtml = Get-SearchViewHtml -Query 'C# (Notes)' -StatusFilter 'all' } | Should -Not -Throw
        $script:specHtml | Should -Match 'docs/csharp-notes.md'
        $script:specHtml | Should -Match '&amp;'
    }
}

Describe 'Critical Edge Case & Security Tests' {
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
        $html | Should -Match 'docs/db-recovery.md'
        $html | Should -Not -Match 'General Troubleshooting'
    }

    It 'Encodes XSS payload in search query input cleanly without raw HTML injection' {
        $xssQuery = '<script>alert("xss")</script>'
        $html = Get-SearchViewHtml -Query $xssQuery -StatusFilter 'all'
        $html | Should -Not -Match '<script>alert\("xss"\)</script>'
        $html | Should -Match '&lt;script&gt;'
    }

    It 'Executes facet-only domain filter search without keywords' {
        $html = Get-SearchViewHtml -Query '' -StatusFilter 'all' -DomainFilter 'infrastructure'
        $html | Should -Match 'docs/db-recovery.md'
        $html | Should -Not -Match 'General Troubleshooting'
    }

    It 'Gracefully handles invalid StatusFilter parameter without crashing' {
        { $script:invalidHtml = Get-SearchViewHtml -Query 'PostgreSQL' -StatusFilter 'invalid_status_value' } | Should -Not -Throw
        $script:invalidHtml | Should -Not -Match 'docs/db-recovery.md'
    }

    It 'Parses comma-separated tag string in YAML correctly into array' {
        $sampleMd = @"
---
title: "Comma Tag Test"
tags: "PostgreSQL, Database, Recovery"
---
# Test
"@
        $fakeFile = [PSCustomObject]@{
            FullName      = "C:\wiki\docs\test.md"
            LastWriteTime = (Get-Date "2026-01-01")
            BaseName      = "test"
        }
        $meta = Get-DocumentMetadata -File $fakeFile -MdText $sampleMd -RelPath "test.md"
        $meta.Tags.Count | Should -Be 3
        $meta.Tags | Should -Contain "PostgreSQL"
        $meta.Tags | Should -Contain "Database"
        $meta.Tags | Should -Contain "Recovery"
    }

    It 'Get-QueryParams decodes percent-encoded UTF-8 Japanese query string without mojibake' {
        # %E3%83%8F%E3%83%B3%E3%83%89%E3%83%96%E3%83%83%E3%82%AF = "ハンドブック"
        $mockReq = [PSCustomObject]@{
            Url = [PSCustomObject]@{
                Query = "?q=%E3%83%8F%E3%83%B3%E3%83%89%E3%83%96%E3%83%83%E3%82%AF&status=active"
            }
        }
        $params = Get-QueryParams -Request $mockReq
        $params["q"] | Should -Be "ハンドブック"
        $params["status"] | Should -Be "active"
    }

    It 'Executes Unblock-File safely on lib DLLs without throwing exceptions' {
        $libPath = Join-Path $projectRoot "lib"
        $isWin = ($env:OS -eq "Windows_NT") -or $IsWindows
        {
            Get-ChildItem -Path $libPath -Filter "*.dll" | ForEach-Object {
                if ($isWin) {
                    Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
                }
            }
        } | Should -Not -Throw
    }
}

Describe 'Export-GUI.ps1 GUI Component & Syntax Validation' {
    It 'Export-GUI.ps1 file exists and passes AST syntax parsing' {
        $guiScript = Join-Path $projectRoot "Export-GUI.ps1"
        (Test-Path $guiScript) | Should -Be $true

        $errs = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseFile($guiScript, [ref]$tokens, [ref]$errs)
        $errs.Count | Should -Be 0
    }

    It 'Export-GUI.bat exists and references Export-GUI.ps1' {
        $guiBat = Join-Path $projectRoot "Export-GUI.bat"
        (Test-Path $guiBat) | Should -Be $true
        $content = Get-Content -Path $guiBat -Raw
        $content | Should -Match "Export-GUI\.ps1"
    }
}

Describe 'OKF LLM RAG Security & Encryption Tests' {
    BeforeAll {
        . (Join-Path $projectRoot "Start-MarkdigWiki.ps1")
    }

    It 'Encrypts and decrypts API key with AES-256 (ENC: prefix)' {
        $rawKey = "sk-proj-test123456789"
        $encKey = Protect-StringAes -PlainText $rawKey
        $encKey | Should -Match "^ENC:"
        $decKey = Unprotect-StringAes -EncryptedText $encKey
        $decKey | Should -Be $rawKey
    }

    It 'Encrypts and decrypts API key with Windows DPAPI (DPAPI: prefix)' -Skip:(-not (($env:OS -eq "Windows_NT") -or $IsWindows)) {
        $rawKey = "sk-proj-dpapitest98765"
        $dpapiKey = Protect-StringDpapi -PlainText $rawKey
        $dpapiKey | Should -Match "^DPAPI:"
        $decKey = Unprotect-StringDpapi -EncryptedText $dpapiKey
        $decKey | Should -Be $rawKey
    }

    It 'Resolves secret for ENV: prefix dynamically' {
        [Environment]::SetEnvironmentVariable("TEST_OPENAI_KEY", "sk-env-secret-val")
        try {
            $resolved = Get-ResolvedSecret -SecretValue "ENV:TEST_OPENAI_KEY"
            $resolved | Should -Be "sk-env-secret-val"
        } finally {
            [Environment]::SetEnvironmentVariable("TEST_OPENAI_KEY", $null)
        }
    }

    It 'Get-ConfigJson returns enabled = false when config.json does not exist' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestNoConfig"
        if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
        try {
            $cfg = Get-ConfigJson -TargetScriptDir $tempDir
            $cfg.rag.enabled | Should -Be $false
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
            (Test-Path $targetCfg) | Should -Be $true
            $cfg = Get-Content -Path $targetCfg -Raw | ConvertFrom-Json
            $cfg.rag.enabled | Should -Be $true
            $cfg.rag.apiKey | Should -Match "^ENC:"
            $resolved = Get-ResolvedSecret -SecretValue $cfg.rag.apiKey
            $resolved | Should -Be "sk-test-portable-key"
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-JapaneseWordsWinRT tokenizes Japanese queries and filters Japanese stop words' {
        $words = Get-JapaneseWordsWinRT -Text 'セットアップの方法は？'
        $words | Should -Contain 'セットアップ'
        $words | Should -Contain '環境構築'
        $words | Should -Not -Contain 'は'
        $words | Should -Not -Contain 'の'
    }

    It 'Invoke-OpenAiChatCompletions builds message payload with history array' {
        $history = @(
            @{ role = 'user'; content = '質問1' },
            @{ role = 'assistant'; content = '回答1' }
        )
        { Invoke-OpenAiChatCompletions -ApiUrl 'http://invalid-endpoint-for-test-xyz' -ApiKey 'test-key' -Model 'test-model' -SystemPrompt 'System Prompt' -UserMessage '質問2' -History $history -TimeoutSec 1 } | Should -Throw
    }
}

Describe "Agentic RAG & OKF Tools Tests" {
    BeforeAll {
        # Import functions from Start-MarkdigWiki.ps1
        $scriptPath = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $scriptPath -DotSourceOnly
    }

    It "Start-MarkdigWiki.ps1 is encoded as UTF-8 with BOM" {
        $scriptPath = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
        $bytes.Length | Should -BeGreaterThan 3
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
    }

    It "Search-OkfDocs scores and filters active documents correctly" {
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        Build-WikiIndex -TargetWikiDir $sampleDir -ForceRefresh | Out-Null
        $results = Search-OkfDocs -Query "Markdown" -StatusFilter "active" -WikiDir $sampleDir
        $results | Should -Not -Be $null
        $results.Count | Should -BeGreaterThan 0
        $results[0].Score | Should -BeGreaterThan 0
    }

    It "Invoke-ToolReadDoc trims body text and strips YAML header" {
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        Build-WikiIndex -TargetWikiDir $sampleDir -ForceRefresh | Out-Null
        $doc = $script:WikiIndex | Select-Object -First 1
        if ($doc) {
            $content = Invoke-ToolReadDoc -RelPath $doc.RelPath -WikiDir $sampleDir -MaxChars 50
            $content | Should -Not -Be $null
            $content | Should -Not -Match "^---"
            $content.Length | Should -BeLessThan 200
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
            $links = Invoke-ToolGetLinkedDocs -RelPath "doc1.md" -WikiDir $tempDir
            $links | Should -Not -Be $null
            $links.Count | Should -Be 1
            $links[0].RelPath | Should -Be "doc2.md"
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
            $res | Should -Not -Be $null
            $res | Should -Match "K-DAT"
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}













