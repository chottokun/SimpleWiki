---
name: powershell-distribution
description: Orchestrates PowerShell script and module distribution, batch file wrappers (.bat/.cmd), double-click runners, UAC elevation launchers, single-file polyglot scripts, installers, and module repository publishing (PSResourceGet, PSGallery, Azure Artifacts). Activate whenever the user wants to distribute, package, deploy, publish, or wrap PowerShell scripts, or asks about making PowerShell scripts executable for end-users, handling ExecutionPolicy, creating batch launchers, or releasing PowerShell modules.
---

# PowerShell Distribution & Packaging Skill

This skill provides workflow patterns, template generators, and validation tools for packaging, wrapping, and distributing PowerShell scripts and modules.

---

## 1. Quick Decision Matrix

Select the right distribution pattern based on the target audience and deployment goal:

| Target Audience / Need | Recommended Pattern | Tool / Template |
| :--- | :--- | :--- |
| **Non-technical end-users** (Double-click GUI / CLI) | Batch Launcher Wrapper (`.bat`) | `New-BatchPackage.ps1` or `launcher-basic.bat.template` |
| **Admin tasks requiring elevation** | UAC Auto-Elevating Launcher | `launcher-elevated.bat.template` |
| **Strict single-file distribution** | Hybrid Batch/PowerShell Polyglot | `hybrid-single-file.bat.template` |
| **Internal deployment / Desktop shortcut** | Standalone Directory Installer | `installer.bat.template` |
| **Developer / DevOps package** (NuGet, Gallery) | PowerShell Module (`.psd1` / `.psm1`) | `New-PowerShellProject.ps1` + `build.ps1.template` |
| **CI/CD Automated packaging** | Automated Zip & Hash pipeline | `build.ps1.template` |

---

## 2. Core Distribution Workflows

### Pattern A: Generating a Batch Wrapper for Existing Scripts

When you have a `.ps1` script (e.g. `Start-App.ps1` or `Export-Data.ps1`) and want non-technical users to execute it without ExecutionPolicy prompts:

```powershell
powershell -ExecutionPolicy Bypass -File .\.agents\skills\powershell-distribution\scripts\New-BatchPackage.ps1 `
    -ScriptPath ".\Start-App.ps1" `
    -NoExit `
    -CreateZip
```

This creates:
1. `Start-App.bat` (UTF-8 without BOM, bypasses ExecutionPolicy, auto-detects `pwsh.exe` or `powershell.exe`).
2. A `.zip` release package containing the `.bat`, `.ps1`, and dependencies with a SHA256 checksum file.

### Pattern B: Scaffolding a New Distributable Project

To start a new project with best-practice structure (`src/`, `tests/`, `build/`, `dist/`):

```powershell
powershell -ExecutionPolicy Bypass -File .\.agents\skills\powershell-distribution\scripts\New-PowerShellProject.ps1 `
    -ProjectPath ".\MyTool" `
    -Type "Tool" `
    -Author "Dev Team"
```

### Pattern C: Publishing a PowerShell Module to a Repository

1. **Validate Readiness**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\.agents\skills\powershell-distribution\scripts\Test-ModuleReadiness.ps1 `
       -ModulePath ".\MyModule"
   ```
2. **Publish**:
   - **PSGallery**:
     ```powershell
     Publish-Module -Path ".\MyModule" -Repository "PSGallery" -NuGetApiKey $ApiKey
     ```

---

## 3. Bundled Resources & References

### References
- [Project Structure & Build Pipelines](references/project-structure-and-build.md): Clean separation of source code (`src/`), tests (`tests/`), and distributable artifacts (`dist/`).
- [Encoding & 5.1/7+ Compatibility](references/encoding-and-compatibility.md): Japanese character encoding (UTF-8 BOM rule) and cross-version compatibility.
- [Batch Distribution Patterns](references/batch-distribution-patterns.md): In-depth guide on launcher techniques, UAC elevation, encoding, and exit codes.
- [Manifest & Versioning](references/manifest-and-versioning.md): Best practices for `.psd1` manifests, Semantic Versioning, and module layout.
- [Repositories & Publishing](references/repositories-and-publishing.md): Setup and publishing to PSGallery, Azure Artifacts, internal SMB shares, and WinGet.
- [Signing & Security](references/signing-and-security.md): Authenticode code signing, execution policy governance, and supply chain security.

### Templates
- [build.ps1.template](templates/build.ps1.template): Clean build script automating tests, UTF-8 BOM enforcement, batch generation, and zip packaging.
- [launcher-basic.bat.template](templates/launcher-basic.bat.template): Standard double-click runner with pwsh/powershell auto-selection.
- [launcher-elevated.bat.template](templates/launcher-elevated.bat.template): UAC auto-elevation wrapper.
- [hybrid-single-file.bat.template](templates/hybrid-single-file.bat.template): Single-file Batch/PowerShell polyglot.
- [installer.bat.template](templates/installer.bat.template): Local deployment and shortcut creation script.
- [module-manifest.psd1.template](templates/module-manifest.psd1.template): Production-ready module manifest.

### Scripts
- [New-PowerShellProject.ps1](scripts/New-PowerShellProject.ps1): Scaffolds clean project directories (`src/`, `tests/`, `build/`, `dist/`) ready for distribution.
- [New-BatchPackage.ps1](scripts/New-BatchPackage.ps1): CLI tool to generate batch wrappers and zip packages from existing scripts.
- [Test-ModuleReadiness.ps1](scripts/Test-ModuleReadiness.ps1): Pre-flight static analysis and manifest sanity checker.
