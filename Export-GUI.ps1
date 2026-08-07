# ==============================================================================
#  SimpleWiki - 静的 HTML エキスポート Simple GUI
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir = [System.IO.Path]::GetFullPath($PSScriptRoot)

# 標準の初期パス設定
$defaultSampleDir = Join-Path $scriptDir "markdown_sample"
$initialInputDir  = if (Test-Path $defaultSampleDir) { $defaultSampleDir } else { $scriptDir }
$initialOutputDir = Join-Path $scriptDir "dist"

# --- Form 作成 ---
$form               = New-Object System.Windows.Forms.Form
$form.Text          = "SimpleWiki - 静的 HTML エキスポート"
$form.Size          = New-Object System.Drawing.Size(560, 290)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox   = $false

# フォント設定
$fontLabel = New-Object System.Drawing.Font("Meiryo UI", 9)
$fontBold  = New-Object System.Drawing.Font("Meiryo UI", 9, [System.Drawing.FontStyle]::Bold)

# 1. 入力フォルダ指定
$labelInput          = New-Object System.Windows.Forms.Label
$labelInput.Location = New-Object System.Drawing.Point(20, 20)
$labelInput.Size     = New-Object System.Drawing.Size(400, 20)
$labelInput.Text     = "入力 Markdown フォルダ:"
$labelInput.Font     = $fontLabel
$form.Controls.Add($labelInput)

$txtInput          = New-Object System.Windows.Forms.TextBox
$txtInput.Location = New-Object System.Drawing.Point(20, 42)
$txtInput.Size     = New-Object System.Drawing.Size(410, 23)
$txtInput.Text     = $initialInputDir
$txtInput.Font     = $fontLabel
$form.Controls.Add($txtInput)

$btnBrowseInput          = New-Object System.Windows.Forms.Button
$btnBrowseInput.Location = New-Object System.Drawing.Point(440, 41)
$btnBrowseInput.Size     = New-Object System.Drawing.Size(80, 25)
$btnBrowseInput.Text     = "参照..."
$btnBrowseInput.Font     = $fontLabel
$btnBrowseInput.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.SelectedPath = $txtInput.Text
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtInput.Text = $dlg.SelectedPath
    }
})
$form.Controls.Add($btnBrowseInput)

# 2. 出力フォルダ指定
$labelOutput          = New-Object System.Windows.Forms.Label
$labelOutput.Location = New-Object System.Drawing.Point(20, 80)
$labelOutput.Size     = New-Object System.Drawing.Size(400, 20)
$labelOutput.Text     = "出力先 HTML フォルダ:"
$labelOutput.Font     = $fontLabel
$form.Controls.Add($labelOutput)

$txtOutput          = New-Object System.Windows.Forms.TextBox
$txtOutput.Location = New-Object System.Drawing.Point(20, 102)
$txtOutput.Size     = New-Object System.Drawing.Size(410, 23)
$txtOutput.Text     = $initialOutputDir
$txtOutput.Font     = $fontLabel
$form.Controls.Add($txtOutput)

$btnBrowseOutput          = New-Object System.Windows.Forms.Button
$btnBrowseOutput.Location = New-Object System.Drawing.Point(440, 101)
$btnBrowseOutput.Size     = New-Object System.Drawing.Size(80, 25)
$btnBrowseOutput.Text     = "参照..."
$btnBrowseOutput.Font     = $fontLabel
$btnBrowseOutput.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.SelectedPath = $txtOutput.Text
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtOutput.Text = $dlg.SelectedPath
    }
})
$form.Controls.Add($btnBrowseOutput)

# ステータスメッセージ
$lblStatus          = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(20, 145)
$lblStatus.Size     = New-Object System.Drawing.Size(500, 20)
$lblStatus.Text     = "準備完了。フォルダを選択して [エキスポート実行] を押してください。"
$lblStatus.Font     = $fontLabel
$lblStatus.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblStatus)

# エキスポート実行ボタン
$btnExport          = New-Object System.Windows.Forms.Button
$btnExport.Location = New-Object System.Drawing.Point(170, 180)
$btnExport.Size     = New-Object System.Drawing.Size(180, 40)
$btnExport.Text     = "🚀 エキスポート実行"
$btnExport.Font     = $fontBold
$btnExport.BackColor = [System.Drawing.Color]::FromArgb(3, 102, 214)
$btnExport.ForeColor = [System.Drawing.Color]::White
$btnExport.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnExport.FlatAppearance.BorderSize = 0

$btnExport.Add_Click({
    $inputPath  = $txtInput.Text.Trim()
    $outputPath = $txtOutput.Text.Trim()

    if (-not (Test-Path $inputPath)) {
        [System.Windows.Forms.MessageBox]::Show("入力フォルダが見つかりません:`n$inputPath", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    $btnExport.Enabled = $false
    $lblStatus.Text    = "エキスポート中... しばらくお待ちください。"
    $lblStatus.ForeColor = [System.Drawing.Color]::Navy
    $form.Refresh()

    try {
        $exportScript = Join-Path $scriptDir "Export-MarkdigWiki.ps1"
        & $exportScript -RootFolder $inputPath -OutputDir $outputPath

        $lblStatus.Text      = "完了いたしました！"
        $lblStatus.ForeColor = [System.Drawing.Color]::Green

        $result = [System.Windows.Forms.MessageBox]::Show("静的 HTML へのエキスポートが完了しました！`n`n出力先:`n$outputPath`n`n出力先フォルダをエクスプローラーで開きますか？", "エキスポート完了", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            Start-Process $outputPath
        }
    } catch {
        $lblStatus.Text      = "エラーが発生しました。"
        $lblStatus.ForeColor = [System.Drawing.Color]::Red
        [System.Windows.Forms.MessageBox]::Show("エキスポート中にエラーが発生しました:`n$_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    } finally {
        $btnExport.Enabled = $true
    }
})
$form.Controls.Add($btnExport)

# アプリケーション起動
[void]$form.ShowDialog()
