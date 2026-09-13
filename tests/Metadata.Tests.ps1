# ==============================================================================
#  Metadata.Tests.ps1
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



Describe "Metadata Helper Functions Suite" {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
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
                tagsList  = @("a", "b", "c")
                tagsCsv   = "tag1, tag2, tag3"
                tagsEmpty = ""
                tagsSingle = @("single")
                tagsStr    = "solo"
            }
            (Get-YamlListProperty -YamlDict $dict -Key "tagsList").Count | Should Be 3
            (Get-YamlListProperty -YamlDict $dict -Key "tagsCsv").Count | Should Be 3
            (Get-YamlListProperty -YamlDict $dict -Key "tagsEmpty").Count | Should Be 0

            # 単一要素や空の場合でも配列（Array）として返ることの検証
            $singleArr = Get-YamlListProperty -YamlDict $dict -Key "tagsSingle"
            ($singleArr -is [System.Array]) | Should Be $true
            $singleArr.Count | Should Be 1
            $singleArr[0] | Should Be "single"

            $singleStr = Get-YamlListProperty -YamlDict $dict -Key "tagsStr"
            ($singleStr -is [System.Array]) | Should Be $true
            $singleStr.Count | Should Be 1
            $singleStr[0] | Should Be "solo"

            $emptyArr = Get-YamlListProperty -YamlDict $dict -Key "tagsEmpty"
            ($emptyArr -is [System.Array]) | Should Be $true
            $emptyArr.Count | Should Be 0

            $nullArr = Get-YamlListProperty -YamlDict $dict -Key "tagsNotExist"
            ($nullArr -is [System.Array]) | Should Be $true
            $nullArr.Count | Should Be 0
        }

        It "Get-DocumentMetadata preserves Tags as array and serializes properly to JSON" {
            $mdSingle = "---`ntags: single`n---`n# Title"
            $metaSingle = Get-DocumentMetadata -File $null -RelPath "single.md" -MdText $mdSingle
            ($metaSingle.Tags -is [System.Array]) | Should Be $true
            $metaSingle.Tags.Count | Should Be 1

            $jsonSingle = $metaSingle | ConvertTo-Json
            $jsonSingle | Should Match '"Tags":\s*\[\s*"single"\s*\]'

            $mdEmpty = "# No Yaml"
            $metaEmpty = Get-DocumentMetadata -File $null -RelPath "empty.md" -MdText $mdEmpty
            ($metaEmpty.Tags -is [System.Array]) | Should Be $true
            $metaEmpty.Tags.Count | Should Be 0

            $jsonEmpty = $metaEmpty | ConvertTo-Json
            $jsonEmpty | Should Match '"Tags":\s*\[\s*\]'
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

        It "Get-RelToRootPath calculates relative path back to root for various depths and formats" {
            Get-RelToRootPath -RelPath "" | Should Be "."
            Get-RelToRootPath -RelPath $null | Should Be "."
            Get-RelToRootPath -RelPath "index.md" | Should Be "."
            Get-RelToRootPath -RelPath "root.html" | Should Be "."
            Get-RelToRootPath -RelPath "docs/page.md" | Should Be ".."
            Get-RelToRootPath -RelPath "a/b/c.md" | Should Be "../.."
            Get-RelToRootPath -RelPath "docs/sub/deep/page.md" | Should Be "../../.."
            Get-RelToRootPath -RelPath "docs\sub\page.md" | Should Be "../.."
            Get-RelToRootPath -RelPath "/docs/sub/page.md" | Should Be "../.."
        }
    }
}

Describe "Glossary & Term-Linked Backlinks Extension Suite" {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
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
