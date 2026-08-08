# Coding Rules

- **Character Encoding & Format Guidelines**:
  - **PowerShell Scripts (`.ps1`, `.psm1`) & Data Files (`.psd1`)**: Save as **UTF-8 with BOM (`EF BB BF`)** to ensure correct multi-byte character interpretation by Windows PowerShell 5.1 and `Import-PowerShellDataFile`.
  - **Batch Files (`.bat`)**: Save strictly as **UTF-8 without BOM (No-BOM)**. `cmd.exe` interprets a leading UTF-8 BOM as `・ｿ` causing `'・ｿ@echo'` command failures.
  - **PowerShell Data Files (`.psd1`)**: Keep string values safe for `Import-PowerShellDataFile` (avoid backtick escapes like `` `n `` or unescaped quote syntax inside hashtables).
- Include PSScriptAnalyzer-equivalent checks in the test/validation process.
- Develop using a TDD approach.

# Project Context

This is a personal learning project.
README is an evidence-based project record, not marketing copy.