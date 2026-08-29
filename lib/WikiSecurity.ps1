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

function Get-MachineFingerprint {
    try {
        $uuid = $null
        if ($IsWindows -or $env:OS -eq "Windows_NT") {
            $csp = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
            if ($csp -and $csp.UUID -and $csp.UUID -ne "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF") {
                $uuid = $csp.UUID.Trim()
            }
        } elseif (Test-Path "/etc/machine-id") {
            $uuid = (Get-Content -Path "/etc/machine-id" -Raw -ErrorAction SilentlyContinue).Trim()
        } elseif (Test-Path "/var/lib/dbus/machine-id") {
            $uuid = (Get-Content -Path "/var/lib/dbus/machine-id" -Raw -ErrorAction SilentlyContinue).Trim()
        }

        if ([string]::IsNullOrWhiteSpace($uuid)) {
            $computerName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [System.Environment]::MachineName }
            $procId = if ($env:PROCESSOR_IDENTIFIER) { $env:PROCESSOR_IDENTIFIER } else { [System.Runtime.InteropServices.RuntimeInformation]::OSDescription }
            $userDomain = if ($env:USERDOMAIN) { $env:USERDOMAIN } else { [System.Environment]::UserName }
            $rawId = "${computerName}:${procId}:${userDomain}"
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($rawId))
            $uuid = [System.BitConverter]::ToString($hash).Replace("-", "")
        }

        # SHA256 で正規化し、扱いやすい 16文字 (4x4 ハイフン区切り) にフォーマット
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($uuid.ToUpperInvariant()))
        $hex = [System.BitConverter]::ToString($hashBytes).Replace("-", "").Substring(0, 16)
        return "$($hex.Substring(0,4))-$($hex.Substring(4,4))-$($hex.Substring(8,4))-$($hex.Substring(12,4))"
    } catch {
        return "DEFAULT-HOST-0000"
    }
}

function Protect-ActivationCode {
    param (
        [Parameter(Mandatory = $true)][string]$ApiKey,
        [Parameter(Mandatory = $true)][string]$MachineId,
        [string]$Email = ""
    )

    $cleanMachine = $MachineId.Trim().ToUpperInvariant()
    $cleanEmail = if ($Email) { $Email.Trim().ToLowerInvariant() } else { "" }
    $seed = "$($cleanMachine):$($cleanEmail)"

    $salt = [System.Text.Encoding]::UTF8.GetBytes("SimpleWiki-Activation-Salt-2026")
    $pass = [System.Text.Encoding]::UTF8.GetBytes("SimpleWiki-ActKey-$($seed)")
    $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($pass, $salt, 5000)
    $key = $derive.GetBytes(32)
    $iv  = $derive.GetBytes(16)

    # APIキーの先頭に検証プレフィックス "SWACT:" を付与
    $payload = "SWACT:" + $ApiKey
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($payload)

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key
    $aes.IV  = $iv
    $encryptor = $aes.CreateEncryptor()

    $encBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
    return "ENC:" + [System.Convert]::ToBase64String($encBytes)
}

function Unprotect-ActivationCode {
    param (
        [Parameter(Mandatory = $true)][string]$EncryptedText,
        [string]$MachineId = "",
        [string]$Email = ""
    )

    if ([string]::IsNullOrWhiteSpace($EncryptedText) -or -not $EncryptedText.StartsWith("ENC:")) { return "" }
    $cipherText = $EncryptedText.Substring(4)
    $cipherBytes = try { [System.Convert]::FromBase64String($cipherText) } catch { return "" }

    # 1. まずマシンID ＋ メールアドレスでの復号を試行
    $cleanMachine = if (-not [string]::IsNullOrWhiteSpace($MachineId)) { $MachineId.Trim().ToUpperInvariant() } else { Get-MachineFingerprint }
    $cleanEmail = if ($Email) { $Email.Trim().ToLowerInvariant() } else { "" }
    $seed = "$($cleanMachine):$($cleanEmail)"

    $salt = [System.Text.Encoding]::UTF8.GetBytes("SimpleWiki-Activation-Salt-2026")
    $pass = [System.Text.Encoding]::UTF8.GetBytes("SimpleWiki-ActKey-$($seed)")

    try {
        $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($pass, $salt, 5000)
        $key = $derive.GetBytes(32)
        $iv  = $derive.GetBytes(16)

        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $key
        $aes.IV  = $iv
        $decryptor = $aes.CreateDecryptor()
        $decBytes = $decryptor.TransformFinalBlock($cipherBytes, 0, $cipherBytes.Length)
        $decStr = [System.Text.Encoding]::UTF8.GetString($decBytes)
        if ($decStr.StartsWith("SWACT:")) {
            return $decStr.Substring(6)
        }
    } catch {
        # マシンバインド復号が不一致
    }

    # 2. メールアドレスなしの同一マシンID試行（Email が指定されていた場合のフォールバック）
    if (-not [string]::IsNullOrWhiteSpace($cleanEmail)) {
        try {
            $seedNoMail = "$($cleanMachine):"
            $passNoMail = [System.Text.Encoding]::UTF8.GetBytes("SimpleWiki-ActKey-$($seedNoMail)")
            $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($passNoMail, $salt, 5000)
            $key = $derive.GetBytes(32)
            $iv  = $derive.GetBytes(16)

            $aes = [System.Security.Cryptography.Aes]::Create()
            $aes.Key = $key
            $aes.IV  = $iv
            $decryptor = $aes.CreateDecryptor()
            $decBytes = $decryptor.TransformFinalBlock($cipherBytes, 0, $cipherBytes.Length)
            $decStr = [System.Text.Encoding]::UTF8.GetString($decBytes)
            if ($decStr.StartsWith("SWACT:")) {
                return $decStr.Substring(6)
            }
        } catch {
            # Suppressed intentionally
        }
    }

    # 3. 後方互換性: 旧固定鍵での復号試行
    return Unprotect-StringAes -EncryptedText $EncryptedText
}

# --- WinRT 日本語形態素解析 ＆ 単語抽出関数 ---

function Get-ResolvedSecret {
    param (
        [string]$SecretValue,
        [string]$Email = ""
    )
    if ([string]::IsNullOrWhiteSpace($SecretValue)) { return "" }
    if ($SecretValue.StartsWith("ENC:")) {
        return Unprotect-ActivationCode -EncryptedText $SecretValue -Email $Email
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
