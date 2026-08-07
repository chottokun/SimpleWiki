# ==============================================================================
#  Markdig + PowerShell 100% オフライン対応 Wiki サーバー
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================
param (
    [int]$Port = 8080,
    [string]$RootFolder = ""
)

# スクリプト自身のディレクトリ ($PSScriptRoot) から lib フォルダを参照
$scriptDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
$libDir    = Join-Path $scriptDir "lib"

# ドキュメントルートの設定 (指定がない場合は markdown_sample フォルダ、存在しない場合は $PSScriptRoot)
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

$fullWikiDir = $wikiDir.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

# --- 1. Markdig.dll および依存ライブラリのロード ---
$markdigDll = Join-Path $libDir "Markdig.dll"
if (-not (Test-Path $markdigDll)) {
    Write-Error "'lib' フォルダに Markdig.dll が見つかりません:`n$markdigDll"
    exit 1
}

Get-ChildItem -Path $libDir -Filter "*.dll" | ForEach-Object {
    Add-Type -Path $_.FullName
}

# --- 2. サイドバー (HTML) の自動生成関数 ---
function Get-SidebarHtml {
    param ($currentRelPath)
    
    $mdFiles = Get-ChildItem -Path $wikiDir -Recurse -Filter "*.md" | 
        Where-Object { $_.FullName -notmatch '[\\/]\.(git|lib|tests|dist)[\\/]' } |
        Sort-Object FullName

    $html = "<ul>`n"
    foreach ($file in $mdFiles) {
        $relPath   = $file.FullName.Substring($wikiDir.Length).TrimStart("\", "/")
        $cleanPath = $relPath -replace "\\", "/"
        $webPath   = "/" + [Uri]::EscapeUriString($cleanPath)
        $title     = [System.Net.WebUtility]::HtmlEncode($file.BaseName)

        $activeClass = if ($relPath -eq $currentRelPath) { ' class="active"' } else { '' }
        $html += "  <li><a href='$webPath'$activeClass>$title</a></li>`n"
    }
    $html += "</ul>"
    return $html
}

# --- 3. HttpListener の起動 ---
$listener = New-Object System.Net.HttpListener
$prefix   = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
} catch {
    Write-Error "ポート $Port でのサーバー起動に失敗しました。既に起動していないか確認してください。"
    exit 1
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  Markdig 完全オフライン Wiki サーバー起動中" -ForegroundColor Green
Write-Host "  ドキュメントルート: $wikiDir" -ForegroundColor Yellow
Write-Host "  URL: $prefix" -ForegroundColor Cyan
Write-Host "  ※ 終了するにはこのウィンドウで [Ctrl + C] を押してください" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Green

# 既定のブラウザで開く
Start-Process $prefix

$mimeTypes = @{
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".gif"  = "image/gif"
    ".svg"  = "image/svg+xml"
    ".css"  = "text/css; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
}

try {
    while ($listener.IsListening) {
        $context  = $listener.GetContext()
        $request  = $context.Request
        $response = $context.Response

        try {
            $rawPath = [System.Net.WebUtility]::UrlDecode($request.Url.LocalPath)
            
            if ($rawPath -eq "/" -or [string]::IsNullOrEmpty($rawPath)) {
                if (Test-Path (Join-Path $wikiDir "index.md")) {
                    $rawPath = "/index.md"
                } elseif (Test-Path (Join-Path $wikiDir "README.md")) {
                    $rawPath = "/README.md"
                }
            }

            $relPath  = $rawPath.TrimStart("/").Replace("/", "\")
            $filePath = Join-Path $wikiDir $relPath

            # /lib/ 配下のリソース要求はスクリプト直下の lib フォルダへフォールバック
            if (-not (Test-Path $filePath) -and $rawPath.StartsWith("/lib/")) {
                $filePath = Join-Path $scriptDir $relPath
            }

            # 安全性検証: ディレクトリトラバーサル防止 ($fullWikiDir または $scriptDir\lib)
            $fullPath = [System.IO.Path]::GetFullPath($filePath)
            $fullScriptLibDir = (Join-Path $scriptDir "lib\").TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
            $isAllowed = $fullPath.StartsWith($fullWikiDir, [System.StringComparison]::OrdinalIgnoreCase) -or $fullPath.StartsWith($fullScriptLibDir, [System.StringComparison]::OrdinalIgnoreCase)
            if (-not $isAllowed) {
                $response.StatusCode = 403
                $forbiddenBytes = [System.Text.Encoding]::UTF8.GetBytes("<h1>403 Forbidden</h1>")
                $response.ContentLength64 = $forbiddenBytes.Length
                $response.OutputStream.Write($forbiddenBytes, 0, $forbiddenBytes.Length)
                continue
            }

            # Markdown ファイルのレンダリング処理
            if ((Test-Path $fullPath -PathType Leaf) -and ($fullPath.EndsWith(".md"))) {
                $mdText = Get-Content -Path $fullPath -Raw -Encoding UTF8

                # Markdig で Markdown -> HTML 変換
                $builder  = New-Object Markdig.MarkdownPipelineBuilder
                $null     = [Markdig.MarkdownExtensions]::UseAdvancedExtensions($builder)
                $pipeline = $builder.Build()
                $bodyHtml = [Markdig.Markdown]::ToHtml($mdText, $pipeline)

                $sidebarHtml = Get-SidebarHtml -currentRelPath $relPath
                $pageTitle   = [System.Net.WebUtility]::HtmlEncode([System.IO.Path]::GetFileNameWithoutExtension($fullPath))

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
    <script src="/lib/mermaid.min.js"></script>
    <script>
        document.addEventListener("DOMContentLoaded", function() {
            document.querySelectorAll("pre code.language-mermaid").forEach(function(el) {
                var pre = el.parentElement;
                var div = document.createElement("div");
                div.className = "mermaid";
                div.textContent = el.textContent;
                pre.replaceWith(div);
            });
            if (typeof mermaid !== "undefined") {
                mermaid.initialize({ startOnLoad: true, theme: "default" });
            }
        });
    </script>
</body>
</html>
'@
                $fullHtml = $template.Replace("{0}", $pageTitle).Replace("{1}", $sidebarHtml).Replace("{2}", $bodyHtml)
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($fullHtml)
                $response.ContentType = "text/html; charset=utf-8"
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            # 画像やその他静的ファイルの返却処理
            } elseif (Test-Path $fullPath -PathType Leaf) {
                $ext = [System.IO.Path]::GetExtension($fullPath).ToLower()
                $response.ContentType = if ($mimeTypes.ContainsKey($ext)) { $mimeTypes[$ext] } else { "application/octet-stream" }
                $bytes = [System.IO.File]::ReadAllBytes($fullPath)
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            # 404 Not Found (XSS 対策済み)
            } else {
                $response.StatusCode = 404
                $safePath = [System.Net.WebUtility]::HtmlEncode($rawPath)
                $notFoundBytes = [System.Text.Encoding]::UTF8.GetBytes("<h1>404 Not Found</h1><p>$safePath</p>")
                $response.ContentLength64 = $notFoundBytes.Length
                $response.OutputStream.Write($notFoundBytes, 0, $notFoundBytes.Length)
            }
        } finally {
            $response.Close()
        }
    }
} finally {
    if ($listener.IsListening) {
        $listener.Stop()
        $listener.Close()
    }
}
