# ==============================================================================
#  Update-WikiTags.ps1
#  glossary.md の用語を記事本文からスキャンし、各 Markdown の tags: に安全に自動マージする
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [string]$WikiDir = "",
    [string]$GlossaryPath = "",
    [switch]$DryRun
)

$scriptDir = [System.IO.Path]::GetFullPath($PSScriptRoot)

# Wiki ディレクトリの判定
if ([string]::IsNullOrWhiteSpace($WikiDir)) {
    $sampleDir = Join-Path $scriptDir "markdown_sample"
    if (Test-Path $sampleDir) {
        $WikiDir = $sampleDir
    } else {
        $WikiDir = $scriptDir
    }
} else {
    $WikiDir = [System.IO.Path]::GetFullPath($WikiDir)
}

if (-not (Test-Path $WikiDir)) {
    Write-Error ("指定された Wiki ディレクトリが存在しません: {0}" -f $WikiDir)
    exit 1
}

# glossary.md パスの判定
if ([string]::IsNullOrWhiteSpace($GlossaryPath)) {
    $GlossaryPath = Join-Path $WikiDir "glossary.md"
    if (-not (Test-Path $GlossaryPath)) {
        $GlossaryPath = Join-Path $scriptDir "markdown_sample/glossary.md"
    }
} else {
    $GlossaryPath = [System.IO.Path]::GetFullPath($GlossaryPath)
}

if (-not (Test-Path $GlossaryPath)) {
    Write-Error ("glossary.md が見つかりません: {0}" -f $GlossaryPath)
    exit 1
}

# ライブラリの読み込み
$metaScript = Join-Path $scriptDir "lib/WikiMetadata.ps1"
if (Test-Path $metaScript) {
    . $metaScript
} else {
    Write-Error "lib/WikiMetadata.ps1 が見つかりません。"
    exit 1
}

# 1. glossary.md から用語一覧と検索パターンの抽出
$glossaryTerms = Get-GlossaryTerms -GlossaryPath $GlossaryPath
if ($glossaryTerms.Count -eq 0) {
    Write-Host "glossary.md に有効な用語が定義されていません。" -ForegroundColor Yellow
    exit 0
}

# 用語キーとパターンのマップ構築
# Key: タグ名, Value: @{ MainTag = "..." ; Patterns = @(...) }
$termMap = [ordered]@{}
foreach ($heading in $glossaryTerms.Keys) {
    $tagName = $heading.Trim()
    $patterns = [System.Collections.Generic.List[string]]::new()
    [void]$patterns.Add($heading)

    if ($heading -match '^\s*([^\(\（]+)\s*[\(\（]([^\)\）]+)[\)\）]') {
        $mainTerm = $matches[1].Trim()
        $altTerm  = $matches[2].Trim()
        $tagName  = $mainTerm
        if (-not $patterns.Contains($mainTerm)) { [void]$patterns.Add($mainTerm) }
        if (-not $patterns.Contains($altTerm)) { [void]$patterns.Add($altTerm) }
    }

    $termMap[$heading] = @{
        TagName  = $tagName
        Patterns = @($patterns)
    }
}

Write-Host ("glossary.md から {0} 件の用語をロードしました。" -f $termMap.Count) -ForegroundColor Cyan

# 2. Markdown ファイルの走査
$mdFiles = Get-ChildItem -Path $WikiDir -Filter "*.md" -Recurse -File | Where-Object {
    $_.FullName -ne (Get-Item $GlossaryPath).FullName
}

$updatedCount = 0
$scannedCount = 0

foreach ($file in $mdFiles) {
    $scannedCount++
    $relPath = $file.FullName.Substring($WikiDir.Length).TrimStart('\', '/')
    $rawText = Get-Content -Path $file.FullName -Raw -Encoding UTF8

    if ([string]::IsNullOrWhiteSpace($rawText)) { continue }

    # YAML ヘッダーと本文の分離
    $parsed = ConvertFrom-YamlHeader -MdText $rawText -RelPath $relPath
    $yamlDict = $parsed.YamlDict
    $bodyText = $parsed.BodyText

    # 既存タグの取得
    $existingTags = [System.Collections.Generic.List[string]]::new()
    $rawTags = Get-YamlListProperty -YamlDict $yamlDict -Key "tags"
    foreach ($t in $rawTags) {
        if (-not $existingTags.Contains($t)) {
            [void]$existingTags.Add($t)
        }
    }

    $detectedTags = [System.Collections.Generic.List[string]]::new()

    # 本文テキストでの用語判定（誤爆・部分一致抑制）
    foreach ($key in $termMap.Keys) {
        $info = $termMap[$key]
        $tagToMerge = $info.TagName
        if ($existingTags.Contains($tagToMerge) -or $detectedTags.Contains($tagToMerge)) {
            continue
        }

        $found = $false
        foreach ($pat in $info.Patterns) {
            if ([string]::IsNullOrWhiteSpace($pat)) { continue }

            # エイリアス/単語境界/記号考慮の判定 regex
            $escapedPat = [regex]::Escape($pat)
            if ($pat -match '^[a-zA-Z0-9_\-]+$') {
                $regexPat = "(?i)\b$escapedPat\b"
            } else {
                $regexPat = "(?i)$escapedPat"
            }

            if ($bodyText -match $regexPat) {
                $found = $true
                break
            }
        }

        if ($found) {
            [void]$detectedTags.Add($tagToMerge)
        }
    }

    if ($detectedTags.Count -gt 0) {
        $updatedCount++
        $mergedTags = [System.Collections.Generic.List[string]]::new($existingTags)
        foreach ($dt in $detectedTags) {
            if (-not $mergedTags.Contains($dt)) {
                [void]$mergedTags.Add($dt)
            }
        }

        Write-Host ("[UPDATE] {0}" -f $relPath) -ForegroundColor Green
        Write-Host ("  既存タグ: [{0}]" -f ($existingTags -join ", ")) -ForegroundColor Gray
        Write-Host ("  追加タグ: [{0}]" -f ($detectedTags -join ", ")) -ForegroundColor Yellow
        Write-Host ("  マージ後: [{0}]" -f ($mergedTags -join ", ")) -ForegroundColor Cyan

        if (-not $DryRun -and $PSCmdlet.ShouldProcess($relPath, "Update tags")) {
            # YAML フロントマターの置換・保存
            $newYamlLines = [System.Collections.Generic.List[string]]::new()
            if ($parsed.HasYaml) {
                # 既存の YAML ブロックをパースして tags 行だけ置き換える
                if ($rawText -match '(?s)^\s*---\r?\n(.*?)\r?\n---\r?\n(.*)$') {
                    $rawYaml = $matches[1]
                    $yamlLines = $rawYaml -split '\r?\n'
                    $inTagsSection = $false

                    foreach ($line in $yamlLines) {
                        if ($line -match '^\s*tags\s*:') {
                            $inTagsSection = $true
                            continue
                        }

                        if ($inTagsSection) {
                            if ($line -match '^\s*-\s+' -or [string]::IsNullOrWhiteSpace($line)) {
                                continue
                            } else {
                                $inTagsSection = $false
                            }
                        }

                        [void]$newYamlLines.Add($line)
                    }
                }
            }

            # 追加の tags 設定生成
            $tagsYaml = "tags:`n" + (($mergedTags | ForEach-Object { "  - `"$($_)`"" }) -join "`n")
            [void]$newYamlLines.Add($tagsYaml)

            $newYamlHeader = "---\n" + (($newYamlLines -join "`n").Trim()) + "\n---\n\n"
            $finalMdText = $newYamlHeader + $bodyText.TrimStart()

            Set-Content -Path $file.FullName -Value $finalMdText -Encoding UTF8
        }
    }
}

if ($DryRun) {
    Write-Host "`n[DryRun Mode] ファイルは変更されていません。" -ForegroundColor Yellow
}
Write-Host ("処理完了: {0} 件中 {1} 件のドキュメントのタグが更新対象でした。" -f $scannedCount, $updatedCount) -ForegroundColor Cyan
