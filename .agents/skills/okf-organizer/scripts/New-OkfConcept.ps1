<#
.SYNOPSIS
    Creates a new OKF (Open Knowledge Format) v0.2 concept document.
.DESCRIPTION
    Generates a concept markdown file with compliant YAML frontmatter.
.PARAMETER Path
    Target markdown file path.
.PARAMETER Type
    Required concept type (e.g., Guide, Architecture Doc, Service, Metric, Playbook, Attested Computation).
.PARAMETER Title
    Display title of the concept.
.PARAMETER Description
    Single-sentence summary of the concept.
.PARAMETER Resource
    Optional canonical URI or asset path.
.PARAMETER Tags
    Array of category tags.
.PARAMETER Status
    Lifecycle status: draft, stable, deprecated.
.PARAMETER Author
    Actor who generated the concept (e.g., 'human:name', 'agent/model').
.PARAMETER Runtime
    Runtime environment for Attested Computation concepts (e.g., bigquery, postgres, python, dbt).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Type,

    [Parameter()]
    [string]$Title,

    [Parameter()]
    [string]$Description,

    [Parameter()]
    [string]$Resource,

    [Parameter()]
    [string[]]$Tags,

    [Parameter()]
    [ValidateSet("draft", "stable", "deprecated")]
    [string]$Status = "stable",

    [Parameter()]
    [string]$Author = "human:user",

    [Parameter()]
    [string]$Runtime
)

$ErrorActionPreference = "Stop"

$fullPath = [System.IO.Path]::GetFullPath($Path)
$parentDir = Split-Path -Parent $fullPath
if ($parentDir -and (-not (Test-Path $parentDir))) {
    New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
}

if (-not $Title) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fullPath)
    $cleanName = $baseName -replace '[-_]', ' '
    $Title = (Get-Culture).TextInfo.ToTitleCase($cleanName)
}

$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$frontmatterLines = [System.Collections.Generic.List[string]]::new()
$frontmatterLines.Add("---")
$frontmatterLines.Add("type: $Type")
if ($Title) { $frontmatterLines.Add("title: `"$Title`"") }
if ($Description) { $frontmatterLines.Add("description: `"$Description`"") }
if ($Resource) { $frontmatterLines.Add("resource: $Resource") }
if ($Tags -and $Tags.Count -gt 0) {
    $tagList = ($Tags | ForEach-Object { "$_" }) -join ", "
    $frontmatterLines.Add("tags: [$tagList]")
}
$frontmatterLines.Add("status: $Status")
$frontmatterLines.Add("generated: { by: $Author, at: $timestamp }")

$rt = if ($Runtime) { $Runtime } else { "python" }
if ($Type -eq "Attested Computation" -or $Runtime) {
    $frontmatterLines.Add("runtime: $rt")
    $frontmatterLines.Add("parameters: []")
}

$frontmatterLines.Add("---")
$frontmatterLines.Add("")

$bodyLines = [System.Collections.Generic.List[string]]::new()
$bodyLines.Add("# $Title")
$bodyLines.Add("")
if ($Description) {
    $bodyLines.Add($Description)
    $bodyLines.Add("")
}

if ($Type -eq "Attested Computation") {
    $bodyLines.Add("# Computation")
    $bodyLines.Add("")
    $bodyLines.Add('```' + $rt)
    $bodyLines.Add("# Sanctioned computation logic")
    $bodyLines.Add('```')
} else {
    $bodyLines.Add("# Details")
    $bodyLines.Add("")
    $bodyLines.Add("Add content here.")
}

$allLines = [System.Collections.Generic.List[string]]::new()
$allLines.AddRange($frontmatterLines)
$allLines.AddRange($bodyLines)
$fileContent = $allLines -join "`n"

[System.IO.File]::WriteAllText($fullPath, $fileContent, [System.Text.Encoding]::UTF8)
Write-Host "Created OKF concept at: $fullPath"