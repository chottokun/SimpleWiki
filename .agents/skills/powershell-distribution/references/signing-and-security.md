# Code Signing and Security Reference

This reference covers code signing PowerShell scripts and modules using Authenticode certificates to comply with enterprise security policies.

---

## 1. ExecutionPolicy Levels

| Policy | Raw .ps1 execution | Downloaded .ps1 | Batch Wrapper (-ExecutionPolicy Bypass) |
| :--- | :--- | :--- | :--- |
| `Restricted` | Blocked | Blocked | Allowed |
| `AllSigned` | Requires valid signature | Requires valid signature | Allowed (unless AppLocker/WDAC blocks) |
| `RemoteSigned` | Allowed | Requires signature or unblocking | Allowed |
| `Unrestricted` | Allowed | Warns before run | Allowed |

> [!NOTE]
> `ExecutionPolicy` is an administrative safety rail, not a hard security boundary. For hard enforcement, enterprise environments use **Windows Defender Application Control (WDAC)** or **AppLocker**.

---

## 2. Signing Scripts with Authenticode

### 2.1 Sign with Local / Machine Certificate
```powershell
# Get available Code Signing certificate
$Cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1

if ($null -eq $Cert) {
    throw "No Code Signing Certificate found in Cert:\CurrentUser\My"
}

# Sign script with timestamp (ensures validity even after cert expiration)
Set-AuthenticodeSignature -FilePath ".\dist\MyScript.ps1" `
    -Certificate $Cert `
    -TimestampServer "http://timestamp.digicert.com" `
    -HashAlgorithm SHA256
```

### 2.2 Verifying Signature
```powershell
Get-AuthenticodeSignature -FilePath ".\dist\MyScript.ps1"
```

Expected status: `Valid`
