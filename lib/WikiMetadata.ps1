# ==============================================================================
#  WikiMetadata.ps1
#  OKF (Open Knowledge Format) v0.2 繝峨く繝･繝｡繝ｳ繝医Γ繧ｿ繝・・繧ｿ謚ｽ蜃ｺ & 繧ｭ繝｣繝・す繝･邂｡逅・#  譁・ｭ励さ繝ｼ繝・ UTF-8 with BOM
# ==============================================================================

# --- OKF YAML Front Matter 讒区枚讀懆ｨｼ髢｢謨ｰ ---
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
            $trimmedLine = if ($line.Length -gt 40) { $line.Substring(0, 40) + "..." } else { $line }
            [void]$result.warnings.Add("${lineNo}陦檎岼: YAML 縺ｮ蠖｢蠑・(key: value) 縺御ｸ肴ｭ｣縺ｧ縺・ `"$trimmedLine`"")
        }
    }

    return $result
}

# --- 繝ｫ繝ｼ繝医ヵ繧ｩ繝ｫ繝豎ｺ螳壹・繝ｫ繝代・髢｢謨ｰ ---
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
        Write-Error "謖・ｮ壹＆繧後◆繝ｫ繝ｼ繝医ヵ繧ｩ繝ｫ繝縺瑚ｦ九▽縺九ｊ縺ｾ縺帙ｓ:`n$resolvedDir"
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

# --- OKF 繝｡繧ｿ繝・・繧ｿ謚ｽ蜃ｺ ・・閾ｪ蜍戊｣懷ｮ・(繝輔か繝ｼ繝ｫ繝舌ャ繧ｯ) 髢｢謨ｰ ---
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

    # LastUpdated (繝輔ぃ繧､繝ｫ譎ょ綾 or YAML謖・ｮ壹ゅ←縺｡繧峨ｂ辟｡縺代ｌ縺ｰ $null 縺ｧ荳肴・謇ｱ縺・
    $lastUpdated = if ($File -and (Test-Path $File.FullName)) { $File.LastWriteTime } else { $null }
    if ($yamlDict.ContainsKey("last_updated") -and -not [string]::IsNullOrWhiteSpace($yamlDict["last_updated"])) {
        try {
            $lastUpdated = [DateTime]::Parse($yamlDict["last_updated"])
        } catch {
            # 繝代・繧ｹ螟ｱ謨玲凾縺ｯ繝輔ぃ繧､繝ｫ譎ょ綾繧堤ｶｭ謖・        }
    }

    # OKF v0.2: Status (繝・ヵ繧ｩ繝ｫ繝・ active)
    $status = "active"
    if ($yamlDict.ContainsKey("status") -and -not [string]::IsNullOrWhiteSpace($yamlDict["status"])) {
        $status = $yamlDict["status"].ToLower().Trim()
    }

    # OKF v0.2: Trust Tier (繝・ヵ繧ｩ繝ｫ繝・ tier-1)
    $trustTier = "tier-1"
    if ($yamlDict.ContainsKey("trust_tier") -and -not [string]::IsNullOrWhiteSpace($yamlDict["trust_tier"])) {
        $trustTier = $yamlDict["trust_tier"].ToLower().Trim()
    }

    # OKF v0.2: Provenance (蜃ｺ謇諠・ｱ)
    $provenance = $null
    if ($yamlDict.ContainsKey("provenance")) {
        $provenance = $yamlDict["provenance"]
    }

    # OKF v0.2: Computations (險育ｮ嶺ｻ墓ｧ倥・邨先棡)
    $computations = $null
    if ($yamlDict.ContainsKey("computations")) {
        $computations = $yamlDict["computations"]
    }

    # OKF v0.2: Contributors (蜈ｱ蜷悟濤遲・・
    $contributors = Get-YamlListProperty -YamlDict $yamlDict -Key "contributors"

    # OKF v0.2: Related (髢｢騾｣繝峨く繝･繝｡繝ｳ繝・
    $related = Get-YamlListProperty -YamlDict $yamlDict -Key "related"

    return [PSCustomObject]@{
        Title        = $title
        Description  = $description
        Author       = $author
        Domain       = $domain
        Tags         = $tags
        LastUpdated  = $lastUpdated
        Status       = $status
        TrustTier    = $trustTier
        Provenance   = $provenance
        Computations = $computations
        Contributors = $contributors
        Related      = $related
        HasYaml      = $hasYaml
        BodyText     = $bodyText
        RawYamlDict  = $yamlDict
    }
}

# --- 蜈ｨ莉ｶ繧､繝ｳ繝・ャ繧ｯ繧ｹ讒狗ｯ・& 繧ｭ繝｣繝・す繝･讖溯・ ---
$script:WikiIndex = @()
$script:WikiIndexLastScan = [DateTime]::MinValue
$script:WikiIndexDirWriteTime = [DateTime]::MinValue