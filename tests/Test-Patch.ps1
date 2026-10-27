param([Parameter(Mandatory=$true)][string]$OriginalPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
function Assert-True($value, [string]$message) { if (-not $value) { throw $message } }
Assert-True (Test-Path (Join-Path $root 'tools\Localization.ps1')) 'Missing localization engine'
. (Join-Path $root 'tools\Localization.ps1')
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('df-zh-tw-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$before = (Get-FileHash -LiteralPath $OriginalPath -Algorithm SHA256).Hash
$output = Join-Path $scratch 'config.exe'
$report = New-LocalizedConfig -Source $OriginalPath -Destination $output -PackageRoot $root
Assert-True ($report.FormStrings -eq 275) 'Expected 275 form translations'
Assert-True ($report.RuntimeStrings -eq 19) 'Expected 19 runtime translations'
Assert-True ($report.ButtonStrings -eq 26) 'Expected 26 standard-button translations'
Assert-True ((Get-FileHash -LiteralPath $OriginalPath).Hash -eq $before) 'Source was modified'
if ($before -eq '3CF6B5EEEF1774354C1B22A8FBDFA3A93A429F64064CFC0D7AB11C609E8A1AB3') {
    Assert-True ((Get-FileHash -LiteralPath $output).Hash -eq 'ED354BB411BB4D63D202A7E74C5FDED264818B878136211C4AF96871706C58CA') 'Output differs from GUI-verified reference'
}
$invalid = Join-Path $scratch 'unsupported.exe'
[IO.File]::WriteAllBytes($invalid, [byte[]](1,2,3,4))
$rejected = $false
try { New-LocalizedConfig -Source $invalid -Destination (Join-Path $scratch 'must-not-exist.exe') -PackageRoot $root | Out-Null } catch { $rejected = $true }
Assert-True $rejected 'Unsupported input must be rejected'
Assert-True (-not (Test-Path (Join-Path $scratch 'must-not-exist.exe'))) 'Rejected input created output'
Write-Output ('PASS: exact-version build, 320 translations, resource readback, source preservation, unsupported-input rejection. Output: ' + $output)
