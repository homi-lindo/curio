[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Failure([string]$Message) {
    $script:failures.Add($Message) | Out-Null
}

function Add-Warning([string]$Message) {
    $script:warnings.Add($Message) | Out-Null
}

function Resolve-OptionalPath([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    return $null
}

function Read-Text([string]$Path, [string]$Label) {
    $resolved = Resolve-OptionalPath $Path
    if (-not $resolved) {
        Add-Failure "$Label not found: $Path"
        return ''
    }

    return Get-Content -LiteralPath $resolved -Raw
}

function Test-Pattern([string]$Text, [string]$Pattern) {
    return [regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
}

function Get-PropertyValue([string]$Text, [string]$Name) {
    $match = [regex]::Match($Text, "(?m)^\s*$([regex]::Escape($Name))\s*=\s*(.+?)\s*$")
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups[1].Value.Trim()
}

function Get-AndroidSdkRoot {
    $candidates = New-Object System.Collections.Generic.List[string]
    $localPropertiesPath = Join-Path $ProjectRoot 'android\local.properties'
    if (Test-Path -LiteralPath $localPropertiesPath) {
        $localProperties = Get-Content -LiteralPath $localPropertiesPath -Raw
        $sdkDir = Get-PropertyValue $localProperties 'sdk.dir'
        if (-not [string]::IsNullOrWhiteSpace($sdkDir)) {
            $candidates.Add(($sdkDir -replace '\\\\', '\')) | Out-Null
        }
    }

    foreach ($envName in @('ANDROID_HOME', 'ANDROID_SDK_ROOT')) {
        $value = [Environment]::GetEnvironmentVariable($envName)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $candidates.Add($value) | Out-Null
        }
    }

    foreach ($candidate in $candidates) {
        $expanded = [Environment]::ExpandEnvironmentVariables($candidate.Trim('"'))
        if (Test-Path -LiteralPath $expanded) {
            return (Resolve-Path -LiteralPath $expanded).Path
        }
    }

    return $null
}

function Test-AndroidCmdlineTools([string]$SdkRoot) {
    $cmdlineRoot = Join-Path $SdkRoot 'cmdline-tools'
    if (-not (Test-Path -LiteralPath $cmdlineRoot)) {
        return $false
    }

    $sdkManagerAtRoot = Join-Path $cmdlineRoot 'bin\sdkmanager.bat'
    if (Test-Path -LiteralPath $sdkManagerAtRoot) {
        return $true
    }

    $toolVersions = Get-ChildItem -LiteralPath $cmdlineRoot -Directory -ErrorAction SilentlyContinue
    foreach ($toolVersion in $toolVersions) {
        $sdkManager = Join-Path $toolVersion.FullName 'bin\sdkmanager.bat'
        if (Test-Path -LiteralPath $sdkManager) {
            return $true
        }
    }

    return $false
}

function Test-AndroidLicenseFiles([string]$SdkRoot) {
    $licenseFile = Join-Path $SdkRoot 'licenses\android-sdk-license'
    $previewLicenseFile = Join-Path $SdkRoot 'licenses\android-sdk-preview-license'
    return (Test-Path -LiteralPath $licenseFile) -and (Test-Path -LiteralPath $previewLicenseFile)
}

function Get-AndroidXmlAttribute($Node, [string]$Name) {
    return $Node.GetAttribute($Name, 'http://schemas.android.com/apk/res/android')
}

function Get-XmlAttribute([System.Xml.XmlElement]$Element, [string]$Name) {
    if ($Element.HasAttribute($Name)) {
        return $Element.GetAttribute($Name)
    }

    return ''
}

function Get-WackFailures([System.Xml.XmlElement]$Root, [bool]$Optional) {
    $failures = New-Object System.Collections.Generic.List[object]
    foreach ($test in $Root.SelectNodes('//TEST')) {
        $resultNode = $test.SelectSingleNode('RESULT')
        $result = if ($resultNode) { $resultNode.InnerText.Trim() } else { 'UNKNOWN' }
        if ($result -eq 'PASS') {
            continue
        }

        $isOptional = (Get-XmlAttribute $test 'OPTIONAL') -eq 'TRUE'
        if ($isOptional -ne $Optional) {
            continue
        }

        $messages = @(
            $test.SelectNodes('MESSAGES/MESSAGE') |
                ForEach-Object { $_.GetAttribute('TEXT') } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )

        $failures.Add([pscustomobject]@{
            Index = Get-XmlAttribute $test 'INDEX'
            Name = Get-XmlAttribute $test 'NAME'
            Result = $result
            Messages = $messages
        }) | Out-Null
    }

    return $failures.ToArray()
}

function Get-NewestInputTimestampUtc([string[]]$RelativePaths) {
    $newest = $null
    foreach ($relativePath in $RelativePaths) {
        $path = Join-Path $ProjectRoot $relativePath
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        $items = if (Test-Path -LiteralPath $path -PathType Leaf) {
            @(Get-Item -LiteralPath $path)
        } else {
            @(Get-ChildItem -LiteralPath $path -Recurse -File)
        }

        foreach ($item in $items) {
            if ($null -eq $newest -or $item.LastWriteTimeUtc -gt $newest) {
                $newest = $item.LastWriteTimeUtc
            }
        }
    }

    return $newest
}

Push-Location $ProjectRoot
try {
    $androidReleaseInputsUtc = Get-NewestInputTimestampUtc @(
        'pubspec.yaml',
        'pubspec.lock',
        'lib',
        'packages\lume_core\lib',
        'android\app',
        'android\key.properties'
    )
    $windowsReleaseInputsUtc = Get-NewestInputTimestampUtc @(
        'pubspec.yaml',
        'pubspec.lock',
        'lib',
        'packages\lume_core\lib',
        'windows'
    )
    $serverReleaseInputsUtc = Get-NewestInputTimestampUtc @(
        'packages\lume_core\lib',
        'server'
    )

    $pubspec = Read-Text (Join-Path $ProjectRoot 'pubspec.yaml') 'pubspec.yaml'
    $androidManifest = Read-Text (Join-Path $ProjectRoot 'android\app\src\main\AndroidManifest.xml') 'Android manifest'
    $networkSecurity = Read-Text (Join-Path $ProjectRoot 'android\app\src\main\res\xml\network_security_config.xml') 'Android release network security config'
    $buildGradle = Read-Text (Join-Path $ProjectRoot 'android\app\build.gradle.kts') 'Android build.gradle.kts'
    $gitignore = Read-Text (Join-Path $ProjectRoot '.gitignore') '.gitignore'
    $reviewEvidencePath = Resolve-OptionalPath (Join-Path $ProjectRoot 'docs\store-review-evidence.md')
    $reviewEvidence = if ($reviewEvidencePath) {
        Get-Content -LiteralPath $reviewEvidencePath -Raw
    } else {
        ''
    }

    $versionMatch = [regex]::Match($pubspec, '(?m)^\s*version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$')
    if ($pubspec -and -not $versionMatch.Success) {
        Add-Failure 'pubspec.yaml version is missing or not in x.y.z+build format.'
    }
    if ($pubspec -and -not (Test-Pattern $pubspec '^\s*msix_version:\s*[0-9]+\.[0-9]+\.[0-9]+\.0\s*$')) {
        Add-Failure 'pubspec.yaml msix_config.msix_version is missing or not in x.y.z.0 format.'
    }

    if ($androidManifest -and $androidManifest -notmatch 'android:allowBackup="false"') {
        Add-Failure 'Android manifest must keep android:allowBackup="false".'
    }
    if ($androidManifest -and $androidManifest -notmatch 'android:fullBackupContent="false"') {
        Add-Failure 'Android manifest must keep android:fullBackupContent="false".'
    }
    if ($androidManifest -and $androidManifest -notmatch 'android:dataExtractionRules="@xml/data_extraction_rules"') {
        Add-Failure 'Android manifest must keep dataExtractionRules configured.'
    }
    if ($androidManifest -and $androidManifest -notmatch 'tools:node="remove"') {
        Add-Failure 'Android manifest must remove AndroidX ProfileInstaller receiver.'
    }
    if ($androidManifest -and $androidManifest -notmatch 'android.permission.SCHEDULE_EXACT_ALARM') {
        Add-Warning 'SCHEDULE_EXACT_ALARM is absent. Verify reminder precision and Play policy before release.'
    }
    if ($androidManifest -and $androidManifest -match 'android.permission.USE_EXACT_ALARM') {
        Add-Failure 'Android manifest must not declare USE_EXACT_ALARM; use SCHEDULE_EXACT_ALARM plus user-grant fallback.'
    }
    if ($androidManifest -and $androidManifest -match 'android.permission.USE_FULL_SCREEN_INTENT') {
        Add-Failure 'Android manifest must not declare USE_FULL_SCREEN_INTENT; Curió reminders are normal notifications.'
    }
    if ($networkSecurity -and $networkSecurity -notmatch 'cleartextTrafficPermitted="false"') {
        Add-Failure 'Release network security config must deny cleartext traffic.'
    }
    if ($buildGradle -and $buildGradle -notmatch 'Android release builds require android/key.properties') {
        Add-Failure 'Android release build must fail closed when key.properties is absent.'
    }
    if (-not $reviewEvidencePath) {
        Add-Warning 'Store review evidence is missing: docs\store-review-evidence.md.'
    } else {
        foreach ($requiredEvidence in @(
            'SCHEDULE_EXACT_ALARM',
            'USE_EXACT_ALARM',
            'USE_FULL_SCREEN_INTENT',
            'flutter_windows.dll',
            'CreateProcessW',
            'https://developer.android.com/about/versions/14/changes/schedule-exact-alarms',
            'https://support.google.com/googleplay/android-developer/answer/9888170',
            'https://learn.microsoft.com/en-us/windows/uwp/debug-test-perf/windows-desktop-bridge-app-tests'
        )) {
            if ($reviewEvidence -notmatch [regex]::Escape($requiredEvidence)) {
                Add-Warning "Store review evidence is missing required review note: $requiredEvidence"
            }
        }
    }

    $releaseManifestPath = Resolve-OptionalPath (Join-Path $ProjectRoot 'build\app\intermediates\merged_manifest\release\processReleaseMainManifest\AndroidManifest.xml')
    if (-not $releaseManifestPath) {
        $releaseManifestPath = Resolve-OptionalPath (Join-Path $ProjectRoot 'build\app\intermediates\merged_manifests\release\processReleaseManifest\AndroidManifest.xml')
    }
    if (-not $releaseManifestPath) {
        Add-Warning 'Generated Android release manifest not found. Run tool\android\build-release-appbundle.ps1 before Play submission.'
    } else {
        try {
            [xml]$releaseManifestXml = Get-Content -LiteralPath $releaseManifestPath -Raw
            $manifestRoot = $releaseManifestXml.manifest
            $application = $manifestRoot.application
            if ($versionMatch.Success) {
                if ((Get-AndroidXmlAttribute $manifestRoot 'versionName') -ne $versionMatch.Groups[1].Value) {
                    Add-Failure 'Generated Android release manifest versionName does not match pubspec.yaml.'
                }
                if ((Get-AndroidXmlAttribute $manifestRoot 'versionCode') -ne $versionMatch.Groups[2].Value) {
                    Add-Failure 'Generated Android release manifest versionCode does not match pubspec.yaml.'
                }
            }
            if ((Get-AndroidXmlAttribute $application 'usesCleartextTraffic') -ne 'false') {
                Add-Failure 'Generated Android release manifest must set usesCleartextTraffic="false".'
            }
            if ((Get-AndroidXmlAttribute $application 'allowBackup') -ne 'false') {
                Add-Failure 'Generated Android release manifest must set allowBackup="false".'
            }
            if ((Get-AndroidXmlAttribute $application 'fullBackupContent') -ne 'false') {
                Add-Failure 'Generated Android release manifest must set fullBackupContent="false".'
            }
            if ((Get-AndroidXmlAttribute $application 'dataExtractionRules') -ne '@xml/data_extraction_rules') {
                Add-Failure 'Generated Android release manifest must keep dataExtractionRules="@xml/data_extraction_rules".'
            }

            $exportedComponents = New-Object System.Collections.Generic.List[string]
            foreach ($componentName in @('activity', 'activity-alias', 'service', 'receiver', 'provider')) {
                foreach ($component in $application.SelectNodes($componentName)) {
                    if ((Get-AndroidXmlAttribute $component 'exported') -eq 'true') {
                        $name = Get-AndroidXmlAttribute $component 'name'
                        $exportedComponents.Add("$componentName`:$name") | Out-Null
                    }
                }
            }
            $allowedExported = 'activity:app.lume.personal.MainActivity'
            foreach ($component in $exportedComponents) {
                if ($component -ne $allowedExported) {
                    Add-Failure "Generated Android release manifest has unexpected exported component: $component"
                }
            }
            if (-not $exportedComponents.Contains($allowedExported)) {
                Add-Failure 'Generated Android release manifest must export only app.lume.personal.MainActivity as the launcher activity.'
            }

            $releaseManifestText = Get-Content -LiteralPath $releaseManifestPath -Raw
            if ($releaseManifestText -notmatch 'android.permission.SCHEDULE_EXACT_ALARM') {
                Add-Warning 'Generated Android release manifest is missing SCHEDULE_EXACT_ALARM; verify reminder precision and Play policy before release.'
            }
            if ($releaseManifestText -match 'android.permission.USE_EXACT_ALARM') {
                Add-Failure 'Generated Android release manifest must not declare USE_EXACT_ALARM.'
            }
            if ($releaseManifestText -match 'android.permission.USE_FULL_SCREEN_INTENT') {
                Add-Failure 'Generated Android release manifest must not declare USE_FULL_SCREEN_INTENT.'
            }
            if ($releaseManifestText -match 'androidx\.profileinstaller\.ProfileInstallReceiver') {
                Add-Failure 'Generated Android release manifest must not include AndroidX ProfileInstaller receiver.'
            }
        } catch {
            Add-Warning "Generated Android release manifest could not be parsed: $($_.Exception.Message)"
        }
    }

    $androidSdkRoot = Get-AndroidSdkRoot
    if (-not $androidSdkRoot) {
        Add-Warning 'Android SDK root was not found. Configure android/local.properties sdk.dir, ANDROID_HOME, or ANDROID_SDK_ROOT before Play release builds.'
    } else {
        if (-not (Test-AndroidCmdlineTools $androidSdkRoot)) {
            Add-Warning "Android SDK cmdline-tools are missing under $androidSdkRoot. Install cmdline-tools;latest and accept Android licenses before building the Play release App Bundle."
        }
        if (-not (Test-AndroidLicenseFiles $androidSdkRoot)) {
            Add-Warning 'Android SDK license files are missing. Run flutter doctor --android-licenses before Play release builds.'
        }
    }

    $keyProperties = Resolve-OptionalPath (Join-Path $ProjectRoot 'android\key.properties')
    if (-not $keyProperties) {
        Add-Warning 'Android release key is not configured yet: android/key.properties is missing.'
    } else {
        $keyText = Get-Content -LiteralPath $keyProperties -Raw
        foreach ($name in @('storeFile', 'storePassword', 'keyAlias', 'keyPassword')) {
            if (-not (Test-Pattern $keyText "^\s*$name\s*=\s*\S+")) {
                Add-Failure "android/key.properties is missing $name."
            }
        }
        if ($keyText -match 'replace-with-private') {
            Add-Failure 'android/key.properties still contains placeholder values.'
        }
        $storeFile = Get-PropertyValue $keyText 'storeFile'
        if ($storeFile) {
            $storeFilePath = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $ProjectRoot 'android\app') $storeFile))
            if (-not (Test-Path -LiteralPath $storeFilePath)) {
                Add-Failure "Android release keystore file does not exist at the Gradle-resolved storeFile path: $storeFile"
            }
        }
    }

    foreach ($ignorePattern in @('android/key.properties', '*.jks', '*.keystore', 'android/*.jks', 'android/*.keystore', '.env', '.lume-sync/')) {
        if ($gitignore -and $gitignore -notmatch [regex]::Escape($ignorePattern)) {
            Add-Failure ".gitignore must include $ignorePattern."
        }
    }

    $msix = Resolve-OptionalPath (Join-Path $ProjectRoot 'build\windows\x64\runner\Release\lume.msix')
    if (-not $msix) {
        Add-Failure 'MSIX artifact not found. Run tool\windows\package-msix.ps1.'
    }
    $apk = Resolve-OptionalPath (Join-Path $ProjectRoot 'build\app\outputs\flutter-apk\app-debug.apk')
    if (-not $apk) {
        Add-Warning 'Debug APK artifact not found. Run flutter build apk --debug --no-pub.'
    }
    $aab = Resolve-OptionalPath (Join-Path $ProjectRoot 'build\app\outputs\bundle\release\app-release.aab')
    if (-not $aab) {
        Add-Warning 'Release Android App Bundle artifact not found. Run tool\android\build-release-appbundle.ps1 before Play submission.'
    } else {
        $bundleSuccessMarker = Resolve-OptionalPath (Join-Path $ProjectRoot 'build\logs\appbundle-release.success.json')
        if (-not $bundleSuccessMarker) {
            Add-Warning 'Release Android App Bundle success marker is missing. Run tool\android\build-release-appbundle.ps1 before Play submission.'
        } else {
            $markerInfo = Get-Item -LiteralPath $bundleSuccessMarker
            if ($androidReleaseInputsUtc -and $markerInfo.LastWriteTimeUtc -lt $androidReleaseInputsUtc) {
                Add-Warning 'Release Android App Bundle is older than Android/Dart release inputs. Rebuild with tool\android\build-release-appbundle.ps1.'
            }
            try {
                $marker = Get-Content -LiteralPath $bundleSuccessMarker -Raw | ConvertFrom-Json
                $aabInfo = Get-Item -LiteralPath $aab
                $aabHash = (Get-FileHash -LiteralPath $aab -Algorithm SHA256).Hash.ToLowerInvariant()
                if ([int64]$marker.sizeBytes -ne $aabInfo.Length) {
                    Add-Warning 'Release Android App Bundle size does not match the latest success marker. Rebuild with tool\android\build-release-appbundle.ps1.'
                }
                if ([string]$marker.sha256 -ne $aabHash) {
                    Add-Warning 'Release Android App Bundle hash does not match the latest success marker. Rebuild with tool\android\build-release-appbundle.ps1.'
                }
                if ($marker.jarsignerVerified -ne $true) {
                    Add-Warning 'Release Android App Bundle success marker does not record jarsigner verification.'
                }
            } catch {
                Add-Warning "Release Android App Bundle success marker is unreadable: $($_.Exception.Message)"
            }
        }

        $bundleFailureLog = Resolve-OptionalPath (Join-Path $ProjectRoot 'build\logs\appbundle-release-verbose.log')
        if ($bundleFailureLog) {
            $referenceInfo = if ($bundleSuccessMarker) {
                Get-Item -LiteralPath $bundleSuccessMarker
            } else {
                Get-Item -LiteralPath $aab
            }
            $logInfo = Get-Item -LiteralPath $bundleFailureLog
            $logText = Get-Content -LiteralPath $bundleFailureLog -Raw
            $failedAfterBundle = $logInfo.LastWriteTimeUtc -ge $referenceInfo.LastWriteTimeUtc
            $hasBundleFailure = $logText -match 'Release app bundle failed|Gradle task bundleRelease failed|Failed to find cmdline-tools'
            if ($failedAfterBundle -and $hasBundleFailure) {
                Add-Warning 'Latest Android App Bundle attempt ended with a Flutter tool failure after the latest verified bundle marker. Rebuild with tool\android\build-release-appbundle.ps1 before Play submission.'
            }
        }
    }
    $serverExe = Resolve-OptionalPath (Join-Path $ProjectRoot 'build\server\lume_sync_server.exe')
    if (-not $serverExe) {
        Add-Warning 'Compiled standalone sync server not found.'
    } else {
        $serverInfo = Get-Item -LiteralPath $serverExe
        if ($serverReleaseInputsUtc -and $serverInfo.LastWriteTimeUtc -lt $serverReleaseInputsUtc) {
            Add-Warning 'Compiled standalone sync server is older than server/core inputs. Rebuild the server executable before publishing server artifacts.'
        }
    }

    $wackCurrent = Resolve-OptionalPath (Join-Path $ProjectRoot 'build\windows\wack-report-1.0.22.xml')
    if (-not $wackCurrent) {
        Add-Warning 'Current WACK report is missing: build\windows\wack-report-1.0.22.xml. Run tool\windows\run-wack-admin.ps1.'
    } else {
        $wackInfo = Get-Item -LiteralPath $wackCurrent
        if ($msix) {
            $msixInfo = Get-Item -LiteralPath $msix
            if ($windowsReleaseInputsUtc -and $msixInfo.LastWriteTimeUtc -lt $windowsReleaseInputsUtc) {
                Add-Warning 'Windows MSIX is older than Windows/Dart release inputs. Rebuild with tool\windows\package-msix.ps1.'
            }
            if ($wackInfo.LastWriteTimeUtc -lt $msixInfo.LastWriteTimeUtc) {
                Add-Warning 'Current WACK report is older than the MSIX. Rerun tool\windows\run-wack-admin.ps1.'
            }
        }
        try {
            [xml]$wackReport = Get-Content -LiteralPath $wackCurrent -Raw
            $wackRoot = $wackReport.DocumentElement
            if (-not $wackRoot -or $wackRoot.Name -ne 'REPORT') {
                Add-Failure 'Current WACK report is not a WACK REPORT XML document.'
            } else {
                if ((Get-XmlAttribute $wackRoot 'OVERALL_RESULT') -ne 'PASS') {
                    Add-Failure 'Current WACK report overall result is not PASS.'
                }
                $requiredWackFailures = Get-WackFailures $wackRoot $false
                foreach ($failure in $requiredWackFailures) {
                    Add-Failure "Current WACK report has required failure: $($failure.Name) (#$($failure.Index))"
                }

                $optionalWackFailures = Get-WackFailures $wackRoot $true
                foreach ($failure in $optionalWackFailures) {
                    $messageText = ($failure.Messages -join ' ')
                    $knownFlutterRuntimeFinding = (
                        $failure.Index -eq '88' -and
                        $messageText -match 'flutter_windows\.dll' -and
                        $messageText -match 'CreateProcessW' -and
                        $messageText -match 'CMD'
                    )
                    if (-not $knownFlutterRuntimeFinding) {
                        Add-Warning "Current WACK report has an unreviewed optional failure: $($failure.Name) (#$($failure.Index))"
                    }
                }
            }
        } catch {
            Add-Warning "Current WACK report could not be parsed: $($_.Exception.Message)"
        }
    }

    Write-Host "Release readiness for $ProjectRoot"
    Write-Host "Failures: $($failures.Count)"
    foreach ($failure in $failures) {
        Write-Host "  [FAIL] $failure"
    }

    Write-Host "Warnings: $($warnings.Count)"
    foreach ($warning in $warnings) {
        Write-Host "  [WARN] $warning"
    }

    if ($failures.Count -gt 0) {
        exit 1
    }
    if ($Strict -and $warnings.Count -gt 0) {
        exit 1
    }
} finally {
    Pop-Location
}
