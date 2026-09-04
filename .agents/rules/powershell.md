# PowerShell & Batch Guidelines

## 1. Character Encoding & File Format
- **PowerShell Files (`.ps1`, `.psm1`, `.psd1`)**:
  - Save strictly as **UTF-8 with BOM (`EF BB BF`)** for Windows PowerShell 5.1 compatibility and reliable multi-byte character parsing.
- **Batch Files (`.bat`, `.cmd`)**:
  - Save strictly as **UTF-8 without BOM (No-BOM)**. `cmd.exe` interprets a leading UTF-8 BOM as `・ｿ` causing `'・ｿ@echo'` command failures.
- **Data Files (`.psd1`)**:
  - Keep string values safe for `Import-PowerShellDataFile` (avoid backtick escapes like `` `n `` or unescaped quote syntax inside hashtables).

## 2. Function Design & Naming Conventions
- **Approved Verbs**: Always use official PowerShell approved verbs (`Get-Verb`, e.g., `New-`, `Get-`, `Set-`, `Test-`, `Update-`, `Invoke-`). Never use unapproved verbs like `Create-`, `Check-`, or `Make-`.
- **Advanced Functions**: Use `[CmdletBinding()]` and explicit `param()` blocks with type definitions (`[string]`, `[switch]`, `[string[]]`) and validation attributes (`[ValidateNotNullOrEmpty()]`, `[Parameter(Mandatory)]`).
- **Support `-WhatIf` / `-Confirm`**: Add `SupportsShouldProcess` to `[CmdletBinding()]` whenever functions modify the filesystem or system state.

## 3. Path Handling & Execution Context
- **Script-Relative Paths**: Always resolve paths relative to `$PSScriptRoot` (e.g., `Join-Path $PSScriptRoot "templates"`), rather than relying on current working directory (`Get-Location` / `$pwd`).
- **Safe Path Joining**: Always use `Join-Path` instead of manual string concatenation (e.g., `"$dir\$file"`).

## 4. Pipeline & Output Hygiene
- **Prevent Pipeline Leakage**: Suppress unwanted return values from .NET methods or collection additions using `$null = ...`, `[void]...`, or `| Out-Null`.
- **Stream Discipline**:
  - Use `Write-Output` (or returned objects) strictly for pipeline data intended for downstream consumption.
  - Use `Write-Verbose`, `Write-Warning`, `Write-Information`, and `Write-Error` for diagnostics and logs.
  - Avoid `Write-Host` in reusable functions/scripts (reserve it only for direct interactive CLI banners).

## 5. Error Handling & Robustness
- **Error Action Preference**: Set `$ErrorActionPreference = 'Stop'` at the top of automation scripts and wrap critical operations in `try { ... } catch { ... }`.
- **Native Command Exit Codes**: After executing external commands (`git`, `npm`, `dotnet`, `cmd.exe`), explicitly verify `$LASTEXITCODE -eq 0`.

## 6. Security & Compatibility (Windows PowerShell 5.1)
- **No `Invoke-Expression`**: Never use `Invoke-Expression` (`iex`) on user-supplied strings to avoid command injection vulnerabilities. Use script blocks `& $scriptBlock` or `Start-Process`.
- **PS 5.1 Syntax Compatibility**: Unless explicitly targeting PowerShell 7+, avoid PS 7-only syntax (e.g., ternary operators `$a ? $b : $c` or null-coalescing operators `$a ?? $b`). Use standard `if / else`.

## 7. Testing & Quality Assurance
- **PSScriptAnalyzer**: Run script analysis to catch code smells, rule violations, and security issues.
- **Pester Unit Testing**: Provide Pester unit tests (`*.Tests.ps1`) for all reusable scripts and modules following a TDD approach.
- **Standard Windows 11 / PowerShell 5.1 Compatibility**:
  - Target execution environment assumes **vanilla Windows 11 without external module installations**.
  - All tests must pass cleanly under the **built-in Pester (v3.4.0)** bundled with Windows PowerShell 5.1.
  - **Strictly prohibit hyphenated Pester 5 assertion operators**: Use `Should Be`, `Should Match`, `Should Not Be`, `Should Throw`. **Never use** `Should -Be`, `Should -Match` etc., as they cause fatal runtime exceptions in Pester 3.4.0.
  - Do not introduce dependencies on `Install-Module` for test execution.

