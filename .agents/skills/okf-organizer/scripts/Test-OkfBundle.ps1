<#
.SYNOPSIS
    Validates an OKF (Open Knowledge Format) v0.2 Knowledge Bundle.
.DESCRIPTION
    Inspects all markdown files within a bundle for OKF v0.2 conformance:
    - YAML Frontmatter presence and required `type` field on concept docs.
    - Reserved filenames (index.md, log.md) structure.
    - Sources and footnotes cross-referencing.
    - Optional broken links detection.
.PARAMETER Path
    Root directory path of the OKF bundle.
.PARAMETER CheckBrokenLinks
    Switch to inspect and report broken internal markdown links as warnings.
.OUTPUTS
    PSCustomObject containing IsValid, Errors, Warnings, and ConceptCount.
.EXAMPLE
    .\Test-OkfBundle.ps1 -Path ".\docs" -CheckBrokenLinks
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [Parameter()]
    [switch]$CheckBrokenLinks
)

$ErrorActionPreference = "Stop"
$bundleRoot = [System.IO.Path]::GetFullPath($Path)

if (-not (Test-Path $bundleRoot)) {
    throw "Bundle directory does not exist: $bundleRoot"
}

$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$conceptCount = 0

$allMdFiles = Get-ChildItem -Path $bundleRoot -Filter "*.md" -Recurse -File

function Parse-Frontmatter {
    param([string]$FilePath)
    $content = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
    if ($content -match '^\s*---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)') {
        return @{
            HasFrontmatter = $true
            FrontmatterRaw = $matches[1]
            Body           = $matches[2]
        }
    }
    return @{
        HasFrontmatter = $false
        FrontmatterRaw = ""
        Body           = $content
    }
}

function Get-YamlField {
    param([string]$YamlRaw, [string]$FieldName)
    if ($YamlRaw -match "(?m)^$FieldName\s*:\s*(.+)$") {
        $val = $matches[1].Trim()
        # strip quotes if wrapped
        if (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'"))) {
            $val = $val.Substring(1, $val.Length - 2)
        }
        return $val
    }
    return $null
}

foreach ($file in $allMdFiles) {
    $relPath = $file.FullName.Substring($bundleRoot.Length).TrimStart('\', '/')
    $fileName = $file.Name
    $isRoot = ($file.DirectoryName -eq $bundleRoot)

    $parsed = Parse-Frontmatter -FilePath $file.FullName

    if ($fileName -eq "index.md") {
        # index.md validation
        if ($parsed.HasFrontmatter) {
            if (-not $isRoot) {
                $errors.Add("Non-root index file '$relPath' MUST NOT contain YAML frontmatter.")
            } else {
                $version = Get-YamlField -YamlRaw $parsed.FrontmatterRaw -FieldName "okf_version"
                if (-not $version) {
                    $warnings.Add("Root index.md frontmatter does not specify okf_version.")
                }
            }
        }
    } elseif ($fileName -eq "log.md") {
        # log.md validation
        if ($parsed.HasFrontmatter) {
            $errors.Add("Log file '$relPath' MUST NOT contain YAML frontmatter.")
        }
        if ($parsed.Body -notmatch '(?m)^##\s+\d{4}-\d{2}-\d{2}') {
            $warnings.Add("Log file '$relPath' should contain ISO 8601 date headings (e.g. '## YYYY-MM-DD').")
        }
    } else {
        # Concept document validation
        $conceptCount++

        if (-not $parsed.HasFrontmatter) {
            $errors.Add("Concept document '$relPath' is missing YAML frontmatter (delimited by ---).")
            continue
        }

        $typeVal = Get-YamlField -YamlRaw $parsed.FrontmatterRaw -FieldName "type"
        if ([string]::IsNullOrWhiteSpace($typeVal)) {
            $errors.Add("Concept document '$relPath': Missing required 'type' field in frontmatter.")
        }

        $statusVal = Get-YamlField -YamlRaw $parsed.FrontmatterRaw -FieldName "status"
        if ($statusVal -and ($statusVal -notin @("draft", "stable", "deprecated"))) {
            $warnings.Add("Concept document '$relPath': 'status' is '$statusVal', expected draft, stable, or deprecated.")
        }

        # Check footnotes matching sources
        if ($parsed.FrontmatterRaw -match '(?m)^\s*sources\s*:') {
            $sourceIds = [System.Collections.Generic.List[string]]::new()
            $srcMatches = [regex]::Matches($parsed.FrontmatterRaw, '(?m)^\s*-\s*id\s*:\s*([^\s]+)')
            foreach ($m in $srcMatches) {
                $sourceIds.Add($m.Groups[1].Value)
            }

            $fnMatches = [regex]::Matches($parsed.Body, '\[\^([a-zA-Z0-9_-]+)\]')
            foreach ($fn in $fnMatches) {
                $fnId = $fn.Groups[1].Value
                if ($sourceIds.Count -gt 0 -and ($fnId -notin $sourceIds)) {
                    $warnings.Add("Concept document '$relPath': Footnote '[^$fnId]' has no matching source id in frontmatter.")
                }
            }
        }
    }

    # Broken links check
    if ($CheckBrokenLinks) {
        $linkMatches = [regex]::Matches($parsed.Body, '\[([^\]]+)\]\(([^)]+)\)')
        foreach ($lm in $linkMatches) {
            $linkTarget = $lm.Groups[2].Value.Trim()
            # Ignore web URLs, anchors, mailto
            if ($linkTarget -match '^(https?://|mailto:|#)') { continue }

            $resolvedTarget = $null
            if ($linkTarget.StartsWith("/")) {
                # Bundle-relative
                $cleanTarget = $linkTarget.TrimStart('/').Split('#')[0]
                $resolvedTarget = Join-Path $bundleRoot $cleanTarget
            } else {
                # Relative
                $cleanTarget = $linkTarget.Split('#')[0]
                $resolvedTarget = Join-Path $file.DirectoryName $cleanTarget
            }

            if ($resolvedTarget -and (-not (Test-Path $resolvedTarget))) {
                $warnings.Add("Link in '$relPath' to '$linkTarget': Target does not exist ($resolvedTarget).")
            }
        }
    }
}

$isValid = ($errors.Count -eq 0)

$result = [PSCustomObject]@{
    BundleRoot   = $bundleRoot
    IsValid      = $isValid
    ConceptCount = $conceptCount
    Errors       = $errors.ToArray()
    Warnings     = $warnings.ToArray()
}

if ($isValid) {
    Write-Host "[OK] OKF v0.2 Bundle is Valid ($conceptCount concepts checked)." -ForegroundColor Green
} else {
    Write-Host "[FAIL] Found $($errors.Count) errors in OKF Bundle." -ForegroundColor Red
    foreach ($err in $errors) {
        Write-Host "  - Error: $err" -ForegroundColor Red
    }
}

if ($warnings.Count -gt 0) {
    Write-Host "[WARN] $($warnings.Count) warning(s) found:" -ForegroundColor Yellow
    foreach ($warn in $warnings) {
        Write-Host "  - Warning: $warn" -ForegroundColor Yellow
    }
}

return $result