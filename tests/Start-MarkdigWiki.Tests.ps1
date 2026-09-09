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

# ディレクトリ一括実行 (例: Invoke-Pester tests/) 時は、Pester 自身が各 *.Tests.ps1 を
# 個別ディスカバリして実行するため、本スクリプト内での重複読み込みをスキップする。
$isDirectTarget = $true
$stack = Get-PSCallStack
$pesterFrame = $stack | Where-Object { $_.Command -eq "Invoke-Pester" }
if ($pesterFrame -and $pesterFrame.InvocationInfo -and $pesterFrame.InvocationInfo.BoundParameters) {
    $paramVal = $pesterFrame.InvocationInfo.BoundParameters['Script']
    if (-not $paramVal) {
        $paramVal = $pesterFrame.InvocationInfo.BoundParameters['Path']
    }
    if ($paramVal) {
        $matchesSelf = $false
        foreach ($p in @($paramVal)) {
            $pStr = if ($p -is [hashtable] -and $p.Path) { $p.Path } else { "$p" }
            if ($pStr -match 'Start-MarkdigWiki\.Tests\.ps1$') {
                $matchesSelf = $true
                break
            }
        }
        $isDirectTarget = $matchesSelf
    } else {
        # 引数なしで Invoke-Pester が実行された場合はディレクトリ走査になるため重複防止
        $isDirectTarget = $false
    }
}

if ($isDirectTarget) {
    $testFiles = Get-ChildItem -Path $PSScriptRoot -Filter "*.Tests.ps1" |
        Where-Object { $_.Name -ne "Start-MarkdigWiki.Tests.ps1" }

    foreach ($file in $testFiles) {
        . $file.FullName
    }
}
