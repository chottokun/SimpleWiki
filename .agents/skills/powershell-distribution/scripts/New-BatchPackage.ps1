<#
.SYNOPSIS
    Generates best-practice batch file wrappers (.bat) for PowerShell scripts.

.DESCRIPTION
    Creates standardized, production-ready batch launchers with ExecutionPolicy bypass,
    UTF-8 encoding, pwsh/powershell auto-selection, and optional UAC elevation or single-file hybrid embedding.

.PARAMETER ScriptPath
    Path to the target PowerShell script (.ps1).

.PARAMETER OutputPath
    Optional output path for the generated batch file or package. Defaults to the same folder as ScriptPath.

.PARAMETER Type
    Type of batch wrapper to generate:
    - Basic: Standard double-click runner (.bat + .ps1).
    - Elevated: Auto-elevating UAC administrator prompt launcher.
    - Hybrid: Single-file combined batch + PowerShell polyglot.
    - Installer: Deployment script that copies files and creates desktop shortcut.

.PARAMETER IncludePause
    If specified, adds a pause prompt at the end of execution to keep the console open for viewing output.

.PARAMETER CreateZip
    If specified, archives the resulting script and batch file into a distributable .zip package.

.EXAMPLE
    .\New-BatchPackage.ps1 -ScriptPath ".\MyTool.ps1" -Type Basic -IncludePause
    Generates "MyTool.bat" alongside "MyTool.ps1".

.EXAMPLE
    .\New-BatchPackage.ps1 -ScriptPath ".\Setup.ps1" -Type Elevated
    Generates an auto-elevating UAC launcher "Setup.bat".

.EXAMPLE
    .\New-BatchPackage.ps1 -ScriptPath ".\Diagnostics.ps1" -Type Hybrid
    Generates a single self-contained "Diagnostics.bat".
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ScriptPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Basic', 'Elevated', 'Hybrid', 'Installer')]
    [string]$Type = 'Basic',

    [Parameter(Mandatory = $false)]
    [switch]$IncludePause,

    [Parameter(Mandatory = $false)]
    [switch]$CreateZip
)

$ErrorActionPreference = 'Stop'

# Resolve Script Path
if (-not (Test-Path -Path $ScriptPath)) {
    throw "Target script not found: $ScriptPath"
}

$resolvedScript = Get-Item -Path $ScriptPath
$scriptDir = $resolvedScript.DirectoryName
$scriptBaseName = $resolvedScript.BaseName
$scriptFileName = $resolvedScript.Name

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $targetBatPath = Join-Path $scriptDir "$scriptBaseName.bat"
} else {
    $targetBatPath = $OutputPath
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Generating PowerShell Distribution Batch" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Source Script : $ScriptPath"
Write-Host "Target Batch  : $targetBatPath"
Write-Host "Wrapper Type  : $Type"
Write-Host ""

$pauseBlock = if ($IncludePause) {
    "`necho.`necho Process completed (Exit Code: %EXIT_CODE%).`npause"
} else {
    "if %EXIT_CODE% neq 0 (`n    echo.`n    echo [ERROR] Process exited with code %EXIT_CODE%.`n    pause`n)"
}

switch ($Type) {
    'Basic' {
        $batContent = @"
@echo off
setlocal
chcp 65001 >nul 2>&1

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%$scriptFileName"

if not exist "%PS_SCRIPT%" (
    echo [ERROR] Target script not found: "%PS_SCRIPT%"
    pause
    exit /b 1
)

where pwsh >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set "PS_EXE=pwsh"
) else (
    set "PS_EXE=powershell.exe"
)

"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

$pauseBlock

endlocal & exit /b %EXIT_CODE%
"@
        Set-Content -Path $targetBatPath -Value $batContent -Encoding OEM
    }

    'Elevated' {
        $batContent = @"
@echo off
setlocal
chcp 65001 >nul 2>&1

net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Requesting Administrator privileges...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\" %*\"' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%$scriptFileName"

if not exist "%PS_SCRIPT%" (
    echo [ERROR] Target script not found: "%PS_SCRIPT%"
    pause
    exit /b 1
)

where pwsh >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set "PS_EXE=pwsh"
) else (
    set "PS_EXE=powershell.exe"
)

"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

$pauseBlock

endlocal & exit /b %EXIT_CODE%
"@
        Set-Content -Path $targetBatPath -Value $batContent -Encoding OEM
    }

    'Hybrid' {
        $sourceScriptContent = Get-Content -Path $resolvedScript.FullName -Raw -Encoding UTF8
        $batContent = @"
<# :
@echo off
setlocal
chcp 65001 >nul 2>&1

where pwsh >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set "PS_EXE=pwsh"
) else (
    set "PS_EXE=powershell.exe"
)

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "`$_f=[System.IO.File]::ReadAllText('%~f0', [System.Text.Encoding]::UTF8); Invoke-Expression (`$_f.Substring(`$_f.IndexOf([char]10)+1))"
set "EXIT_CODE=%ERRORLEVEL%"

$pauseBlock

endlocal & exit /b %EXIT_CODE%
#>

$sourceScriptContent
"@
        [System.IO.File]::WriteAllText($targetBatPath, $batContent, [System.Text.Encoding]::UTF8)
    }

    'Installer' {
        $batContent = @"
@echo off
setlocal
chcp 65001 >nul 2>&1

echo ==========================================
echo  $scriptBaseName Installer
echo ==========================================
echo.

set "SOURCE_DIR=%~dp0"
set "TARGET_DIR=%LOCALAPPDATA%\$scriptBaseName"

echo Deploying files to: "%TARGET_DIR%"
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"

xcopy /E /I /Y "%SOURCE_DIR%*" "%TARGET_DIR%\" >nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to copy files.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "`$ws = New-Object -ComObject WScript.Shell; " ^
    "`$s = `$ws.CreateShortcut([IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), '$scriptBaseName.lnk')); " ^
    "`$s.TargetPath = [IO.Path]::Combine('%TARGET_DIR%', '$scriptBaseName.bat'); " ^
    "`$s.WorkingDirectory = '%TARGET_DIR%'; " ^
    "`$s.Description = '$scriptBaseName Application'; " ^
    "`$s.Save()"

echo.
echo [SUCCESS] Installation completed! Desktop shortcut created.
pause

endlocal & exit /b 0
"@
        Set-Content -Path $targetBatPath -Value $batContent -Encoding OEM
    }
}

Write-Host "[OK] Created batch wrapper: $targetBatPath" -ForegroundColor Green

# Optional ZIP creation
if ($CreateZip) {
    $zipPath = Join-Path $scriptDir "$scriptBaseName-Package.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    $filesToZip = @($targetBatPath)
    if ($Type -ne 'Hybrid') {
        $filesToZip += $resolvedScript.FullName
    }

    Compress-Archive -Path $filesToZip -DestinationPath $zipPath -Force
    Write-Host "[OK] Created distributable archive: $zipPath" -ForegroundColor Green
}
