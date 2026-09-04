$psFiles = Get-ChildItem -Path $PSScriptRoot -Recurse -Include "*.ps1", "*.psm1", "*.psd1" |
    Where-Object { $_.FullName -notmatch '[\\/]\.(git|cache)[\\/]' }

$utf8Bom = New-Object System.Text.UTF8Encoding($true)

foreach ($file in $psFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if (-not $hasBom) {
        $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($file.FullName, $text, $utf8Bom)
        Write-Host "Added UTF-8 BOM: $($file.Name)" -ForegroundColor Green
    }
}
