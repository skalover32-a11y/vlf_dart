<#
.SYNOPSIS
  Signs a VLF VPN Windows executable with a code-signing certificate.

.DESCRIPTION
  Wraps signtool.exe invocation so release builds can be signed before
  distribution. Provide the path to the compiled .exe, the .pfx certificate,
  and (optionally) the certificate password and timestamping URL.

.PARAMETER ExecutablePath
  Path to the VLF_VPN.exe that should be signed (release output).

.PARAMETER CertificatePath
  Path to the code-signing certificate in PFX format (never store it in the repo).

.PARAMETER CertificatePassword
  Optional password that protects the PFX.

.PARAMETER TimestampUrl
  RFC 3161 timestamp server URL. Defaults to DigiCert.

.PARAMETER SigntoolPath
  Optional explicit path to signtool.exe. When omitted the script attempts to
  locate signtool in the current PATH (install "Windows SDK -> App Certification Kit").
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ExecutablePath,

  [Parameter(Mandatory = $true)]
  [string]$CertificatePath,

  [Parameter(Mandatory = $false)]
  [string]$CertificatePassword,

  [Parameter(Mandatory = $false)]
  [string]$TimestampUrl = 'http://timestamp.digicert.com',

  [Parameter(Mandatory = $false)]
  [string]$SigntoolPath
)

function Resolve-FullPath {
  param([string]$Path)
  $resolved = Resolve-Path -Path $Path -ErrorAction Stop
  return $resolved.ProviderPath
}

try {
  $exePath = Resolve-FullPath -Path $ExecutablePath
} catch {
  throw "Executable not found: $ExecutablePath"
}

try {
  $certPath = Resolve-FullPath -Path $CertificatePath
} catch {
  throw "Certificate not found: $CertificatePath"
}

if (-not $SigntoolPath) {
  $signtoolCmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
  if (-not $signtoolCmd) {
    throw 'signtool.exe not found. Install the Windows SDK (App Certification Kit) or provide -SigntoolPath.'
  }
  $SigntoolPath = $signtoolCmd.Source
}

if (-not (Test-Path -Path $SigntoolPath)) {
  throw "signtool.exe not found at $SigntoolPath"
}

$arguments = @('sign', '/fd', 'SHA256', '/f', $certPath)

if ($CertificatePassword) {
  $arguments += @('/p', $CertificatePassword)
}

if ($TimestampUrl) {
  $arguments += @('/tr', $TimestampUrl, '/td', 'SHA256')
}

$arguments += $exePath

Write-Host "Signing $exePath using $SigntoolPath" -ForegroundColor Cyan
$process = Start-Process -FilePath $SigntoolPath -ArgumentList $arguments -Wait -PassThru
if ($process.ExitCode -ne 0) {
  throw "signtool.exe exited with code $($process.ExitCode)"
}

Write-Host 'Signing completed successfully.' -ForegroundColor Green
