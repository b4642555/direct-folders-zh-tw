param([Parameter(Mandatory=$true)][string]$OriginalPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$installer = Join-Path $root 'Install.ps1'
function Assert-True($value, [string]$message) { if (-not $value) { throw $message } }
Assert-True (Test-Path -LiteralPath $installer) 'Missing installer'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('df-zh-tw-install-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'config.exe'
Copy-Item -LiteralPath $OriginalPath -Destination $target
$originalHash = (Get-FileHash -LiteralPath $target).Hash
# Sentinels demonstrate the installer does not change nearby settings or executables.
[IO.File]::WriteAllText((Join-Path $scratch 'Options.ini'), 'UseMiddleButton=2')
[IO.File]::WriteAllText((Join-Path $scratch 'menu.json'), '{"favorites":["keep"]}')
[IO.File]::WriteAllText((Join-Path $scratch 'df.exe'), 'do not modify')
& $installer -ProgramDirectory $scratch -NoElevation -NoLaunch
$localizedHash = (Get-FileHash -LiteralPath $target).Hash
Assert-True ($localizedHash -ne $originalHash) 'Install did not change config.exe'
& $installer -ProgramDirectory $scratch -NoElevation -NoLaunch
Assert-True ((Get-FileHash -LiteralPath $target).Hash -eq $localizedHash) 'Repeat install changed output'
& $installer -Action Restore -ProgramDirectory $scratch -NoElevation -NoLaunch
Assert-True ((Get-FileHash -LiteralPath $target).Hash -eq $originalHash) 'Restore was not byte-exact'
& $installer -Action Restore -ProgramDirectory $scratch -NoElevation -NoLaunch
Assert-True ((Get-FileHash -LiteralPath $target).Hash -eq $originalHash) 'Repeat restore changed output'
Assert-True ([IO.File]::ReadAllText((Join-Path $scratch 'Options.ini')) -ceq 'UseMiddleButton=2') 'Options.ini was changed'
Assert-True ([IO.File]::ReadAllText((Join-Path $scratch 'menu.json')) -ceq '{"favorites":["keep"]}') 'Favorites were changed'
Assert-True ([IO.File]::ReadAllText((Join-Path $scratch 'df.exe')) -ceq 'do not modify') 'Main application was changed'
& $installer -ProgramDirectory $scratch -NoElevation -NoLaunch
[IO.File]::WriteAllText($target, 'simulate an app update')
$rejected = $false
try { & $installer -Action Restore -ProgramDirectory $scratch -NoElevation -NoLaunch } catch { $rejected = $true }
Assert-True $rejected 'Restore must reject changed application versions'
Assert-True ([IO.File]::ReadAllText($target) -ceq 'simulate an app update') 'Restore overwrote an unknown version'
Write-Output 'PASS: install, repeat install, byte-exact restore, repeat restore, preserved settings/favorites/main executable, changed-version rejection.'
