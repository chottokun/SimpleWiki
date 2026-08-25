<#
.SYNOPSIS
    Updates index.md and log.md files within an OKF v0.2 Knowledge Bundle.
.DESCRIPTION
    Scans concept documents in directories, extracts title and description from frontmatter,
    and updates index.md files for progressive disclosure. Optionally logs changes to log.md.
.PARAMETER Path
    Root or specific directory to update.
.PARAMETER Recurse
    If specified, updates index.md across all subdirectories.
.PARAMETER LogMessage
    Optional message to append to the root log.md.
.PARAMETER LogType
    Log category: Update, Creation, Deprecation, Refactor (default: Update).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [Parameter()]
    [switch]$Recurse,

    [Parameter()]
    [string]$LogMessage,

    [Parameter()]
    [ValidateSet("Update", "Creation", "Deprecation", "Refactor")]
    [string]$LogType = "Update"
)

$ErrorActionPreference = "Stop"
$targetDir = [System.IO.Path]::GetFullPath($Path)

if (-not (Test-Path $targetDir)) {
    throw "Target directory does not exist: $targetDir"
}

function Parse-FrontmatterMetadata {
    param([string]$FilePath)
    $content = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
    $title = $null
    $desc = $null
    $version = $null

    if ($content -match '^\s*---\r?\n([\s\S]*?)\r?\n---\r?\n?') {
        $fm = $matches[1]
        if ($fm -match '(?m)^title\s*:\s*(.+)$') {
            $title = $matches[1].Trim().Trim('"', "'")
        }
        if ($fm -match '(?m)^description\s*:\s*(.+)$') {
            $desc = $matches[1].Trim().Trim('"', "'")
        }
        if ($fm -match '(?m)^okf_version\s*:\s*(.+)$') {
            $version = $matches[1].Trim().Trim('"', "'")
        }
    }

    if (-not $title) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        $cleanBase = $base -replace '[-_]', ' '
        $title = (Get-Culture).TextInfo.ToTitleCase($cleanBase)
    }

    return @{
        Title       = $title
        Description = $desc
        OkfVersion  = $version
    }
}

function Update-SingleDirectoryIndex {
    param([string]$DirectoryPath, [bool]$IsRoot)

    $indexFile = Join-Path $DirectoryPath "index.md"
    $existingVersion = "0.2"
    if (Test-Path $indexFile) {
        $meta = Parse-FrontmatterMetadata -FilePath $indexFile
        if ($meta.OkfVersion) { $existingVersion = $meta.OkfVersion }
    }

    $dirName = Split-Path -Leaf $DirectoryPath
    $cleanDir = $dirName -replace '[-_]', ' '
    $sectionTitle = if ($IsRoot) { "Index" } else { (Get-Culture).TextInfo.ToTitleCase($cleanDir) }

    # Subdirectories
    $subDirs = Get-ChildItem -Path $DirectoryPath -Directory | Where-Object { $_.Name -notmatch '^\.' }
    # Markdown concept files (excluding index.md and log.md)
    $mdFiles = Get-ChildItem -Path $DirectoryPath -File -Filter "*.md" | Where-Object { $_.Name -notin @("index.md", "log.md") }

    $lines = [System.Collections.Generic.List[string]]::new()

    if ($IsRoot) {
        $lines.Add("---")
        $lines.Add("okf_version: `"$existingVersion`"")
        $lines.Add("---")
        $lines.Add("")
    }

    $lines.Add("# $sectionTitle")
    $lines.Add("")

    if ($subDirs.Count -gt 0) {
        $lines.Add("## Subdirectories")
        $lines.Add("")
        foreach ($sd in $subDirs) {
            $sdClean = $sd.Name -replace '[-_]', ' '
            $sdName = (Get-Culture).TextInfo.ToTitleCase($sdClean)
            $lines.Add("* [$sdName]($($sd.Name)/) - Documentation in $($sd.Name).")
        }
        $lines.Add("")
    }

    if ($mdFiles.Count -gt 0) {
        if ($subDirs.Count -gt 0) {
            $lines.Add("## Concepts & Documents")
            $lines.Add("")
        }
        foreach ($mf in $mdFiles) {
            $meta = Parse-FrontmatterMetadata -FilePath $mf.FullName
            $descSuffix = if ($meta.Description) { " - $($meta.Description)" } else { "" }
            $lines.Add("* [$($meta.Title)]($($mf.Name))$descSuffix")
        }
        $lines.Add("")
    }

    $content = $lines -join "`n"
    [System.IO.File]::WriteAllText($indexFile, $content, [System.Text.Encoding]::UTF8)
    Write-Host "Updated index at: $indexFile"
}

if ($Recurse) {
    $allDirs = @($targetDir) + @(Get-ChildItem -Path $targetDir -Directory -Recurse | Where-Object { $_.FullName -notmatch '[\\/]\.' } | Select-Object -ExpandProperty FullName)
    foreach ($d in $allDirs) {
        $isRoot = ($d -eq $targetDir)
        Update-SingleDirectoryIndex -DirectoryPath $d -IsRoot $isRoot
    }
} else {
    Update-SingleDirectoryIndex -DirectoryPath $targetDir -IsRoot $true
}

# Optional log update
if ($LogMessage) {
    $logFile = Join-Path $targetDir "log.md"
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $logEntry = "* **$LogType**: $LogMessage"

    if (Test-Path $logFile) {
        $logContent = [System.IO.File]::ReadAllText($logFile, [System.Text.Encoding]::UTF8)
        if ($logContent -match "(?m)^##\s+$today") {
            # Append under today's heading
            $logContent = $logContent -replace "(?m)(^##\s+$today\r?\n)", "`$1$logEntry`n"
        } else {
            # Add new heading under main title
            $logContent = $logContent -replace "(?m)(^#\s+Directory Update Log\r?\n)", "`$1`n## $today`n$logEntry`n"
        }
        [System.IO.File]::WriteAllText($logFile, $logContent, [System.Text.Encoding]::UTF8)
    } else {
        $newLog = @"
# Directory Update Log

## $today
$logEntry
"@
        [System.IO.File]::WriteAllText($logFile, $newLog, [System.Text.Encoding]::UTF8)
    }
    Write-Host "Updated log at: $logFile"
}