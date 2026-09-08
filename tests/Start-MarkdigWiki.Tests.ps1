# ==============================================================================
#  Start-MarkdigWiki.Tests.ps1 (Master Test Suite Runner)
#  Encoding: UTF-8 with BOM
# ==============================================================================

[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingInvokeExpression", "")]
param()

if (-not $script:projectRoot) {
    $script:projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

$testFiles = Get-ChildItem -Path $PSScriptRoot -Filter "*.Tests.ps1" |
    Where-Object { $_.Name -ne "Start-MarkdigWiki.Tests.ps1" }

foreach ($file in $testFiles) {
    . $file.FullName
}
