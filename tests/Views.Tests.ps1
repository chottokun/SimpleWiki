# ==============================================================================
#  Views.Tests.ps1
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

Describe 'OKF Dynamic View and API Endpoint Tests' {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        Build-WikiIndex -TargetWikiDir $sampleDir -ForceRefresh | Out-Null
    }

    It "Builds WikiIndex from sample directory successfully" {
        $script:WikiIndex.Count | Should BeGreaterThan 0
    }

    It "Generates JSON for /api/index.json containing Envelope structure and OKF metadata" {
        $json = Get-ApiIndexJson
        $json | Should Not Be $null
        $obj = $json | ConvertFrom-Json
        $obj.Total | Should BeGreaterThan 0
        $obj.Count | Should BeGreaterThan 0
        $obj.Limit | Should BeGreaterThan 0
        $obj.Items[0].Title | Should Not Be $null
        $obj.Items[0].RelPath | Should Not Be $null
    }

    It "TC-API-01: Correctly applies limit and offset pagination boundaries" {
        $json = Get-ApiIndexJson -QueryParams @{ limit = "1"; offset = "0" }
        $obj = $json | ConvertFrom-Json
        $obj.Count | Should Be 1
        $obj.Limit | Should Be 1
        $obj.Offset | Should Be 0
        $obj.IsTruncated | Should Be $true

        # Boundary: offset out of bounds
        $jsonOutOfBounds = Get-ApiIndexJson -QueryParams @{ limit = "10"; offset = "99999" }
        $objOutOfBounds = $jsonOutOfBounds | ConvertFrom-Json
        $objOutOfBounds.Count | Should Be 0
        $objOutOfBounds.Items.Count | Should Be 0
        $objOutOfBounds.IsTruncated | Should Be $false

        # Boundary: negative offset fallback to 0
        $jsonNegOffset = Get-ApiIndexJson -QueryParams @{ limit = "2"; offset = "-5" }
        $objNegOffset = $jsonNegOffset | ConvertFrom-Json
        $objNegOffset.Offset | Should Be 0
    }

    It "TC-API-02: Handles invalid limit and maxLimit enforcement" {
        # Invalid string limit falls back to default limit
        $jsonInvalidLimit = Get-ApiIndexJson -QueryParams @{ limit = "invalid_number" }
        $objInvalidLimit = $jsonInvalidLimit | ConvertFrom-Json
        $objInvalidLimit.Limit | Should Be 100

        # Excess limit capped at maxLimit (1000)
        $jsonExcessLimit = Get-ApiIndexJson -QueryParams @{ limit = "5000" }
        $objExcessLimit = $jsonExcessLimit | ConvertFrom-Json
        $objExcessLimit.Limit | Should Be 1000

        # Bypass maxLimit with limit=all or -1
        $jsonAll = Get-ApiIndexJson -QueryParams @{ limit = "all" }
        $objAll = $jsonAll | ConvertFrom-Json
        $objAll.Limit | Should Be $objAll.Total
        $objAll.Count | Should Be $objAll.Total
    }

    It "TC-API-03: Filters by domain, tag, and since date accurately" {
        # Non-existent domain returns empty result cleanly
        $jsonNoDomain = Get-ApiIndexJson -QueryParams @{ domain = "non_existent_domain_xyz" }
        $objNoDomain = $jsonNoDomain | ConvertFrom-Json
        $objNoDomain.Total | Should Be 0
        $objNoDomain.Count | Should Be 0

        # Non-existent tag returns empty result cleanly
        $jsonNoTag = Get-ApiIndexJson -QueryParams @{ tag = "NonExistentTag999" }
        $objNoTag = $jsonNoTag | ConvertFrom-Json
        $objNoTag.Total | Should Be 0
        $objNoTag.Count | Should Be 0

        # Invalid since date string is safely ignored
        $jsonBadSince = Get-ApiIndexJson -QueryParams @{ since = "not-a-valid-date" }
        $objBadSince = $jsonBadSince | ConvertFrom-Json
        $objBadSince.Total | Should BeGreaterThan 0

        # Valid since date filters out older documents
        $futureDateStr = (Get-Date).AddYears(10).ToString("yyyy-MM-dd")
        $jsonFutureSince = Get-ApiIndexJson -QueryParams @{ since = $futureDateStr }
        $objFutureSince = $jsonFutureSince | ConvertFrom-Json
        $objFutureSince.Total | Should Be 0
    }

    It "TC-API-04: Selects specific fields with case-insensitivity and handles single item array preservation" {
        # Fields parameter selects only requested properties
        $jsonFields = Get-ApiIndexJson -QueryParams @{ fields = "title,relpath"; limit = "1" }
        $objFields = $jsonFields | ConvertFrom-Json
        $firstItem = $objFields.Items[0]
        $firstItem.Title | Should Not Be $null
        $firstItem.RelPath | Should Not Be $null
        $firstItem.PSObject.Properties["Description"] | Should Be $null
        $firstItem.PSObject.Properties["Author"] | Should Be $null

        # Single item response still preserves array type for Items
        $objFields.Items -is [Array] | Should Be $true
    }

    It "Get-ApiIndexJson guarantees Tags and Links are always JSON arrays across all items" {
        $json = Get-ApiIndexJson -QueryParams @{ limit = "all" }
        $obj = $json | ConvertFrom-Json
        foreach ($item in $obj.Items) {
            ($item.Tags -is [System.Array]) | Should Be $true
            ($item.Links -is [System.Array]) | Should Be $true
        }
    }

    It "Generates pre-chunked JSON for /api/chunks.json containing section-level RAG chunks" {
        $json = Get-ApiChunksJson
        $json | Should Not Be $null
        $json | Should Match "ChunkId"
        $json | Should Match "EnrichedText"
        $json | Should Match "Section"

        $chunksObj = $json | ConvertFrom-Json
        $chunksObj.Count | Should BeGreaterThan 0
        $chunksObj[0].ChunkId | Should Match "#chunk-"
        $chunksObj[0].EnrichedText | Should Match "\[Document:"
    }

    It "Generates HTML for /recent view" {
        $html = Get-RecentViewHtml
        $html | Should Match "最近の更新"
    }

    It "Generates HTML for /tags view" {
        $html = Get-TagsViewHtml
        $html | Should Match "タグ"
    }

    It "Generates HTML for /maintenance view" {
        $html = Get-MaintenanceViewHtml
        $html | Should Match "品質"
    }

    It "Generates HTML for /authors view" {
        $html = Get-AuthorsViewHtml
        $html | Should Match "著者"
    }

    It "Generates HTML for /search view" {
        $html = Get-SearchViewHtml -Query "API"
        $html | Should Match "検索結果"
    }
}


Describe 'Editor Settings and Read-Only Guard Tests' {
    BeforeAll {
        . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly
    }

    It "Get-SettingsViewData includes EditorEnabledChecked and EditorMaxBackups fields for ja and en" {
        $dataJa = Get-SettingsViewData -Lang "ja"
        $dataJa.EditorEnabledChecked | Should Not Be $null
        ($dataJa.EditorMaxBackups -ge 0) | Should Be $true
        $dataJa.EditorTitleLbl | Should Match "エディター設定"

        $dataEn = Get-SettingsViewData -Lang "en"
        $dataEn.EditorTitleLbl | Should Match "Editor Settings"
    }

    It "Get-SettingsViewHtml renders editor settings card, enable checkbox, and editor type selector" {
        $html = Get-SettingsViewHtml -Lang "ja"
        $html | Should Match "editorEnabled"
        $html | Should Match "editorType"
        $html | Should Match "toastui"
        $html | Should Match "textarea"
        $html | Should Match "editorMaxBackups"
        $html | Should Match "エディター設定"
        $html | Should Match "エディタエンジン:"
    }

    It "Get-WikiEditorModalHtml renders TOAST UI Editor container and JavaScript helpers" {
        $html = Get-WikiEditorModalHtml -Lang "ja"
        $html | Should Match 'id="wikiEditorToastUiContainer"'
        $html | Should Match 'function initToastEditor'
        $html | Should Match 'function getEditorContent'
        $html | Should Match 'function setEditorContent'
    }

    It "Get-WikiEditorModalHtml renders collapsible metadata accordion and toggle functions" {
        $htmlJa = Get-WikiEditorModalHtml -Lang "ja"
        $htmlJa | Should Match 'id="wikiMetaBody"'
        $htmlJa | Should Match 'id="metaAccordionIcon"'
        $htmlJa | Should Match 'id="metaAccordionSummary"'
        $htmlJa | Should Match 'function toggleMetaAccordion'
        $htmlJa | Should Match 'function updateMetaSummary'
        $htmlJa | Should Match 'クリックで開閉'

        $htmlEn = Get-WikiEditorModalHtml -Lang "en"
        $htmlEn | Should Match 'Click to toggle'
    }

    It "Get-WikiEditorModalHtml renders fullscreen maximize button and JavaScript toggle function" {
        $htmlJa = Get-WikiEditorModalHtml -Lang "ja"
        $htmlJa | Should Match 'id="wikiEditorFullscreenBtn"'
        $htmlJa | Should Match 'function toggleWikiEditorFullscreen'
        $htmlJa | Should Match 'toggleWikiEditorFullscreen\(\)'
        $htmlJa | Should Match '⛶ 最大化'

        $htmlEn = Get-WikiEditorModalHtml -Lang "en"
        $htmlEn | Should Match '⛶ Maximize'
    }

    It "Get-WikiEditorModalHtml binds save alert texts accurately without token prefix collision like dJs" {
        $htmlJa = Get-WikiEditorModalHtml -Lang "ja"
        $htmlJa | Should Match 'alert\(data\.warning \? "保存しました。'
        $htmlJa | Should Match ': "保存しました。"\);'
        $htmlJa | Should Not Match '保存dJs'
        $htmlJa | Should Not Match 'dWarningJs'
        $htmlJa | Should Not Match '\$ed[A-Za-z]+'

        $htmlEn = Get-WikiEditorModalHtml -Lang "en"
        $htmlEn | Should Match 'alert\(data\.warning \? "Saved successfully\.'
        $htmlEn | Should Match ': "Saved successfully\."\);'
        $htmlEn | Should Not Match 'SaveddJs'
        $htmlEn | Should Not Match '\$ed[A-Za-z]+'
    }

    It "Get-MainViewHtml renders Japanese typography stack and fullscreen modal CSS rules" {
        $html = Get-MainViewHtml -Title "Test" -RelPath "test.md" -ContentHtml "<p>Test</p>" -Config @{} -Lang "ja"
        $html | Should Match 'BIZ UDPGothic'
        $html | Should Match 'BIZ UDGothic'
        $html | Should Match 'Cascadia Mono'
        $html | Should Match '\.wiki-editor-modal\.fullscreen'
        $html | Should Match '\.wiki-editor-container\.fullscreen'
    }

    It "Get-OkfTopBarHtml hides edit button when EditorEnabled is false" {
        $meta = [PSCustomObject]@{
            Title       = "Test Doc"
            Domain      = "docs"
            Status      = "active"
            Tags        = @("test")
            LastUpdated = (Get-Date)
        }

        $topBarEnabled = Get-OkfTopBarHtml -Meta $meta -RelPath "test.md" -Lang "ja" -EditorEnabled $true
        $topBarEnabled | Should Match "edit-doc-btn"

        $topBarDisabled = Get-OkfTopBarHtml -Meta $meta -RelPath "test.md" -Lang "ja" -EditorEnabled $false
        $topBarDisabled | Should Not Match "edit-doc-btn"
    }

    It "/api/config saves editor enabled and maxBackups settings safely" {
        $tempIsolatedDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestEditorIsolated"
        if (Test-Path $tempIsolatedDir) { Remove-Item -Path $tempIsolatedDir -Recurse -Force -ErrorAction SilentlyContinue }
        $null = New-Item -ItemType Directory -Path $tempIsolatedDir

        Copy-Item -Path (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -Destination $tempIsolatedDir -Force
        Copy-Item -Path (Join-Path $projectRoot "lib") -Destination (Join-Path $tempIsolatedDir "lib") -Recurse -Force
        Copy-Item -Path (Join-Path $projectRoot "markdown_sample") -Destination (Join-Path $tempIsolatedDir "markdown_sample") -Recurse -Force

        $isolatedConfig = Join-Path $tempIsolatedDir "config.json"
        @{
            editor = @{ enabled = $true; maxBackups = 3 }
            search = @{ prebuildIndex = $false; useCache = $false; cacheFolder = ".cache" }
        } | ConvertTo-Json -Depth 5 | Out-File -FilePath $isolatedConfig -Encoding UTF8

        $port = 8095
        $psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { (Get-Command pwsh).Source } elseif (Get-Command powershell -ErrorAction SilentlyContinue) { (Get-Command powershell).Source } else { (Get-Process -Id $PID).Path }
        $proc = Start-Process $psExe -ArgumentList "-File", (Join-Path $tempIsolatedDir "Start-MarkdigWiki.ps1"), "-RootFolder", (Join-Path $tempIsolatedDir "markdown_sample"), "-Port", $port -PassThru
        Start-Sleep -Seconds 3
        try {
            # 1. /api/config POST with editor.enabled = false
            $payload = @{
                editor = @{
                    enabled    = $false
                    maxBackups = 5
                }
            } | ConvertTo-Json -Depth 5

            $res = Invoke-RestMethod -Uri "http://localhost:$port/api/config" -Method Post -Body $payload -ContentType "application/json; charset=utf-8"
            $res.success | Should Be $true

            # Verify saved config
            $savedCfg = Get-Content -Path $isolatedConfig -Raw -Encoding UTF8 | ConvertFrom-Json
            $savedCfg.editor.enabled | Should Be $false
            $savedCfg.editor.maxBackups | Should Be 5

            # 2. /api/save POST should return 403 Forbidden when editor.enabled = false
            $savePayload = @{
                relPath  = "概要.md"
                markdown = "# Read Only Test"
            } | ConvertTo-Json -Depth 5

            try {
                Invoke-RestMethod -Uri "http://localhost:$port/api/save" -Method Post -Body $savePayload -ContentType "application/json; charset=utf-8"
                throw "Expected 403 Forbidden exception"
            } catch {
                $_.Exception.Response.StatusCode.value__ | Should Be 403
            }
        } finally {
            Invoke-RestMethod -Uri "http://localhost:$port/api/shutdown" -Method Post -ErrorAction SilentlyContinue
            if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
            Remove-Item -Path $tempIsolatedDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}


Describe 'Directory Listing and Fallback Tests (Get-DirectoryListingHtml)' {
    BeforeAll {
        $projectRoot = (Resolve-Path "$PSScriptRoot\..").Path
        . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly

        # テスト用ディレクトリ構造を作成
        $testRoot = Join-Path $TestDrive "wiki-dir-listing"
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

        # サブフォルダ (index.md あり)
        $subWithIndex = Join-Path $testRoot "法律A"
        New-Item -Path $subWithIndex -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $subWithIndex "index.md") -Value "# 法律A" -Encoding UTF8

        # サブフォルダ (index.md なし)
        $subNoIndex = Join-Path $testRoot "法律B"
        New-Item -Path $subNoIndex -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $subNoIndex "art_001.md") -Value "# 条文1" -Encoding UTF8

        # ルート直下の .md ファイル
        Set-Content -Path (Join-Path $testRoot "glossary.md") -Value "# 用語集" -Encoding UTF8

        # 空フォルダ
        $emptyDir = Join-Path $testRoot "empty"
        New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null
    }

    It "ルートにフォルダと .md ファイルの一覧を生成する" {
        $html = Get-DirectoryListingHtml -DirFullPath $testRoot -RawUrlPath "/"
        $html | Should Match "dir-listing-list"
        $html | Should Match "法律A"
        $html | Should Match "法律B"
        $html | Should Match "glossary"
        $html | Should Match "dir-listing-notice"
        $html | Should Match "index\.md / README\.md がないため"
    }

    It "フォルダは太字リンク、ファイルは通常リンクで表示される" {
        $html = Get-DirectoryListingHtml -DirFullPath $testRoot -RawUrlPath "/"
        $html | Should Match "dir-listing-folder"
        $html | Should Match "dir-listing-file"
    }

    It "アイテム数が正しく表示される" {
        $html = Get-DirectoryListingHtml -DirFullPath $testRoot -RawUrlPath "/"
        # 3 subdirs (法律A, 法律B, empty) + 1 file (glossary.md) = 4
        $html | Should Match "4 件のアイテム"
    }

    It "空フォルダではコンテンツなしメッセージを表示する" {
        $emptyDir = Join-Path $testRoot "empty"
        $html = Get-DirectoryListingHtml -DirFullPath $emptyDir -RawUrlPath "/empty/"
        $html | Should Match "コンテンツがありません"
        $html | Should Match "dir-listing-notice"
    }

    It "フォルダリンクの href に URL エンコードされた名前が含まれる" {
        $html = Get-DirectoryListingHtml -DirFullPath $testRoot -RawUrlPath "/"
        # 日本語フォルダ名は URL エンコードされる
        $encodedName = [Uri]::EscapeDataString("法律A")
        $html | Should Match $encodedName
    }

    It "ルートの index.md/README.md フォールバック: index.md が存在する場合に正しく解決される" {
        # index.md があるディレクトリ
        $dirWithIndex = Join-Path $testRoot "法律A"
        $fullPath = [System.IO.Path]::GetFullPath($dirWithIndex)
        $relPath = "法律A"

        # ディレクトリ内の index.md を探す (スクリプトのロジックを再現)
        $dirIndexPath = Join-Path $fullPath "index.md"
        (Test-Path $dirIndexPath -PathType Leaf) | Should Be $true

        $newFullPath = [System.IO.Path]::GetFullPath($dirIndexPath)
        $newRelPath = (($relPath.TrimEnd('\') + '\index.md').TrimStart('\'))
        $newRelPath | Should Be "法律A\index.md"
        $newFullPath | Should Match "index\.md$"
    }

    It "ルートの index.md/README.md フォールバック: どちらもない場合は一覧表示される" {
        $fullPath = [System.IO.Path]::GetFullPath($testRoot)
        $dirIndexPath = Join-Path $fullPath "index.md"
        $dirReadmePath = Join-Path $fullPath "README.md"

        (Test-Path $dirIndexPath -PathType Leaf) | Should Be $false
        (Test-Path $dirReadmePath -PathType Leaf) | Should Be $false

        # フォルダ一覧が生成されることを確認
        $html = Get-DirectoryListingHtml -DirFullPath $fullPath -RawUrlPath "/"
        $html | Should Not BeNullOrEmpty
        $html | Should Match "dir-listing-list"
    }

    It "ルートパスの relPath 変換で空文字列から index.md への変換が正しい" {
        $relPath = ""
        $newRelPath = (($relPath.TrimEnd('\') + '\index.md').TrimStart('\'))
        $newRelPath | Should Be "index.md"
    }

    It "サブディレクトリパスの relPath 変換が正しい" {
        $relPath = "docs\"
        $newRelPath = (($relPath.TrimEnd('\') + '\index.md').TrimStart('\'))
        $newRelPath | Should Be "docs\index.md"
    }

    It "空の Markdown ファイルを読み込んでも例外をスローせずレンダリングできる" {
        $emptyMdPath = Join-Path $testRoot "empty-file.md"
        New-Item -Path $emptyMdPath -ItemType File -Force | Out-Null

        {
            $mdText = Get-Content -Path $emptyMdPath -Raw -Encoding UTF8
            if ($null -eq $mdText) { $mdText = "" }

            $builder  = New-Object Markdig.MarkdownPipelineBuilder
            $null     = [Markdig.MarkdownExtensions]::UseAdvancedExtensions($builder)
            $pipeline = $builder.Build()
            $rendered = [Markdig.Markdown]::ToHtml($mdText, $pipeline)
            $rendered | Should Be ""
        } | Should Not Throw
    }

    It "Render-ServerFolderTreeHtml pins index.md and README.md to the top of folder listings" {
        $node = [PSCustomObject]@{
            Files = [System.Collections.Generic.List[PSObject]]@(
                [PSCustomObject]@{ FullName = "C:\wiki\zoo.md"; BaseName = "zoo" },
                [PSCustomObject]@{ FullName = "C:\wiki\about.md"; BaseName = "about" },
                [PSCustomObject]@{ FullName = "C:\wiki\index.md"; BaseName = "index" },
                [PSCustomObject]@{ FullName = "C:\wiki\README.md"; BaseName = "README" }
            )
            SubFolders = [ordered]@{}
        }
        $treeHtml = Render-ServerFolderTreeHtml -node $node -currentRelPath "" -wikiDir "C:\wiki"
        $idxPos = $treeHtml.IndexOf("index")
        $readmePos = $treeHtml.IndexOf("README")
        $aboutPos = $treeHtml.IndexOf("about")
        $zooPos = $treeHtml.IndexOf("zoo")

        ($idxPos -lt $readmePos) | Should Be $true
        ($readmePos -lt $aboutPos) | Should Be $true
        ($aboutPos -lt $zooPos) | Should Be $true
    }

    It "Render-ServerFolderTreeHtml attaches data-folder and openNewDocModal click handlers to folder summary add buttons" {
        $subNode = [PSCustomObject]@{
            Files = [System.Collections.Generic.List[PSObject]]@()
            SubFolders = [ordered]@{}
        }
        $node = [PSCustomObject]@{
            Files = [System.Collections.Generic.List[PSObject]]@()
            SubFolders = [ordered]@{
                "user-guide" = $subNode
            }
        }
        $treeHtml = Render-ServerFolderTreeHtml -node $node -currentRelPath "" -wikiDir "C:\wiki" -parentRelPath "docs"
        $treeHtml | Should Match 'data-folder=.docs/user-guide/.'
        $treeHtml | Should Match 'openNewDocModal\("docs/user-guide/"\)'
        $treeHtml | Should Match 'event\.stopPropagation\(\)'
        $treeHtml | Should Match 'sidebar-add-doc-btn'
    }

    It "Render-ServerFolderTreeHtml safely sorts folders without index.md or empty files" {
        $node = [PSCustomObject]@{
            Files = [System.Collections.Generic.List[PSObject]]@(
                [PSCustomObject]@{ FullName = "C:\wiki\zeta.md"; BaseName = "zeta" },
                [PSCustomObject]@{ FullName = "C:\wiki\alpha.md"; BaseName = "alpha" }
            )
            SubFolders = [ordered]@{}
        }
        {
            $treeHtml = Render-ServerFolderTreeHtml -node $node -currentRelPath "" -wikiDir "C:\wiki"
            $alphaPos = $treeHtml.IndexOf("alpha")
            $zetaPos = $treeHtml.IndexOf("zeta")
            ($alphaPos -lt $zetaPos) | Should Be $true
        } | Should Not Throw
    }

    It "Get-ChatWidgetHtml に開いているページを含めるデフォルトONのチェックボックスが含まれる" {
        $html = Get-ChatWidgetHtml
        $html | Should Match "okfIncludeCurrentPage"
        $html | Should Match "checked"
        $html | Should Match "開いているページを含める"
        $html | Should Match "根拠ドキュメント \(Markdown\)"
        $html | Should Match "text/event-stream"
        $html | Should Match "getReader"
        $html | Should Match "stream: true"
    }
}


Describe "Multi-Language (i18n) & Localization Tests" {
    BeforeAll {
        Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
    }

    It "Get-LocalizedStr returns Japanese by default and English when requested" {
        $jaHome = Get-LocalizedStr -Key "home" -Lang "ja"
        $jaHome | Should Be "🏠 ホーム"

        $enHome = Get-LocalizedStr -Key "home" -Lang "en"
        $enHome | Should Be "🏠 Home"
    }

    It "Get-LocalizedStr falls back to Japanese when requested language key is missing" {
        $fallbackStr = Get-LocalizedStr -Key "home" -Lang "unknown_lang"
        $fallbackStr | Should Be "🏠 ホーム"
    }

    It "Get-RequestLanguage resolves language with correct priority: Query > Cookie > Config > Default" {
        $cfgJa = [PSCustomObject]@{ defaultLanguage = "ja" }
        $cfgEn = [PSCustomObject]@{ defaultLanguage = "en" }

        # 1. Query parameter overrides all (both NameValueCollection and Hashtable)
        $qParams = [System.Web.HttpUtility]::ParseQueryString("lang=en")
        $cookieCol = New-Object System.Net.CookieCollection
        $cookieCol.Add((New-Object System.Net.Cookie("lang", "ja", "/", "localhost")))
        $resolved = Get-RequestLanguage -QueryParams $qParams -Cookies $cookieCol -Config $cfgJa
        $resolved | Should Be "en"

        $qHash = @{ "lang" = "en" }
        $resolvedHash = Get-RequestLanguage -QueryParams $qHash -Cookies $cookieCol -Config $cfgJa
        $resolvedHash | Should Be "en"

        # 2. Cookie overrides Config
        $emptyQ = [System.Web.HttpUtility]::ParseQueryString("")
        $resolvedCookie = Get-RequestLanguage -QueryParams $emptyQ -Cookies $cookieCol -Config $cfgEn
        $resolvedCookie | Should Be "ja"

        # 3. Config defaultLanguage
        $resolvedCfg = Get-RequestLanguage -QueryParams $emptyQ -Cookies (New-Object System.Net.CookieCollection) -Config $cfgEn
        $resolvedCfg | Should Be "en"

        # 4. Default fallback
        $resolvedDef = Get-RequestLanguage -QueryParams $emptyQ -Cookies (New-Object System.Net.CookieCollection) -Config $null
        $resolvedDef | Should Be "ja"
    }

    It "Generates localized HTML views in English when requested" {
        $recentHtml = Get-RecentViewHtml -Lang "en"
        $recentHtml | Should Match "🕒 Recent Updates"
        $recentHtml | Should Match "<th>Last Updated</th>"

        $tagsHtml = Get-TagsViewHtml -Lang "en"
        $tagsHtml | Should Match "🏷️ Tags"

        $maintHtml = Get-MaintenanceViewHtml -Lang "en"
        $maintHtml | Should Match "🧹 Quality & Maintenance Dashboard"

        $authorsHtml = Get-AuthorsViewHtml -Lang "en"
        $authorsHtml | Should Match "👥 Authors"

        $searchHtml = Get-SearchViewHtml -Query "test" -Lang "en"
        $searchHtml | Should Match "🔍 OKF Knowledge Search Results"
        $searchHtml | Should Match "Active"

        $settingsHtml = Get-SettingsViewHtml -Lang "en"
        $settingsHtml | Should Match "⚙️ System Settings"
        $settingsHtml | Should Match "Enable index cache"

        $chatWidgetHtml = Get-ChatWidgetHtml -Lang "en"
        $chatWidgetHtml | Should Match "🤖 OKF Wiki AI Assistant"
        $chatWidgetHtml | Should Match "chat-widget-btn"

        $sidebarHtml = Get-SidebarHtml -currentRelPath "" -Lang "en"
        $sidebarHtml | Should Not Match "🔄 Clear Cache"
        $sidebarHtml | Should Match "nav-file"
    }

    It "Static HTML exporter supports -Language en parameter and localizes metadata cards" {
        $exportScript = Join-Path $projectRoot "Export-MarkdigWiki.ps1"
        $sampleDir    = Join-Path $projectRoot "markdown_sample"
        $testOutDir   = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_I18nExportTest"

        if (Test-Path $testOutDir) { Remove-Item -Path $testOutDir -Recurse -Force }
        try {
            & $exportScript -RootFolder $sampleDir -OutputDir $testOutDir -Language "en"
            $indexHtml = Join-Path $testOutDir "index.html"
            (Test-Path $indexHtml) | Should Be $true
            $content = [System.IO.File]::ReadAllText($indexHtml)
            $content | Should Match '<html lang="en">'
            $content | Should Match '<h2>📄 Document List</h2>'
            $content | Should Match 'ℹ️ Document Metadata \(OKF\)'
            $content | Should Match 'Last Updated:'
        } finally {
            if (Test-Path $testOutDir) { Remove-Item -Path $testOutDir -Recurse -Force }
        }
    }

    It "Dynamically merges external i18n.json dictionary entries" {
        $tempI18nFile = Join-Path $projectRoot "i18n.json"
        $i18nContent = '{ "zh": { "home": "首页" }, "en": { "home": "Custom Home" } }'
        [System.IO.File]::WriteAllText($tempI18nFile, $i18nContent, [System.Text.Encoding]::UTF8)

        try {
            # Reload script logic to parse i18n.json
            . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly

            $homeZh = Get-LocalizedStr -Key "home" -Lang "zh"
            $homeZh | Should Be "首页"

            $homeEnOverride = Get-LocalizedStr -Key "home" -Lang "en"
            $homeEnOverride | Should Be "Custom Home"
        } finally {
            if (Test-Path $tempI18nFile) { Remove-Item -Path $tempI18nFile -Force }
            # Restore default script state
            . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly
        }
    }

    It "Get-LocalizedStr safely handles format arguments and non-existent keys" {
        # FormatArgs substitution
        $itemsJa = Get-LocalizedStr -Key "items_count" -Lang "ja" -FormatArgs @(42)
        $itemsJa | Should Be "42 件のアイテム"

        $itemsEn = Get-LocalizedStr -Key "items_count" -Lang "en" -FormatArgs @(42)
        $itemsEn | Should Be "42 items"

        # Missing key returns the key itself
        $missing = Get-LocalizedStr -Key "non_existent_custom_key_123" -Lang "en"
        $missing | Should Be "non_existent_custom_key_123"
    }

    It "Get-RequestLanguage normalizes uppercase and mixed-case language inputs" {
        $qParams = [System.Web.HttpUtility]::ParseQueryString("lang=EN")
        $resolved = Get-RequestLanguage -QueryParams $qParams -Cookies $null -Config $null
        $resolved | Should Be "en"

        $cookieCol = New-Object System.Net.CookieCollection
        $cookieCol.Add((New-Object System.Net.Cookie("lang", "JA", "/", "localhost")))
        $resolvedCookie = Get-RequestLanguage -QueryParams $null -Cookies $cookieCol -Config $null
        $resolvedCookie | Should Be "ja"
    }

    It "Get-DirectoryListingHtml produces properly localized output in English" {
        $sampleDir = Join-Path $projectRoot "markdown_sample"
        $dirHtml = Get-DirectoryListingHtml -DirFullPath $sampleDir -RawUrlPath "/" -Lang "en"
        $dirHtml | Should Match "items"
        $dirHtml | Should Match "Showing directory listing because index.md / README.md is missing."
    }

    It "Get-OkfTopBarHtml and Get-OkfFooterCardHtml correctly localize warning and labels in English" {
        $mockMeta = [PSCustomObject]@{
            Title       = "Test Deprecated Doc"
            Description = "A test deprecated document"
            Author      = "Tester"
            Domain      = "testing"
            Status      = "deprecated"
            Tags        = @("test")
            LastUpdated = (Get-Date "2025-01-01")
        }

        $topBar = Get-OkfTopBarHtml -Meta $mockMeta -RelPath "test.md" -Lang "en"
        $topBar | Should Match "Warning: Deprecated Document"
        $topBar | Should Match "Edit"

        $footer = Get-OkfFooterCardHtml -Meta $mockMeta -Lang "en"
        $footer | Should Match "Document Metadata \(OKF\)"
        $footer | Should Match "Author:"
        $footer | Should Match "Last Updated:"
    }

    It "Chat prompts (Fast RAG and Agentic RAG) are localized properly in English and Japanese" {
        $sysJa = Get-LocalizedStr -Key "default_system_prompt" -Lang "ja"
        $sysJa | Should Match "Wikiのナレッジを元に回答するアシスタント"
        $sysJa | Should Match "用語のブレも考慮し"

        $sysEn = Get-LocalizedStr -Key "default_system_prompt" -Lang "en"
        $sysEn | Should Match "assistant who answers based on the knowledge of the Wiki"
        $sysEn | Should Match "variations in terminology"

        $agentJa = Get-LocalizedStr -Key "default_agentic_system_prompt" -Lang "ja"
        $agentJa | Should Match "自律調査して回答する Agentic RAG アシスタント"

        $agentEn = Get-LocalizedStr -Key "default_agentic_system_prompt" -Lang "en"
        $agentEn | Should Match "Agentic RAG assistant that autonomously investigates"

        # Agentic RAG fallback with Lang = "en"
        $resEn = Invoke-AgenticRagChat -ApiUrl "http://invalid-url-for-test.local/v1" -ApiKey "dummy" -Model "test" -UserMessage "What is the architecture?" -MaxTurns 1 -Lang "en"
        $resEn.answer | Should Match "I autonomously investigated the Wiki|I searched the Wiki"
    }
}


Describe "UI Shutdown and Brand Title Customization Tests" {
    BeforeAll {
        . (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -DotSourceOnly
    }

    It "Localizes brand_title correctly for ja and en" {
        $brandJa = Get-LocalizedStr -Key "brand_title" -Lang "ja"
        $brandJa | Should Match "SimpleWiki"

        $brandEn = Get-LocalizedStr -Key "brand_title" -Lang "en"
        $brandEn | Should Match "SimpleWiki"
    }

    It "Localizes all shutdown dictionary keys in ja and en" {
        $keys = @("shutdown_btn", "shutdown_confirm", "shutdown_done_title", "shutdown_done_desc", "settings_server_title", "settings_shutdown_desc", "settings_shutdown_btn")
        foreach ($k in $keys) {
            $valJa = Get-LocalizedStr -Key $k -Lang "ja"
            $valJa | Should Not Be $k
            $valJa.Length | Should BeGreaterThan 0

            $valEn = Get-LocalizedStr -Key $k -Lang "en"
            $valEn | Should Not Be $k
            $valEn.Length | Should BeGreaterThan 0
        }
    }

    It "Get-SettingsViewHtml renders server control section and shutdown trigger" {
        $htmlJa = Get-SettingsViewHtml -Lang "ja"
        $htmlJa | Should Match "サーバー制御"
        $htmlJa | Should Match "shutdownWikiServer\(\)"

        $htmlEn = Get-SettingsViewHtml -Lang "en"
        $htmlEn | Should Match "Server Control"
        $htmlEn | Should Match "shutdownWikiServer\(\)"
    }

    It "Start-MarkdigWiki.ps1 includes /api/shutdown endpoint and brand_title placeholder" {
        $scriptContent = (Get-ChildItem -Path $projectRoot -Filter "*.ps1" -Recurse | ForEach-Object { Get-Content -Path $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        $scriptContent | Should Match '/api/shutdown'
        $scriptContent | Should Match 'shutdown-btn'
        $scriptContent | Should Match 'shutdownWikiServer'
        $scriptContent | Should Match 'shutdownOverlay'
    }

    It "All i18n dictionary keys are completely synchronized between ja and en" {
        $jaKeys = $script:I18n["ja"].Keys | Sort-Object
        $enKeys = $script:I18n["en"].Keys | Sort-Object

        $missingInEn = $jaKeys | Where-Object { -not $script:I18n["en"].ContainsKey($_) }
        $missingInJa = $enKeys | Where-Object { -not $script:I18n["ja"].ContainsKey($_) }

        $missingInEn.Count | Should Be 0
        $missingInJa.Count | Should Be 0
    }

    It "Start-MarkdigWiki.ps1 binds all editor i18n variables into template and JS" {
        $scriptContent = (Get-ChildItem -Path $projectRoot -Filter "*.ps1" -Recurse | ForEach-Object { Get-Content -Path $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        $scriptContent | Should Match 'editor_gen_prefix'
        $scriptContent | Should Match 'editor_warning_yaml'
        $scriptContent | Should Match 'editor_loading'
        $scriptContent | Should Match 'editor_history_loading'
        $scriptContent | Should Match 'editor_load_error'
        $scriptContent | Should Match 'editor_backup_load_err'
        $scriptContent | Should Match 'editor_saved_warning'
        $scriptContent | Should Match 'editor_saved'
        $scriptContent | Should Match 'indexing_searching'
        $scriptContent | Should Match 'editor_meta_section_title'
        $scriptContent | Should Match 'editor_mode_form'
        $scriptContent | Should Match 'editor_mode_raw'
        $scriptContent | Should Match 'editor_field_type'
        $scriptContent | Should Match 'editor_field_title'
        $scriptContent | Should Match 'editor_field_status'
        $scriptContent | Should Match 'editor_status_draft'
        $scriptContent | Should Match 'editor_status_stable'
        $scriptContent | Should Match 'editor_status_deprecated'
        $scriptContent | Should Match 'editor_field_version'
        $scriptContent | Should Match 'editor_field_domain'
        $scriptContent | Should Match 'editor_field_author'
        $scriptContent | Should Match 'editor_field_reviewer'
        $scriptContent | Should Match 'editor_field_last_updated'
        $scriptContent | Should Match 'editor_set_today'
        $scriptContent | Should Match 'editor_field_desc'
        $scriptContent | Should Match 'editor_field_tags'
        $scriptContent | Should Match 'editor_field_related'
        $scriptContent | Should Match 'editor_field_superseded'
        $scriptContent | Should Match 'editor_auto_date'
        $scriptContent | Should Match 'editor_body_placeholder'
        $scriptContent | Should Match 'editor_shortcut_hint'
    }

    It "Start-MarkdigWiki.ps1 contains Form & RAW YAML separated editor modal HTML and JS functions" {
        $scriptContent = (Get-ChildItem -Path $projectRoot -Filter "*.ps1" -Recurse | ForEach-Object { Get-Content -Path $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        $scriptContent | Should Match 'id="yamlFormContainer"'
        $scriptContent | Should Match 'id="yamlRawContainer"'
        $scriptContent | Should Match 'id="wikiEditorBodyTextarea"'
        $scriptContent | Should Match 'id="metaType"'
        $scriptContent | Should Match 'id="metaLastUpdated"'
        $scriptContent | Should Match 'function parseMarkdownWithYaml'
        $scriptContent | Should Match 'function populateYamlForm'
        $scriptContent | Should Match 'function generateMarkdownWithYaml'
        $scriptContent | Should Match 'function switchYamlMode'
        $scriptContent | Should Match 'function onStatusChange'
        $scriptContent | Should Match 'function setEditorDateToday'
        $scriptContent | Should Match 'supersededByGroup'
        $scriptContent | Should Match 'metaAutoDate'
    }

    It "Start-MarkdigWiki.ps1 includes keyboard shortcuts for editor modal (Ctrl+S save and Esc cancel)" {
        $scriptContent = (Get-ChildItem -Path $projectRoot -Filter "*.ps1" -Recurse | ForEach-Object { Get-Content -Path $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        $scriptContent | Should Match 'addEventListener\("keydown"'
        $scriptContent | Should Match 'saveWikiMarkdown\(\)'
        $scriptContent | Should Match 'closeWikiEditor\(\)'
    }

    It "Start-MarkdigWiki.ps1 sanitizes RAW YAML delimiters and uses local date generation" {
        $scriptContent = (Get-ChildItem -Path $projectRoot -Filter "*.ps1" -Recurse | ForEach-Object { Get-Content -Path $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        $scriptContent | Should Match 'replace\(\/\^---\\r\?\\n\?\/, \x27\x27\)\.replace\(\/\\r\?\\n\?---\\r\?\$\/, \x27\x27\)'
        $scriptContent | Should Match 'd\.getFullYear\(\)'
        $scriptContent | Should Match 'd\.getMonth\(\) \+ 1'
        $scriptContent | Should Match 'd\.getDate\(\)'
    }

    It "/api/config handles OrderedDictionary and saves config.json without errors" {
        $tempIsolatedDir = Join-Path ([System.IO.Path]::GetTempPath()) "SimpleWiki_TestServerIsolated"
        if (Test-Path $tempIsolatedDir) { Remove-Item -Path $tempIsolatedDir -Recurse -Force -ErrorAction SilentlyContinue }
        $null = New-Item -ItemType Directory -Path $tempIsolatedDir

        # サーバー起動に必要な最小構成（スクリプト、lib、sample、config）を一時ディレクトリにコピー
        Copy-Item -Path (Join-Path $projectRoot "Start-MarkdigWiki.ps1") -Destination $tempIsolatedDir -Force
        Copy-Item -Path (Join-Path $projectRoot "lib") -Destination (Join-Path $tempIsolatedDir "lib") -Recurse -Force
        Copy-Item -Path (Join-Path $projectRoot "markdown_sample") -Destination (Join-Path $tempIsolatedDir "markdown_sample") -Recurse -Force

        $isolatedConfig = Join-Path $tempIsolatedDir "config.json"
        @{
            search = @{ prebuildIndex = $false; useCache = $false; cacheFolder = ".cache" }
            rag    = @{ enabled = $false; apiUrl = "http://localhost:11434/v1"; model = "test-model" }
        } | ConvertTo-Json -Depth 5 | Out-File -FilePath $isolatedConfig -Encoding UTF8

        $port = 8096
        $psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { (Get-Command pwsh).Source } elseif (Get-Command powershell -ErrorAction SilentlyContinue) { (Get-Command powershell).Source } else { (Get-Process -Id $PID).Path }
        $proc = Start-Process $psExe -ArgumentList "-File", (Join-Path $tempIsolatedDir "Start-MarkdigWiki.ps1"), "-RootFolder", (Join-Path $tempIsolatedDir "markdown_sample"), "-Port", $port -PassThru
        Start-Sleep -Seconds 3
        try {
            $payload = @{
                search = @{
                    prebuildIndex = $false
                    useCache      = $true
                    cacheFolder   = ".cache"
                }
                rag = @{
                    enabled = $false
                    apiUrl  = "http://localhost:11434/v1"
                    model   = "qwen2.5-coder-7b-instruct"
                }
            } | ConvertTo-Json -Depth 5

            $res = Invoke-RestMethod -Uri "http://localhost:$port/api/config" -Method Post -Body $payload -ContentType "application/json; charset=utf-8"
            $res.success | Should Be $true

            # Activation Code 結合テスト: 自PCマシンID向けアクティベーションコードの送信
            $mid = Get-MachineFingerprint
            $actCode = Protect-ActivationCode -ApiKey "sk-live-test-12345" -MachineId $mid
            $actPayload = @{
                rag = @{
                    enabled        = $true
                    activationCode = $actCode
                }
            } | ConvertTo-Json -Depth 5
            $actRes = Invoke-RestMethod -Uri "http://localhost:$port/api/config" -Method Post -Body $actPayload -ContentType "application/json; charset=utf-8"
            $actRes.success | Should Be $true

            # 保存された隔離環境の config.json が DPAPI 形式になっていることを検証
            $savedCfg = Get-Content -Path $isolatedConfig -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($IsWindows -or $env:OS -eq "Windows_NT") { $savedCfg.rag.apiKey | Should Match "^DPAPI:" } else { $savedCfg.rag.apiKey | Should Match "^ENC:" }
            $resolvedKey = Get-ResolvedSecret -SecretValue $savedCfg.rag.apiKey
            $resolvedKey | Should Be "sk-live-test-12345"

            # 不正なマシンID用アクティベーションコード送信時のエラー拒絶テスト
            $badActCode = Protect-ActivationCode -ApiKey "sk-other-key" -MachineId "OTHER-MACHINE-9999"
            $badPayload = @{
                rag = @{
                    enabled        = $true
                    activationCode = $badActCode
                }
            } | ConvertTo-Json -Depth 5

            try {
                Invoke-RestMethod -Uri "http://localhost:$port/api/config" -Method Post -Body $badPayload -ContentType "application/json; charset=utf-8"
                throw "Expected HTTP 400 failure"
            } catch {
                # 400 Bad Request で弾かれることを検証
                $_.Exception.Response.StatusCode.value__ | Should Be 400
            }
        } finally {
            Invoke-RestMethod -Uri "http://localhost:$port/api/shutdown" -Method Post -ErrorAction SilentlyContinue
            if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
            Remove-Item -Path $tempIsolatedDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}




Describe "WikiViews Helper Functions Suite" {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
    }

    Context "PR #25 & #32: WikiViews Helper Functions" {
        It "Get-DocListHtml generates valid HTML with escaped titles, normalized paths, and formatted dates" {
            $docs = @(
                [PSCustomObject]@{
                    Title       = "Doc & <Tag> One"
                    RelPath     = "guide\doc1.md"
                    LastUpdated = [DateTime]::Parse("2026-08-01")
                },
                [PSCustomObject]@{
                    Title       = "Doc Two"
                    RelPath     = "guide/doc2.md"
                    LastUpdated = "2026-08-02"
                }
            )

            $html = Get-DocListHtml -docArray $docs -emptyMsg "No docs available"
            $html | Should Match "^<ul>.*</ul>$"
            $html | Should Match "<li><a href='/guide/doc1.md'>Doc &amp; &lt;Tag&gt; One</a> <span class='muted'>\(2026-08-01\)</span></li>"
            $html | Should Match "<li><a href='/guide/doc2.md'>Doc Two</a> <span class='muted'>\(2026-08-02\)</span></li>"
        }

        It "Get-DocListHtml handles null, empty, and null-element arrays gracefully with emptyMsg" {
            $nullHtml = Get-DocListHtml -docArray $null -emptyMsg "No items found"
            $nullHtml | Should Be "<p class='empty-msg'>No items found</p>"

            $emptyHtml = Get-DocListHtml -docArray @() -emptyMsg "No items found"
            $emptyHtml | Should Be "<p class='empty-msg'>No items found</p>"

            $nullElementsHtml = Get-DocListHtml -docArray @($null, $null) -emptyMsg "No items found"
            $nullElementsHtml | Should Be "<p class='empty-msg'>No items found</p>"
        }

        It "Render-DocList generates valid HTML by delegating to Get-DocListHtml" {
            $docs = @(
                [PSCustomObject]@{
                    Title       = "Doc & <Tag> One"
                    RelPath     = "guide\doc1.md"
                    LastUpdated = [DateTime]::Parse("2026-08-01")
                },
                [PSCustomObject]@{
                    Title       = "Doc Two"
                    RelPath     = "guide/doc2.md"
                    LastUpdated = "2026-08-02"
                }
            )

            $html = Render-DocList -docArray $docs -emptyMsg "No docs available"
            $html | Should Match "<ul>"
            $html | Should Match "Doc &amp; &lt;Tag&gt; One"
            $html | Should Match "/guide/doc1.md"
            $html | Should Match "\(2026-08-01\)"

            $emptyHtml = Render-DocList -docArray @() -emptyMsg "Empty List"
            $emptyHtml | Should Be "<p class='empty-msg'>Empty List</p>"
        }

        It "Get-SettingsViewData prepares complete data packet for view rendering" {
            $dataJa = Get-SettingsViewData -Lang "ja"
            $dataJa.Lang | Should Be "ja"
            $dataJa.TitleLbl | Should Not BeNullOrEmpty
            $dataJa.SearchTitleLbl | Should Not BeNullOrEmpty

            $dataEn = Get-SettingsViewData -Lang "en"
            $dataEn.Lang | Should Be "en"
            $dataEn.TitleLbl | Should Not BeNullOrEmpty
        }

        It "Render-SettingsSearchCard, Render-SettingsRagCard, Render-SettingsServerCard render semantic cards" {
            $data = Get-SettingsViewData -Lang "ja"
            $searchCard = Render-SettingsSearchCard -Data $data
            $searchCard | Should Match "okf-card"
            $searchCard | Should Match "rebuildBtn"

            $ragCard = Render-SettingsRagCard -Data $data
            $ragCard | Should Match "machineIdText"

            $serverCard = Render-SettingsServerCard -Data $data
            $serverCard | Should Match "shutdownWikiServer\(\)"
        }
    }
}


Describe "Refactoring & Facade Integration Unit Tests" {
    BeforeAll {
        $serverScript = Join-Path $projectRoot "Start-MarkdigWiki.ps1"
        . $serverScript -DotSourceOnly
    }

    It "Dot-sourcing lib/WikiViews.ps1 facade correctly exports all functions from lib/views/ sub-modules" {
        (Get-Command Initialize-WikiIndex -ErrorAction SilentlyContinue) | Should Not Be $null
        (Get-Command Get-GlossaryBoxHtml -ErrorAction SilentlyContinue) | Should Not Be $null
        (Get-Command Get-DocListHtml -ErrorAction SilentlyContinue) | Should Not Be $null
        (Get-Command Get-SettingsViewData -ErrorAction SilentlyContinue) | Should Not Be $null
        (Get-Command Get-StellaViewHtml -ErrorAction SilentlyContinue) | Should Not Be $null
    }

    It "Backward-compatibility alias/wrappers delegate correctly to new Approved Verbs functions" {
        { Ensure-WikiIndexLoaded -TargetWikiDir $projectRoot } | Should Not Throw
        (Render-DocList -docArray @() -emptyMsg "Empty") | Should Match "Empty"

        $sampleWikiDir = Join-Path $projectRoot "markdown_sample"
        $gBox = Render-GlossaryBoxHtml -Term "OKF" -TargetWikiDir $sampleWikiDir
        $gBox | Should Match "OKF"
    }

    It "Measure-WikiNodeCoordinate works identically to Measure-WikiNodeCoordinates and Calculate-WikiNodeCoordinates" {
        $docs = @(
            [PSCustomObject]@{ Title = "Doc A"; RelPath = "a.md"; Domain = "d1"; Status = "active" },
            [PSCustomObject]@{ Title = "Doc B"; RelPath = "b.md"; Domain = "d2"; Status = "active" }
        )
        $p1 = Measure-WikiNodeCoordinate -DocList $docs
        $p2 = Measure-WikiNodeCoordinates -DocList $docs
        $p3 = Calculate-WikiNodeCoordinates -DocList $docs

        $p1.Count | Should Be 2
        $p2.Count | Should Be 2
        $p3.Count | Should Be 2
    }

    It "Get-ServerFolderTreeHtml and Get-FileTreeHtml alias wrappers render folder trees without exceptions" {
        $node = [PSCustomObject]@{
            Files = [System.Collections.Generic.List[PSObject]]@(
                [PSCustomObject]@{ FullName = "C:\wiki\index.md"; BaseName = "index" }
            )
            SubFolders = [ordered]@{}
        }
        $tree1 = Get-ServerFolderTreeHtml -node $node -currentRelPath "" -wikiDir "C:\wiki"
        $tree2 = Render-ServerFolderTreeHtml -node $node -currentRelPath "" -wikiDir "C:\wiki"
        $tree1 | Should Be $tree2
    }
}
