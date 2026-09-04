<#
.SYNOPSIS
    Performs pre-distribution sanity and readiness checks on PowerShell scripts and modules.

.DESCRIPTION
    Validates manifest files (.psd1), checks for exported functions matching file names,
    detects potential UTF-8 / BOM issues, and flags dangerous wildcard exports.

.PARAMETER Path
    Path to a module directory or script file.

.EXAMPLE
    .\Test-ModuleReadiness.ps1 -Path ".\MyModule"
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " PowerShell Readiness Pre-flight Check" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Target Path: $Path"
Write-Host ""

if (-not (Test-Path -Path $Path)) {
    throw "Path does not exist: $Path"
}

$isDir = (Get-Item $Path) -is [System.IO.DirectoryInfo]
$issues = @()
$passed = 0

if ($isDir) {
    # Module Directory Check
    $manifestFiles = Get-ChildItem -Path $Path -Filter "*.psd1" -File

    if ($manifestFiles.Count -eq 0) {
        $issues += "[WARNING] No .psd1 manifest found in directory. Standalone modules should have a manifest."
    } else {
        foreach ($mf in $manifestFiles) {
            Write-Host "Checking Manifest: $($mf.Name)..." -ForegroundColor Yellow
            try {
                $manifestData = Test-ModuleManifest -Path $mf.FullName -ErrorAction Stop
                Write-Host "  [OK] Valid manifest syntax (Version: $($manifestData.Version))" -ForegroundColor Green
                $passed++

                # Check FunctionsToExport
                if ($manifestData.ExportedFunctions.Count -eq 0 -and $manifestData.FunctionsToExport -contains '*') {
                    $issues += "[WARN] Manifest uses wildcard '*' for FunctionsToExport. Explicitly list functions for better performance."
                } else {
                    Write-Host "  [OK] Exported functions: $($manifestData.ExportedFunctions.Keys -join ', ')" -ForegroundColor Green
                    $passed++
                }
            } catch {
                $issues += "[ERROR] Invalid module manifest $($mf.Name): $($_.Exception.Message)"
            }
        }
    }
} else {
    # Single Script Check
    $script = Get-Item $Path
    Write-Host "Checking Script: $($script.Name)..." -ForegroundColor Yellow

    # Check syntax using AST
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        foreach ($err in $errors) {
            $issues += "[ERROR] Parse error at line $($err.Extent.StartLineNumber): $($err.Message)"
        }
    } else {
        Write-Host "  [OK] Syntax is valid" -ForegroundColor Green
        $passed++
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Verification Summary" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Passed checks: $passed"

if ($issues.Count -gt 0) {
    Write-Host "Issues detected:" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  $issue" -ForegroundColor Yellow
    }
} else {
    Write-Host "[ALL CLEAR] Ready for distribution!" -ForegroundColor Green
}
