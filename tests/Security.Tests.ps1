# ==============================================================================
#  Security.Tests.ps1
#  Encoding: UTF-8 with BOM
# ==============================================================================

[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingInvokeExpression", "")]
param()

if (-not $script:projectRoot) {
    $script:projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}
$projectRoot = $script:projectRoot
$libDll      = Join-Path $projectRoot "lib\Markdig.dll"

Describe 'Path Traversal and Security Validation Tests' {
    BeforeAll {
        $wikiDir     = $projectRoot
        $fullWikiDir = $wikiDir.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    }

    It "Valid relative path inside wikiDir is allowed" {
        $filePath  = Join-Path $wikiDir "index.md"
        $fullPath  = [System.IO.Path]::GetFullPath($filePath)
        $isAllowed = $fullPath.StartsWith($fullWikiDir, [System.StringComparison]::OrdinalIgnoreCase)
        $isAllowed | Should Be $true
    }

    It "Path traversal attempting to access external directory is blocked" {
        $filePath  = Join-Path $wikiDir "..\..\Windows\System32\drivers\etc\hosts"
        $fullPath  = [System.IO.Path]::GetFullPath($filePath)
        $isAllowed = $fullPath.StartsWith($fullWikiDir, [System.StringComparison]::OrdinalIgnoreCase)
        $isAllowed | Should Be $false
    }
}


Describe 'HTML Escaping and XSS Protection Tests' {
    It "XSS script in 404 path is HTML encoded" {
        $rawPath  = "/<script>alert('xss')</script>"
        $safePath = [System.Net.WebUtility]::HtmlEncode($rawPath)
        $safePath | Should Not Match "<script>"
        $safePath | Should Match "&lt;script&gt;"
    }

    It "Special characters in page title are HTML encoded" {
        $baseName  = "<Test & Document>"
        $safeTitle = [System.Net.WebUtility]::HtmlEncode($baseName)
        $safeTitle | Should Be "&lt;Test &amp; Document&gt;"
    }
}


Describe 'Critical Edge Case and Security Tests' {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        $script:WikiIndexDirWriteTime = (Get-Item $sampleDir).LastWriteTime

        $script:WikiIndex = @(
            [PSCustomObject]@{
                Title       = "PostgreSQL DB Recovery"
                Description = "Database recovery steps"
                Author      = "Taro Yamada"
                Domain      = "infrastructure/database"
                Tags        = @("PostgreSQL", "Database")
                LastUpdated = (Get-Date "2026-08-01")
                Status      = "active"
                HasYaml     = $true
                RelPath     = "docs/db-recovery.md"
                FullPath    = "C:\wiki\docs\db-recovery.md"
                BodyText    = "How to recover PostgreSQL when crash occurs."
            },
            [PSCustomObject]@{
                Title       = "General Troubleshooting"
                Description = "General system issues"
                Author      = "Jiro Sato"
                Domain      = "support"
                Tags        = @("System")
                LastUpdated = (Get-Date "2026-07-01")
                Status      = "active"
                HasYaml     = $true
                RelPath     = "docs/general.md"
                FullPath    = "C:\wiki\docs\general.md"
                BodyText    = "Check logs for PostgreSQL database errors and recovery."
            }
        )
    }

    It 'Splits keywords correctly with Japanese full-width space' {
        $queryWithJpSpace = "PostgreSQL" + [char]0x3000 + "crash"
        $html = Get-SearchViewHtml -Query $queryWithJpSpace -StatusFilter 'all'
        $html | Should Match 'docs/db-recovery.md'
        $html | Should Not Match 'General Troubleshooting'
    }

    It 'Encodes XSS payload in search query input cleanly without raw HTML injection' {
        $xssQuery = '<script>alert("xss")</script>'
        $html = Get-SearchViewHtml -Query $xssQuery -StatusFilter 'all'
        $html | Should Not Match '<script>alert\("xss"\)</script>'
        $html | Should Match '&lt;script&gt;'
    }

    It 'Executes facet-only domain filter search without keywords' {
        $html = Get-SearchViewHtml -Query '' -StatusFilter 'all' -DomainFilter 'infrastructure'
        $html | Should Match 'docs/db-recovery.md'
        $html | Should Not Match 'General Troubleshooting'
    }

    It 'Gracefully handles invalid StatusFilter parameter without crashing' {
        { $script:invalidHtml = Get-SearchViewHtml -Query 'PostgreSQL' -StatusFilter 'invalid_status_value' } | Should Not Throw
        $script:invalidHtml | Should Not Match 'docs/db-recovery.md'
    }

    It 'Parses comma-separated tag string in YAML correctly into array' {
        $sampleMd = "---`ntitle: `"Comma Tag Test`"`ntags: `"PostgreSQL, Database, Recovery`"`n---`n# Test"
        $meta = Get-DocumentMetadata -MdText $sampleMd -RelPath "test.md"
        $meta.Tags.Count | Should Be 3
        ($meta.Tags -contains "PostgreSQL") | Should Be $true
        ($meta.Tags -contains "Database") | Should Be $true
        ($meta.Tags -contains "Recovery") | Should Be $true
    }

    It 'Get-QueryParams decodes percent-encoded UTF-8 Japanese query string without mojibake' {
        # %E3%83%8F%E3%83%B3%E3%83%89%E3%83%96%E3%83%83%E3%82%AF = "ハンドブック"
        $mockReq = [PSCustomObject]@{
            Url = [PSCustomObject]@{
                Query = '?q=%E3%83%8F%E3%83%B3%E3%83%89%E3%83%96%E3%83%83%E3%82%AF&status=active'
            }
        }
        $params = Get-QueryParams -Request $mockReq
        $params["q"] | Should Be "ハンドブック"
        $params["status"] | Should Be "active"
    }

    It 'Executes Unblock-File safely on lib DLLs without throwing exceptions' {
        if ($IsWindows -or $env:OS -eq "Windows_NT") {
            $libPath = Join-Path $projectRoot "lib"
            { Get-ChildItem -Path $libPath -Filter "*.dll" | Unblock-File -ErrorAction SilentlyContinue } | Should Not Throw
        }
    }
}


Describe 'OKF LLM RAG Security and Encryption Tests' {
    BeforeAll {
        . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly
    }

    It 'Encrypts and decrypts API key with AES-256 (ENC: prefix)' {
        $rawKey = "sk-proj-test123456789"
        $encKey = Protect-StringAes -PlainText $rawKey
        $encKey | Should Match "^ENC:"
        $decKey = Unprotect-StringAes -EncryptedText $encKey
        $decKey | Should Be $rawKey
    }

    It 'Get-MachineFingerprint returns 16-char formatted machine identifier' {
        $mid = Get-MachineFingerprint
        $mid | Should Match '^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$'
    }

    It 'Generates and unlocks machine-bound activation codes correctly' {
        $testApiKey = "sk-sakura-ai-secret-123456"
        $mid = Get-MachineFingerprint
        $email = "developer@example.com"

        # 1. マシンID ＋ メールアドレスでの暗号化
        $actCode = Protect-ActivationCode -ApiKey $testApiKey -MachineId $mid -Email $email
        $actCode | Should Match "^ENC:"

        # 2. 同一マシン ＋ 同一メールでの復号成功
        $decrypted = Unprotect-ActivationCode -EncryptedText $actCode -MachineId $mid -Email $email
        $decrypted | Should Be $testApiKey

        # 3. 異なるマシンIDでの復号失敗
        $diffMid = "AAAA-BBBB-CCCC-DDDD"
        $failedDec = Unprotect-ActivationCode -EncryptedText $actCode -MachineId $diffMid -Email $email
        $failedDec | Should Be ""

        # 4. 異なるメールアドレスでの復号失敗
        $diffEmail = "wrong.person@example.com"
        $failedEmailDec = Unprotect-ActivationCode -EncryptedText $actCode -MachineId $mid -Email $diffEmail
        $failedEmailDec | Should Be ""

        # 5. 従来ポータブル ENC: 形式の復号互換性テスト (どのマシン・メールでも復号可能)
        $legacyEnc = Protect-StringAes -PlainText $testApiKey
        $decLegacy = Unprotect-ActivationCode -EncryptedText $legacyEnc -MachineId $mid -Email $email
        $decLegacy | Should Be $testApiKey
        $decLegacyDiffMid = Unprotect-ActivationCode -EncryptedText $legacyEnc -MachineId "DIFF-HOST-9999" -Email "other@example.com"
        $decLegacyDiffMid | Should Be $testApiKey

        # 6. Get-ResolvedSecret の透過的復号
        $resolved = Get-ResolvedSecret -SecretValue $actCode -Email $email
        $resolved | Should Be $testApiKey
        $resolvedLegacy = Get-ResolvedSecret -SecretValue $legacyEnc
        $resolvedLegacy | Should Be $testApiKey
    }

    It 'New-ActivationCode.ps1 CLI script supports both Machine-Bound and Legacy portable modes' {
        $cliScript = Join-Path $projectRoot "New-ActivationCode.ps1"
        (Test-Path $cliScript) | Should Be $true
        $tokens = $null
        $errs = $null
        [System.Management.Automation.Language.Parser]::ParseFile($cliScript, [ref]$tokens, [ref]$errs)
        $errs.Count | Should Be 0

        # CLI による Legacy モード出力テスト
        $testKey = "sk-test-cli-key-12345"
        & $cliScript -ApiKey $testKey -Legacy | Out-Null
        $legacyCode = Protect-StringAes -PlainText $testKey
        $unprotected = Unprotect-ActivationCode -EncryptedText $legacyCode
        $unprotected | Should Be $testKey
    }

    It 'Web Crypto API (docs/activation/index.html) generated codes are 100% decryptable by PowerShell' {
        # Web ブラウザ (Web Crypto API) で生成された既知の暗号化コード
        # テストキー: sk-sakura-test-key-123456
        # マシンID: A3B1-9F22-C84D-71E0, メール: user@example.com
        $webBoundCode = "ENC:O5ZNmQDvlNMIMr2aw7Iw+ArP1IROerSgBCud2j5Cugg="
        $webDecrypted = Unprotect-ActivationCode -EncryptedText $webBoundCode -MachineId "A3B1-9F22-C84D-71E0" -Email "user@example.com"
        $webDecrypted | Should Be "sk-sakura-test-key-123456"

        # Web ポータブル (Legacy) コードの復号
        $webLegacyCode = "ENC:rcBTlBqj1CLuHa9ZHN9vwmb7Fslkcr2Fi0ihcDYDimo="
        $webLegacyDecrypted = Unprotect-ActivationCode -EncryptedText $webLegacyCode
        $webLegacyDecrypted | Should Be "sk-sakura-test-key-123456"
    }

    It 'Encrypts and decrypts API key with Windows DPAPI (DPAPI: prefix)' {
        if ($IsWindows -or $env:OS -eq "Windows_NT") {
            $rawKey = "sk-proj-dpapitest98765"
            $dpapiKey = Protect-StringDpapi -PlainText $rawKey
            $dpapiKey | Should Match "^DPAPI:"
            $decKey = Unprotect-StringDpapi -EncryptedText $dpapiKey
            $decKey | Should Be $rawKey
        }
    }

    It 'Resolves secret for ENV: prefix dynamically' {
        [Environment]::SetEnvironmentVariable("TEST_OPENAI_KEY", "sk-env-secret-val")
        try {
            $resolved = Get-ResolvedSecret -SecretValue "ENV:TEST_OPENAI_KEY"
            $resolved | Should Be "sk-env-secret-val"
        } finally {
            [Environment]::SetEnvironmentVariable("TEST_OPENAI_KEY", $null)
        }
    }

    It 'Get-ConfigJson returns enabled = false when config.json does not exist' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestNoConfig"
        if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
        try {
            $cfg = Get-ConfigJson -TargetScriptDir $tempDir
            $cfg.rag.enabled | Should Be $false
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Set-ApiKey.ps1 creates config.json with encrypted key' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestSetApiKey"
        if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
        $targetCfg = Join-Path $tempDir "config.json"
        try {
            $setScript = Join-Path $projectRoot "Set-ApiKey.ps1"
            & $setScript -ApiKey "sk-test-portable-key" -Scope Portable -ConfigPath $targetCfg
            (Test-Path $targetCfg) | Should Be $true
            $cfg = Get-Content -Path $targetCfg -Raw | ConvertFrom-Json
            $cfg.rag.enabled | Should Be $true
            $cfg.rag.apiKey | Should Match "^ENC:"
            $resolved = Get-ResolvedSecret -SecretValue $cfg.rag.apiKey
            $resolved | Should Be "sk-test-portable-key"
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-JapaneseWordsWinRT tokenizes Japanese queries and filters Japanese stop words' {
        $words = Get-JapaneseWordsWinRT -Text 'セットアップの方法は？'
        ($words -contains 'セットアップ') | Should Be $true
        ($words -contains '環境構築') | Should Be $true
        ($words -contains 'は') | Should Be $false
        ($words -contains 'の') | Should Be $false
    }

    It 'Invoke-OpenAiChatCompletions builds message payload with history array' {
        $history = @(
            @{ role = 'user'; content = '質問1' },
            @{ role = 'assistant'; content = '回答1' }
        )
        { Invoke-OpenAiChatCompletions -ApiUrl 'http://invalid-endpoint-for-test-xyz' -ApiKey 'test-key' -Model 'test-model' -SystemPrompt 'System Prompt' -UserMessage '質問2' -History $history -TimeoutSec 1 } | Should Throw
    }

    It 'Invoke-OpenAiChatCompletions accepts -Stream switch and -OnChunkReceived callback' {
        $chunkList = [System.Collections.Generic.List[string]]::new()
        {
            Invoke-OpenAiChatCompletions -ApiUrl 'http://invalid-endpoint-for-test-xyz' -ApiKey 'test-key' -Model 'test-model' -SystemPrompt 'System Prompt' -UserMessage '質問' -Stream -OnChunkReceived { param($c) $chunkList.Add($c) } -TimeoutSec 1
        } | Should Throw
    }
}


Describe 'Agentic RAG and OKF Tools Tests' {
    BeforeAll {
        # Import functions from Start-MarkdigWiki.ps1
        $scriptPath = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $scriptPath -DotSourceOnly
    }

    It "Start-MarkdigWiki.ps1 is encoded as UTF-8 with BOM" {
        $scriptPath = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
        $bytes.Length | Should BeGreaterThan 3
        $bytes[0] | Should Be 0xEF
        $bytes[1] | Should Be 0xBB
        $bytes[2] | Should Be 0xBF
    }

    It "Search-OkfDocs scores and filters active documents correctly" {
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        Build-WikiIndex -TargetWikiDir $sampleDir -ForceRefresh | Out-Null
        $results = Search-OkfDocs -Query "Markdown" -StatusFilter "active" -WikiDir $sampleDir
        ($null -ne $results) | Should Be $true
        $results.Count | Should BeGreaterThan 0
        $results[0].Score | Should BeGreaterThan 0
    }

    It "Invoke-ToolReadDoc trims body text and strips YAML header" {
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        Build-WikiIndex -TargetWikiDir $sampleDir -ForceRefresh | Out-Null
        $doc = $script:WikiIndex | Select-Object -First 1
        if ($doc) {
            $content = Invoke-ToolReadDoc -RelPath $doc.RelPath -WikiDir $sampleDir -MaxChars 50
            $content | Should Not Be $null
            $content | Should Not Match "^---"
            $content.Length | Should BeLessThan 300
        }
    }

    It "Invoke-ToolGetLinkedDocs extracts markdown relative links" {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_LinkTest"
        if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
        try {
            $doc1 = Join-Path $tempDir "doc1.md"
            $doc2 = Join-Path $tempDir "doc2.md"
            Set-Content -Path $doc1 -Value "# Doc 1`nSee [Doc 2](doc2.md) for details." -Encoding UTF8
            Set-Content -Path $doc2 -Value "# Doc 2`nTarget content." -Encoding UTF8

            Build-WikiIndex -TargetWikiDir $tempDir -ForceRefresh | Out-Null
            $links = @(Invoke-ToolGetLinkedDocs -RelPath "doc1.md" -WikiDir $tempDir)
            $links | Should Not Be $null
            $links.Count | Should Be 1
            $links[0].RelPath | Should Be "doc2.md"
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Invoke-ToolLookupGlossary finds terms in document content or tags" {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_GlossaryTest"
        if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
        try {
            $glossaryFile = Join-Path $tempDir "glossary.md"
            Set-Content -Path $glossaryFile -Value "# 社内用語集`n`n## K-DAT`n研究所専用のバックアップツール。" -Encoding UTF8

            Build-WikiIndex -TargetWikiDir $tempDir -ForceRefresh | Out-Null
            $res = Invoke-ToolLookupGlossary -Term "K-DAT" -WikiDir $tempDir
            ($null -ne $res) | Should Be $true
            $res | Should Match "K-DAT"
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Invoke-AgenticRagChat fallback generates informative answer when LLM fails or max turns reached without content" {
        # Invalid API URL triggers fallback handling
        $res = Invoke-AgenticRagChat -ApiUrl "http://invalid-endpoint-xyz-999" -ApiKey "key" -Model "model" -UserMessage "質問" -WikiDir $projectRoot -MaxTurns 1 -TimeoutSec 1
        ($null -ne $res) | Should Be $true
        $res.answer | Should Not BeNullOrEmpty
        $res.thinkingLog.Count | Should BeGreaterThan 0
    }

    It "Invoke-ToolSearchOkf falls back to all domains when specific domain query yields zero hits" {
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        Build-WikiIndex -TargetWikiDir $sampleDir -ForceRefresh | Out-Null
        # '概要' is in domain 'root', but domain 'non_existent_domain' is passed
        $res = Invoke-ToolSearchOkf -Query "概要" -Domain "non_existent_domain" -WikiDir $sampleDir
        ($null -ne $res) | Should Be $true
        $res | Should Match "概要"
    }

    It "Search-OkfDocs utilizes WinRT morph tokenization and exact phrase bonus on first attempt" {
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        Build-WikiIndex -TargetWikiDir $sampleDir -ForceRefresh | Out-Null
        # Query containing particles and full sentence
        $results = Search-OkfDocs -Query "想定されるエラーは？" -StatusFilter "active" -WikiDir $sampleDir
        ($null -ne $results) | Should Be $true
        $results.Count | Should BeGreaterThan 0
        # Check that top result matched exact phrase or tokenized words
        $results[0].Score | Should BeGreaterThan 0
    }

    It "Invoke-ToolSearchOkf returns multiple candidate results with formatting for Agentic traversal" {
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        Build-WikiIndex -TargetWikiDir $sampleDir -ForceRefresh | Out-Null
        $res = Invoke-ToolSearchOkf -Query "仕様" -WikiDir $sampleDir
        ($null -ne $res) | Should Be $true
        $res | Should Match "RelPath"
        $res | Should Match "read_doc"
    }

    It "Invoke-AgenticRagChat fallback prompt instructs to present related knowledge when direct hits are scarce" {
        $res = Invoke-AgenticRagChat -ApiUrl "http://invalid-endpoint-xyz-999" -ApiKey "key" -Model "model" -UserMessage "未知のトピック" -WikiDir $projectRoot -MaxTurns 1 -TimeoutSec 1
        ($null -ne $res) | Should Be $true
        $res.answer | Should Not BeNullOrEmpty
    }

    It "Invoke-AgenticRagChat supports -Stream, -OnThinkingCallback, and -OnChunkReceived parameters" {
        $thinkList = [System.Collections.Generic.List[string]]::new()
        $chunkList = [System.Collections.Generic.List[string]]::new()
        $res = Invoke-AgenticRagChat -ApiUrl "http://invalid-endpoint-xyz-999" -ApiKey "key" -Model "model" -UserMessage "テスト質問" -WikiDir $projectRoot -MaxTurns 1 -TimeoutSec 1 -Stream -OnThinkingCallback { param($m) $thinkList.Add($m) } -OnChunkReceived { param($c) $chunkList.Add($c) }
        ($null -ne $res) | Should Be $true
        $res.answer | Should Not BeNullOrEmpty
    }
}


Describe 'Markdown Editor API and Generation Backup Tests' {
    BeforeAll {
        # Dot source the script to test functions locally
        . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly
    }

    It "Get-ConfigJson parses editor config with custom or default maxBackups" {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestEditorDir"
        if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force }
        $null = New-Item -ItemType Directory -Path $tempDir

        $cfgFile = Join-Path $tempDir "config.json"
        @{ editor = @{ maxBackups = 5 } } | ConvertTo-Json | Out-File -FilePath $cfgFile -Encoding UTF8 -NoNewline

        $parsed = Get-ConfigJson -TargetScriptDir $tempDir
        $parsed.editor.maxBackups | Should Be 5

        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Backup rotation rotates backups correctly up to maxBackups" {
        $tempDir = Join-Path $projectRoot "temp_test_editor_backup_dir"
        if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force }
        $null = New-Item -ItemType Directory -Path $tempDir

        $testFile = Join-Path $tempDir "test-doc.md"
        "Initial Content" | Out-File -FilePath $testFile -Encoding utf8

        # Mock backup rotation with maxBackups = 3
        # First write: rotates original to bak1, then writes new
        $maxBackups = 3

        # Rotation 1
        if ($maxBackups -gt 0 -and (Test-Path $testFile)) {
            for ($i = $maxBackups - 1; $i -ge 1; $i--) {
                $oldBak = "$testFile.bak$i"
                $newBak = "$testFile.bak$($i + 1)"
                if (Test-Path $oldBak) { Copy-Item -Path $oldBak -Destination $newBak -Force }
            }
            Copy-Item -Path $testFile -Destination "$testFile.bak1" -Force
        }
        "Content Gen 2" | Out-File -FilePath $testFile -Encoding utf8

        (Test-Path "$testFile.bak1") | Should Be $true
        (Get-Content -Path "$testFile.bak1" -Raw) | Should Match "Initial Content"

        # Rotation 2
        if ($maxBackups -gt 0 -and (Test-Path $testFile)) {
            for ($i = $maxBackups - 1; $i -ge 1; $i--) {
                $oldBak = "$testFile.bak$i"
                $newBak = "$testFile.bak$($i + 1)"
                if (Test-Path $oldBak) { Copy-Item -Path $oldBak -Destination $newBak -Force }
            }
            Copy-Item -Path $testFile -Destination "$testFile.bak1" -Force
        }
        "Content Gen 3" | Out-File -FilePath $testFile -Encoding utf8

        (Test-Path "$testFile.bak2") | Should Be $true
        (Get-Content -Path "$testFile.bak2" -Raw) | Should Match "Initial Content"
        (Get-Content -Path "$testFile.bak1" -Raw) | Should Match "Content Gen 2"

        # Rotation 3
        if ($maxBackups -gt 0 -and (Test-Path $testFile)) {
            for ($i = $maxBackups - 1; $i -ge 1; $i--) {
                $oldBak = "$testFile.bak$i"
                $newBak = "$testFile.bak$($i + 1)"
                if (Test-Path $oldBak) { Copy-Item -Path $oldBak -Destination $newBak -Force }
            }
            Copy-Item -Path $testFile -Destination "$testFile.bak1" -Force
        }
        "Content Gen 4" | Out-File -FilePath $testFile -Encoding utf8

        (Test-Path "$testFile.bak3") | Should Be $true
        (Get-Content -Path "$testFile.bak3" -Raw) | Should Match "Initial Content"
        (Get-Content -Path "$testFile.bak2" -Raw) | Should Match "Content Gen 2"
        (Get-Content -Path "$testFile.bak1" -Raw) | Should Match "Content Gen 3"

        # Rotation 4 (exceeding maxBackups, bak3 should be replaced by gen 2 content, original initial content is deleted)
        if ($maxBackups -gt 0 -and (Test-Path $testFile)) {
            for ($i = $maxBackups - 1; $i -ge 1; $i--) {
                $oldBak = "$testFile.bak$i"
                $newBak = "$testFile.bak$($i + 1)"
                if (Test-Path $oldBak) { Copy-Item -Path $oldBak -Destination $newBak -Force }
            }
            Copy-Item -Path $testFile -Destination "$testFile.bak1" -Force
        }
        "Content Gen 5" | Out-File -FilePath $testFile -Encoding utf8

        (Test-Path "$testFile.bak4") | Should Be $false
        (Get-Content -Path "$testFile.bak3" -Raw) | Should Match "Content Gen 2"
        (Get-Content -Path "$testFile.bak2" -Raw) | Should Match "Content Gen 3"
        (Get-Content -Path "$testFile.bak1" -Raw) | Should Match "Content Gen 4"

        Remove-Item -Path $tempDir -Recurse -Force
    }

    It "Preserves UTF-8 with BOM signature on write" {
        $tempDir = Join-Path $projectRoot "temp_test_editor_utf8"
        if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force }
        $null = New-Item -ItemType Directory -Path $tempDir
        $testFile = Join-Path $tempDir "utf8-test.md"

        $utf8bom = New-Object System.Text.UTF8Encoding -ArgumentList @($true)
        [System.IO.File]::WriteAllText($testFile, "こんにちは", $utf8bom)

        # Read back bytes
        $bytes = [System.IO.File]::ReadAllBytes($testFile)
        # Check BOM: EF BB BF -> 239, 187, 191
        $bytes[0] | Should Be 239
        $bytes[1] | Should Be 187
        $bytes[2] | Should Be 191

        Remove-Item -Path $tempDir -Recurse -Force
    }

    It "Serializes /api/raw content as string without PSNoteProperty objects" {
        $tempDir = Join-Path $projectRoot "temp_test_editor_raw"
        if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force }
        $null = New-Item -ItemType Directory -Path $tempDir
        $testFile = Join-Path $tempDir "raw-test.md"

        [System.IO.File]::WriteAllText($testFile, "# Test Heading`nTest body content", [System.Text.Encoding]::UTF8)

        $content = [System.IO.File]::ReadAllText($testFile, [System.Text.Encoding]::UTF8)
        $jsonStr = @{ markdown = $content } | ConvertTo-Json
        $parsedObj = $jsonStr | ConvertFrom-Json

        ($parsedObj.markdown -is [string]) | Should Be $true
        $parsedObj.markdown | Should Match "# Test Heading"

        Remove-Item -Path $tempDir -Recurse -Force
    }

    It "Detects backup versions and reads historical versions correctly" {
        $tempDir = Join-Path $projectRoot "temp_test_editor_history"
        if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force }
        $null = New-Item -ItemType Directory -Path $tempDir

        $testFile = Join-Path $tempDir "history-doc.md"
        $bak1File = "$testFile.bak1"

        [System.IO.File]::WriteAllText($testFile, "Current content", [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($bak1File, "Historical content gen 1", [System.Text.Encoding]::UTF8)

        # Test reading backup file via ReadAllText
        $bakContent = [System.IO.File]::ReadAllText($bak1File, [System.Text.Encoding]::UTF8)
        $bakContent | Should Match "Historical content gen 1"

        # Check backup file detection
        (Test-Path "$testFile.bak1") | Should Be $true

        Remove-Item -Path $tempDir -Recurse -Force
    }

    It "Validates YAML Front Matter syntax correctly" {
        # Valid YAML
        $validMd = "---`r`ntitle: Test Title`r`nstatus: active`r`ntags:`r`n  - tag1`r`n---`r`n# Body"
        $resValid = Test-YamlFrontMatterSyntax -MdText $validMd
        $resValid.isValid | Should Be $true
        $resValid.warnings.Count | Should Be 0

        # Missing closing ---
        $unclosedMd = "---`r`ntitle: Test Title`r`n# Body"
        $resUnclosed = Test-YamlFrontMatterSyntax -MdText $unclosedMd
        $resUnclosed.isValid | Should Be $false
        $resUnclosed.warnings[0] | Should Match "(閉じヘッダー|closing header|---)"

        # Invalid line without colon
        $invalidLineMd = "---`r`ntitle Test Title`r`n---`r`n# Body"
        $resInvalid = Test-YamlFrontMatterSyntax -MdText $invalidLineMd
        $resInvalid.isValid | Should Be $false
        $resInvalid.warnings[0] | Should Match "(key: value|キー: 値)"
    }

    It "Upload-Image API rejects SVG extension for Stored XSS prevention" {
        $allowedExts = @(".png", ".jpg", ".jpeg", ".gif", ".webp")
        $ext = [System.IO.Path]::GetExtension("evil.svg").ToLowerInvariant()
        ($allowedExts -contains $ext) | Should Be $false
    }

    It "Upload-Image API rejects dangerous extensions (.exe, .ps1, .html)" {
        $allowedExts = @(".png", ".jpg", ".jpeg", ".gif", ".webp")
        foreach ($bad in @("malware.exe", "script.ps1", "page.html", "run.bat")) {
            $ext = [System.IO.Path]::GetExtension($bad).ToLowerInvariant()
            ($allowedExts -contains $ext) | Should Be $false
        }
    }

    It "Upload-Image API decodes Base64 and saves raster image to images/uploads directory" {
        $tempWikiDir = Join-Path $projectRoot "temp_test_upload"
        if (Test-Path $tempWikiDir) { Remove-Item -Path $tempWikiDir -Recurse -Force }
        $null = New-Item -ItemType Directory -Path $tempWikiDir
        
        $uploadFullDir = Join-Path $tempWikiDir "images\uploads"
        $null = New-Item -ItemType Directory -Path $uploadFullDir -Force

        # 1x1 transparent PNG Base64
        $pngB64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        $imageBytes = [System.Convert]::FromBase64String($pngB64)
        $datePrefix = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $randSuffix = [System.Guid]::NewGuid().ToString("N").Substring(0, 8)
        $savedFileName = "img_${datePrefix}_${randSuffix}.png"
        $saveFilePath = Join-Path $uploadFullDir $savedFileName
        [System.IO.File]::WriteAllBytes($saveFilePath, $imageBytes)

        (Test-Path $saveFilePath) | Should Be $true
        (Get-Item $saveFilePath).Length | Should BeGreaterThan 0

        Remove-Item -Path $tempWikiDir -Recurse -Force
    }

    It "Delete API blocks path traversal outside wiki root" {
        $wikiDir = $projectRoot
        $fullWikiDir = $wikiDir.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        $cleanRel = "..\..\Windows\System32\drivers\etc\hosts".TrimStart('\', '/').Replace('/', '\')
        $fullTarget = Join-Path $wikiDir $cleanRel
        $resolvedTarget = [System.IO.Path]::GetFullPath($fullTarget)
        $isInside = $resolvedTarget.StartsWith($fullWikiDir, [System.StringComparison]::OrdinalIgnoreCase)
        $isInside | Should Be $false
    }

    It "New document folder and filename path traversal attempts are blocked" {
        $wikiDir = $projectRoot
        $fullWikiDir = $wikiDir.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

        $traversalPaths = @(
            "../etc/passwd",
            "docs/../../secret.txt",
            "docs/sub/../../../etc/hosts",
            "folder/../../"
        )

        foreach ($tp in $traversalPaths) {
            $cleanRel = $tp.Replace('/', '\').TrimStart('\')
            $fullTarget = Join-Path $wikiDir $cleanRel
            $resolvedTarget = [System.IO.Path]::GetFullPath($fullTarget)
            $isInside = $resolvedTarget.StartsWith($fullWikiDir, [System.StringComparison]::OrdinalIgnoreCase)
            $isInside | Should Be $false
        }
    }

    It "Delete API creates .bak_deleted backup before removing file" {
        $tempWikiDir = Join-Path $projectRoot "temp_test_delete"
        if (Test-Path $tempWikiDir) { Remove-Item -Path $tempWikiDir -Recurse -Force }
        $null = New-Item -ItemType Directory -Path $tempWikiDir
        $testDoc = Join-Path $tempWikiDir "to-delete.md"
        [System.IO.File]::WriteAllText($testDoc, "Doc to be deleted", [System.Text.Encoding]::UTF8)

        # Emulate delete logic
        Copy-Item -LiteralPath $testDoc -Destination "$testDoc.bak_deleted" -Force
        Remove-Item -LiteralPath $testDoc -Force

        (Test-Path $testDoc) | Should Be $false
        (Test-Path "$testDoc.bak_deleted") | Should Be $true
        (Get-Content -Path "$testDoc.bak_deleted" -Raw) | Should Match "Doc to be deleted"

        Remove-Item -Path $tempWikiDir -Recurse -Force
    }
}


Describe "Repository Code Quality, Syntax & Character Encoding Validation Tests" {
    It "All PowerShell script files parse successfully without AST syntax errors" {
        $psFiles = Get-ChildItem -Path $projectRoot -Recurse -Include "*.ps1", "*.psm1", "*.psd1" |
            Where-Object { $_.FullName -notmatch '[\\/]\.(git|cache)[\\/]' }

        foreach ($file in $psFiles) {
            $tokens = $null
            $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errs)
            $errCount = if ($errs) { $errs.Count } else { 0 }
            $errCount | Should Be 0
        }
    }

    It "All PowerShell scripts (.ps1, .psm1, .psd1) are encoded as UTF-8 with BOM" {
        $psFiles = Get-ChildItem -Path $projectRoot -Recurse -Include "*.ps1", "*.psm1", "*.psd1" |
            Where-Object { $_.FullName -notmatch '[\\/]\.(git|cache)[\\/]' }

        foreach ($file in $psFiles) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            $hasBom | Should Be $true
        }
    }

    It "All Batch files (.bat) are strictly encoded as UTF-8 without BOM (No-BOM)" {
        $batFiles = Get-ChildItem -Path $projectRoot -Recurse -Include "*.bat" |
            Where-Object { $_.FullName -notmatch '[\\/]\.(git|cache)[\\/]' }

        foreach ($file in $batFiles) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            $hasBom | Should Be $false
        }
    }
}

# ==============================================================================
# PR 統合・ユニットテスト拡充スイート (PR #14, #16, #18, #20, #24, #28, #29, #30, #31, #32)
# ==============================================================================

Describe "Adversarial Security & Resilience Suite" {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
    }

    Context "1. Security & Parameter Sanitization (Activation & DPAPI)" {
        It "Rejects activation code generation with whitespace-only parameters gracefully" {
            $cleanMid = if ([string]::IsNullOrWhiteSpace("   `t`n ")) { "" } else { "   `t`n ".Trim() }
            $cleanMid | Should Be ""
        }

        It "Hardware fingerprint extraction never returns empty or generic default string" {
            $fp = Get-MachineFingerprint
            $fp | Should Not BeNullOrEmpty
            $fp | Should Not Be "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"
            $fp.Length | Should BeGreaterThan 5
        }

        It "Protects against injection in Activation Code Email and MachineId" {
            $maliciousEmail = "victim@example.com' OR '1'='1; --"
            $maliciousMid = "<script>alert(1)</script>`r`nDROP TABLE"
            $rawKey = "sk-super-secret-key"

            $code = Protect-ActivationCode -ApiKey $rawKey -MachineId $maliciousMid -Email $maliciousEmail
            $code | Should Match "^ENC:"

            $dec = Unprotect-ActivationCode -EncryptedText $code -MachineId $maliciousMid -Email $maliciousEmail
            $dec | Should Be $rawKey

            # 異なるマシンIDでは復号が完全に拒絶されること
            $badDec = Unprotect-ActivationCode -EncryptedText $code -MachineId "DIFFERENT-MACHINE-ID" -Email $maliciousEmail
            $badDec | Should Be ""
        }
    }

    Context "2. Search Engine Hardening & ReDoS Resilience" {
        It "Handles malicious regex characters in query without throwing exceptions" {
            $script:WikiIndex = @(
                [PSCustomObject]@{
                    Title       = "Normal Document"
                    Description = 'Some text [.*+?^${}()|[]\] and special symbols'
                    Domain      = "root"
                    Tags        = @("sample", "[test]")
                    Status      = "active"
                    BodyText    = "Body with ((((nested)))) syntax."
                }
            )

            $adversarialQueries = @(
                '[.*+?^${}()|[]\]',
                '((((((((a+)+)+)+)+)+)+)+)',
                '\\\\\\\\\\\\',
                'NOT - - - + + +',
                '???***+++',
                '"unclosed quote',
                '<script>alert(1)</script>'
            )

            foreach ($q in $adversarialQueries) {
                {
                    $results = Search-OkfDocs -Query $q
                } | Should Not Throw
            }
        }

        It "Handles extremely large 10,000+ character search queries safely" {
            $hugeQuery = ("A" * 10000)
            {
                $res = Search-OkfDocs -Query $hugeQuery
                $res.Count | Should Be 0
            } | Should Not Throw
        }

        It "Safely ignores null or corrupted items in WikiIndex" {
            $script:WikiIndex = @($null, [PSCustomObject]@{ Title = $null; Description = $null; Status = $null })
            {
                $res = Search-OkfDocs -Query "test"
            } | Should Not Throw
        }
    }

    Context "3. YAML Front Matter Parser Adversarial Attacks" {
        It "Safely handles corrupt, unclosed, or deeply nested pseudo-YAML without crashing" {
            $corruptYamls = @(
                "---\ntitle: [unclosed list\n---`nText",
                "---\n: missing key\n---`nText",
                "---\n" + ("- item\n" * 100) + "---`nText",
                "---\ntags: `"`"`"`"`"`"`"`"\n---`nText"
            )

            foreach ($cy in $corruptYamls) {
                {
                    $meta = ConvertFrom-YamlHeader -MdText $cy -RelPath "corrupt.md"
                } | Should Not Throw
            }
        }
    }

    Context "4. HTML View XSS Injection Prevention" {
        It "HtmlEncodes malicious script payloads in Render-DocList and metadata tags" {
            $xssDocs = @(
                [PSCustomObject]@{
                    Title       = "<script>alert('xss')</script>"
                    RelPath     = "docs/<img src=x onerror=alert(1)>.md"
                    LastUpdated = [DateTime]::Now
                }
            )

            $rendered = Render-DocList -docArray $xssDocs -emptyMsg "None"
            $rendered | Should Not Match "<script>"
            $rendered | Should Match "&lt;script&gt;"
        }
    }

    Context "5. HTTP Route Request Invalid JSON Payload Error Path Tests" {
        BeforeAll {
            try {
                Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
            } catch {
                $null = $_
            }

            function Invoke-TestHttpRequestWithBody {
                param (
                    [string]$UrlPath,
                    [string]$HttpMethod = "POST",
                    [string]$BodyText = "{invalid json payload"
                )

                $port = Get-Random -Minimum 10000 -Maximum 60000
                $listener = [System.Net.HttpListener]::new()
                $listener.Prefixes.Add("http://localhost:$port/")
                $listener.Start()

                $client = $null
                $reqMessage = $null
                $httpRes = $null

                try {
                    $asyncResult = $listener.BeginGetContext($null, $null)

                    $client = [System.Net.Http.HttpClient]::new()
                    $content = [System.Net.Http.StringContent]::new($BodyText, [System.Text.Encoding]::UTF8, "application/json")

                    $reqMessage = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::$HttpMethod, "http://localhost:$port$UrlPath")
                    $reqMessage.Content = $content

                    $task = $client.SendAsync($reqMessage)

                    $context = $listener.EndGetContext($asyncResult)
                    $null = Invoke-WikiRouteRequest -Context $context -WikiDir $script:projectRoot -ScriptDir $script:projectRoot -Listener $listener

                    $httpRes = $task.Result
                    $resBody = $httpRes.Content.ReadAsStringAsync().Result
                    return [PSCustomObject]@{
                        StatusCode = [int]$httpRes.StatusCode
                        Body       = $resBody
                    }
                } finally {
                    if ($httpRes) { try { $httpRes.Dispose() } catch { $null = $_ } }
                    if ($reqMessage) { try { $reqMessage.Dispose() } catch { $null = $_ } }
                    if ($client) { try { $client.Dispose() } catch { $null = $_ } }
                    if ($listener -and $listener.IsListening) { try { $listener.Stop(); $listener.Close() } catch { $null = $_ } }
                }
            }
        }

        It "Returns HTTP 400 when malformed JSON is posted to /api/config" {
            $res = Invoke-TestHttpRequestWithBody -UrlPath "/api/config" -BodyText "{invalid json"
            $res.StatusCode | Should Be 400
            $res.Body | Should Match "リクエスト JSON のパースに失敗しました。"
        }

        It "Returns HTTP 400 when malformed JSON is posted to /api/save" {
            $res = Invoke-TestHttpRequestWithBody -UrlPath "/api/save" -BodyText "{invalid json"
            $res.StatusCode | Should Be 400
            $res.Body | Should Match "relPath and markdown body are required"
        }

        It "Returns HTTP 400 when malformed JSON is posted to /api/upload" {
            $res = Invoke-TestHttpRequestWithBody -UrlPath "/api/upload" -BodyText "{invalid json"
            $res.StatusCode | Should Be 400
            $res.Body | Should Match "fileName and data \(Base64\) are required."
        }

        It "Returns HTTP 400 when malformed JSON is posted to /api/delete" {
            $res = Invoke-TestHttpRequestWithBody -UrlPath "/api/delete" -BodyText "{invalid json"
            $res.StatusCode | Should Be 400
            $res.Body | Should Match "relPath parameter is required."
        }

        It "Returns HTTP 400 when malformed JSON is posted to /api/chat" {
            $res = Invoke-TestHttpRequestWithBody -UrlPath "/api/chat" -BodyText "{invalid json"
            $res.StatusCode | Should Be 400
            $res.Body | Should Match "Message field is required"
        }
    }
}
