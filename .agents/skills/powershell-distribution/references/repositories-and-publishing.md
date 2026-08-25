# Repositories and Publishing Guide

This guide details configuring repositories and publishing modules using both modern (`Microsoft.PowerShell.PSResourceGet`) and legacy (`PowerShellGet`) tooling.

---

## 1. Tooling Comparison

| Feature | `Microsoft.PowerShell.PSResourceGet` (Modern) | `PowerShellGet` v2 (Legacy) |
| :--- | :--- | :--- |
| **Bundled in** | PowerShell 7.4+ | Windows PowerShell 5.1 / PS 7.0-7.3 |
| **Protocol** | NuGet v3 / v2 API (Fast, parallel) | NuGet v2 API (Slower, single-threaded) |
| **Find Command** | `Find-PSResource` | `Find-Module` |
| **Install Command** | `Install-PSResource` | `Install-Module` |
| **Publish Command** | `Publish-PSResource` | `Publish-Module` |
| **Repository Reg** | `Register-PSResourceRepository` | `Register-PSRepository` |

---

## 2. Public Publishing (PowerShell Gallery)

### Using PSResourceGet
```powershell
# Publish module
Publish-PSResource -Path ".\MyModule" -Repository "PSGallery" -ApiKey $env:PSGALLERY_API_KEY
```

### Using PowerShellGet
```powershell
Publish-Module -Path ".\MyModule" -Repository "PSGallery" -NuGetApiKey $env:PSGALLERY_API_KEY
```

---

## 3. Private / Internal Repositories

### Option A: Azure Artifacts (NuGet Feed)
```powershell
# Register Azure DevOps feed
Register-PSResourceRepository -Name "CompanyFeed" `
    -Uri "https://pkgs.dev.azure.com/your-org/_packaging/your-feed/nuget/v3/index.json" `
    -Trusted

# Publish with Personal Access Token (PAT)
Publish-PSResource -Path ".\MyModule" -Repository "CompanyFeed" -ApiKey $env:AZURE_PAT
```

### Option B: Local / Internal SMB File Share (UNC Path)
Ideal for small teams without dedicated artifact management infrastructure:

```powershell
# Register network share
Register-PSResourceRepository -Name "InternalShare" `
    -Uri "\\fileserver\psmodules" `
    -Trusted

# Publish
Publish-PSResource -Path ".\MyModule" -Repository "InternalShare"
```

---

## 4. Package Manager Distribution (WinGet / Chocolatey / Scoop)

For standalone tools, CLI scripts, and utility applications:
- **WinGet**: Submit a YAML manifest to `microsoft/winget-pkgs`.
- **Chocolatey**: Package as `.nupkg` with a `chocolateyInstall.ps1` script calling `Install-ChocolateyPackage`.
- **Scoop**: JSON manifest defining download URL, hash, and `bin` entry points.
