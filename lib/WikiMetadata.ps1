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
    return ,@($list)
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
        $cleanRel = $RelPath.Replace('\', '/')
        $dir = [System.IO.Path]::GetDirectoryName($cleanRel)
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
            $null = $_ # Keep file time on parse failure
        }
    }

    $rawStatus = "active"
    if ($yamlDict.ContainsKey("status") -and -not [string]::IsNullOrWhiteSpace($yamlDict["status"])) {
        $rawStatus = $yamlDict["status"].ToString().ToLower().Trim()
    }

    $status = switch ($rawStatus) {
        "active"      { "active" }
        "stable"      { "stable" }
        "draft"       { "draft" }
        "deprecated"  { "deprecated" }
        "archived"    { "archived" }
        "wip"         { "draft" }
        "review"      { "draft" }
        "in-review"   { "draft" }
        "obsolete"    { "deprecated" }
        default       { "active" }
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
    $related      = Get-YamlListProperty -YamlDict $yamlDict -Key "related"
    $links        = Get-YamlListProperty -YamlDict $yamlDict -Key "links"

    $createdAt = $null
    if ($yamlDict.ContainsKey("created_at") -and -not [string]::IsNullOrWhiteSpace($yamlDict["created_at"])) {
        try { $createdAt = [DateTime]::Parse($yamlDict["created_at"]) } catch {}
    }

    $updatedAt = $lastUpdated
    if ($yamlDict.ContainsKey("updated_at") -and -not [string]::IsNullOrWhiteSpace($yamlDict["updated_at"])) {
        try { $updatedAt = [DateTime]::Parse($yamlDict["updated_at"]) } catch {}
    }

    if ($null -eq $createdAt) {
        $createdAt = if ($updatedAt) { $updatedAt } elseif ($lastUpdated) { $lastUpdated } else { Get-Date }
    }
    if ($null -eq $updatedAt) {
        $updatedAt = if ($lastUpdated) { $lastUpdated } else { Get-Date }
    }

    return [PSCustomObject]@{
        Title        = $title
        Description  = $description
        Author       = $author
        Domain       = $domain
        Tags         = $tags
        LastUpdated  = $lastUpdated
        CreatedAt    = $createdAt
        UpdatedAt    = $updatedAt
        Status       = $status
        Version      = $version
        Reviewer     = $reviewer
        SupersededBy = $supersededBy
        TrustTier    = $trustTier
        Provenance   = $provenance
        Computations = $computations
        Contributors = $contributors
        Related      = $related
        Links        = $links
        HasYaml      = $hasYaml
        RelPath      = $RelPath
        FullPath     = if ($File) { $File.FullName } else { "" }
        BodyText     = $bodyText
        RawYamlDict  = $yamlDict
        X            = 0
        Y            = 0
    }
}

function Measure-WikiNodeCoordinates {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param (
        [array]$DocList = @(),
        [int]$CanvasWidth = 1000,
        [int]$CanvasHeight = 800,
        [double]$MinDistance = 45.0
    )

    if ($null -eq $DocList -or $DocList.Count -eq 0) {
        return @()
    }

    $docCount = $DocList.Count

    # ドキュメント数に応じた仮想キャンバスの動的スケーリング (過密防止)
    $scaleUnit = 1.0
    if ($docCount -gt 25) {
        $scaleUnit = [Math]::Sqrt($docCount / 25.0)
        $CanvasWidth = [int][Math]::Max($CanvasWidth, [Math]::Round($CanvasWidth * $scaleUnit))
        $CanvasHeight = [int][Math]::Max($CanvasHeight, [Math]::Round($CanvasHeight * $scaleUnit))
    }

    $centerX = [int]($CanvasWidth / 2)
    $centerY = [int]($CanvasHeight / 2)
    $maxRadius = [Math]::Min($CanvasWidth, $CanvasHeight) * 0.42

    # 1. 共通タグおよび関連文書 (related) による親和性スコアとクラスタの計算
    $totalAffinity = @{}

    for ($i = 0; $i -lt $docCount; $i++) {
        $d1 = $DocList[$i]
        $r1 = if ($d1.RelPath) { $d1.RelPath.Replace('\', '/').ToLower() } else { $i.ToString() }
        if (-not $totalAffinity.ContainsKey($r1)) { $totalAffinity[$r1] = 0 }
        $tags1 = @(if ($d1.Tags) { foreach ($t in $d1.Tags) { if ($t -is [string] -and -not [string]::IsNullOrWhiteSpace($t)) { $t.Trim().ToLower() } } })

        for ($j = $i + 1; $j -lt $docCount; $j++) {
            $d2 = $DocList[$j]
            $r2 = if ($d2.RelPath) { $d2.RelPath.Replace('\', '/').ToLower() } else { $j.ToString() }
            if (-not $totalAffinity.ContainsKey($r2)) { $totalAffinity[$r2] = 0 }
            $tags2 = @(if ($d2.Tags) { foreach ($t in $d2.Tags) { if ($t -is [string] -and -not [string]::IsNullOrWhiteSpace($t)) { $t.Trim().ToLower() } } })

            $score = 0
            foreach ($t in $tags1) {
                if ($tags2 -contains $t) { $score += 3 }
            }
            if ($d1.Related -and ($d1.Related -contains $d2.RelPath -or $d1.Related -contains $r2)) { $score += 5 }
            if ($d2.Related -and ($d2.Related -contains $d1.RelPath -or $d2.Related -contains $r1)) { $score += 5 }
            if ($d1.Domain -and $d2.Domain) {
                if ($d1.Domain.ToLower() -eq $d2.Domain.ToLower()) {
                    $score += 2
                } else {
                    $dom1Parent = ($d1.Domain -split '[\\/]')[0].ToLower()
                    $dom2Parent = ($d2.Domain -split '[\\/]')[0].ToLower()
                    if ($dom1Parent -eq $dom2Parent) { $score += 1 }
                }
            }

            if ($score -gt 0) {
                $totalAffinity[$r1] += $score
                $totalAffinity[$r2] += $score
            }
        }
    }

    # 2. 親和性スコアが高いノード（知識のハブ文書）を中心に、関連ノードを周囲に配置
    $sortedDocs = @($DocList | Sort-Object -Descending {
        $r = if ($_.RelPath) { $_.RelPath.Replace('\', '/').ToLower() } else { "" }
        if ($totalAffinity.ContainsKey($r)) { $totalAffinity[$r] } else { 0 }
    })

    $domainGroups = @($DocList | Group-Object Domain | Sort-Object Count -Descending)
    $domainAngles = @{}
    $dCount = $domainGroups.Count
    if ($dCount -eq 0) { $dCount = 1 }
    for ($d = 0; $d -lt $dCount; $d++) {
        $domainAngles[$domainGroups[$d].Name] = (2 * [Math]::PI / $dCount) * $d
    }

    $placedNodes = [System.Collections.Generic.List[PSObject]]::new()

    # 3. 時間軸 (Z座標) のレンジ計算 (最古 = 奥/過去, 最新 = 手前/現在)
    $allTimes = foreach ($d in $DocList) {
        $dt = $null
        if ($d.UpdatedAt) {
            if ($d.UpdatedAt -is [DateTime]) { $dt = $d.UpdatedAt }
            else { [void][DateTime]::TryParse($d.UpdatedAt.ToString(), [ref]$dt) }
        }
        if (-not $dt -and $d.CreatedAt) {
            if ($d.CreatedAt -is [DateTime]) { $dt = $d.CreatedAt }
            else { [void][DateTime]::TryParse($d.CreatedAt.ToString(), [ref]$dt) }
        }
        if (-not $dt) { $dt = Get-Date }
        $dt.Ticks
    }

    $minTicks = ($allTimes | Measure-Object -Minimum).Minimum
    $maxTicks = ($allTimes | Measure-Object -Maximum).Maximum
    $timeRange = if ($maxTicks -gt $minTicks) { [double]($maxTicks - $minTicks) } else { 1.0 }
    $maxZDepth = [Math]::Round(350.0 * $scaleUnit)

    for ($i = 0; $i -lt $docCount; $i++) {
        $doc = $sortedDocs[$i]
        $r = if ($doc.RelPath) { $doc.RelPath.Replace('\', '/').ToLower() } else { "" }
        $aff = if ($totalAffinity.ContainsKey($r)) { $totalAffinity[$r] } else { 0 }

        if ($i -eq 0 -and $aff -gt 0) {
            $posX = $centerX
            $posY = $centerY
        } else {
            $baseAngle = if ($domainAngles.ContainsKey($doc.Domain)) { $domainAngles[$doc.Domain] } else { ($i * 2.39996) }
            $distFromCenter = if ($aff -ge 8) {
                90 + ($i * 10)
            } elseif ($aff -gt 0) {
                160 + ($i * 9)
            } else {
                240 + ($i * 7)
            }
            $distFromCenter = [Math]::Min($maxRadius, [double]$distFromCenter)
            $jitterAngle = $baseAngle + ((($i % 5) - 2) * 0.28)

            $posX = [Math]::Round($centerX + ($distFromCenter * [Math]::Cos($jitterAngle)))
            $posY = [Math]::Round($centerY + ($distFromCenter * [Math]::Sin($jitterAngle)))
        }

        # 衝突回避（重なり防止）
        $hasCollision = $true
        $attempts = 0
        while ($hasCollision -and $attempts -lt 50) {
            $hasCollision = $false
            foreach ($pn in $placedNodes) {
                $dx = $posX - $pn.X
                $dy = $posY - $pn.Y
                $dist = [Math]::Sqrt(($dx * $dx) + ($dy * $dy))
                if ($dist -lt $MinDistance) {
                    $hasCollision = $true
                    $overlap = $MinDistance - $dist + 1.0
                    if ($dist -gt 0) {
                        $posX += [Math]::Round(($dx / $dist) * $overlap)
                        $posY += [Math]::Round(($dy / $dist) * $overlap)
                    } else {
                        $posX += [Math]::Round($MinDistance)
                    }
                    break
                }
            }
            $attempts++
        }

        $posX = [Math]::Max(50, [Math]::Min($CanvasWidth - 50, $posX))
        $posY = [Math]::Max(50, [Math]::Min($CanvasHeight - 50, $posY))

        # Z座標（時間軸: 最古 = -$maxZDepth [奥/過去], 最新 = +$maxZDepth [手前/現在]）
        $docDt = $null
        if ($doc.UpdatedAt) {
            if ($doc.UpdatedAt -is [DateTime]) { $docDt = $doc.UpdatedAt }
            else { [void][DateTime]::TryParse($doc.UpdatedAt.ToString(), [ref]$docDt) }
        }
        if (-not $docDt -and $doc.CreatedAt) {
            if ($doc.CreatedAt -is [DateTime]) { $docDt = $doc.CreatedAt }
            else { [void][DateTime]::TryParse($doc.CreatedAt.ToString(), [ref]$docDt) }
        }
        if (-not $docDt) { $docDt = Get-Date }

        $posZ = if ($maxTicks -eq $minTicks) {
            0
        } else {
            [Math]::Round(((($docDt.Ticks - $minTicks) / $timeRange) * (2 * $maxZDepth)) - $maxZDepth)
        }

        if ($doc.PSObject -and $doc.PSObject.Properties["X"]) {
            $doc.X = [int]$posX
        } else {
            Add-Member -InputObject $doc -NotePropertyName X -NotePropertyValue ([int]$posX) -Force
        }

        if ($doc.PSObject -and $doc.PSObject.Properties["Y"]) {
            $doc.Y = [int]$posY
        } else {
            Add-Member -InputObject $doc -NotePropertyName Y -NotePropertyValue ([int]$posY) -Force
        }

        if ($doc.PSObject -and $doc.PSObject.Properties["Z"]) {
            $doc.Z = [int]$posZ
        } else {
            Add-Member -InputObject $doc -NotePropertyName Z -NotePropertyValue ([int]$posZ) -Force
        }

        $doc.X = [int]$posX
        $doc.Y = [int]$posY
        $doc.Z = [int]$posZ

        [void]$placedNodes.Add($doc)
    }

    return @($DocList)
}
Set-Alias -Name Calculate-WikiNodeCoordinates -Value Measure-WikiNodeCoordinates -ErrorAction SilentlyContinue

function Get-GlossaryTerms {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "")]
    param (
        [string]$GlossaryPath = "",
        [string]$MdText = ""
    )

    $terms = [ordered]@{}

    if ([string]::IsNullOrWhiteSpace($MdText) -and -not [string]::IsNullOrWhiteSpace($GlossaryPath) -and (Test-Path $GlossaryPath)) {
        try {
            $MdText = Get-Content -Path $GlossaryPath -Raw -Encoding UTF8
        } catch {
            return $terms
        }
    }

    if ([string]::IsNullOrWhiteSpace($MdText)) {
        return $terms
    }

    # YAML Front Matter の除去
    $bodyText = $MdText
    if ($MdText -match '(?s)^\s*---\r?\n.*?\r?\n---\r?\n(.*)$') {
        $bodyText = $matches[1]
    }

    $lines = $bodyText -split '\r?\n'
    $currentTerm = $null
    $currentLines = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $lines) {
        # 見出し (## 用語名) の判定
        if ($line -match '^\s*##\s+(.+)$') {
            $rawHeading = $matches[1].Trim()
            # 「出典」や「Sources」などの特殊見出し、または1文字以下/記号のみの無効な見出しはスキップ
            if ($rawHeading -match '^(出典|Sources|\uD83D\uDCDA)' -or [string]::IsNullOrWhiteSpace($rawHeading)) {
                if ($currentTerm) {
                    $def = ($currentLines -join "`n").Trim()
                    $terms[$currentTerm] = $def
                    $currentLines.Clear()
                    $currentTerm = $null
                }
                continue
            }

            if ($currentTerm) {
                $def = ($currentLines -join "`n").Trim()
                $terms[$currentTerm] = $def
                $currentLines.Clear()
            }
            $currentTerm = $rawHeading
        } else {
            if ($currentTerm) {
                # 上位見出し (# ...) または区切り線 (---) の出現で用語セクションを終了
                if ($line -match '^\s*#\s+' -or $line -match '^\s*---\s*$') {
                    $def = ($currentLines -join "`n").Trim()
                    $terms[$currentTerm] = $def
                    $currentLines.Clear()
                    $currentTerm = $null
                } else {
                    [void]$currentLines.Add($line)
                }
            }
        }
    }

    if ($currentTerm) {
        $def = ($currentLines -join "`n").Trim()
        $terms[$currentTerm] = $def
    }

    return $terms
}

function Get-GlossaryTermDefinition {
    param (
        [string]$Term = "",
        [string]$GlossaryPath = "",
        [string]$MdText = ""
    )

    if ([string]::IsNullOrWhiteSpace($Term)) { return $null }

    $terms = Get-GlossaryTerms -GlossaryPath $GlossaryPath -MdText $MdText
    if ($terms.Contains($Term)) {
        return $terms[$Term]
    }

    # 完全一致しない場合、略称やエイリアス表記（例: "OKF (Open Knowledge Format)" に対する "OKF"）の部分一致/カッコ抽出検索
    foreach ($key in $terms.Keys) {
        if ($key -eq $Term) { return $terms[$key] }
        if ($key -match '^\s*([^\(\（]+)\s*[\(\（]([^\)\）]+)[\)\）]') {
            $mainTerm = $matches[1].Trim()
            $altTerm  = $matches[2].Trim()
            if ($mainTerm -ieq $Term -or $altTerm -ieq $Term) {
                return $terms[$key]
            }
        }
    }

    return $null
}

function Get-SinglePageId {
    param ([string]$relPath)

    if ([string]::IsNullOrWhiteSpace($relPath)) { return "index" }
    $norm = $relPath.Replace('\', '/').TrimStart('/')
    $clean = $norm -replace '\.md$', '' -replace '\.html$', ''
    if ($clean -eq "index") { return "index" }

    $pageId = $clean -replace '[^a-zA-Z0-9_\-\u4e00-\u9faf\u3040-\u309f\u30a0-\u30ff]', '_'
    if ([string]::IsNullOrWhiteSpace($pageId)) { return "index" }
    return "page_$pageId"
}

function Get-RelToRootPath {
    param ([string]$relPath)

    if ([string]::IsNullOrWhiteSpace($relPath)) { return "." }
    $norm = $relPath.Replace('\', '/').TrimStart('/')
    $parts = $norm -split '/'
    $depth = $parts.Length - 1
    if ($depth -le 0) { return "." }
    return ((1..$depth | ForEach-Object { ".." }) -join "/")
}

$script:WikiIndex = @()
$script:WikiIndexLastScan = [DateTime]::MinValue
$script:WikiIndexDirWriteTime = [DateTime]::MinValue
