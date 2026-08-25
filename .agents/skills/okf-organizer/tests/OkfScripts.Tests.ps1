#requires -Version 5.1
$ErrorActionPreference = "Stop"

$script:testsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $script:testsDir) { $script:testsDir = $PSScriptRoot }
$script:skillRoot = Split-Path -Parent $script:testsDir
$script:scriptsDir = Join-Path $script:skillRoot "scripts"
$script:testWorkDir = Join-Path $env:TEMP ("okf_test_" + [Guid]::NewGuid().ToString("N"))

Describe "OKF v0.2 PowerShell Scripts Tests" {
    BeforeAll {
        if (-not (Test-Path $script:testWorkDir)) {
            New-Item -Path $script:testWorkDir -ItemType Directory -Force | Out-Null
        }
    }

    AfterAll {
        if (Test-Path $script:testWorkDir) {
            Remove-Item -Path $script:testWorkDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "New-OkfBundle.ps1" {
        It "creates a minimal OKF v0.2 bundle with index.md and log.md" {
            $bundlePath = Join-Path $script:testWorkDir "minimal_bundle"
            & (Join-Path $script:scriptsDir "New-OkfBundle.ps1") -Path $bundlePath -Preset "minimal" -BundleTitle "Minimal Knowledge Base"

            (Test-Path (Join-Path $bundlePath "index.md")) | Should Be $true
            (Test-Path (Join-Path $bundlePath "log.md")) | Should Be $true

            $indexContent = Get-Content (Join-Path $bundlePath "index.md") -Raw
            $indexContent | Should Match 'okf_version:\s*"0\.2"'
        }

        It "creates a preset bundle (system-docs)" {
            $bundlePath = Join-Path $script:testWorkDir "system_bundle"
            & (Join-Path $script:scriptsDir "New-OkfBundle.ps1") -Path $bundlePath -Preset "system-docs" -BundleTitle "System Architecture"

            (Test-Path (Join-Path $bundlePath "architecture")) | Should Be $true
            (Test-Path (Join-Path $bundlePath "components")) | Should Be $true
            (Test-Path (Join-Path $bundlePath "playbooks")) | Should Be $true
        }
    }

    Context "New-OkfConcept.ps1" {
        It "creates a concept with valid frontmatter" {
            $bundlePath = Join-Path $script:testWorkDir "minimal_bundle"
            $conceptPath = Join-Path $bundlePath "concepts/sample-concept.md"
            & (Join-Path $script:scriptsDir "New-OkfConcept.ps1") -Path $conceptPath -Type "Architecture Doc" -Title "Sample Architecture" -Description "Overview of the sample system." -Author "human:testuser"

            (Test-Path $conceptPath) | Should Be $true
            $content = Get-Content $conceptPath -Raw
            $content | Should Match 'type:\s*Architecture Doc'
            $content | Should Match 'title:\s*"Sample Architecture"'
            $content | Should Match 'generated:\s*\{\s*by:\s*human:testuser'
        }
    }

    Context "Test-OkfBundle.ps1" {
        It "passes validation for a well-formed OKF v0.2 bundle" {
            $bundlePath = Join-Path $script:testWorkDir "minimal_bundle"
            $res = & (Join-Path $script:scriptsDir "Test-OkfBundle.ps1") -Path $bundlePath
            $res.IsValid | Should Be $true
            $res.Errors.Count | Should Be 0
        }

        It "detects missing type field in frontmatter" {
            $badBundle = Join-Path $script:testWorkDir "bad_bundle"
            New-Item -Path $badBundle -ItemType Directory -Force | Out-Null
            $badDoc = @"
---
title: Broken Doc
---
# Missing type
"@
            Set-Content -Path (Join-Path $badBundle "broken.md") -Value $badDoc -Encoding utf8
            $res = & (Join-Path $script:scriptsDir "Test-OkfBundle.ps1") -Path $badBundle
            $res.IsValid | Should Be $false
            ($res.Errors -match "Missing required 'type'").Count | Should BeGreaterThan 0
        }

        It "detects broken markdown links" {
            $brokenLinkBundle = Join-Path $script:testWorkDir "broken_link_bundle"
            New-Item -Path $brokenLinkBundle -ItemType Directory -Force | Out-Null
            $doc = @"
---
type: Concept
title: Broken Link
---
See [Missing](/nonexistent/target.md)
"@
            Set-Content -Path (Join-Path $brokenLinkBundle "broken_link.md") -Value $doc -Encoding utf8
            $res = & (Join-Path $script:scriptsDir "Test-OkfBundle.ps1") -Path $brokenLinkBundle -CheckBrokenLinks
            ($res.Warnings -match "Target does not exist").Count | Should BeGreaterThan 0
        }
    }

    Context "Update-OkfIndex.ps1" {
        It "scans concepts and updates index.md" {
            $bundlePath = Join-Path $script:testWorkDir "minimal_bundle"
            & (Join-Path $script:scriptsDir "Update-OkfIndex.ps1") -Path $bundlePath -Recurse
            $indexContent = Get-Content (Join-Path $bundlePath "concepts/index.md") -Raw
            $indexContent | Should Match "Sample Architecture"
        }
    }
}