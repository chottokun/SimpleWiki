<#
.SYNOPSIS
    Scaffolds a new PowerShell project directory layout optimized for distribution.

.DESCRIPTION
    Creates standard project directories (src/, tests/, build/, docs/, dist/),
    along with starter scripts, .gitignore, and build.ps1 packaging automation.

.PARAMETER ProjectPath
    Target directory path for the new project.

.PARAMETER Type
    Project type: 'Tool' (Standalone script/app) or 'Module' (PowerShell module).

.EXAMPLE
    .\New-PowerShellProject.ps1 -ProjectPath "C:\Projects\MyNewTool" -Type Tool
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ProjectPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Tool', 'Module')]
    [string]$Type = 'Tool'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ProjectPath)) {
    New-Item -ItemType Directory -Path $ProjectPath -Force | Out-Null
}

$resolvedProject = Get-Item $ProjectPath
$projectName = $resolvedProject.Name

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Scaffolding PowerShell Project Layout" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Project Name : $projectName"
Write-Host "Location     : $($resolvedProject.FullName)"
Write-Host "Type         : $Type"
Write-Host ""

# Create Directory Structure
$dirs = @('src', 'tests', 'build', 'docs')
foreach ($d in $dirs) {
    $p = Join-Path $resolvedProject.FullName $d
    if (-not (Test-Path $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        Write-Host "[+] Created folder: $d/" -ForegroundColor Green
    }
}

# Create .gitignore
$gitIgnoreContent = @"
# Build and Distribution Artifacts
dist/
*.zip
*.nupkg

# Temporary and Test Outputs
TestResults/
*.log
.vscode/
"@
Set-Content -Path (Join-Path $resolvedProject.FullName '.gitignore') -Value $gitIgnoreContent -Encoding UTF8

# Copy build script template
$skillRoot = Split-Path -Path $PSScriptRoot -Parent
$buildTemplate = Join-Path $skillRoot 'templates\build.ps1.template'
if (Test-Path $buildTemplate) {
    Copy-Item -Path $buildTemplate -Destination (Join-Path $resolvedProject.FullName 'build\build.ps1') -Force
    Write-Host "[+] Created build script: build/build.ps1" -ForegroundColor Green
}

if ($Type -eq 'Tool') {
    # Tool Starter Files
    $srcTool = Join-Path $resolvedProject.FullName "src\$projectName.ps1"
    $starterScript = @"
<#
.SYNOPSIS
    $projectName Application

.DESCRIPTION
    Main entry point for $projectName.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = `$false)]
    [string]`$Target = 'World'
)

# Enforce UTF-8 console output
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
`$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " $projectName v1.0.0" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Hello, `$Target!" -ForegroundColor Yellow
Write-Host "PowerShell Engine: `$(`$PSVersionTable.PSVersion)"
"@
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($srcTool, $starterScript, $utf8Bom)
    Write-Host "[+] Created starter script: src/$projectName.ps1 (UTF-8 with BOM)" -ForegroundColor Green

    # Starter Test
    $testScript = Join-Path $resolvedProject.FullName "tests\$projectName.Tests.ps1"
    $starterTest = @"
Describe '$projectName Tests' {
    It 'Script file exists' {
        Test-Path "`$PSScriptRoot/../src/$projectName.ps1" | Should -Be `$true
    }
}
"@
    [System.IO.File]::WriteAllText($testScript, $starterTest, $utf8Bom)
    Write-Host "[+] Created starter test: tests/$projectName.Tests.ps1" -ForegroundColor Green
} else {
    # Module Starter Structure
    $publicDir = Join-Path $resolvedProject.FullName 'src\Public'
    $privateDir = Join-Path $resolvedProject.FullName 'src\Private'
    New-Item -ItemType Directory -Path $publicDir, $privateDir -Force | Out-Null

    # Starter Manifest & Root Module
    $manifestTemplate = Join-Path $skillRoot 'templates\module-manifest.psd1.template'
    $manifestContent = (Get-Content -Path $manifestTemplate -Raw) `
        -replace '{{MODULE_NAME}}', $projectName `
        -replace '{{MODULE_VERSION}}', '0.1.0' `
        -replace '{{MODULE_GUID}}', ([guid]::NewGuid().ToString()) `
        -replace '{{AUTHOR}}', $env:USERNAME `
        -replace '{{COMPANY_NAME}}', 'Internal' `
        -replace '{{YEAR}}', (Get-Date).Year `
        -replace '{{DESCRIPTION}}', "$projectName module" `
        -replace '{{FUNCTIONS_TO_EXPORT}}', "    'Get-$projectName'"

    $manifestDest = Join-Path $resolvedProject.FullName "src\$projectName.psd1"
    [System.IO.File]::WriteAllText($manifestDest, $manifestContent, (New-Object System.Text.UTF8Encoding($true)))
    Write-Host "[+] Created manifest: src/$projectName.psd1" -ForegroundColor Green
}

Write-Host ""
Write-Host "[SUCCESS] Project scaffolded successfully! Run 'build/build.ps1' to generate dist/ artifacts." -ForegroundColor Green
