# Coding Rules

- **Character Encoding & Format Guidelines**:
  - **PowerShell Scripts (`.ps1`, `.psm1`) & Data Files (`.psd1`)**: Save as **UTF-8 with BOM (`EF BB BF`)** to ensure correct multi-byte character interpretation by Windows PowerShell 5.1 and `Import-PowerShellDataFile`.
  - **Batch Files (`.bat`)**: Save strictly as **UTF-8 without BOM (No-BOM)**. `cmd.exe` interprets a leading UTF-8 BOM as `・ｿ` causing `'・ｿ@echo'` command failures.
  - **PowerShell Data Files (`.psd1`)**: Keep string values safe for `Import-PowerShellDataFile` (avoid backtick escapes like `` `n `` or unescaped quote syntax inside hashtables).
- Include PSScriptAnalyzer-equivalent checks in the test/validation process.
- Develop using a TDD approach.
- Target execution & test environment is vanilla Windows 11 / Windows PowerShell 5.1 with built-in Pester (v3.4.0). Do NOT use hyphenated Pester 5 assertion operators (e.g., use `Should Be`, NOT `Should -Be`). See `.agents/rules/powershell.md`.
- **OKF Document Display Order Policy (ドキュメント表示順・カタログ順序ポリシー)**:
  - **ファイル命名**: 各ドキュメント（Concept）は内容を表す不変のkebab-caseで命名すること（数字プレフィックス `01_` 等は付与しない）。
  - **表示順の管理**: バンドル内の表示順・読了順は、バンドル直下の `index.md` 内に記述されたリンクリスト出現順を最優先（Single Source of Truth）とする。
  - **推奨フォーマット**: 順序が重要なドキュメント群は番号付きリスト（`1. [概要](overview.md)`）、並列なドキュメント群は箇条書きを推奨。
  - **新規追加時の責務**: 新規ファイルを生成したツールやエージェントは、`index.md` の目次セクションに適切な順序でリンクを追記すること。


# Project Context

This is a personal learning project.
README is an evidence-based project record, not marketing copy.