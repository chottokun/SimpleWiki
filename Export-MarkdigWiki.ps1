# ==============================================================================
#  Markdig + PowerShell 100% オフライン Wiki 静的 HTML エキスポート機能
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================
param (
    [string]$RootFolder = "",
    [string]$OutputDir  = ""
)

$scriptDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
$libDir    = Join-Path $scriptDir "lib"

# 入力ルートフォルダの設定 (指定がない場合は markdown_sample フォルダ、存在しない場合は $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($RootFolder)) {
    $sampleDir = Join-Path $scriptDir "markdown_sample"
    if (Test-Path $sampleDir) {
        $wikiDir = $sampleDir
    } else {
        $wikiDir = $scriptDir
    }
} else {
    $wikiDir = [System.IO.Path]::GetFullPath($RootFolder)
}

if (-not (Test-Path $wikiDir)) {
    Write-Error "指定されたルートフォルダが見つかりません:`n$wikiDir"
    exit 1
}

# 出力ディレクトリの設定
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $targetDistDir = Join-Path $scriptDir "dist"
} else {
    $targetDistDir = [System.IO.Path]::GetFullPath($OutputDir)
}

if (-not (Test-Path $targetDistDir)) {
    New-Item -ItemType Directory -Path $targetDistDir -Force | Out-Null
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  Markdig Wiki 静的 HTML エキスポート開始" -ForegroundColor Green
Write-Host "  入力元: $wikiDir" -ForegroundColor Yellow
Write-Host "  出力先: $targetDistDir" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Green

# --- 1. Markdig.dll および依存ライブラリのロード ---
$markdigDll = Join-Path $libDir "Markdig.dll"
if (-not (Test-Path $markdigDll)) {
    Write-Error "'lib' フォルダに Markdig.dll が見つかりません:`n$markdigDll"
    exit 1
}

Get-ChildItem -Path $libDir -Filter "*.dll" | ForEach-Object {
    Add-Type -Path $_.FullName
}

# --- 2. 静的 HTML 用サイドバーの自動生成関数 (相対パス計算対応) ---
function Get-ExportSidebarHtml {
    param ($currentFile, $allMdFiles)

    $currentHtmlPath = $currentFile.FullName -replace '\.md$', '.html'
    $currentUri      = New-Object System.Uri($currentHtmlPath)

    $html = "<ul>`n"
    foreach ($file in $allMdFiles) {
        $targetHtmlPath = $file.FullName -replace '\.md$', '.html'
        $targetUri      = New-Object System.Uri($targetHtmlPath)

        # 現在地からの相対パスを動的計算 (file:// のローカル表示および Web サーバーの双方で動作)
        $relativeUri = $currentUri.MakeRelativeUri($targetUri).ToString()
        $title       = [System.Net.WebUtility]::HtmlEncode($file.BaseName)
        $activeClass = if ($file.FullName -eq $currentFile.FullName) { ' class="active"' } else { '' }

        $html += "  <li><a href='$relativeUri'$activeClass>$title</a></li>`n"
    }
    $html += "</ul>"
    return $html
}

# --- 3. マークダウンファイルの抽出と HTML 変換 ---
$allMdFiles = Get-ChildItem -Path $wikiDir -Recurse -Filter "*.md" | 
    Where-Object { $_.FullName -notmatch '[\\/]\.(git|lib|tests|dist)[\\/]' } |
    Sort-Object FullName

$builder  = New-Object Markdig.MarkdownPipelineBuilder
$null     = [Markdig.MarkdownExtensions]::UseAdvancedExtensions($builder)
$pipeline = $builder.Build()

$template = @'
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<title>{0} - Local Wiki</title>
<style>
    * { box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; margin: 0; padding: 0; display: flex; height: 100vh; color: #24292e; background-color: #fff; }
    nav { width: 260px; background-color: #f6f8fa; border-right: 1px solid #e1e4e8; padding: 20px 10px; overflow-y: auto; flex-shrink: 0; }
    nav h2 { font-size: 14px; text-transform: uppercase; color: #586069; margin: 0 0 10px 10px; letter-spacing: 0.5px; }
    nav ul { list-style: none; padding: 0; margin: 0; }
    nav li a { display: block; padding: 6px 10px; color: #0366d6; text-decoration: none; border-radius: 6px; font-size: 14px; word-break: break-all; }
    nav li a:hover { background-color: #f0f3f6; text-decoration: none; }
    nav li a.active { background-color: #0366d6; color: #ffffff; font-weight: bold; }
    main { flex: 1; padding: 40px 60px; overflow-y: auto; }
    .markdown-body { max-width: 880px; margin: 0 auto; line-height: 1.6; }
    h1, h2, h3 { border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; margin-top: 24px; margin-bottom: 16px; }
    code { background: rgba(27,31,35,0.05); padding: 0.2em 0.4em; border-radius: 3px; font-family: monospace; }
    pre { background: #f6f8fa; padding: 16px; border-radius: 6px; overflow: auto; }
    pre code { background: transparent; padding: 0; }
    blockquote { border-left: 4px solid #dfe2e5; color: #6a737d; margin: 0; padding-left: 1em; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 16px; }
    table th, table td { border: 1px solid #dfe2e5; padding: 8px 13px; }
    table th { background: #f6f8fa; }
    img { max-width: 100%; }
</style>
</head>
<body>
    <nav>
        <h2>📄 ドキュメント一覧</h2>
        {1}
    </nav>
    <main>
        <div class="markdown-body">
            {2}
        </div>
    </main>
</body>
</html>
'@

foreach ($file in $allMdFiles) {
    $relPath  = $file.FullName.Substring($wikiDir.Length).TrimStart("\", "/")
    $htmlRel  = $relPath -replace '\.md$', '.html'
    $destFile = Join-Path $targetDistDir $htmlRel

    $destParent = [System.IO.Path]::GetDirectoryName($destFile)
    if (-not (Test-Path $destParent)) {
        New-Item -ItemType Directory -Path $destParent -Force | Out-Null
    }

    $mdText   = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    $bodyHtml = [Markdig.Markdown]::ToHtml($mdText, $pipeline)

    # 本文中の .md ハイパーリンクを .html に自動変換
    $bodyHtml = $bodyHtml -replace 'href="([^"]+)\.md"', 'href="$1.html"'
    $bodyHtml = $bodyHtml -replace "href='([^']+)\.md'", "href='$1.html'"

    $sidebarHtml = Get-ExportSidebarHtml -currentFile $file -allMdFiles $allMdFiles
    $pageTitle   = [System.Net.WebUtility]::HtmlEncode([System.IO.Path]::GetFileNameWithoutExtension($file.FullName))

    $fullHtml = $template.Replace("{0}", $pageTitle).Replace("{1}", $sidebarHtml).Replace("{2}", $bodyHtml)

    [System.IO.File]::WriteAllText($destFile, $fullHtml, [System.Text.Encoding]::UTF8)
    Write-Host "  [HTML 変換] $relPath -> $htmlRel" -ForegroundColor Green
}

# --- 4. 静的アセット (画像、CSS 等) のコピー ---
$assetFiles = Get-ChildItem -Path $wikiDir -Recurse | 
    Where-Object { 
        -not $_.PSIsContainer -and 
        $_.Extension -ne ".md" -and 
        $_.FullName -notmatch '[\\/]\.(git|lib|tests|dist)[\\/]' 
    }

foreach ($asset in $assetFiles) {
    $relPath  = $asset.FullName.Substring($wikiDir.Length).TrimStart("\", "/")
    $destFile = Join-Path $targetDistDir $relPath

    $destParent = [System.IO.Path]::GetDirectoryName($destFile)
    if (-not (Test-Path $destParent)) {
        New-Item -ItemType Directory -Path $destParent -Force | Out-Null
    }

    Copy-Item -Path $asset.FullName -Destination $destFile -Force
    Write-Host "  [アセット コピー] $relPath" -ForegroundColor DarkGray
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  エキスポート完了! 静的ファイル出力先:" -ForegroundColor Green
Write-Host "  $targetDistDir" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Green
