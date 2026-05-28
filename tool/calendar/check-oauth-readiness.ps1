param(
  [string] $GoogleWindowsClientId = $env:CURIO_GOOGLE_WINDOWS_CLIENT_ID,
  [string] $GoogleAndroidClientId = $env:CURIO_GOOGLE_ANDROID_CLIENT_ID,
  [string] $MicrosoftClientId = $env:CURIO_MICROSOFT_CLIENT_ID,
  [string] $MicrosoftTenant = $env:CURIO_MICROSOFT_TENANT,
  [switch] $Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($MicrosoftTenant)) {
  $MicrosoftTenant = "common"
}

$warnings = New-Object System.Collections.Generic.List[string]

function Test-GoogleClientId {
  param([string] $Value, [string] $Name)
  if ([string]::IsNullOrWhiteSpace($Value)) {
    $warnings.Add("$Name ausente.")
    return
  }
  if (-not $Value.Trim().EndsWith(".apps.googleusercontent.com")) {
    $warnings.Add("$Name nao parece um Client ID OAuth do Google.")
  }
}

function Test-MicrosoftClientId {
  param([string] $Value)
  if ([string]::IsNullOrWhiteSpace($Value)) {
    $warnings.Add("CURIO_MICROSOFT_CLIENT_ID ausente.")
    return
  }
  if ($Value.Trim() -notmatch "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$") {
    $warnings.Add("CURIO_MICROSOFT_CLIENT_ID nao parece um GUID.")
  }
}

Test-GoogleClientId -Value $GoogleWindowsClientId -Name "CURIO_GOOGLE_WINDOWS_CLIENT_ID"
Test-GoogleClientId -Value $GoogleAndroidClientId -Name "CURIO_GOOGLE_ANDROID_CLIENT_ID"
Test-MicrosoftClientId -Value $MicrosoftClientId

Write-Host "Curio calendar import/export OAuth readiness"
Write-Host ""
Write-Host "Windows dart-defines:"
Write-Host "--dart-define=CURIO_GOOGLE_WINDOWS_CLIENT_ID=""$GoogleWindowsClientId"""
Write-Host "--dart-define=CURIO_MICROSOFT_CLIENT_ID=""$MicrosoftClientId"""
Write-Host "--dart-define=CURIO_MICROSOFT_TENANT=""$MicrosoftTenant"""
Write-Host ""
Write-Host "Android dart-defines:"
Write-Host "--dart-define=CURIO_GOOGLE_ANDROID_CLIENT_ID=""$GoogleAndroidClientId"""
Write-Host "--dart-define=CURIO_MICROSOFT_CLIENT_ID=""$MicrosoftClientId"""
Write-Host "--dart-define=CURIO_MICROSOFT_TENANT=""$MicrosoftTenant"""
Write-Host ""
Write-Host "Escopos esperados:"
Write-Host "- Google: https://www.googleapis.com/auth/calendar.events"
Write-Host "- Microsoft: User.Read, Calendars.ReadWrite"
Write-Host ""
Write-Host "Guias:"
Write-Host "- docs/calendar-app-registration.md"
Write-Host "- docs/calendar-oauth-readiness.md"

if ($warnings.Count -gt 0) {
  Write-Host ""
  Write-Warning "Pendencias:"
  foreach ($warning in $warnings) {
    Write-Warning "- $warning"
  }
  if ($Strict) {
    exit 1
  }
}
