[CmdletBinding()]
param(
    [string]$ProjectRoot = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$runner = Join-Path $ProjectRoot 'tool\windows\run-wack.ps1'
if (-not (Test-Path -LiteralPath $runner)) {
    throw "WACK runner not found: $runner"
}

$command = @"
Set-Location -LiteralPath '$($ProjectRoot.Replace("'", "''"))'
& '$($runner.Replace("'", "''"))' -ProjectRoot '$($ProjectRoot.Replace("'", "''"))'
`$exitCode = `$LASTEXITCODE
Write-Host ''
if (`$exitCode -eq 0) {
    Write-Host 'WACK finished successfully.'
} else {
    Write-Host "WACK finished with exit code `$exitCode."
}
Read-Host 'Press Enter to close'
exit `$exitCode
"@

Start-Process -FilePath 'powershell.exe' `
    -Verb RunAs `
    -WorkingDirectory $ProjectRoot `
    -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        $command
    ) `
    -Wait
