# ==============================================================================
#  SimpleWiki Metadata & YAML Front Matter モジュール
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================

function Test-YamlFrontMatterSyntax {
    param (
        [string]$MdText = ""
    )

    $result = @{
        isValid  = $true
        warnings = [System.Collections.Generic.List[string]]::new()
    }

    if ([string]::IsNullOrWhiteSpace($MdText)) {
        return $result
    }

    if ($MdText -match '(?s)^\s*---\r?\n(.*)$') {
        $afterFirstHeader = $matches[1]
        if ($afterFirstHeader -notmatch '(?s)^(.*?)\r?\n---\r?\n(.*)$') {
            $result.isValid = $false
            [void]$result.warnings.Add("YAML Front Matter の閉じヘッダー ('---') が見つかりません。")
            return $result
        }

        $rawYaml = $matches[1]
        $lines = $rawYaml -split '\r?\n'
        $lineNo = 1

        foreach ($line in $lines) {
            $lineNo++
            if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*#') {
                continue
            }

            if ($line -match '^\s*-\s+.*$') {
                continue
            }

            if ($line -match '^\s*([a-zA-Z0-9_\-]+)\s*:\s*(.*)$') {
                continue
            }

            $result.isValid = $false
            $trimmedLine = if ($line.Length -gt 40) { $line.Substring(0, 40) + "..." } else { $line }
            [void]$result.warnings.Add("${lineNo}行目: YAML の形式 (key: value) が不正です: `"$trimmedLine`"")
        }
    }

    return $result
}

# --- OKF メタデータ抽出し ＆ 自動補完 (フォールバック) 関数 ---
function Get-DocumentMetadata {
    param (
        [Parameter(Mandatory = $true)]$File,
        [string]$RelPath = "",
        [string]$MdText = ""
    )

    if ([string]::IsNullOrEmpty($MdText) -and $File -and (Test-Path $File.FullName)) {
        $MdText = Get-Content -Path $File.FullName -Raw -Encoding UTF8
    }

    $hasYaml  = $false
    $bodyText = $MdText
    $yamlDict = @{}

    if ($MdText -match '(?s)^\s*---\r?\n(.*?)\r?\n---\r?\n(.*)$') {
        $hasYaml  = $true
        $rawYaml  = $matches[1]
        $bodyText = $matches[2]

        try {
            $currentKey = $null
            $lines = $rawYaml -split '\r?\n'
            foreach ($line in $lines) {
                if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }

                if ($currentKey -and $line -match '^\s*-\s+(.*)$') {
                    $itemVal = $matches[1].Trim().Trim('"', "'")
                    if (-not $yamlDict.ContainsKey($currentKey) -or $yamlDict[$currentKey] -isnot [System.Collections.IList]) {
                        $yamlDict[$currentKey] = [System.Collections.Generic.List[string]]::new()
                    }
                    [void]$yamlDict[$currentKey].Add($itemVal)
                    continue
                }

                if ($line -match '^\s*([a-zA-Z0-9_\-]+)\s*:\s*(.*)$') {
                    $key = $matches[1].ToLower().Trim()
                    $val = $matches[2].Trim()
                    $currentKey = $key

                    if ($val -match '^\[(.*)\]$') {
                        $items = $matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"', "'") } | Where-Object { $_ -ne "" }
                        $yamlDict[$key] = @($items)
                    } elseif (-not [string]::IsNullOrWhiteSpace($val)) {
                        $val = $val.Trim('"', "'")
                        $yamlDict[$key] = $val
                    }
                }
            }
        } catch {
            Write-Warning "YAML parsing failed for $RelPath : $_"
        }
    }

    # Title
    $title = ""
    if ($yamlDict.ContainsKey("title") -and -not [string]::IsNullOrWhiteSpace($yamlDict["title"])) {
        $title = $yamlDict["title"]
    } else {
        if ($bodyText -match '(?m)^\s*#\s+(.+)$') {
            $title = $matches[1].Trim()
        } elseif ($File) {
            $title = $File.BaseName
        } else {
            $title = "Untitled"
        }
    }

    # Description
    $description = ""
    if ($yamlDict.ContainsKey("description") -and -not [string]::IsNullOrWhiteSpace($yamlDict["description"])) {
        $description = $yamlDict["description"]
    } else {
        $cleanBody = $bodyText -replace '(?m)^\s*#+\s*', '' -replace '[\*\`\[\]\(\)]', '' -replace '\s+', ' '
        $cleanBody = $cleanBody.Trim()
        if ($cleanBody.Length -gt 150) {
            $description = $cleanBody.Substring(0, 150) + "..."
        } else {
            $description = $cleanBody
        }
    }

    # Author
    $author = ""
    if ($yamlDict.ContainsKey("author") -and -not [string]::IsNullOrWhiteSpace($yamlDict["author"])) {
        $author = $yamlDict["author"]
    }

    # Domain
    $domain = ""
    if ($yamlDict.ContainsKey("domain") -and -not [string]::IsNullOrWhiteSpace($yamlDict["domain"])) {
        $domain = $yamlDict["domain"]
    } else {
        if (-not [string]::IsNullOrWhiteSpace($RelPath)) {
            $dir = [System.IO.Path]::GetDirectoryName($RelPath)
            $domain = if ([string]::IsNullOrWhiteSpace($dir)) { "root" } else { $dir.Replace('\', '/') }
        } else {
            $domain = "root"
        }
    }

    # Tags
    $tags = @()
    if ($yamlDict.ContainsKey("tags")) {
        if ($yamlDict["tags"] -is [System.Collections.IEnumerable] -and $yamlDict["tags"] -isnot [string]) {
            $tags = @($yamlDict["tags"])
        } elseif (-not [string]::IsNullOrWhiteSpace($yamlDict["tags"])) {
            $rawStr = $yamlDict["tags"].ToString()
            $tags = @($rawStr -split ',\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    }

    # LastUpdated
    $lastUpdated = if ($File) { $File.LastWriteTime } else { Get-Date }
    if ($yamlDict.ContainsKey("last_updated") -and -not [string]::IsNullOrWhiteSpace($yamlDict["last_updated"])) {
        $parsedDate = [DateTime]::MinValue
        if ([DateTime]::TryParse($yamlDict["last_updated"], [ref]$parsedDate)) {
            $lastUpdated = $parsedDate
        }
    }

    # Status (active, draft, deprecated)
    $status = "active"
    if ($yamlDict.ContainsKey("status") -and -not [string]::IsNullOrWhiteSpace($yamlDict["status"])) {
        $st = $yamlDict["status"].ToString().ToLower().Trim()
        if ($st -in @("active", "draft", "deprecated")) {
            $status = $st
        }
    }

    return [PSCustomObject]@{
        Title       = $title
        Description = $description
        Author      = $author
        Domain      = $domain
        Tags        = $tags
        LastUpdated = $lastUpdated
        Status      = $status
        HasYaml     = $hasYaml
        RelPath     = $RelPath
        FullPath    = if ($File) { $File.FullName } else { "" }
        BodyText    = $bodyText
    }
}

# --- 全件インデックス構築 & キャッシュ機能 ---
$script:WikiIndex = @()
$script:WikiIndexLastScan = [DateTime]::MinValue
$script:WikiIndexDirWriteTime = [DateTime]::MinValue
