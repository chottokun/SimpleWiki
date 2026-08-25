# Module Manifest and Versioning Guidelines

This guide covers authoring PowerShell Module Manifests (`.psd1`), structuring module repositories, and adhering to Semantic Versioning (SemVer).

---

## 1. Directory Structure

```
MyModule/
├── MyModule.psd1           # Manifest file (defines exports, version, dependencies)
├── MyModule.psm1           # Root module (loads public/private functions)
├── Public/                 # Functions exported to module consumers
│   ├── Get-MyItem.ps1
│   └── Set-MyItem.ps1
├── Private/                # Internal helper functions (not exported)
│   └── Test-IsInternal.ps1
└── en-US/                  # Localization strings and markdown help
    └── about_MyModule.help.txt
```

---

## 2. Manifest (`.psd1`) Best Practices

### 2.1 Explicit Exports (Never use wildcard `*`)
Wildcard exports (`FunctionsToExport = '*'`) force PowerShell to parse all files during module discovery, significantly slowing down startup and command completion.

```powershell
# BAD
FunctionsToExport = '*'

# GOOD
FunctionsToExport = @(
    'Get-MyItem',
    'Set-MyItem'
)
CmdletsToExport   = @()
VariablesToExport = @()
AliasesToExport   = @()
```

### 2.2 Compatible Editions & PowerShell Versions
Declare runtime compatibility explicitly:

```powershell
PowerShellVersion    = '5.1'
CompatiblePSEditions = @('Desktop', 'Core')
```

### 2.3 Semantic Versioning (SemVer)
- **Patch (`1.0.x`)**: Bug fixes, documentation updates, non-breaking internal optimizations.
- **Minor (`1.x.0`)**: New functions or backward-compatible parameter additions.
- **Major (`x.0.0`)**: Breaking changes, removed functions/parameters, altered output types.

---

## 3. Dynamic Function Loading in `.psm1`

A clean root module (`.psm1`) dynamically dot-sources `Public` and `Private` functions:

```powershell
$Public  = @(Get-ChildItem -Path "$PSScriptRoot/Public/*.ps1" -ErrorAction SilentlyContinue)
$Private = @(Get-ChildItem -Path "$PSScriptRoot/Private/*.ps1" -ErrorAction SilentlyContinue)

foreach ($script in @($Private + $Public)) {
    try {
        . $script.FullName
    }
    catch {
        Write-Error "Failed to load $($script.FullName): $_"
    }
}
```
