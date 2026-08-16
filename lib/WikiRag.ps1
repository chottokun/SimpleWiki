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

    # 2. クエリ全体で0件だった場合、日本語形態素単語分割でフォールバック検索
    if ($res.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($Query)) {
        $kwList = Get-JapaneseWordsWinRT -Text $Query
        if ($kwList -and $kwList.Count -gt 0) {
            $subQuery = $kwList -join " "
            if ($subQuery -ne $Query) {
                $res = Search-OkfDocs -Query $subQuery -DomainFilter "" -StatusFilter "active" -WikiDir $targetDir -MaxResults 5
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
    [void]$sb.AppendLine("`n※ 情報を網羅・検証するために、必要に応じて未確認の上記候補ドキュメントの RelPath に対して `read_doc(relPath)` を呼び出して参照してください。")
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

    # 概要・目次ドキュメント判定（index.md, README.md や内部リンクを含むドキュメントへの自律回遊ヒント追加）
    $linkMatches = [regex]::Matches($body, '\[([^\]]+)\]\(([^)]+\.md)(?:#[^)]*)?\)')
    $linkHint = ""
    if ($linkMatches.Count -gt 0) {
        $linkedPaths = [System.Collections.Generic.List[string]]::new()
        $baseDir = [System.IO.Path]::GetDirectoryName($cleanRel)

        foreach ($m in $linkMatches) {
            $linkText = $m.Groups[1].Value
            $linkTarget = $m.Groups[2].Value
            $resolvedRel = if ([string]::IsNullOrWhiteSpace($baseDir)) { $linkTarget } else { Join-Path $baseDir $linkTarget }
            $resolvedRel = $resolvedRel.Replace('/', '\')
            [void]$linkedPaths.Add("・'$resolvedRel' ($linkText)")
        }

        $linkStr = $linkedPaths -join "`n"
        $linkHint = "`n`n--------------------------------------------------`n" +
            "💡【ネクストステップ指示 (自律深掘り)】`n" +
            "このドキュメント内には以下の関連 Markdown ファイルへのリンクが含まれています。`n" +
            "目次・概要の記述だけで回答を完結させず、質問の回答に必要な本文情報を得るために、未確認の以下の RelPath に対して `read_doc(relPath)` を呼び出して【詳細本文】を確認してください：`n" +
            $linkStr
    }

    return "■ ドキュメント: $($meta.Title) ($cleanRel)`n$body$linkHint"
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
    $matches = [regex]::Matches($mdText, '\[([^\]]+)\]\(([^)]+\.md)(?:#[^)]*)?\)')

    if ($matches.Count -eq 0) {
        return @()
    }

    $linkedItems = [System.Collections.Generic.List[PSCustomObject]]::new()
    $baseDir = [System.IO.Path]::GetDirectoryName($cleanRel)

    foreach ($m in $matches) {
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
        [int]$TimeoutSec = 30
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
    $jsonBody = $payloadObj | ConvertTo-Json -Depth 5
    $reqBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

    $webReq = [System.Net.HttpWebRequest]::Create($endpointUrl)
    $webReq.Method = "POST"
    $webReq.ContentType = "application/json; charset=utf-8"
    $webReq.Timeout = $TimeoutSec * 1000
    if (-not [string]::IsNullOrWhiteSpace($resolvedKey)) {
        $webReq.Headers["Authorization"] = "Bearer $resolvedKey"
    }

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
                return $parsed.choices[0].message.content
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
        [string]$SystemPrompt = ""
    )

    $targetDir = if (-not [string]::IsNullOrWhiteSpace($WikiDir)) { $WikiDir } else { $script:wikiDir }
    if ([string]::IsNullOrWhiteSpace($targetDir)) { $targetDir = $scriptDir }

    $thinkingLog = [System.Collections.Generic.List[string]]::new()
    $sourcesList = [System.Collections.Generic.List[PSObject]]::new()
    $visitedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $tools = @(
        @{
            type = "function"
            function = @{
                name = "search_okf"
                description = "OKFスコアリングによりWiki内のActiveドキュメントを検索します。"
                parameters = @{
                    type = "object"
                    properties = @{
                        query = @{ type = "string"; description = "検索キーワード (日本語キーワードをそのまま使用し、勝手に英語翻訳しないでください)" }
                        domain = @{ type = "string"; description = "絞り込みドメイン (原則は空文字列 '' を指定してWiki全域を検索してください)" }
                    }
                    required = @("query")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "lookup_glossary"
                description = "用語集 (glossary.md) またはWiki内の記述から特定用語の定義を調べます。"
                parameters = @{
                    type = "object"
                    properties = @{
                        term = @{ type = "string"; description = "調べたい社内用語" }
                    }
                    required = @("term")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "read_doc"
                description = "指定したドキュメントの本文を取得します (YAMLヘッダー除外)。"
                parameters = @{
                    type = "object"
                    properties = @{
                        relPath = @{ type = "string"; description = "Markdownファイルの相対パス (例: docs/infrastructure/db.md)" }
                    }
                    required = @("relPath")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "get_linked_docs"
                description = "指定ドキュメント内に含まれる他のMarkdownファイルへのハイパーリンク一覧を取得します。"
                parameters = @{
                    type = "object"
                    properties = @{
                        relPath = @{ type = "string"; description = "調査対象のMarkdownファイルパス" }
                    }
                    required = @("relPath")
                }
            }
        }
    )

    $baseRolePrompt = if (-not [string]::IsNullOrWhiteSpace($SystemPrompt)) {
        $SystemPrompt
    } else {
        "あなたは社内Wikiのナレッジを自律調査して回答する Agentic RAG アシスタントです。"
    }

    $sysPrompt = $baseRolePrompt + "`n" +
        "【自律探索・キーワード限界突破ルール】`n" +
        "1. 質問に対する直接の単語一致・該当記述が見つからない・薄い場合でも『該当なし』で諦めないでください。`n" +
        "2. `search_okf` で得られた候補ドキュメント（上位 5 件）や `get_linked_docs` の関連リンクを積極的に `read_doc` で回遊・深掘りし、周辺知識や関連ガイドラインを探索してください。`n" +
        "3. index.md や README.md 等の目次・概要ドキュメントを参照した際、他 Markdown ファイルへのリンク（例: `[仕様](docs/spec.md)`）が含まれている場合は、目次の記述だけで回答を終わらせず、必ず該当リンク先の RelPath に対して `read_doc(relPath)` を呼び出して【詳細本文】を取得・確認した上で回答を作成してください。`n" +
        "4. 直接の回答がない場合でも、『直接の記載はありませんが、関連する以下の仕様・手順が参考になります』として、収集した関連ナレッジや補足情報をユーザーに提示してください。`n" +
        "5. 検索キーワード (query) はユーザーが入力した日本語単語（例: 'エラー', '想定されるエラー'）をそのまま使用し、勝手に英語へ翻訳しないでください。`n" +
        "6. search_okf の domain パラメータは原則として空文字列 '' を指定し、Wiki 全域から広範にドキュメントを検索してください。`n" +
        "7. 非推奨 (status: deprecated) の記述は避け、常に現行 (active) 情報のみを根拠にしてください。"

    if ($CurrentDoc -and $CurrentDoc.RelPath) {
        if (-not $visitedPaths.Contains($CurrentDoc.RelPath)) {
            [void]$visitedPaths.Add($CurrentDoc.RelPath)
        }
        $currSnippet = $CurrentDoc.BodyText
        if ($currSnippet -and $currSnippet.Length -gt 1500) {
            $currSnippet = $currSnippet.Substring(0, 1500) + "..."
        }
        $sysPrompt += "`n`n【現在ユーザーが開いているページのコンテキスト】`n" +
            "・タイトル: $($CurrentDoc.Title)`n" +
            "・相対パス: $($CurrentDoc.RelPath)`n" +
            "・本文:`n$currSnippet"
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
            [void]$thinkingLog.Add("⚠️ LLM API Tool Calling 通信エラー。Fast モードへフォールバックします。")
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
                        [void]$thinkingLog.Add("🔍 Tool Call: search_okf (query: '$q', domain: '$d')")
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
                        [void]$thinkingLog.Add("📖 Tool Call: lookup_glossary (term: '$t')")
                        $toolResult = Invoke-ToolLookupGlossary -Term $t -WikiDir $targetDir
                    }
                    "read_doc" {
                        $p = if ($argsObj.relPath) { $argsObj.relPath } else { "" }
                        [void]$thinkingLog.Add("📄 Tool Call: read_doc (relPath: '$p')")
                        $toolResult = Invoke-ToolReadDoc -RelPath $p -WikiDir $targetDir -MaxChars $MaxDocChars
                        if ($p -and -not $visitedPaths.Contains($p)) {
                            [void]$visitedPaths.Add($p)
                        }
                    }
                    "get_linked_docs" {
                        $p = if ($argsObj.relPath) { $argsObj.relPath } else { "" }
                        [void]$thinkingLog.Add("🔗 Tool Call: get_linked_docs (relPath: '$p')")
                        $links = Invoke-ToolGetLinkedDocs -RelPath $p -WikiDir $targetDir
                        if ($links -and $links.Count -gt 0) {
                            $linkStrList = foreach ($l in $links) { "・[$($l.LinkText)]($($l.RelPath)) [Status: $($l.Status)]" }
                            $toolResult = "リンク一覧:`n" + ($linkStrList -join "`n")
                        } else {
                            $toolResult = "リンクは見つかりませんでした。"
                        }
                    }
                    default {
                        $toolResult = "未知のツール名: $fnName"
                    }
                }

                [void]$messages.Add(@{
                    role         = "tool"
                    tool_call_id = $callId
                    content      = $toolResult
                })
            }
        } else {
            $finalAnswer = $resMsg.content
            break
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
        [void]$thinkingLog.Add("⏱️ ターン上限 ($MaxTurns) に達したため、収集情報から要約回答を生成します。")
        [void]$messages.Add(@{ role = "user"; content = "※これ以上のツール呼び出しを行わず、ここまでに取得・探索した情報を元に結論をテキストで最終出力してください。質問に対する完全な直接回答が無い場合でも『該当なし』で終わらせず、探索したドキュメントから得られる関連知識や補足情報を分かりやすく提示してください。" })

        $payloadObj = @{
            model       = $Model
            temperature = 0.2
            messages    = $messages
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
                $resJson = $reader.ReadToEnd()
                $parsed = $resJson | ConvertFrom-Json
                if ($parsed -and $parsed.choices -and $parsed.choices.Count -gt 0) {
                    $finalAnswer = $parsed.choices[0].message.content
                }
            } finally {
                $webRes.Close()
            }
        } catch {
            # 通信例外等のキャッチ
        }

        if ([string]::IsNullOrWhiteSpace($finalAnswer)) {
            if ($visitedPaths.Count -gt 0) {
                $finalAnswer = "Wiki 内を自律調査しましたが、質問に完全一致する直接記述は見つかりませんでした。\n\n### 調査した関連ドキュメント\n" + (($visitedPaths | ForEach-Object { "- [$_]($_)" }) -join "`n")
            } else {
                $finalAnswer = "Wiki 内を自律検索しましたが、質問に直接該当する明確な記載は見つかりませんでした。関連するガイド（`guides/環境構築.md` や `docs/詳細仕様.md` など）を参照してください。"
            }
        }
    }

    return [PSCustomObject]@{
        answer      = $finalAnswer
        thinkingLog = $thinkingLog
        sources     = $sourcesList
    }
}
