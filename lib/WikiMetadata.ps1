# ==============================================================================
#  WikiMetadata.ps1
#  OKF (Open Knowledge Format) v0.2 Document Metadata Extraction & Cache
#  Encoding: UTF-8 with BOM
# ==============================================================================

function Test-YamlFrontMatterSyntax {
    param (
        [string]$MdText = ""
    )

    $result = [PSCustomObject]@{
        isValid  = $true
        hasYaml  = $false
        warnings = [System.Collections.Generic.List[string]]::new()
    }

    if ([string]::IsNullOrEmpty($MdText)) {
        return $result
    }

    if ($MdText -match '^\s*---\r?\n' -and $MdText -notmatch '(?s)^\s*---\r?\n(.*?)\r?\n---\r?\n') {
        $result.isValid = $false
        $result.hasYaml = $true
        [void]$result.warnings.Add("YAML Front Matter closing header (---) not found.")
        return $result
    }

    if ($MdText -notmatch '(?s)^\s*---\r?\n(.*?)\r?\n---\r?\n') {
        return $result
    }

    $result.hasYaml = $true
    $rawYaml = $matches[1]

    $lines = $rawYaml -split '\r?\n'
    $lineNo = 1
    foreach ($line in $lines) {
        $lineNo++
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -match '^\s*-\s+') {
            continue
        }

        if ($line -notmatch '^\s*([a-zA-Z0-9_\-]+)\s*:') {
            if ($line -match ':\s*$') {
                continue
            }

            $result.isValid = $false
            $trimmedLine = $line
            if ($line.Length -gt 40) {
                $trimmedLine = $line.Substring(0, 40) + "..."
            }
            [void]$result.warnings.Add(("Line {0}: Invalid YAML format (key: value): {1}" -f $lineNo, $trimmedLine))
        }
    }

    return $result
}

function Get-WikiDir {
    param (
        [string]$RootFolder = "",
        [string]$TargetScriptDir = ""
    )

    if ([string]::IsNullOrWhiteSpace($TargetScriptDir)) {
        $TargetScriptDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
    }

    if ([string]::IsNullOrWhiteSpace($RootFolder)) {
        $sampleDir = Join-Path $TargetScriptDir "markdown_sample"
        if (Test-Path $sampleDir) {
            $resolvedDir = $sampleDir
        } else {
            $resolvedDir = $TargetScriptDir
        }
    } else {
        $resolvedDir = [System.IO.Path]::GetFullPath($RootFolder)
    }

    if (-not (Test-Path $resolvedDir)) {
        Write-Error ("Specified root folder not found: {0}" -f $resolvedDir)
        exit 1
    }

    return $resolvedDir
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
            Write-Warning ("YAML parsing failed for {0}: {1}" -f $RelPath, $_)
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
        return $YamlDict["title"].ToString().Trim()
    }
    if ($BodyText -and ($BodyText -match '(?m)^\s*#\s+(.+)$')) {
        return $matches[1].Trim()
    }
    if ($File -and -not [string]::IsNullOrWhiteSpace($File.BaseName)) {
        return $File.BaseName.ToString().Trim()
    }
    return "Untitled"
}

function Get-DocumentDescription {
    param (
        [hashtable]$YamlDict,
        [string]$BodyText
    )

    if ($YamlDict -and $YamlDict.ContainsKey("description") -and -not [string]::IsNullOrWhiteSpace($YamlDict["description"])) {
        return $YamlDict["description"].ToString().Trim()
    }
    if ([string]::IsNullOrWhiteSpace($BodyText)) { return "" }
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
        return $YamlDict["domain"].ToString().Trim()
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

    $author = ""
    if ($yamlDict.ContainsKey("author") -and -not [string]::IsNullOrWhiteSpace($yamlDict["author"])) {
        $author = $yamlDict["author"].ToString().Trim()
    }

    $tags = Get-YamlListProperty -YamlDict $yamlDict -Key "tags"

    $lastUpdated = if ($File -and (Test-Path $File.FullName)) { $File.LastWriteTime } else { $null }
    if ($yamlDict.ContainsKey("last_updated") -and -not [string]::IsNullOrWhiteSpace($yamlDict["last_updated"])) {
        try {
            $lastUpdated = [DateTime]::Parse($yamlDict["last_updated"])
        } catch {
            # Keep file time on parse failure
        }
    }

    $status = "active"
    if ($yamlDict.ContainsKey("status") -and -not [string]::IsNullOrWhiteSpace($yamlDict["status"])) {
        $status = $yamlDict["status"].ToString().ToLower().Trim()
    }

    $version = if ($yamlDict.ContainsKey("version") -and -not [string]::IsNullOrWhiteSpace($yamlDict["version"])) { $yamlDict["version"].ToString().Trim() } else { "" }
    $reviewer = if ($yamlDict.ContainsKey("reviewer") -and -not [string]::IsNullOrWhiteSpace($yamlDict["reviewer"])) { $yamlDict["reviewer"].ToString().Trim() } else { "" }
    $supersededBy = if ($yamlDict.ContainsKey("superseded_by") -and -not [string]::IsNullOrWhiteSpace($yamlDict["superseded_by"])) { $yamlDict["superseded_by"].ToString().Trim() } else { "" }

    $trustTier = "tier-1"
    if ($yamlDict.ContainsKey("trust_tier") -and -not [string]::IsNullOrWhiteSpace($yamlDict["trust_tier"])) {
        $trustTier = $yamlDict["trust_tier"].ToString().ToLower().Trim()
    }

    $provenance = $null
    if ($yamlDict.ContainsKey("provenance")) {
        $provenance = $yamlDict["provenance"]
    }

    $computations = $null
    if ($yamlDict.ContainsKey("computations")) {
        $computations = $yamlDict["computations"]
    }

    $contributors = Get-YamlListProperty -YamlDict $yamlDict -Key "contributors"
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
        TrustTier    = $trustTier
        Provenance   = $provenance
        Computations = $computations
        Contributors = $contributors
        Related      = $related
        HasYaml      = $hasYaml
        RelPath      = $RelPath
        FullPath     = if ($File) { $File.FullName } else { "" }
        BodyText     = $bodyText
        RawYamlDict  = $yamlDict
    }
}

$script:WikiIndex = @()
$script:WikiIndexLastScan = [DateTime]::MinValue
$script:WikiIndexDirWriteTime = [DateTime]::MinValue