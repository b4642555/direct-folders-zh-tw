[CmdletBinding()]
param(
    [ValidateSet('Install','Restore')][string]$Action = 'Install',
    [string]$ProgramDirectory,
    [switch]$NoLaunch,
    [switch]$NoElevation
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-ConfigHash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Write-State($State, [string]$Path) {
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $State | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporary -Encoding UTF8
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary, $Path, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}

if (-not $ProgramDirectory) {
    $candidates = @()
    foreach ($parent in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($parent) { $candidates += Join-Path $parent 'Direct Folders' }
    }
    $found = @($candidates | Select-Object -Unique | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'config.exe') })
    if ($found.Count -ne 1) { throw '找不到唯一的安裝位置。請使用 -ProgramDirectory 指定 Direct Folders 的資料夾。' }
    $ProgramDirectory = $found[0]
}
$ProgramDirectory = (Resolve-Path -LiteralPath $ProgramDirectory).Path
$target = Join-Path $ProgramDirectory 'config.exe'
if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw '指定位置找不到 config.exe。' }
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'translations\manifest-4.3.5.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$backupDirectory = Join-Path $ProgramDirectory '.direct-folders-zh-tw-backup'
$statePath = Join-Path $backupDirectory 'state.json'
$state = $null
if (Test-Path -LiteralPath $statePath) { $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json }
$currentHash = Get-ConfigHash $target

if ($Action -eq 'Install') {
    if ($state -and $state.active -and $currentHash -eq $state.localizedHash) {
        Write-Host '已套用繁體中文，無需重複安裝。'
        return
    }
    if ($manifest.supportedSourceHashes -notcontains $currentHash) {
        throw '這份 config.exe 不在已驗證的 4.3.5 原版清單內。尚未變更任何檔案。請先還原原版，或等待相容更新。'
    }
} else {
    if (-not $state) { throw '找不到本工具建立的還原紀錄，未變更任何檔案。' }
    if (-not $state.active -and $currentHash -eq $state.originalHash) {
        Write-Host '目前已是英文原版，無需重複還原。'
        return
    }
    if ($currentHash -ne $state.localizedHash) { throw '程式已更新或被修改，為避免覆寫其他版本，還原已停止。' }
    if ($state.backupFile -notmatch '^[0-9a-f-]+-config\.exe$') { throw '還原紀錄中的備份檔名無效。' }
    $originalBackup = Join-Path $backupDirectory $state.backupFile
    if ($manifest.supportedSourceHashes -notcontains $state.originalHash -or
        (Get-ConfigHash $originalBackup) -ne $state.originalHash) { throw '原檔備份驗證失敗，還原已停止。' }
}

$running = @(Get-CimInstance Win32_Process -Filter "Name='config.exe'" | Where-Object { $_.ExecutablePath -eq $target })
if ($running.Count -gt 0) { throw '請先關閉 Direct Folders 的設定視窗，再執行本工具。' }

# Request administrator rights only when the destination is actually unwritable.
$probe = Join-Path $ProgramDirectory ('.df-zh-tw-write-test-' + [guid]::NewGuid().ToString('N'))
$canWrite = $false
try { [IO.File]::WriteAllBytes($probe, [byte[]]@()); $canWrite = $true }
catch [UnauthorizedAccessException] { $canWrite = $false }
finally { if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe } }
if (-not $canWrite) {
    if ($NoElevation) { throw '無法寫入安裝資料夾，請以系統管理員身分執行。' }
    Write-Host '寫入安裝資料夾需要管理員權限，請在 Windows 授權視窗選擇「是」。'
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'),'-Action',$Action,'-ProgramDirectory',('"' + $ProgramDirectory + '"'),'-NoElevation','-NoLaunch')
    $child = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if ($child.ExitCode -ne 0) { throw '管理員階段未完成。請先關閉設定視窗，或從 PowerShell 手動執行以查看錯誤。' }
    $installedState = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $expected = if ($Action -eq 'Install') { $installedState.localizedHash } else { $installedState.originalHash }
    if ((Get-ConfigHash $target) -ne $expected) { throw '套用後的檔案驗證失敗。' }
    Write-Host $(if ($Action -eq 'Install') { '繁體中文已安裝。' } else { '已還原英文原版。' })
    if (-not $NoLaunch) { Start-Process -FilePath $target -WorkingDirectory $ProgramDirectory }
    return
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('direct-folders-zh-tw-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$staged = Join-Path $scratch 'config.exe'
$candidate = Join-Path $ProgramDirectory ('.df-zh-tw-' + [guid]::NewGuid().ToString('N') + '.tmp')
$replaced = $false
$rollbackSource = $null
try {
    if ($Action -eq 'Install') {
        . (Join-Path $PSScriptRoot 'tools\Localization.ps1')
        $report = New-LocalizedConfig -Source $target -Destination $staged -PackageRoot $PSScriptRoot
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
        $backupFile = [guid]::NewGuid().ToString('N') + '-config.exe'
        $originalBackup = Join-Path $backupDirectory $backupFile
        Copy-Item -LiteralPath $target -Destination $originalBackup
        if ((Get-ConfigHash $originalBackup) -ne $currentHash) { throw '原檔備份驗證失敗，安裝已停止。' }
        $rollbackSource = $originalBackup
        $expectedHash = $report.OutputHash
        $nextState = [pscustomobject]@{
            version = '4.3.5'; active = $true; backupFile = $backupFile
            originalHash = $currentHash; localizedHash = $expectedHash
            installedAt = [DateTime]::UtcNow.ToString('o')
        }
    } else {
        Copy-Item -LiteralPath $originalBackup -Destination $staged
        $rollbackSource = Join-Path $scratch 'localized-before-restore.exe'
        Copy-Item -LiteralPath $target -Destination $rollbackSource
        $expectedHash = $state.originalHash
        $nextState = $state
        $nextState.active = $false
    }
    # Recheck immediately before replacing the executable to avoid overwriting an intervening update.
    if ((Get-ConfigHash $target) -ne $currentHash) { throw '安裝過程中程式已變更，操作已停止。' }
    Copy-Item -LiteralPath $staged -Destination $candidate
    [IO.File]::Replace($candidate, $target, [System.Management.Automation.Language.NullString]::Value)
    $replaced = $true
    if ((Get-ConfigHash $target) -ne $expectedHash) { throw '檔案雜湊驗證失敗。' }
    Write-State $nextState $statePath
    Write-Host $(if ($Action -eq 'Install') { '繁體中文已安裝，共翻譯 320 處文字。' } else { '已完整還原英文原版。' })
    Write-Host ('原檔備份：' + $backupDirectory)
} catch {
    if ($replaced -and $rollbackSource) { Copy-Item -LiteralPath $rollbackSource -Destination $target -Force }
    throw
} finally {
    if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate }
    # Keep only this run's two known temporary files; never recursively delete a supplied directory.
    foreach ($file in @($staged, (Join-Path $scratch 'localized-before-restore.exe'))) {
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
    }
    if ((Get-ChildItem -LiteralPath $scratch -Force | Measure-Object).Count -eq 0) { Remove-Item -LiteralPath $scratch }
}
if (-not $NoLaunch) { Start-Process -FilePath $target -WorkingDirectory $ProgramDirectory }
