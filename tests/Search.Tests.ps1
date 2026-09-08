# ==============================================================================
#  Search.Tests.ps1
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

        # Clear-WikiIndexCache wrapper validation
        $script:WikiIndex = @([PSCustomObject]@{ Title = "MemoryCache2" })
        $clearResult2 = Clear-WikiIndexCache -TargetScriptDir $testProjectRoot
        $clearResult2.success | Should Be $true
        $script:WikiIndex.Count | Should Be 0
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

    It "Get-SidebarHtml ensures index is loaded and caches sidebar tree on initial request" {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("SimpleWiki_SidebarCache_" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path (Join-Path $tempDir "docs") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempDir "empty_folder") -Force | Out-Null
        try {
            Set-Content -Path (Join-Path $tempDir "index.md") -Value "# Index" -Encoding UTF8
            Set-Content -Path (Join-Path $tempDir "docs\guide.md") -Value "# Guide" -Encoding UTF8

            $script:WikiIndex = @()
            $script:CachedSidebarTree = $null
            $script:wikiDir = $tempDir

            $html = Get-SidebarHtml -currentRelPath "index.md"
            $html | Should Not BeNullOrEmpty
            $html | Should Match "guide"
            $html | Should Not Match "empty_folder"
            $html | Should Not Match "refreshWikiSidebarCache"

            $script:WikiIndex.Count | Should Be 2
            $script:CachedSidebarTree | Should Not BeNullOrEmpty

            $cachedTreeBefore = $script:CachedSidebarTree
            $html2 = Get-SidebarHtml -currentRelPath "docs\guide.md"
            $script:CachedSidebarTree | Should Be $cachedTreeBefore
        } finally {
            $script:wikiDir = $null
            $script:WikiIndex = @()
            $script:CachedSidebarTree = $null
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}


Describe "WikiSearch Modular Engine & Trees Suite" {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
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

        It "Build-ServerFileTreeNode excludes empty folders and folders containing only non-md assets during disk scan" {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("SimpleWiki_TreeTest_" + [System.Guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path (Join-Path $tempDir "docs") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $tempDir "images") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $tempDir "empty_folder") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $tempDir "nested\sub_empty") -Force | Out-Null
            try {
                Set-Content -Path (Join-Path $tempDir "index.md") -Value "# Top" -Encoding UTF8
                Set-Content -Path (Join-Path $tempDir "docs\guide.md") -Value "# Guide" -Encoding UTF8
                Set-Content -Path (Join-Path $tempDir "images\logo.png") -Value "fake binary" -Encoding UTF8
                Set-Content -Path (Join-Path $tempDir "nested\sub_empty\photo.jpg") -Value "fake binary" -Encoding UTF8

                $tree = Build-ServerFileTreeNode -wikiDir $tempDir
                $tree.Files.Count | Should Be 1
                $tree.SubFolders.Contains("docs") | Should Be $true
                $tree.SubFolders["docs"].Files.Count | Should Be 1
                $tree.SubFolders.Contains("images") | Should Be $false
                $tree.SubFolders.Contains("empty_folder") | Should Be $false
                $tree.SubFolders.Contains("nested") | Should Be $false
            } finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
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
