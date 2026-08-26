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

function ConvertFrom-YamlHeader {
    param (
        [string]$MdText = "",
        [string]$RelPath = ""
    )

    $result = @{
        HasYaml  = $false
        BodyText = $MdText
        YamlDict = @{}
    }

    if ($MdText -match '(?s)^\s*---\r?\n(.*?)\r?\n---\r?\n(.*)$') {
        $result.HasYaml  = $true
        $rawYaml         = $matches[1]
        $result.BodyText = $matches[2]
        $yamlDict        = @{}

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

        $result.YamlDict = $yamlDict
    }

    return $result
}

function Get-YamlListProperty {
    param (
        [hashtable]$YamlDict,
        [string]$Key
    )

    $list = @()
    if ($YamlDict -and $YamlDict.ContainsKey($Key)) {
        $val = $YamlDict[$Key]
        if ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
            $list = @($val)
        } elseif (-not [string]::IsNullOrWhiteSpace($val)) {
            $rawStr = $val.ToString()
            $list = @($rawStr -split ',\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    }
    return $list
}

function Get-DocumentTitle {
    param (
        [hashtable]$YamlDict,
        [string]$BodyText,
        $File
    )

    if ($YamlDict -and $YamlDict.ContainsKey("title") -and -not [string]::IsNullOrWhiteSpace($YamlDict["title"])) {
        return $YamlDict["title"]
    }
    if ($BodyText -match '(?m)^\s*#\s+(.+)$') {
        return $matches[1].Trim()
    }
    if ($File) {
        return $File.BaseName
    }
    return "Untitled"
}

function Get-DocumentDescription {
    param (
        [hashtable]$YamlDict,
        [string]$BodyText
    )

    if ($YamlDict -and $YamlDict.ContainsKey("description") -and -not [string]::IsNullOrWhiteSpace($YamlDict["description"])) {
        return $YamlDict["description"]
    }
    $cleanBody = $BodyText -replace '(?m)^\s*#+\s*', '' -replace '[\*\`\[\]\(\)]', '' -replace '\s+', ' '
    $cleanBody = $cleanBody.Trim()
    if ($cleanBody.Length -gt 150) {
        return $cleanBody.Substring(0, 150) + "..."
    }
    return $cleanBody
}

function Get-DocumentDomain {
    param (
        [hashtable]$YamlDict,
        [string]$RelPath
    )

    if ($YamlDict -and $YamlDict.ContainsKey("domain") -and -not [string]::IsNullOrWhiteSpace($YamlDict["domain"])) {
        return $YamlDict["domain"]
    }
    if (-not [string]::IsNullOrWhiteSpace($RelPath)) {
        $dir = [System.IO.Path]::GetDirectoryName($RelPath)
        if ([string]::IsNullOrWhiteSpace($dir)) {
            return "root"
        } else {
            return $dir.Replace('\', '/')
        }
    }
    return "root"
}

# --- OKF メタデータ抽出 ＆ 自動補完 (フォールバック) 関数 ---
function Get-DocumentMetadata {
    param (
        [Parameter(Mandatory = $false)]$File = $null,
        [string]$RelPath = "",
        [string]$MdText = ""
    )

    if ([string]::IsNullOrEmpty($MdText) -and $File -and (Test-Path $File.FullName)) {
        $MdText = Get-Content -Path $File.FullName -Raw -Encoding UTF8
    }

    $parsedYaml = ConvertFrom-YamlHeader -MdText $MdText -RelPath $RelPath
    $hasYaml   = $parsedYaml.HasYaml
    $bodyText  = $parsedYaml.BodyText
    $yamlDict  = $parsedYaml.YamlDict

    $title       = Get-DocumentTitle -YamlDict $yamlDict -BodyText $bodyText -File $File
    $description = Get-DocumentDescription -YamlDict $yamlDict -BodyText $bodyText
    $domain      = Get-DocumentDomain -YamlDict $yamlDict -RelPath $RelPath

    # Author
    $author = ""
    if ($yamlDict.ContainsKey("author") -and -not [string]::IsNullOrWhiteSpace($yamlDict["author"])) {
        $author = $yamlDict["author"]
    }

    # Tags
    $tags = Get-YamlListProperty -YamlDict $yamlDict -Key "tags"

    # LastUpdated (ファイル時刻 or YAML指定。どちらも無ければ $null で不明扱い)
    $lastUpdated = if ($File -and (Test-Path $File.FullName)) { $File.LastWriteTime } else { $null }
    if ($yamlDict.ContainsKey("last_updated") -and -not [string]::IsNullOrWhiteSpace($yamlDict["last_updated"])) {
        $parsedDate = [DateTime]::MinValue
        if ([DateTime]::TryParse($yamlDict["last_updated"], [ref]$parsedDate)) {
            $lastUpdated = $parsedDate
        }
    }

    # Status (OKF v0.2: active, stable, draft, review, in-review, deprecated, archived, obsolete)
    $status = "active"
    if ($yamlDict.ContainsKey("status") -and -not [string]::IsNullOrWhiteSpace($yamlDict["status"])) {
        $st = $yamlDict["status"].ToString().ToLower().Trim()
        if ($st -in @("active", "stable", "draft", "review", "in-review", "deprecated", "archived", "obsolete")) {
            $status = $st
        }
    }

    # OKF v0.2: Version
    $version = ""
    if ($yamlDict.ContainsKey("version") -and -not [string]::IsNullOrWhiteSpace($yamlDict["version"])) {
        $version = $yamlDict["version"].ToString().Trim()
    }

    # OKF v0.2: Reviewer
    $reviewer = ""
    if ($yamlDict.ContainsKey("reviewer") -and -not [string]::IsNullOrWhiteSpace($yamlDict["reviewer"])) {
        $reviewer = $yamlDict["reviewer"].ToString().Trim()
    }

    # OKF v0.2: SupersededBy (後継ドキュメント)
    $supersededBy = ""
    if ($yamlDict.ContainsKey("superseded_by") -and -not [string]::IsNullOrWhiteSpace($yamlDict["superseded_by"])) {
        $supersededBy = $yamlDict["superseded_by"].ToString().Trim()
    }

    # OKF v0.2: Contributors (共同執筆者)
    $contributors = Get-YamlListProperty -YamlDict $yamlDict -Key "contributors"

    # OKF v0.2: Related (関連ドキュメント)
    $related = Get-YamlListProperty -YamlDict $yamlDict -Key "related"

    return [PSCustomObject]@{
        Title        = $title
        Description  = $description
        Author       = $author
        Domain       = $domain
        Tags         = $tags
        LastUpdated  = $lastUpdated
        Status       = $status
        Version      = $version
        Reviewer     = $reviewer
        SupersededBy = $supersededBy
        Contributors = $contributors
        Related      = $related
        HasYaml      = $hasYaml
        RelPath      = $RelPath
        FullPath     = if ($File) { $File.FullName } else { "" }
        BodyText     = $bodyText
    }
}

# --- 全件インデックス構築 & キャッシュ機能 ---
$script:WikiIndex = @()
$script:WikiIndexLastScan = [DateTime]::MinValue
$script:WikiIndexDirWriteTime = [DateTime]::MinValue
