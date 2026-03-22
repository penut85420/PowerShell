# MSIX Signing Record

Date: 2026-03-22
Working directory: `C:\PowerShell`
Target package: `C:\PowerShell\PowerShellPreview-7.7.0-preview.1-win-x64.msix`

## Initial failure

Original install command:

```powershell
Add-AppxPackage -Path "C:\PowerShell\PowerShellPreview-7.7.0-preview.1-win-x64.msix"
```

Initial error:

- `0x80073CF0`
- `0x800B0100`
- Message indicated the app package needed a digital signature.

## Validation of package state

Checked the package signature:

```powershell
$p='C:\PowerShell\PowerShellPreview-7.7.0-preview.1-win-x64.msix'
Get-AuthenticodeSignature -FilePath $p | Select-Object Status,StatusMessage,SignerCertificate
```

Result:

- `Status: NotSigned`

## Read manifest publisher

Extracted `AppxManifest.xml` from the `.msix` and read the package identity:

```powershell
$msix='C:\PowerShell\PowerShellPreview-7.7.0-preview.1-win-x64.msix'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[System.IO.Compression.ZipFile]::OpenRead($msix)
$entry=$zip.Entries | Where-Object { $_.FullName -ieq 'AppxManifest.xml' }
$sr=New-Object System.IO.StreamReader($entry.Open())
[xml]$xml=$sr.ReadToEnd()
$sr.Close()
$zip.Dispose()
$xml.Package.Identity | Select-Object Name,Publisher,Version
```

Manifest identity:

- `Name: Microsoft.PowerShellPreview`
- `Publisher: CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US`
- `Version: 7.7.1.0`

The signing certificate subject had to match that `Publisher` value exactly.

## Locate signing tool

Located `signtool.exe` from the Windows SDK:

```powershell
Get-ChildItem 'C:\Program Files (x86)\Windows Kits' -Recurse -Filter signtool.exe
```

Tool used:

- `C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe`

## Create self-signed certificate

Created a test-signing certificate whose subject matched the manifest publisher:

```powershell
$publisher='CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
$cert=New-SelfSignedCertificate `
  -Type Custom `
  -Subject $publisher `
  -KeyUsage DigitalSignature `
  -FriendlyName 'PowerShellPreview MSIX Test Signing' `
  -CertStoreLocation 'Cert:\CurrentUser\My' `
  -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3')
```

## Export certificate files

Exported both `.pfx` and `.cer`:

```powershell
$pfx='C:\PowerShell\PowerShellPreview-TestSign.pfx'
$cer='C:\PowerShell\PowerShellPreview-TestSign.cer'
$pwd=ConvertTo-SecureString '<generated-password>' -AsPlainText -Force

Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $pwd
Export-Certificate -Cert $cert -FilePath $cer
```

Then exported an additional reusable PFX with a known password:

```powershell
$known='C0dex-TestSign-2026!'
$pwd=ConvertTo-SecureString $known -AsPlainText -Force
Export-PfxCertificate `
  -Cert $cert `
  -FilePath 'C:\PowerShell\PowerShellPreview-TestSign-knownpwd.pfx' `
  -Password $pwd `
  -Force
```

Generated files:

- `C:\PowerShell\PowerShellPreview-TestSign.cer`
- `C:\PowerShell\PowerShellPreview-TestSign.pfx`
- `C:\PowerShell\PowerShellPreview-TestSign-knownpwd.pfx`

Known-password PFX:

- Path: `C:\PowerShell\PowerShellPreview-TestSign-knownpwd.pfx`
- Password: `C0dex-TestSign-2026!`

## Import certificate trust

First imported into current user stores:

```powershell
Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\CurrentUser\TrustedPeople'
Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\CurrentUser\Root'
```

After signing, installation still failed with:

- `0x80073CF0`
- `0x800B0109`
- Message indicated the root certificate had to be trusted.

Resolved by importing the certificate into local machine stores:

```powershell
Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople'
Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\Root'
```

## Sign the package

Signed the `.msix` with SHA-256:

```powershell
$signtool='C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe'
& $signtool sign /fd SHA256 /f $pfx /p '<pfx-password>' $msix
```

Observed result:

- `Successfully signed: C:\PowerShell\PowerShellPreview-7.7.0-preview.1-win-x64.msix`

## Verify signature

Verified using both `signtool` and PowerShell:

```powershell
& $signtool verify /pa $msix
Get-AuthenticodeSignature -FilePath $msix | Select-Object Status,StatusMessage,SignerCertificate
```

Verification result:

- `Successfully verified`
- `Status: Valid`
- `StatusMessage: Signature verified.`

Signer certificate:

- `Subject: CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US`
- `Thumbprint: DD42FADBECF0FCACDD0D0041A7A5A5683C54A910`

## Install package

Installed after local machine trust was added:

```powershell
Add-AppxPackage -Path 'C:\PowerShell\PowerShellPreview-7.7.0-preview.1-win-x64.msix'
```

Confirmed installation:

```powershell
Get-AppxPackage -Name Microsoft.PowerShellPreview |
  Select-Object Name,PackageFullName,Publisher,Version,InstallLocation
```

Installed package:

- `Name: Microsoft.PowerShellPreview`
- `PackageFullName: Microsoft.PowerShellPreview_7.7.1.0_x64__8wekyb3d8bbwe`
- `Publisher: CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US`
- `Version: 7.7.1.0`
- `InstallLocation: C:\Program Files\WindowsApps\Microsoft.PowerShellPreview_7.7.1.0_x64__8wekyb3d8bbwe`

## Notes

- This used a self-signed certificate for local testing.
- The certificate subject matched the manifest publisher exactly, which is required for MSIX installation.
- Trusting the certificate in `LocalMachine\Root` and `LocalMachine\TrustedPeople` was required on this machine before `Add-AppxPackage` succeeded.
- For distribution to other machines, use a proper code-signing certificate or have each target machine trust the test certificate.
