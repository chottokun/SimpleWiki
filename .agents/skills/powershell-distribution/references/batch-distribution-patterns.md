# Batch File Distribution Patterns for PowerShell

This reference covers practical patterns, technical mechanisms, and edge cases for distributing PowerShell scripts via batch files (`.bat` / `.cmd`).

---

## 1. Core Technical Mechanisms

### 1.1 ExecutionPolicy Bypass
Windows defaults to `Restricted` or `RemoteSigned` which blocks raw `.ps1` execution.
Launching PowerShell from cmd with `-ExecutionPolicy Bypass` sets the policy **strictly for that specific process scope** without modifying machine-wide registry settings:

```batch
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0script.ps1" %*
```

- `-NoLogo`: Suppresses copyright banner.
- `-NoProfile`: Skips loading `$PROFILE` (speeds up launch, avoids dependency on user configuration).
- `%~dp0`: Expands to the drive and path of the folder containing the running batch file (ensures correct relative path resolution even when launched from another working directory).
- `%*`: Passes all command-line arguments directly to the PowerShell script.

---

### 1.2 UTF-8 Encoding & Code Page
Windows cmd defaults to OEM code pages (e.g., CP932 in Japan, CP437 in US).
Adding `chcp 65001 >nul 2>&1` at the beginning of the batch file switches the console to UTF-8 output to prevent Japanese/multilingual characters from corrupting.

---

### 1.3 Exit Code Propagation
Always capture `%ERRORLEVEL%` and exit with `exit /b %EXIT_CODE%` to maintain exit status for scheduling tools (Task Scheduler, JP1, Jenkins, etc.):

```batch
set "EXIT_CODE=%ERRORLEVEL%"
if %EXIT_CODE% neq 0 (
    echo [ERROR] Process finished with exit code %EXIT_CODE%
)
endlocal & exit /b %EXIT_CODE%
```

---

## 2. Detailed Patterns

### Pattern 1: Universal Launcher (with PowerShell 7 / 5.1 Auto-Detection)
Detects whether PowerShell 7 (`pwsh.exe`) is installed. Uses `pwsh` if available; otherwise falls back to Windows PowerShell 5.1 (`powershell.exe`).

```batch
@echo off
setlocal
chcp 65001 >nul 2>&1
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%MyScript.ps1"

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

if %EXIT_CODE% neq 0 (
    pause
)

endlocal & exit /b %EXIT_CODE%
```

---

### Pattern 2: Auto-Elevating UAC Launcher
Checks if the current process has administrative rights using `net session`. If not, re-launches itself with the `RunAs` verb to prompt the standard Windows UAC dialog.

```batch
@echo off
setlocal
chcp 65001 >nul 2>&1

net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Requesting Administrator privileges...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\" %*\"' -Verb RunAs"
    exit /b
)

:: Running with Administrator privileges
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%MyAdminScript.ps1"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
echo Process complete (Exit Code: %EXIT_CODE%).
pause
exit /b %EXIT_CODE%
```

---

### Pattern 3: Single-File Hybrid (Polyglot Batch + PowerShell)
Useful when distributing via email, Teams, or Slack where a single `.bat` file is much easier to manage than a `.zip` containing separate `.bat` and `.ps1` files.

```batch
<# :
@echo off
setlocal
chcp 65001 >nul 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$_f=[System.IO.File]::ReadAllText('%~f0', [System.Text.Encoding]::UTF8); Invoke-Expression ($_f.Substring($_f.IndexOf([char]10)+1))"
set "EXIT_CODE=%ERRORLEVEL%"
if %EXIT_CODE% neq 0 pause
exit /b %EXIT_CODE%
#>

# PowerShell Code Starts Here
[CmdletBinding()]
param()

Write-Host "Running hybrid script..." -ForegroundColor Green
# Your logic here...
```

---

## 3. Pitfalls and Edge Cases

1. **Working Directory Shift on RunAs**:
   When elevated via `RunAs`, cmd often resets the working directory to `C:\Windows\System32`. Always use `%~dp0` or explicitly `cd /d "%~dp0"` in elevated batches.
2. **Quoting and Space in Paths**:
   Always surround paths with quotes: `"%~dp0script.ps1"`.
3. **BOM (Byte Order Mark)**:
   Ensure `.ps1` files are encoded in UTF-8 with BOM for Windows PowerShell 5.1 compatibility. Hybrid `.bat` files can be UTF-8 without BOM or Shift-JIS.
