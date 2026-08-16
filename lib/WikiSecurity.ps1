# ==============================================================================
#  SimpleWiki セキュリティ & 暗号化 & 設定情報モジュール
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================

function Protect-StringAes {
    param ([string]$PlainText)
    $salt = [System.Text.Encoding]::UTF8.GetBytes("SimpleWiki-OKF-RAG-2026-Salt")
    $pass = [System.Text.Encoding]::UTF8.GetBytes("SimpleWiki-Portable-Secret-Key-2026")
    $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($pass, $salt, 1000)
    $key = $derive.GetBytes(32)
    $iv  = $derive.GetBytes(16)

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key
    $aes.IV  = $iv
    $encryptor = $aes.CreateEncryptor()

    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $encBytes   = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
    return "ENC:" + [System.Convert]::ToBase64String($encBytes)
}

function Protect-StringDpapi {
    param ([string]$PlainText)
    Add-Type -AssemblyName System.Security
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $enc   = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return "DPAPI:" + [System.Convert]::ToBase64String($enc)
}

function Unprotect-StringAes {
    param ([string]$EncryptedText)
    if ([string]::IsNullOrWhiteSpace($EncryptedText) -or -not $EncryptedText.StartsWith("ENC:")) { return "" }
    try {
        $cipherText = $EncryptedText.Substring(4)
        $cipherBytes = [System.Convert]::FromBase64String($cipherText)
        $salt = [System.Text.Encoding]::UTF8.GetBytes("SimpleWiki-OKF-RAG-2026-Salt")
        $pass = [System.Text.Encoding]::UTF8.GetBytes("SimpleWiki-Portable-Secret-Key-2026")
        $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($pass, $salt, 1000)
        $key = $derive.GetBytes(32)
        $iv  = $derive.GetBytes(16)

        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $key
        $aes.IV  = $iv
        $decryptor = $aes.CreateDecryptor()
        $decBytes = $decryptor.TransformFinalBlock($cipherBytes, 0, $cipherBytes.Length)
        return [System.Text.Encoding]::UTF8.GetString($decBytes)
    } catch {
        Write-Warning "AES 復号に失敗しました: $_"
        return ""
    }
}

function Unprotect-StringDpapi {
    param ([string]$EncryptedText)
    if ([string]::IsNullOrWhiteSpace($EncryptedText) -or -not $EncryptedText.StartsWith("DPAPI:")) { return "" }
    try {
        Add-Type -AssemblyName System.Security
        $cipherText = $EncryptedText.Substring(6)
        $bytes = [System.Convert]::FromBase64String($cipherText)
        $dec = [System.Security.Cryptography.ProtectedData]::Unprotect($bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [System.Text.Encoding]::UTF8.GetString($dec)
    } catch {
        Write-Warning "DPAPI 復号に失敗しました: $_"
        return ""
    }
}

# --- WinRT 日本語形態素解析 ＆ 単語抽出関数 ---

function Get-ResolvedSecret {
    param ([string]$SecretValue)
    if ([string]::IsNullOrWhiteSpace($SecretValue)) { return "" }
    if ($SecretValue.StartsWith("ENC:")) {
        return Unprotect-StringAes -EncryptedText $SecretValue
    } elseif ($SecretValue.StartsWith("DPAPI:")) {
        return Unprotect-StringDpapi -EncryptedText $SecretValue
    } elseif ($SecretValue.StartsWith("ENV:")) {
        $envName = $SecretValue.Substring(4).Trim()
        $envVal = [Environment]::GetEnvironmentVariable($envName)
        if ($envVal) { return $envVal } else { return "" }
    }
    return $SecretValue
}

function Get-ConfigJson {
    param ([string]$TargetScriptDir = $scriptDir)
    $configPath = Join-Path $TargetScriptDir "config.json"
    if (-not (Test-Path $configPath)) {
        return [PSCustomObject]@{
            rag = [PSCustomObject]@{
                enabled         = $false
                maxContextDocs  = 3
                maxHistoryTurns = 3
                maxHistoryChars = 4000
                timeoutSec      = 30
            }
        }
    }
    try {
        $raw = Get-Content -Path $configPath -Raw -Encoding UTF8
        return ($raw | ConvertFrom-Json)
    } catch {
        return [PSCustomObject]@{
            rag = [PSCustomObject]@{
                enabled         = $false
                maxContextDocs  = 3
                maxHistoryTurns = 3
                maxHistoryChars = 4000
                timeoutSec      = 30
            }
        }
    }
}
