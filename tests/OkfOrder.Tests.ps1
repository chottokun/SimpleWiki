# ==============================================================================
#  OkfOrder.Tests.ps1
#  SimpleWiki - OKF Ordered Files Unit Tests
#  Encoding: UTF-8 with BOM
# ==============================================================================

[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingInvokeExpression", "")]
param()

if (-not $script:projectRoot) {
    $script:projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}
$projectRoot = $script:projectRoot

Describe "Get-OkfOrderedFiles Unit Tests (Pester 3.4.0 Compatible)" {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
    }

    It "TC-ORDER-01: Returns files ordered according to index.md links (mixed list styles)" {
        $testDir = Join-Path $TestDrive "tc01"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "overview.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "architecture.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "api-reference.md") -Force | Out-Null

        $indexContent = @"
# Table of Contents
1. [Overview](overview.md)
* [Architecture](architecture.md)
- [API Reference](api-reference.md)
"@
        Set-Content -Path (Join-Path $testDir "index.md") -Value $indexContent -Encoding UTF8

        $result = Get-OkfOrderedFiles -BundleRoot $testDir
        $result.Count | Should Be 3
        $result[0].Name | Should Be "overview.md"
        $result[1].Name | Should Be "architecture.md"
        $result[2].Name | Should Be "api-reference.md"
    }

    It "TC-ORDER-02: Skips dead links in index.md without throwing error" {
        $testDir = Join-Path $TestDrive "tc02"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "real-doc.md") -Force | Out-Null

        $indexContent = @"
# Catalog
1. [Non Existent](ghost-file.md)
2. [Real Doc](real-doc.md)
3. [Another Ghost](missing.md)
"@
        Set-Content -Path (Join-Path $testDir "index.md") -Value $indexContent -Encoding UTF8

        $result = Get-OkfOrderedFiles -BundleRoot $testDir
        $result.Count | Should Be 1
        $result[0].Name | Should Be "real-doc.md"
    }

    It "TC-ORDER-03: Appends unlisted files sorted by filename at the end" {
        $testDir = Join-Path $TestDrive "tc03"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "b-doc.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "a-doc.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "z-doc.md") -Force | Out-Null

        $indexContent = @"
# Catalog
1. [Zeta Doc](z-doc.md)
"@
        Set-Content -Path (Join-Path $testDir "index.md") -Value $indexContent -Encoding UTF8

        $result = Get-OkfOrderedFiles -BundleRoot $testDir
        $result.Count | Should Be 3
        $result[0].Name | Should Be "z-doc.md"
        $result[1].Name | Should Be "a-doc.md"
        $result[2].Name | Should Be "b-doc.md"
    }

    It "TC-ORDER-04: Returns all files sorted by filename when index.md is missing" {
        $testDir = Join-Path $TestDrive "tc04"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "charlie.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "alpha.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "bravo.md") -Force | Out-Null

        $result = Get-OkfOrderedFiles -BundleRoot $testDir
        $result.Count | Should Be 3
        $result[0].Name | Should Be "alpha.md"
        $result[1].Name | Should Be "bravo.md"
        $result[2].Name | Should Be "charlie.md"
    }

    It "TC-ORDER-05: Returns all files sorted by filename when index.md is empty or corrupted" {
        $testDir = Join-Path $TestDrive "tc05"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "charlie.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "alpha.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "index.md") -Force | Out-Null

        $result = Get-OkfOrderedFiles -BundleRoot $testDir
        $result.Count | Should Be 2
        $result[0].Name | Should Be "alpha.md"
        $result[1].Name | Should Be "charlie.md"
    }

    It "TC-ORDER-06: Matches filenames case-insensitively" {
        $testDir = Join-Path $TestDrive "tc06"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "search-score.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "architecture-guide.md") -Force | Out-Null

        $indexContent = @"
1. [Search Score](SEARCH-SCORE.MD)
2. [Architecture](Architecture-Guide.md)
"@
        Set-Content -Path (Join-Path $testDir "index.md") -Value $indexContent -Encoding UTF8

        $result = Get-OkfOrderedFiles -BundleRoot $testDir
        $result.Count | Should Be 2
        $result[0].Name | Should Be "search-score.md"
        $result[1].Name | Should Be "architecture-guide.md"
    }

    It "TC-ORDER-07: Deduplicates multiple links to the same file" {
        $testDir = Join-Path $TestDrive "tc07"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "guide.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "extra.md") -Force | Out-Null

        $indexContent = @"
1. [Guide First Mention](guide.md)
2. [Extra](extra.md)
3. [Guide Repeated Mention](guide.md)
"@
        Set-Content -Path (Join-Path $testDir "index.md") -Value $indexContent -Encoding UTF8

        $result = Get-OkfOrderedFiles -BundleRoot $testDir
        $result.Count | Should Be 2
        $result[0].Name | Should Be "guide.md"
        $result[1].Name | Should Be "extra.md"
    }

    It "TC-ORDER-08: Extracts filenames correctly with dot-slash prefix, anchors, and queries" {
        $testDir = Join-Path $TestDrive "tc08"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "spec.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "faq.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "changelog.md") -Force | Out-Null

        $indexContent = @"
1. [Specification](./spec.md#section-1)
2. [FAQ](faq.md?lang=ja)
3. [Changelog](./changelog.md?version=2#latest)
"@
        Set-Content -Path (Join-Path $testDir "index.md") -Value $indexContent -Encoding UTF8

        $result = Get-OkfOrderedFiles -BundleRoot $testDir
        $result.Count | Should Be 3
        $result[0].Name | Should Be "spec.md"
        $result[1].Name | Should Be "faq.md"
        $result[2].Name | Should Be "changelog.md"
    }

    It "TC-ORDER-09: Includes index.md at the front when -IncludeIndex is specified" {
        $testDir = Join-Path $TestDrive "tc09"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "doc-b.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "doc-a.md") -Force | Out-Null

        $indexContent = @"
1. [Doc A](doc-a.md)
2. [Doc B](doc-b.md)
"@
        Set-Content -Path (Join-Path $testDir "index.md") -Value $indexContent -Encoding UTF8

        # Without -IncludeIndex
        $resultNoIndex = Get-OkfOrderedFiles -BundleRoot $testDir
        $resultNoIndex.Count | Should Be 2
        $resultNoIndex[0].Name | Should Be "doc-a.md"

        # With -IncludeIndex
        $resultWithIndex = Get-OkfOrderedFiles -BundleRoot $testDir -IncludeIndex
        $resultWithIndex.Count | Should Be 3
        $resultWithIndex[0].Name | Should Be "index.md"
        $resultWithIndex[1].Name | Should Be "doc-a.md"
        $resultWithIndex[2].Name | Should Be "doc-b.md"
    }

    It "TC-ORDER-10: Ignores links to subdirectories and does not falsely match root files" {
        $testDir = Join-Path $TestDrive "tc10"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $testDir "api") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "index.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "root-guide.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "api\doc.md") -Force | Out-Null

        $indexContent = @"
1. [API Doc](api/doc.md)
2. [Root Guide](root-guide.md)
"@
        Set-Content -Path (Join-Path $testDir "index.md") -Value $indexContent -Encoding UTF8

        $result = Get-OkfOrderedFiles -BundleRoot $testDir
        # Should only match root-guide.md, api/doc.md should be ignored in root bundle scan
        $result.Count | Should Be 1
        $result[0].Name | Should Be "root-guide.md"
    }

    It "TC-ORDER-11: Handles non-existent BundleRoot gracefully" {
        $result = Get-OkfOrderedFiles -BundleRoot (Join-Path $TestDrive "non_existent_folder_xyz")
        $result.Count | Should Be 0
    }
}

Describe "SimpleWiki Navigation Integration with OKF Order" {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
    }

    It "TC-INT-01: Build-ServerFileTreeNode orders files according to index.md in disk scan mode" {
        $testDir = Join-Path $TestDrive "int01"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "z-last.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "m-middle.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "a-first.md") -Force | Out-Null

        $indexContent = @"
# Table of Contents
1. [Zeta](z-last.md)
2. [Alpha](a-first.md)
"@
        Set-Content -Path (Join-Path $testDir "index.md") -Value $indexContent -Encoding UTF8

        $tree = Build-ServerFileTreeNode -wikiDir $testDir
        # Files should be: index.md (pinned at top), z-last.md, a-first.md, m-middle.md (unlisted at end)
        $tree.Files.Count | Should Be 4
        $tree.Files[0].Name | Should Be "index.md"
        $tree.Files[1].Name | Should Be "z-last.md"
        $tree.Files[2].Name | Should Be "a-first.md"
        $tree.Files[3].Name | Should Be "m-middle.md"
    }

    It "TC-INT-02: Get-ServerFolderTreeHtml preserves OKF order in rendered HTML" {
        $testDir = Join-Path $TestDrive "int02"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "step2.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "step1.md") -Force | Out-Null

        $indexContent = @"
# Steps
1. [Step 2](step2.md)
2. [Step 1](step1.md)
"@
        Set-Content -Path (Join-Path $testDir "index.md") -Value $indexContent -Encoding UTF8

        $tree = Build-ServerFileTreeNode -wikiDir $testDir
        $html = Get-ServerFolderTreeHtml -node $tree -wikiDir $testDir -DisplayMode "basename"

        # Step 2 must appear before Step 1 in the HTML
        $posStep2 = $html.IndexOf("step2")
        $posStep1 = $html.IndexOf("step1")
        $posStep2 | Should BeGreaterThan -1
        $posStep1 | Should BeGreaterThan -1
        ($posStep2 -lt $posStep1) | Should Be $true
    }

    It "TC-INT-03: Get-DirectoryListingHtml displays files in OKF order" {
        $testDir = Join-Path $TestDrive "int03"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "zebra.md") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $testDir "apple.md") -Force | Out-Null

        $indexContent = @"
# List
1. [Zebra](zebra.md)
2. [Apple](apple.md)
"@
        Set-Content -Path (Join-Path $testDir "index.md") -Value $indexContent -Encoding UTF8

        $html = Get-DirectoryListingHtml -DirFullPath $testDir -RawUrlPath "/int03"

        $posZebra = $html.IndexOf("zebra")
        $posApple = $html.IndexOf("apple")
        $posZebra | Should BeGreaterThan -1
        $posApple | Should BeGreaterThan -1
        ($posZebra -lt $posApple) | Should Be $true
    }
}
