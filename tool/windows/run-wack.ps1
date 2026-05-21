[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$PackagePath = '',
    [string]$ReportPath = '',
    [switch]$ReportOnly
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Resolve-RequiredPath([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Assert-ChildPath([string]$Parent, [string]$Child) {
    $parentPath = (Resolve-Path -LiteralPath $Parent).Path
    $childPath = if (Test-Path -LiteralPath $Child) {
        (Resolve-Path -LiteralPath $Child).Path
    } else {
        [System.IO.Path]::GetFullPath($Child)
    }

    if (-not $childPath.StartsWith($parentPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write WACK output outside $parentPath`: $childPath"
    }
}

function Find-AppCertTool {
    $candidates = @()
    if (${env:ProgramFiles(x86)}) {
        $candidates += Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\App Certification Kit\appcert.exe'
    }
    if ($env:ProgramFiles) {
        $candidates += Join-Path $env:ProgramFiles 'Windows Kits\10\App Certification Kit\appcert.exe'
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function Get-MsixVersion([string]$Root) {
    $pubspecPath = Resolve-RequiredPath (Join-Path $Root 'pubspec.yaml') 'pubspec.yaml'
    $pubspec = Get-Content -LiteralPath $pubspecPath -Raw
    $match = [regex]::Match($pubspec, '(?m)^\s*msix_version:\s*([0-9]+(?:\.[0-9]+){3})\s*$')
    if (-not $match.Success) {
        throw 'msix_config.msix_version was not found in pubspec.yaml'
    }

    return $match.Groups[1].Value
}

function Get-DefaultReportPath([string]$Root) {
    $msixVersion = Get-MsixVersion $Root
    $shortVersion = $msixVersion -replace '\.0$', ''
    return Join-Path $Root "build\windows\wack-report-$shortVersion.xml"
}

function Get-ElementAttribute([System.Xml.XmlElement]$Element, [string]$Name) {
    if ($Element.HasAttribute($Name)) {
        return $Element.GetAttribute($Name)
    }

    return ''
}

function Read-WackReport([string]$Path) {
    $resolvedReport = Resolve-RequiredPath $Path 'WACK report'
    [xml]$report = Get-Content -LiteralPath $resolvedReport -Raw
    $root = $report.DocumentElement
    if (-not $root -or $root.Name -ne 'REPORT') {
        throw "Not a WACK report: $resolvedReport"
    }

    $tests = @($root.SelectNodes('//TEST'))
    $failures = @()

    foreach ($test in $tests) {
        $resultNode = $test.SelectSingleNode('RESULT')
        $result = if ($resultNode) { $resultNode.InnerText.Trim() } else { 'UNKNOWN' }

        if ($result -ne 'PASS') {
            $messages = @(
                $test.SelectNodes('MESSAGES/MESSAGE') |
                    ForEach-Object { $_.GetAttribute('TEXT') } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )

            $failures += [pscustomobject]@{
                Index = Get-ElementAttribute $test 'INDEX'
                Name = Get-ElementAttribute $test 'NAME'
                Optional = (Get-ElementAttribute $test 'OPTIONAL') -eq 'TRUE'
                Result = $result
                Messages = $messages
            }
        }
    }

    $requiredFailures = @($failures | Where-Object { -not $_.Optional })
    $optionalFailures = @($failures | Where-Object { $_.Optional })

    return [pscustomobject]@{
        ReportPath = $resolvedReport
        OverallResult = Get-ElementAttribute $root 'OVERALL_RESULT'
        AppName = Get-ElementAttribute $root 'APP_NAME'
        AppVersion = Get-ElementAttribute $root 'APP_VERSION'
        GeneratedAt = Get-ElementAttribute $root 'ReportGenerationTime'
        TestCount = $tests.Count
        RequiredFailures = $requiredFailures
        OptionalFailures = $optionalFailures
    }
}

function Write-WackSummary($Summary) {
    Write-Host "WACK report: $($Summary.ReportPath)"
    Write-Host "App: $($Summary.AppName) $($Summary.AppVersion)"
    Write-Host "Generated: $($Summary.GeneratedAt)"
    Write-Host "Overall: $($Summary.OverallResult)"
    Write-Host "Tests: $($Summary.TestCount)"
    Write-Host "Required failures: $($Summary.RequiredFailures.Count)"
    Write-Host "Optional failures: $($Summary.OptionalFailures.Count)"

    $allFailures = @($Summary.RequiredFailures + $Summary.OptionalFailures)
    foreach ($failure in $allFailures) {
        $scope = if ($failure.Optional) { 'optional' } else { 'required' }
        Write-Host "[$scope] $($failure.Result): $($failure.Name) (#$($failure.Index))"
        foreach ($message in $failure.Messages) {
            Write-Host "  - $message"
        }
    }
}

function Get-CleanErrorMessage([System.Management.Automation.ErrorRecord]$ErrorRecord) {
    $message = $ErrorRecord.Exception.Message
    if ($message -match '(?i)elevation|eleva') {
        return 'WACK requires elevated PowerShell. Rerun tool\windows\run-wack.ps1 from an elevated terminal.'
    }

    return (($message -split "(`r`n|`n)")[0]).Trim()
}

try {
    Push-Location $ProjectRoot
    try {
        $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

        if ([string]::IsNullOrWhiteSpace($ReportPath)) {
            $ReportPath = Get-DefaultReportPath $ProjectRoot
        }
        $ReportPath = [System.IO.Path]::GetFullPath($ReportPath)

        if (-not $ReportOnly) {
            if ([string]::IsNullOrWhiteSpace($PackagePath)) {
                $PackagePath = Join-Path $ProjectRoot 'build\windows\x64\runner\Release\lume.msix'
            }
            $PackagePath = Resolve-RequiredPath $PackagePath 'MSIX package'
            $buildRoot = Resolve-RequiredPath (Join-Path $ProjectRoot 'build\windows') 'Windows build directory'
            Assert-ChildPath $buildRoot $ReportPath

            $appCert = Find-AppCertTool
            if (-not $appCert) {
                throw 'Windows App Certification Kit appcert.exe was not found. Install the Windows SDK App Certification Kit and rerun this script.'
            }

            $reportDirectory = Split-Path -Parent $ReportPath
            if (-not (Test-Path -LiteralPath $reportDirectory)) {
                New-Item -ItemType Directory -Path $reportDirectory | Out-Null
            }

            if (Test-Path -LiteralPath $ReportPath) {
                Remove-Item -LiteralPath $ReportPath -Force
            }

            Write-Host "Running WACK: $appCert"
            Write-Host "Package: $PackagePath"
            Write-Host "Report: $ReportPath"
            & $appCert test -appxpackagepath $PackagePath -reportoutputpath $ReportPath | Out-Host
            $appCertExitCode = $LASTEXITCODE

            if ($appCertExitCode -ne 0 -and -not (Test-Path -LiteralPath $ReportPath)) {
                throw "WACK failed with exit code $appCertExitCode before creating a report. If Windows requested elevation, accept it and rerun this script."
            }

            if ($appCertExitCode -ne 0) {
                Write-Warning "WACK exited with code $appCertExitCode. Parsing the generated report anyway."
            }
        }

        $summary = Read-WackReport $ReportPath
        Write-WackSummary $summary

        if ($summary.RequiredFailures.Count -gt 0 -or $summary.OverallResult -ne 'PASS') {
            exit 1
        }
    } finally {
        Pop-Location
    }
} catch {
    [Console]::Error.WriteLine("WACK check error: $(Get-CleanErrorMessage $_)")
    exit 1
}
