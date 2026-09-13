# ==============================================================================
#  Stella.Tests.ps1
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

    It "Get-WikiEditorModalHtml binds i18n texts without unexpanded variable strings" {
        $editorHtmlJa = Get-WikiEditorModalHtml -Lang "ja"
        $editorHtmlJa | Should Match "Markdown"
        $editorHtmlJa | Should Match "OKF"
        $editorHtmlJa | Should Not Match '\$edTitle'
        $editorHtmlJa | Should Not Match '\$edLatest'
        $editorHtmlJa | Should Not Match '\$edLoadingJs'

        $editorHtmlEn = Get-WikiEditorModalHtml -Lang "en"
        $editorHtmlEn | Should Match "Markdown Editor"
        $editorHtmlEn | Should Match "Latest"
        $editorHtmlEn | Should Not Match '\$edTitle'
        $editorHtmlEn | Should Not Match '\$edLatest'
    }

    It "Get-MainViewHtml binds PSCustomObject Config without parameter binding exceptions" {
        $customConfig = [PSCustomObject]@{
            editor = [PSCustomObject]@{ enabled = $true }
            rag    = [PSCustomObject]@{ enabled = $false }
        }
        {
            $layoutHtml = Get-MainViewHtml -PageTitle "Config Test" -BodyContent "<p>Content</p>" -RelPath "index.md" -Lang "ja" -Config $customConfig
            $layoutHtml | Should Match "Config Test"
        } | Should Not Throw
    }

    It "Ensure-WikiIndexLoaded populates script:WikiIndex when index is null or empty" {
        $sampleWikiDir = Join-Path $projectRoot "markdown_sample"
        $script:WikiIndex = $null
        Ensure-WikiIndexLoaded -TargetWikiDir $sampleWikiDir
        $script:WikiIndex | Should Not Be $null
        ($script:WikiIndex.Count -gt 0) | Should Be $true
    }

    It "Render-GlossaryBoxHtml returns formatted box for existing glossary term and empty string for non-existent" {
        $sampleWikiDir = Join-Path $projectRoot "markdown_sample"
        $boxHtml = Render-GlossaryBoxHtml -Term "OKF" -TargetWikiDir $sampleWikiDir
        $boxHtml | Should Match '<div class="glossary-box"'
        $boxHtml | Should Match 'OKF'

        $emptyBox = Render-GlossaryBoxHtml -Term "NonExistentTerm12345" -TargetWikiDir $sampleWikiDir
        $emptyBox | Should Be ""
    }
}


Describe 'Stella View & 3D Spacetime Specification Tests' {
    BeforeAll {
        . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly
    }

    It "Parses links, created_at, updated_at, and enforces schema status validation in Get-DocumentMetadata" {
        $mdText = @"
---
title: "Stella Spec Doc"
status: active
created_at: 2025-01-15
updated_at: 2025-06-20
links:
  - "docs/api.md"
  - "docs/architecture.md"
---
# Stella Spec Body
"@
        $meta = Get-DocumentMetadata -File $null -RelPath "docs/stella-spec.md" -MdText $mdText
        $meta.Title | Should Be "Stella Spec Doc"
        $meta.Status | Should Be "active"
        $meta.CreatedAt.ToString("yyyy-MM-dd") | Should Be "2025-01-15"
        $meta.UpdatedAt.ToString("yyyy-MM-dd") | Should Be "2025-06-20"
        $meta.Links.Count | Should Be 2
        $meta.Links -contains "docs/api.md" | Should Be $true

        # Validate invalid/unknown status falls back to active
        $mdInvalidStatus = @"
---
title: "Invalid Status Doc"
status: invalid_unknown_status
---
"@
        $metaInvalid = Get-DocumentMetadata -File $null -RelPath "docs/invalid.md" -MdText $mdInvalidStatus
        $metaInvalid.Status | Should Be "active"
    }

    It "Computes deterministic 3D coordinates (X, Y, Z) with collision avoidance and time depth" {
        $docs = @(
            [PSCustomObject]@{ Title = "Doc Old"; RelPath = "a.md"; Domain = "domain1"; Status = "active"; CreatedAt = [DateTime]"2023-01-01"; UpdatedAt = [DateTime]"2023-01-01"; Links = @() },
            [PSCustomObject]@{ Title = "Doc Mid"; RelPath = "b.md"; Domain = "domain1"; Status = "active"; CreatedAt = [DateTime]"2024-06-01"; UpdatedAt = [DateTime]"2024-06-01"; Links = @() },
            [PSCustomObject]@{ Title = "Doc New"; RelPath = "c.md"; Domain = "domain2"; Status = "draft"; CreatedAt = [DateTime]"2026-09-01"; UpdatedAt = [DateTime]"2026-09-01"; Links = @() }
        )

        $placedDocs = Measure-WikiNodeCoordinates -DocList $docs
        $placedDocs.Count | Should Be 3
        foreach ($d in $placedDocs) {
            ($null -ne $d.X) | Should Be $true
            ($null -ne $d.Y) | Should Be $true
            ($null -ne $d.Z) | Should Be $true
        }

        # Verify coordinates are not all overlapping (distance >= minDistance)
        $dist = [Math]::Sqrt([Math]::Pow(($placedDocs[0].X - $placedDocs[1].X), 2) + [Math]::Pow(($placedDocs[0].Y - $placedDocs[1].Y), 2))
        ($dist -ge 30) | Should Be $true

        # Verify time depth Z reflects chronology (Doc Old has lower Z than Doc New)
        ($placedDocs[0].Z -lt $placedDocs[2].Z) | Should Be $true
    }

    It "Get-StellaViewHtml renders 3D canvas, control panel with view presets, and time HUD" {
        $sampleWikiDir = Join-Path $projectRoot "markdown_sample"
        Ensure-WikiIndexLoaded -TargetWikiDir $sampleWikiDir
        $html = Get-StellaViewHtml -Lang "ja"
        $html | Should Match "stellaCanvas"
        $html | Should Match "stella-control-panel"
        $html | Should Match "stella-slidein-pane"
        $html | Should Match "stella-preset-btn"
        $html | Should Match "setStellaPreset"
        $html | Should Match "project3D"
        $html | Should Match "stellaTimeHud"
        $html | Should Match "flyToNode"
        $html | Should Match "stella-help-overlay"
        $html | Should Match "stella-reset-btn"
        $html | Should Match "resetStellaView"
        $html | Should Match "highlightConstellation"
        $html | Should Match "stellaConnectedSection"
    }

    It "Get-StellaViewHtml contains defensive tag normalization against string and invalid tag inputs" {
        $sampleWikiDir = Join-Path $projectRoot "markdown_sample"
        Ensure-WikiIndexLoaded -TargetWikiDir $sampleWikiDir
        $html = Get-StellaViewHtml -Lang "ja"
        $html | Should Match "Array\.isArray\(rawTags\)"
        $html | Should Match "rawTags\.split"
        $html | Should Match "Array\.isArray\(n1\.tags\)"
        $html | Should Match "Array\.isArray\(n\.tags\)"
    }

    It "Get-StellaControlPanelHtml renders control panel structure and respects language parameter" {
        $sampleWikiDir = Join-Path $projectRoot "markdown_sample"
        Ensure-WikiIndexLoaded -TargetWikiDir $sampleWikiDir

        $htmlJa = Get-StellaControlPanelHtml -ActiveView "stella" -Lang "ja"
        $htmlJa | Should Match 'class="stella-control-panel"'
        $htmlJa | Should Match 'id="stellaSearchInput"'
        $htmlJa | Should Match 'id="stellaStatusSelect"'
        $htmlJa | Should Match 'id="stellaTagSelect"'
        $htmlJa | Should Match 'class="stella-preset-btn'
        $htmlJa | Should Match 'class="stella-reset-btn"'
        $htmlJa | Should Match 'resetStellaView'
        $htmlJa | Should Match 'setStellaPreset'

        # Japanese localized text assertions
        $htmlJa | Should Match '3D ステラ'
        $htmlJa | Should Match 'すべて'

        # English localized text assertions
        $htmlEn = Get-StellaControlPanelHtml -ActiveView "stella" -Lang "en"
        $htmlEn | Should Match '3D Stella'
        $htmlEn | Should Match 'All'
    }

    It "Get-StellaControlPanelHtml deduplicates, trims, sorts, and HTML-encodes tags from script:WikiIndex" {
        $script:WikiIndex = @(
            [PSCustomObject]@{ Tags = @("  frontend  ", "Architecture", "<script>alert(1)</script>") },
            [PSCustomObject]@{ Tags = @("frontend", "C# & .NET", "   ") }
        )

        $html = Get-StellaControlPanelHtml -Lang "ja"

        # Verify HTML encoding of special characters
        $html | Should Match "<option value='&lt;script&gt;alert\(1\)&lt;/script&gt;'>🏷️ &lt;script&gt;alert\(1\)&lt;/script&gt;</option>"
        $html | Should Match "<option value='C# &amp; .NET'>🏷️ C# &amp; .NET</option>"

        # Verify deduplication and trimming
        $html | Should Match "<option value='frontend'>🏷️ frontend</option>"

        # Verify alphabetical sorting (<script> before Architecture before C# & .NET before frontend)
        $scriptIndex = $html.IndexOf("&lt;script&gt;")
        $archIndex = $html.IndexOf("Architecture")
        $dotnetIndex = $html.IndexOf("C# &amp; .NET")
        $frontendIndex = $html.IndexOf("frontend")

        ($scriptIndex -lt $archIndex) | Should Be $true
        ($archIndex -lt $dotnetIndex) | Should Be $true
        ($dotnetIndex -lt $frontendIndex) | Should Be $true
    }

    It "HTTP route requests handle /stella endpoint" {
        $scriptContent = (Get-ChildItem -Path $projectRoot -Filter "*.ps1" -Recurse | ForEach-Object { Get-Content -Path $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        $scriptContent | Should Match 'rawPath -eq "/stella"'
    }
}
