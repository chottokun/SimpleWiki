<#
.SYNOPSIS
    Creates a new OKF (Open Knowledge Format) v0.2 Knowledge Bundle.
.DESCRIPTION
    Initializes a directory tree conformant with OKF v0.2, including root index.md,
    log.md, and optional domain presets (system-docs, team-knowledge, data-catalog, minimal).
.PARAMETER Path
    The target directory path for the bundle.
.PARAMETER Preset
    Preset structure type: minimal, system-docs, team-knowledge, data-catalog.
.PARAMETER BundleTitle
    Human-readable title of the knowledge bundle.
.PARAMETER Actor
    Actor identifier (e.g., 'human:name', 'agent/model-name').
.EXAMPLE
    .\New-OkfBundle.ps1 -Path ".\docs" -Preset "system-docs" -BundleTitle "System Architecture Docs"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [Parameter()]
    [ValidateSet("minimal", "system-docs", "team-knowledge", "data-catalog")]
    [string]$Preset = "minimal",

    [Parameter()]
    [string]$BundleTitle = "Knowledge Bundle",

    [Parameter()]
    [string]$Actor = "human:user"
)

$ErrorActionPreference = "Stop"

$fullPath = [System.IO.Path]::GetFullPath($Path)
if (-not (Test-Path $fullPath)) {
    New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
}

$today = (Get-Date).ToString("yyyy-MM-dd")
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# 1. Root log.md
$logPath = Join-Path $fullPath "log.md"
if (-not (Test-Path $logPath)) {
    $logContent = @"
# Directory Update Log

## $today
* **Initialization**: Initialized OKF v0.2 knowledge bundle with preset '$Preset'.
"@
    [System.IO.File]::WriteAllText($logPath, $logContent, [System.Text.Encoding]::UTF8)
}

# 2. Preset Specific Structure
switch ($Preset) {
    "minimal" {
        $conceptsDir = Join-Path $fullPath "concepts"
        if (-not (Test-Path $conceptsDir)) { New-Item -Path $conceptsDir -ItemType Directory -Force | Out-Null }

        $rootIndex = @"
---
okf_version: "0.2"
---

# $BundleTitle

* [Concepts](concepts/) - Core knowledge concepts and documentation.
"@
        [System.IO.File]::WriteAllText((Join-Path $fullPath "index.md"), $rootIndex, [System.Text.Encoding]::UTF8)

        $conceptIndex = @"
# Concepts

* [Getting Started](getting-started.md) - Introduction to this knowledge base.
"@
        [System.IO.File]::WriteAllText((Join-Path $conceptsDir "index.md"), $conceptIndex, [System.Text.Encoding]::UTF8)

        $gettingStartedDoc = @"
---
type: Guide
title: Getting Started
description: Introduction to this knowledge base.
tags: [onboarding, guide]
status: stable
generated: { by: $Actor, at: $timestamp }
---

# Overview

Welcome to the **$BundleTitle**. This bundle is organized according to the Open Knowledge Format (OKF) v0.2.

# Structure

- All knowledge documents are markdown files with YAML frontmatter containing at least a \`type\` field.
- Reserved files (\`index.md\`, \`log.md\`) provide progressive disclosure and change tracking.
"@
        [System.IO.File]::WriteAllText((Join-Path $conceptsDir "getting-started.md"), $gettingStartedDoc, [System.Text.Encoding]::UTF8)
    }

    "system-docs" {
        $dirs = @("architecture", "components", "playbooks", "references")
        foreach ($d in $dirs) {
            $dirPath = Join-Path $fullPath $d
            if (-not (Test-Path $dirPath)) { New-Item -Path $dirPath -ItemType Directory -Force | Out-Null }
        }

        $rootIndex = @"
---
okf_version: "0.2"
---

# $BundleTitle

## Architecture & Design
* [Architecture](architecture/) - System high-level design, topology, and data flow.
* [Components](components/) - Service modules, API boundaries, and specifications.

## Operations & References
* [Playbooks](playbooks/) - Operational guides, incident response, and runbooks.
* [References](references/) - External references, schema definitions, and assets.
"@
        [System.IO.File]::WriteAllText((Join-Path $fullPath "index.md"), $rootIndex, [System.Text.Encoding]::UTF8)

        # Architecture index & sample
        $archIndex = @"
# Architecture

* [System Overview](overview.md) - High-level system architecture and component interactions.
"@
        [System.IO.File]::WriteAllText((Join-Path $fullPath "architecture/index.md"), $archIndex, [System.Text.Encoding]::UTF8)

        $archOverview = @"
---
type: Architecture Overview
title: System Overview
description: High-level system architecture and component interactions.
tags: [architecture, design, overview]
status: stable
generated: { by: $Actor, at: $timestamp }
---

# System Architecture

Describes the end-to-end architecture.

# Components

See the individual [Components](/components/) for deep dives.
"@
        [System.IO.File]::WriteAllText((Join-Path $fullPath "architecture/overview.md"), $archOverview, [System.Text.Encoding]::UTF8)

        # Components index
        $compIndex = @"
# Components

* [Core Service](core-service.md) - Main backend orchestration service.
"@
        [System.IO.File]::WriteAllText((Join-Path $fullPath "components/index.md"), $compIndex, [System.Text.Encoding]::UTF8)

        $compDoc = @"
---
type: Service
title: Core Service
description: Main backend orchestration service.
tags: [backend, service]
status: stable
generated: { by: $Actor, at: $timestamp }
---

# Schema & Interfaces

# Examples
"@
        [System.IO.File]::WriteAllText((Join-Path $fullPath "components/core-service.md"), $compDoc, [System.Text.Encoding]::UTF8)

        # Playbooks index
        $playIndex = @"
# Playbooks

* [Incident Response](incident-response.md) - Standard operational triage and recovery steps.
"@
        [System.IO.File]::WriteAllText((Join-Path $fullPath "playbooks/index.md"), $playIndex, [System.Text.Encoding]::UTF8)

        $playDoc = @"
---
type: Playbook
title: Incident Response
description: Standard operational triage and recovery steps.
tags: [oncall, playbook, operations]
status: stable
generated: { by: $Actor, at: $timestamp }
---

# Trigger

# Steps
"@
        [System.IO.File]::WriteAllText((Join-Path $fullPath "playbooks/incident-response.md"), $playDoc, [System.Text.Encoding]::UTF8)

        # References index
        $refIndex = @"
# References

External specifications and mirrored documentation.
"@
        [System.IO.File]::WriteAllText((Join-Path $fullPath "references/index.md"), $refIndex, [System.Text.Encoding]::UTF8)
    }

    "team-knowledge" {
        $dirs = @("guidelines", "policies", "processes", "onboarding")
        foreach ($d in $dirs) {
            $dirPath = Join-Path $fullPath $d
            if (-not (Test-Path $dirPath)) { New-Item -Path $dirPath -ItemType Directory -Force | Out-Null }
        }

        $rootIndex = @"
---
okf_version: "0.2"
---

# $BundleTitle

* [Guidelines](guidelines/) - Coding, style, and engineering standards.
* [Policies](policies/) - Team governance, security, and compliance policies.
* [Processes](processes/) - Release workflows, code reviews, and meeting cadences.
* [Onboarding](onboarding/) - New hire guides and environment setup.
"@
        [System.IO.File]::WriteAllText((Join-Path $fullPath "index.md"), $rootIndex, [System.Text.Encoding]::UTF8)

        foreach ($d in $dirs) {
            $subIndex = "# $(Get-Culture).TextInfo.ToTitleCase($d)`n`n"
            [System.IO.File]::WriteAllText((Join-Path $fullPath "$d/index.md"), $subIndex, [System.Text.Encoding]::UTF8)
        }
    }

    "data-catalog" {
        $dirs = @("datasets", "tables", "metrics", "computations", "references")
        foreach ($d in $dirs) {
            $dirPath = Join-Path $fullPath $d
            if (-not (Test-Path $dirPath)) { New-Item -Path $dirPath -ItemType Directory -Force | Out-Null }
        }

        $rootIndex = @"
---
okf_version: "0.2"
---

# $BundleTitle

## Data Assets
* [Datasets](datasets/) - Logical collections of data tables and views.
* [Tables](tables/) - Table schemas, partition definitions, and relationships.

## Metrics & Computations
* [Metrics](metrics/) - Business metric definitions and semantics.
* [Computations](computations/) - Sanctioned, attested computations.
"@
        [System.IO.File]::WriteAllText((Join-Path $fullPath "index.md"), $rootIndex, [System.Text.Encoding]::UTF8)

        foreach ($d in $dirs) {
            $subIndex = "# $(Get-Culture).TextInfo.ToTitleCase($d)`n`n"
            [System.IO.File]::WriteAllText((Join-Path $fullPath "$d/index.md"), $subIndex, [System.Text.Encoding]::UTF8)
        }
    }
}

Write-Host "Created OKF v0.2 Knowledge Bundle at: $fullPath (Preset: $Preset)"