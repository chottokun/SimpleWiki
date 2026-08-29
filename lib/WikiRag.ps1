# ==============================================================================
#  SimpleWiki Agentic RAG & LLM AI チャットモジュール
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================

function Invoke-ToolSearchOkf {
    param (
        [string]$Query = "",
        [string]$Domain = "",
        [string]$WikiDir = ""
    )
    $targetDir = if (-not [string]::IsNullOrWhiteSpace($WikiDir)) { $WikiDir } else { $script:wikiDir }
    if ([string]::IsNullOrWhiteSpace($targetDir)) { $targetDir = $scriptDir }

    $res = Search-OkfDocs -Query $Query -DomainFilter $Domain -StatusFilter "active" -WikiDir $targetDir -MaxResults 5

    # 1. ドメイン絞り込みで0件だった場合、全ドメインでフォールバック検索
    if ($res.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($Domain)) {
        $res = Search-OkfDocs -Query $Query -DomainFilter "" -StatusFilter "active" -WikiDir $targetDir -MaxResults 5
    }

    # 2. クエリ全体で0件だった場合、日本語形態素単語分割でフォールバック検索 (除外条件は保持)
    if ($res.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($Query)) {
        $parsed = Split-SearchQueryTerms -Query $Query
        if (-not [string]::IsNullOrWhiteSpace($parsed.CleanQuery)) {
            $kwList = Get-JapaneseWordsWinRT -Text $parsed.CleanQuery
            if ($kwList -and $kwList.Count -gt 0) {
                $subQuery = ($kwList -join " ")
                if ($parsed.ExcludeKeywords.Count -gt 0) {
                    $subQuery += " " + (($parsed.ExcludeKeywords | ForEach-Object { "-$_" }) -join " ")
                }
                if ($subQuery -ne $Query) {
                    $res = Search-OkfDocs -Query $subQuery -DomainFilter "" -StatusFilter "active" -WikiDir $targetDir -MaxResults 5
                }
            }
        }
    }

    if ($res.Count -eq 0) {
        return "検索結果は見つかりませんでした。domain を空文字 '' に指定して全Wiki検索を試すか、別のキーワードを指定してください。"
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("🔍 検索結果候補 (計 $($res.Count) 件):")
    $idx = 0
    foreach ($r in $res) {
        $idx++
        $meta = $r.Meta
        [void]$sb.AppendLine("[$idx] 📄 タイトル: $($meta.Title) | RelPath: '$($meta.RelPath)' | Domain: '$($meta.Domain)' | 更新: $($meta.LastUpdated.ToString('yyyy-MM-dd'))")
        [void]$sb.AppendLine("    ・概要: $($meta.Description)")
        if (-not [string]::IsNullOrWhiteSpace($r.Snippet)) {
            [void]$sb.AppendLine("    ・本文スニペット:`n$($r.Snippet)")
        }
    }
    [void]$sb.AppendLine("`n※ 情報を網羅・検証するために、必要に応じて未確認の上記候補ドキュメントの RelPath に対して ``read_doc(relPath)`` を呼び出して参照してください。")
    return $sb.ToString()
}

function Invoke-ToolReadDoc {
    param (
        [string]$RelPath = "",
        [string]$WikiDir = "",
        [int]$MaxChars = 2000
    )
    if ([string]::IsNullOrWhiteSpace($RelPath)) { return "エラー: RelPath が指定されていません。" }

    $targetDir = if (-not [string]::IsNullOrWhiteSpace($WikiDir)) { $WikiDir } else { $script:wikiDir }
    if ([string]::IsNullOrWhiteSpace($targetDir)) { $targetDir = $scriptDir }

    $cleanRel = $RelPath.TrimStart('\', '/').Replace('/', '\')
    $full = Join-Path $targetDir $cleanRel

    if (-not (Test-Path $full)) {
        Build-WikiIndex -TargetWikiDir $targetDir | Out-Null
        $found = $script:WikiIndex | Where-Object { $_.RelPath -eq $cleanRel -or $_.RelPath -like "*$cleanRel*" } | Select-Object -First 1
        if ($found) {
            $full = Join-Path $targetDir $found.RelPath
            $cleanRel = $found.RelPath
        } else {
            return "エラー: ドキュメント 『$RelPath』 が見つかりません。"
        }
    }

    $fileObj = Get-Item $full
    $meta = Get-DocumentMetadata -File $fileObj -RelPath $cleanRel
    if ($meta.Status -eq "deprecated") {
        return "⚠️ 警告: ドキュメント 『$cleanRel』 は非推奨 (deprecated) です。現行Active情報ではありません。"
    }

    $body = $meta.BodyText
    if ([string]::IsNullOrWhiteSpace($body)) { return "ドキュメント本文は空です。" }

    if ($MaxChars -gt 0 -and $body.Length -gt $MaxChars) {
        $body = $body.Substring(0, $MaxChars) + "`n...[文字数制限により以降省略 (最大 $MaxChars 文字)]"
    }

    return "■ ドキュメント: $($meta.Title) ($cleanRel)`n$body"
}

function Invoke-ToolLookupGlossary {
    param (
        [string]$Term = "",
        [string]$WikiDir = ""
    )
    if ([string]::IsNullOrWhiteSpace($Term)) { return "エラー: Term が指定されていません。" }

    $targetDir = if (-not [string]::IsNullOrWhiteSpace($WikiDir)) { $WikiDir } else { $script:wikiDir }
    if ([string]::IsNullOrWhiteSpace($targetDir)) { $targetDir = $scriptDir }

    Build-WikiIndex -TargetWikiDir $targetDir | Out-Null

    $glossaryDoc = $script:WikiIndex | Where-Object { $_.RelPath -like "*glossary.md*" -or $_.Title -like "*用語*" } | Select-Object -First 1
    if ($glossaryDoc -and $glossaryDoc.BodyText) {
        $lines = $glossaryDoc.BodyText -split "\r?\n"
        $termRegex = [regex]::Escape($Term)
        $matchedBlock = [System.Collections.Generic.List[string]]::new()
        $recording = $false

        foreach ($line in $lines) {
            if ($line -match "(?i)^\s*#{1,4}\s+.*$termRegex" -or $line -match "(?i)^\s*[\*\-]\s+.*$termRegex") {
                $recording = $true
            } elseif ($recording -and $line -match "^\s*#{1,3}\s+") {
                break
            }
            if ($recording) {
                $matchedBlock.Add($line)
            }
        }

        if ($matchedBlock.Count -gt 0) {
            return "📖 用語集 ($($glossaryDoc.RelPath)) より抽出:`n" + ($matchedBlock -join "`n")
        }
    }

    $results = Search-OkfDocs -Query $Term -StatusFilter "active" -WikiDir $targetDir -MaxResults 2
    if ($results.Count -gt 0) {
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine("📖 用語 『$Term』 に関連するドキュメント記述:")
        foreach ($r in $results) {
            [void]$sb.AppendLine("・$($r.Meta.Title) ($($r.Meta.RelPath)): $($r.Snippet)")
        }
        return $sb.ToString()
    }

    return "用語 『$Term』 の定義は Wiki 内で見つかりませんでした。"
}

function Invoke-ToolGetLinkedDocs {
    param (
        [string]$RelPath = "",
        [string]$WikiDir = ""
    )
    if ([string]::IsNullOrWhiteSpace($RelPath)) { return @() }

    $targetDir = if (-not [string]::IsNullOrWhiteSpace($WikiDir)) { $WikiDir } else { $script:wikiDir }
    if ([string]::IsNullOrWhiteSpace($targetDir)) { $targetDir = $scriptDir }

    $cleanRel = $RelPath.TrimStart('\', '/').Replace('/', '\')
    $full = Join-Path $targetDir $cleanRel
    if (-not (Test-Path $full)) {
        return @()
    }

    $mdText = Get-Content -Path $full -Raw -Encoding UTF8
    $foundMatches = [regex]::Matches($mdText, '\[([^\]]+)\]\(([^)]+\.md)(?:#[^)]*)?\)')

    if ($foundMatches.Count -eq 0) {
        return @()
    }

    $linkedItems = [System.Collections.Generic.List[PSCustomObject]]::new()
    $baseDir = [System.IO.Path]::GetDirectoryName($cleanRel)

    foreach ($m in $foundMatches) {
        $linkText = $m.Groups[1].Value
        $linkTarget = $m.Groups[2].Value

        $resolvedRel = if ([string]::IsNullOrWhiteSpace($baseDir)) { $linkTarget } else { Join-Path $baseDir $linkTarget }
        $resolvedRel = $resolvedRel.Replace('/', '\')

        $targetFull = Join-Path $targetDir $resolvedRel
        $status = "not_found"
        $title = $linkText

        if (Test-Path $targetFull) {
            $meta = Get-DocumentMetadata -File (Get-Item $targetFull) -RelPath $resolvedRel
            $status = $meta.Status
            $title = $meta.Title
        }

        $linkedItems.Add([PSCustomObject]@{
            LinkText = $linkText
            RelPath  = $resolvedRel
            Title    = $title
            Status   = $status
        })
    }

    return $linkedItems
}

# --- 検索結果ビュー生成関数 (OKF 文脈検索エンジン) ---

function Invoke-OpenAiChatCompletions {
    param (
        [string]$ApiUrl,
        [string]$ApiKey,
        [string]$Model,
        [string]$SystemPrompt,
        [string]$UserMessage,
        [array]$History = @(),
        [int]$TimeoutSec = 30,
        [switch]$Stream,
        [scriptblock]$OnChunkReceived
    )

    $resolvedKey = Get-ResolvedSecret -SecretValue $ApiKey
    $cleanApiUrl = $ApiUrl.TrimEnd('/')
    $endpointUrl = "$cleanApiUrl/chat/completions"
    if ($cleanApiUrl.EndsWith("/chat/completions")) {
        $endpointUrl = $cleanApiUrl
    }

    $msgList = [System.Collections.Generic.List[PSObject]]::new()
    $msgList.Add(@{ role = "system"; content = $SystemPrompt })

    if ($History -and $History.Count -gt 0) {
        foreach ($h in $History) {
            if ($h -and $h.role -and $h.content) {
                $msgList.Add(@{ role = $h.role.ToString(); content = $h.content.ToString() })
            }
        }
    }
    $msgList.Add(@{ role = "user"; content = $UserMessage })

    $payloadObj = @{
        model       = $Model
        temperature = 0.3
        messages    = $msgList
    }
    if ($Stream) {
        $payloadObj["stream"] = $true
    }
    $jsonBody = $payloadObj | ConvertTo-Json -Depth 5
    $reqBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

    $executeRequest = {
        param([bool]$UseStreamPayload)

        $currentPayload = @{
            model       = $Model
            temperature = 0.3
            messages    = $msgList
        }
        if ($UseStreamPayload) {
            $currentPayload["stream"] = $true
        }
        $currentJson = $currentPayload | ConvertTo-Json -Depth 5
        $currentBytes = [System.Text.Encoding]::UTF8.GetBytes($currentJson)

        $webReq = [System.Net.HttpWebRequest]::Create($endpointUrl)
        $webReq.Method = "POST"
        $webReq.ContentType = "application/json; charset=utf-8"
        $webReq.Timeout = $TimeoutSec * 1000
        if (-not [string]::IsNullOrWhiteSpace($resolvedKey)) {
            $webReq.Headers["Authorization"] = "Bearer $resolvedKey"
        }

        $reqStream = $webReq.GetRequestStream()
        $reqStream.Write($currentBytes, 0, $currentBytes.Length)
        $reqStream.Close()

        return $webReq.GetResponse()
    }

    try {
        $webRes = $null
        $isStreamMode = [bool]$Stream
        try {
            $webRes = & $executeRequest $isStreamMode
        } catch [System.Net.WebException] {
            # ストリーム要求で失敗した場合、ストリーム非対応APIへのフォールバックとして非ストリームで再試行
            if ($isStreamMode) {
                try {
                    $isStreamMode = $false
                    $webRes = & $executeRequest $false
                } catch {
                    if ($_.Response) {
                        $errStream = $_.Response.GetResponseStream()
                        $errReader = New-Object System.IO.StreamReader($errStream, [System.Text.Encoding]::UTF8)
                        $errBody = $errReader.ReadToEnd()
                        throw "API エラー ($($_.Response.StatusCode)): $errBody"
                    }
                    throw $_
                }
            } else {
                if ($_.Response) {
                    $errStream = $_.Response.GetResponseStream()
                    $errReader = New-Object System.IO.StreamReader($errStream, [System.Text.Encoding]::UTF8)
                    $errBody = $errReader.ReadToEnd()
                    throw "API エラー ($($_.Response.StatusCode)): $errBody"
                }
                throw $_
            }
        }

        try {
            $resStream = $webRes.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($resStream, [System.Text.Encoding]::UTF8)
            $contentType = if ($webRes.ContentType) { $webRes.ContentType.ToLower() } else { "" }

            # ストリームモードかつ SSE レスポンスの場合の処理
            if ($isStreamMode -and -not $contentType.Contains("application/json")) {
                $fullTextBuilder = [System.Text.StringBuilder]::new()
                $firstLine = $true
                $isActualSse = $false

                while (($line = $reader.ReadLine()) -ne $null) {
                    if ($firstLine) {
                        $firstLine = $false
                        # 最初の行が { で始まるなら通常の JSON レスポンスと判定してフォールバック
                        if ($line.Trim().StartsWith("{")) {
                            $rest = $reader.ReadToEnd()
                            $allJson = $line + "`n" + $rest
                            $parsed = try { $allJson | ConvertFrom-Json } catch { $null }
                            if ($parsed -and $parsed.choices -and $parsed.choices.Count -gt 0) {
                                $content = $parsed.choices[0].message.content
                                if ($OnChunkReceived) { & $OnChunkReceived $content }
                                return $content
                            }
                            throw "LLM から無効な JSON レスポンスが返却されました。"
                        }
                    }

                    if ($line.StartsWith("data: ")) {
                        $isActualSse = $true
                        $payload = $line.Substring(6).Trim()
                        if ($payload -eq "[DONE]") { break }
                        $chunkObj = try { $payload | ConvertFrom-Json } catch { $null }
                        if ($chunkObj -and $chunkObj.choices -and $chunkObj.choices.Count -gt 0) {
                            $delta = $chunkObj.choices[0].delta
                            if ($delta -and $delta.content) {
                                [void]$fullTextBuilder.Append($delta.content)
                                if ($OnChunkReceived) { & $OnChunkReceived $delta.content }
                            }
                        }
                    }
                }

                if ($isActualSse) {
                    return $fullTextBuilder.ToString()
                }
            }

            # 通常の一括 JSON 処理 (非ストリーム、または非SSEフォールバック)
            $resJson = $reader.ReadToEnd()
            $parsed = $resJson | ConvertFrom-Json
            if ($parsed -and $parsed.choices -and $parsed.choices.Count -gt 0) {
                $content = $parsed.choices[0].message.content
                if ($OnChunkReceived) {
                    & $OnChunkReceived $content
                }
                return $content
            }
            throw "LLM から無効なレスポンスが返却されました。"
        } finally {
            $webRes.Close()
        }
    } catch [System.Net.WebException] {
        if ($_.Response) {
            $errStream = $_.Response.GetResponseStream()
            $errReader = New-Object System.IO.StreamReader($errStream, [System.Text.Encoding]::UTF8)
            $errBody = $errReader.ReadToEnd()
            throw "API エラー ($($_.Response.StatusCode)): $errBody"
        }
        throw $_
    }
}

# --- Agentic RAG ReAct ループ実行関数 ---
function Invoke-AgenticRagChat {
    param (
        [string]$ApiUrl,
        [string]$ApiKey,
        [string]$Model,
        [string]$UserMessage,
        [array]$History = @(),
        [string]$WikiDir = "",
        [int]$MaxTurns = 5,
        [int]$MaxDocChars = 2000,
        [int]$TimeoutSec = 30,
        [PSCustomObject]$CurrentDoc = $null,
        [string]$Lang = "ja",
        [string]$CustomAgenticPrompt = "",
        [switch]$Stream,
        [scriptblock]$OnThinkingCallback,
        [scriptblock]$OnChunkReceived
    )

    $targetDir = if (-not [string]::IsNullOrWhiteSpace($WikiDir)) { $WikiDir } else { $script:wikiDir }
    if ([string]::IsNullOrWhiteSpace($targetDir)) { $targetDir = $scriptDir }

    $thinkingLog = [System.Collections.Generic.List[string]]::new()
    $sourcesList = [System.Collections.Generic.List[PSObject]]::new()
    $visitedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $logStep = {
        param([string]$Message)
        [void]$thinkingLog.Add($Message)
        if ($OnThinkingCallback) {
            try { & $OnThinkingCallback $Message } catch { }
        }
    }

    $isEn = ($Lang -eq "en")

    $baseAgenticHeader = if (-not [string]::IsNullOrWhiteSpace($CustomAgenticPrompt)) {
        $CustomAgenticPrompt
    } else {
        Get-LocalizedStr -Key "default_agentic_system_prompt" -Lang $Lang
    }

    $tools = @(
        @{
            type = "function"
            function = @{
                name = "search_okf"
                description = if ($isEn) { "Searches active Wiki documents using OKF scoring and keyword/NOT filtering." } else { "OKFスコアリングによりWiki内のActiveドキュメントを検索します。" }
                parameters = @{
                    type = "object"
                    properties = @{
                        query = @{ type = "string"; description = if ($isEn) { "Search query keywords (supports NOT syntax like '-word' or 'NOT word')." } else { "検索キーワード (日本語キーワードをそのまま使用。除外したい単語がある場合は '-単語' や 'NOT 単語' が指定可能)" } }
                        domain = @{ type = "string"; description = if ($isEn) { "Domain filter (specify '' to search all Wiki documents by default)." } else { "絞り込みドメイン (原則は空文字列 '' を指定してWiki全域を検索してください)" } }
                    }
                    required = @("query")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "lookup_glossary"
                description = if ($isEn) { "Looks up term definitions from glossary.md or Wiki descriptions." } else { "用語集 (glossary.md) またはWiki内の記述から特定用語の定義を調べます。" }
                parameters = @{
                    type = "object"
                    properties = @{
                        term = @{ type = "string"; description = if ($isEn) { "Term to look up" } else { "調べたい社内用語" } }
                    }
                    required = @("term")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "read_doc"
                description = if ($isEn) { "Retrieves the body text of a specified markdown document (YAML header stripped)." } else { "指定したドキュメントの本文を取得します (YAMLヘッダー除外)。" }
                parameters = @{
                    type = "object"
                    properties = @{
                        relPath = @{ type = "string"; description = if ($isEn) { "Relative path to markdown file (e.g. docs/infrastructure/db.md)" } else { "Markdownファイルの相対パス (例: docs/infrastructure/db.md)" } }
                    }
                    required = @("relPath")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "get_linked_docs"
                description = if ($isEn) { "Retrieves all relative markdown hyperlinks contained within a specified document." } else { "指定ドキュメント内に含まれる他のMarkdownファイルへのハイパーリンク一覧を取得します。" }
                parameters = @{
                    type = "object"
                    properties = @{
                        relPath = @{ type = "string"; description = if ($isEn) { "Path of markdown file to inspect" } else { "調査対象のMarkdownファイルパス" } }
                    }
                    required = @("relPath")
                }
            }
        }
    )

    $sysPrompt = if ($isEn) {
        "$baseAgenticHeader`n" +
        "【Autonomous Exploration & Knowledge Expansion Rules】`n" +
        "1. If direct keyword matches or explicit answers are scarce, do NOT give up with 'No information found'.`n" +
        "2. Actively explore and drill down using `read_doc` on candidates returned by `search_okf` (top 5) and related links from `get_linked_docs`.`n" +
        "3. Even if there is no direct answer, present related specifications, guidelines, or relevant background knowledge gathered during investigation clearly.`n" +
        "4. Use search keywords without unwarranted modification or translation unless necessary.`n" +
        "5. Specify an empty string '' for the domain parameter in search_okf to search broadly across the entire Wiki by default.`n" +
        "6. Avoid deprecated content (status: deprecated) and rely on active information.`n" +
        "7. If the user requests exclusions (e.g. 'excluding X', 'without Y'), use `-keyword` or `NOT keyword` syntax in `search_okf`.`n" +
        "8. Reply in English with clear Markdown formatting."
    } else {
        "$baseAgenticHeader`n" +
        "【自律探索・キーワード限界突破ルール】`n" +
        "1. 質問に対する直接の単語一致・該当記述が見つからない・薄い場合でも『該当なし』で諦めないでください。`n" +
        "2. `search_okf` で得られた候補ドキュメント（上位 5 件）や `get_linked_docs` の関連リンクを積極的に `read_doc` で回遊・深掘りし、周辺知識や関連ガイドラインを探索してください。`n" +
        "3. 直接の回答がない場合でも、『直接の記載はありませんが、関連する以下の仕様・手順が参考になります』として、収集した関連ナレッジや補足情報をユーザーに提示してください。`n" +
        "4. 検索キーワード (query) はユーザーが入力した日本語単語（例: 'エラー', '想定されるエラー'）をそのまま使用し、勝手に英語へ翻訳しないでください。`n" +
        "5. search_okf の domain パラメータは原則として空文字列 '' を指定し、Wiki 全域から広範にドキュメントを検索してください。`n" +
        "6. 非推奨 (status: deprecated) の記述は避け、常に現行 (active) 情報のみを根拠にしてください。`n" +
        "7. ユーザーが『〇〇以外』『〇〇を除いて』等の除外条件を求めている場合や、ノイズを除去したい場合は、`search_okf` の query に `-除外語` や `NOT 除外語`（例: 'サーバー -Windows', 'API NOT deprecated'）を活用してください。"
    }


    if ($CurrentDoc -and $CurrentDoc.RelPath) {
        if (-not $visitedPaths.Contains($CurrentDoc.RelPath)) {
            [void]$visitedPaths.Add($CurrentDoc.RelPath)
        }
        $currSnippet = $CurrentDoc.BodyText
        if ($currSnippet -and $currSnippet.Length -gt 1500) {
            $currSnippet = $currSnippet.Substring(0, 1500) + "..."
        }
        if ($isEn) {
            $sysPrompt += "`n`n【Context of Current Page Open in User's Browser】`n" +
                "・Title: $($CurrentDoc.Title)`n" +
                "・Relative Path: $($CurrentDoc.RelPath)`n" +
                "・Body:`n$currSnippet"
        } else {
            $sysPrompt += "`n`n【現在ユーザーが開いているページのコンテキスト】`n" +
                "・タイトル: $($CurrentDoc.Title)`n" +
                "・相対パス: $($CurrentDoc.RelPath)`n" +
                "・本文:`n$currSnippet"
        }
    }

    $messages = [System.Collections.Generic.List[PSObject]]::new()
    [void]$messages.Add(@{ role = "system"; content = $sysPrompt })


    if ($History -and $History.Count -gt 0) {
        foreach ($h in $History) {
            if ($h -and $h.role -and $h.content) {
                [void]$messages.Add(@{ role = $h.role.ToString(); content = $h.content.ToString() })
            }
        }
    }
    [void]$messages.Add(@{ role = "user"; content = $UserMessage })

    $resolvedKey = Get-ResolvedSecret -SecretValue $ApiKey
    $cleanApiUrl = $ApiUrl.TrimEnd('/')
    $endpointUrl = "$cleanApiUrl/chat/completions"
    if ($cleanApiUrl.EndsWith("/chat/completions")) {
        $endpointUrl = $cleanApiUrl
    }

    $currentTurn = 0
    $finalAnswer = ""

    while ($currentTurn -lt $MaxTurns) {
        $currentTurn++

        $payloadObj = @{
            model       = $Model
            temperature = 0.2
            messages    = $messages
            tools       = $tools
        }

        $jsonBody = $payloadObj | ConvertTo-Json -Depth 6
        $reqBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

        $webReq = [System.Net.HttpWebRequest]::Create($endpointUrl)
        $webReq.Method = "POST"
        $webReq.ContentType = "application/json; charset=utf-8"
        $webReq.Timeout = $TimeoutSec * 1000
        if (-not [string]::IsNullOrWhiteSpace($resolvedKey)) {
            $webReq.Headers["Authorization"] = "Bearer $resolvedKey"
        }

        $resMsg = $null
        try {
            $reqStream = $webReq.GetRequestStream()
            $reqStream.Write($reqBytes, 0, $reqBytes.Length)
            $reqStream.Close()

            $webRes = $webReq.GetResponse()
            try {
                $resStream = $webRes.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($resStream, [System.Text.Encoding]::UTF8)
                $resJson = $reader.ReadToEnd()
                $parsed = $resJson | ConvertFrom-Json
                if ($parsed -and $parsed.choices -and $parsed.choices.Count -gt 0) {
                    $resMsg = $parsed.choices[0].message
                }
            } finally {
                $webRes.Close()
            }
        } catch {
            & $logStep "⚠️ LLM API Tool Calling 通信エラー。Fast モードへフォールバックします。"
            break
        }

        if (-not $resMsg) { break }

        $msgHashtable = @{ role = "assistant" }
        if ($resMsg.content) { $msgHashtable["content"] = $resMsg.content }
        if ($resMsg.tool_calls) { $msgHashtable["tool_calls"] = $resMsg.tool_calls }
        [void]$messages.Add($msgHashtable)

        if ($resMsg.tool_calls -and $resMsg.tool_calls.Count -gt 0) {
            foreach ($toolCall in $resMsg.tool_calls) {
                $callId = $toolCall.id
                $fnName = $toolCall.function.name
                $argsJson = $toolCall.function.arguments
                $argsObj = try { $argsJson | ConvertFrom-Json } catch { @{} }

                $toolResult = ""

                switch ($fnName) {
                    "search_okf" {
                        $q = if ($argsObj.query) { $argsObj.query } else { "" }
                        $d = if ($argsObj.domain) { $argsObj.domain } else { "" }
                        & $logStep "🔍 Tool Call: search_okf (query: '$q', domain: '$d')"
                        $toolResult = Invoke-ToolSearchOkf -Query $q -Domain $d -WikiDir $targetDir
                        # 検索ヒット候補を visitedPaths にも記録
                        $rawHits = Search-OkfDocs -Query $q -DomainFilter $d -StatusFilter "active" -WikiDir $targetDir -MaxResults 5
                        if ($rawHits) {
                            foreach ($rh in $rawHits) {
                                if ($rh.Meta -and $rh.Meta.RelPath -and -not $visitedPaths.Contains($rh.Meta.RelPath)) {
                                    [void]$visitedPaths.Add($rh.Meta.RelPath)
                                }
                            }
                        }
                    }
                    "lookup_glossary" {
                        $t = if ($argsObj.term) { $argsObj.term } else { "" }
                        & $logStep "📖 Tool Call: lookup_glossary (term: '$t')"
                        $toolResult = Invoke-ToolLookupGlossary -Term $t -WikiDir $targetDir
                    }
                    "read_doc" {
                        $p = if ($argsObj.relPath) { $argsObj.relPath } else { "" }
                        & $logStep "📄 Tool Call: read_doc (relPath: '$p')"
                        $toolResult = Invoke-ToolReadDoc -RelPath $p -WikiDir $targetDir -MaxChars $MaxDocChars
                        if ($p -and -not $visitedPaths.Contains($p)) {
                            [void]$visitedPaths.Add($p)
                        }
                    }
                    "get_linked_docs" {
                        $p = if ($argsObj.relPath) { $argsObj.relPath } else { "" }
                        & $logStep "🔗 Tool Call: get_linked_docs (relPath: '$p')"
                        $links = Invoke-ToolGetLinkedDocs -RelPath $p -WikiDir $targetDir
                        if ($links -and $links.Count -gt 0) {
                            $linkStrList = foreach ($l in $links) { "・[$($l.LinkText)]($($l.RelPath)) [Status: $($l.Status)]" }
                            $headerTxt = if ($isEn) { "Link List:" } else { "リンク一覧:" }
                            $toolResult = "$headerTxt`n" + ($linkStrList -join "`n")
                        } else {
                            $toolResult = if ($isEn) { "No hyperlinks found in document." } else { "リンクは見つかりませんでした。" }
                        }
                    }
                    default {
                        $toolResult = if ($isEn) { "Unknown tool name: $fnName" } else { "未知のツール名: $fnName" }
                    }
                }

                [void]$messages.Add(@{
                    role         = "tool"
                    tool_call_id = $callId
                    content      = $toolResult
                })
            }
        } else {
            # ツール呼び出しを行わずに最終回答が返ってきた場合
            if ($resMsg.content) {
                $finalAnswer = $resMsg.content
                if ($OnChunkReceived) {
                    & $OnChunkReceived $finalAnswer
                }
                break
            }
        }
    }

    Build-WikiIndex -TargetWikiDir $targetDir | Out-Null
    foreach ($vp in $visitedPaths) {
        $found = $script:WikiIndex | Where-Object { $_.RelPath -eq $vp -or $_.RelPath -like "*$vp*" } | Select-Object -First 1
        if ($found) {
            $relUri = "/" + [Uri]::EscapeUriString($found.RelPath.Replace('\', '/'))
            [void]$sourcesList.Add([PSCustomObject]@{
                title       = $found.Title
                relPath     = $found.RelPath
                relUri      = $relUri
                lastUpdated = $found.LastUpdated.ToString("yyyy-MM-dd")
                author      = $found.Author
                status      = $found.Status
            })
        }
    }

    if ([string]::IsNullOrWhiteSpace($finalAnswer)) {
        $maxTurnsLog = if ($isEn) { "⏱️ Reached turn limit ($MaxTurns); generating summarized answer from gathered knowledge." } else { "⏱️ ターン上限 ($MaxTurns) に達したため、収集情報から要約回答を生成します。" }
        & $logStep $maxTurnsLog
        $fallbackUserPrompt = if ($isEn) {
            "※Output your final conclusion as text based on the information gathered so far without making further tool calls. Even if there is no direct answer, clearly present related knowledge, specifications, and helpful information gathered from the explored documents in English."
        } else {
            "※これ以上のツール呼び出しを行わず、ここまでに取得・探索した情報を元に結論をテキストで最終出力してください。質問に対する完全な直接回答が無い場合でも『該当なし』で終わらせず、探索したドキュメントから得られる関連知識や補足情報を分かりやすく提示してください。"
        }
        [void]$messages.Add(@{ role = "user"; content = $fallbackUserPrompt })

        $payloadObj = @{
            model       = $Model
            temperature = 0.2
            messages    = $messages
        }
        if ($Stream) {
            $payloadObj["stream"] = $true
        }
        $jsonBody = $payloadObj | ConvertTo-Json -Depth 5
        $reqBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

        try {
            $webReq = [System.Net.HttpWebRequest]::Create($endpointUrl)
            $webReq.Method = "POST"
            $webReq.ContentType = "application/json; charset=utf-8"
            $webReq.Timeout = $TimeoutSec * 1000
            if (-not [string]::IsNullOrWhiteSpace($resolvedKey)) {
                $webReq.Headers["Authorization"] = "Bearer $resolvedKey"
            }

            $reqStream = $webReq.GetRequestStream()
            $reqStream.Write($reqBytes, 0, $reqBytes.Length)
            $reqStream.Close()

            $webRes = $webReq.GetResponse()
            try {
                $resStream = $webRes.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($resStream, [System.Text.Encoding]::UTF8)
                $contentType = if ($webRes.ContentType) { $webRes.ContentType.ToLower() } else { "" }

                if ($Stream -and -not $contentType.Contains("application/json")) {
                    $sb = [System.Text.StringBuilder]::new()
                    $firstLine = $true
                    $isActualSse = $false
                    while (($line = $reader.ReadLine()) -ne $null) {
                        if ($firstLine) {
                            $firstLine = $false
                            if ($line.Trim().StartsWith("{")) {
                                $rest = $reader.ReadToEnd()
                                $allJson = $line + "`n" + $rest
                                $parsed = try { $allJson | ConvertFrom-Json } catch { $null }
                                if ($parsed -and $parsed.choices -and $parsed.choices.Count -gt 0) {
                                    $finalAnswer = $parsed.choices[0].message.content
                                    if ($OnChunkReceived) { & $OnChunkReceived $finalAnswer }
                                }
                                break
                            }
                        }
                        if ($line.StartsWith("data: ")) {
                            $isActualSse = $true
                            $payload = $line.Substring(6).Trim()
                            if ($payload -eq "[DONE]") { break }
                            $chunkObj = try { $payload | ConvertFrom-Json } catch { $null }
                            if ($chunkObj -and $chunkObj.choices -and $chunkObj.choices.Count -gt 0) {
                                $delta = $chunkObj.choices[0].delta
                                if ($delta -and $delta.content) {
                                    [void]$sb.Append($delta.content)
                                    if ($OnChunkReceived) { & $OnChunkReceived $delta.content }
                                }
                            }
                        }
                    }
                    if ($isActualSse) {
                        $finalAnswer = $sb.ToString()
                    }
                } else {
                    $resJson = $reader.ReadToEnd()
                    $parsed = $resJson | ConvertFrom-Json
                    if ($parsed -and $parsed.choices -and $parsed.choices.Count -gt 0) {
                        $finalAnswer = $parsed.choices[0].message.content
                        if ($OnChunkReceived) { & $OnChunkReceived $finalAnswer }
                    }
                }
            } finally {
                $webRes.Close()
            }
        } catch {
            # 通信例外等のキャッチ
        }

        if ([string]::IsNullOrWhiteSpace($finalAnswer)) {
            if ($visitedPaths.Count -gt 0) {
                if ($isEn) {
                    $finalAnswer = "I autonomously investigated the Wiki, but could not find a direct mention exactly matching your query.\n\n### Investigated Related Documents\n" + (($visitedPaths | ForEach-Object { "- [$_]($_)" }) -join "`n")
                } else {
                    $finalAnswer = "Wiki 内を自律調査しましたが、質問に完全一致する直接記述は見つかりませんでした。\n\n### 調査した関連ドキュメント\n" + (($visitedPaths | ForEach-Object { "- [$_]($_)" }) -join "`n")
                }
            } else {
                if ($isEn) {
                    $finalAnswer = "I searched the Wiki, but could not find any direct mention matching your query. Please refer to relevant guide documents."
                } else {
                    $finalAnswer = "Wiki 内を自律検索しましたが、質問に直接該当する明確な記載は見つかりませんでした。関連するガイド（`guides/環境構築.md` や `docs/詳細仕様.md` など）を参照してください。"
                }
            }
            if ($OnChunkReceived) { & $OnChunkReceived $finalAnswer }
        }
    }


    return [PSCustomObject]@{
        answer      = $finalAnswer
        thinkingLog = $thinkingLog
        sources     = $sourcesList
    }
}
