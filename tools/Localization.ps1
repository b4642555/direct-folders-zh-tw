Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (-not ('DirectFoldersZhTW.Resources' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'Resources.cs')
}

function Get-BytesHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-Translation([string]$Text, [hashtable]$Dictionary) {
    if ($Dictionary.ContainsKey($Text)) { return [string]$Dictionary[$Text] }
    $trimmed = $Text.Trim()
    if ($Dictionary.ContainsKey($trimmed)) {
        return $Text.Substring(0, $Text.Length - $Text.TrimStart().Length) +
            $Dictionary[$trimmed] + $Text.Substring($Text.TrimEnd().Length)
    }
    return $Text
}

function New-LocalizedConfig {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination,
        [Parameter(Mandatory=$true)][string]$PackageRoot
    )
    $Source = [IO.Path]::GetFullPath($Source)
    $Destination = [IO.Path]::GetFullPath($Destination)
    if ($Source -eq $Destination) { throw 'Source and destination must be different files.' }
    if (Test-Path -LiteralPath $Destination) { throw 'Destination already exists; no file was overwritten.' }
    $manifest = Get-Content -LiteralPath (Join-Path $PackageRoot 'translations\manifest-4.3.5.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $dictionaryObject = Get-Content -LiteralPath (Join-Path $PackageRoot 'translations\zh-TW.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    # Case-sensitive: changing an internal identifier or a differently capitalized label is unsafe.
    $dictionary = [Collections.Hashtable]::new([StringComparer]::Ordinal)
    foreach ($entry in $dictionaryObject.strings) { $dictionary[[string]$entry.source] = [string]$entry.target }
    [byte[]]$bytes = [IO.File]::ReadAllBytes($Source)
    $sourceHash = Get-BytesHash $bytes
    if ($manifest.supportedSourceHashes -notcontains $sourceHash) {
        throw ('Unsupported config.exe. Only the verified Direct Folders 4.3.5 builds are supported. SHA256: ' + $sourceHash)
    }
    $runtimeCount = 0
    foreach ($patch in $manifest.runtimeStrings) {
        [int]$offset = $patch.offset
        [byte[]]$old = [Text.Encoding]::Unicode.GetBytes([string]$patch.source)
        [byte[]]$actual = New-Object byte[] $old.Length
        [Buffer]::BlockCopy($bytes, $offset, $actual, 0, $actual.Length)
        if (-not [DirectFoldersZhTW.Resources]::Equal($old, $actual) -or
            [BitConverter]::ToInt32($bytes, $offset - 8) -ne -1 -or
            [BitConverter]::ToInt32($bytes, $offset - 4) -ne ($old.Length / 2)) {
            throw ('Runtime string validation failed at ' + $offset)
        }
        [string]$translation = Get-Translation ([string]$patch.source) $dictionary
        [byte[]]$replacement = [Text.Encoding]::Unicode.GetBytes($translation)
        if ($replacement.Length -gt $old.Length -or $translation -eq $patch.source) {
            throw ('Missing or oversized runtime translation: ' + $patch.source)
        }
        [Array]::Clear($bytes, $offset, $old.Length)
        [Buffer]::BlockCopy($replacement, 0, $bytes, $offset, $replacement.Length)
        [Buffer]::BlockCopy([BitConverter]::GetBytes([int]$translation.Length), 0, $bytes, $offset - 4, 4)
        $runtimeCount++
    }
    $sourceResources = [DirectFoldersZhTW.Resources]::Read($Source)
    $updates = New-Object 'Collections.Generic.List[DirectFoldersZhTW.ResourceEntry]'
    $formCount = 0
    $buttonCount = 0
    foreach ($resource in $sourceResources) {
        [byte[]]$rebuilt = $resource.Data
        if ($resource.Type -eq 10) {
            $forms = @($manifest.forms | Where-Object { $_.name -ceq $resource.Name })
            if ($forms.Count -ne 1) { continue }
            $form = $forms[0]
            if ((Get-BytesHash $rebuilt) -ne $form.sha256) { throw ('Unexpected form data: ' + $form.name) }
            $end = $rebuilt.Length
            foreach ($patch in ($form.strings | Sort-Object offset -Descending)) {
                if ($patch.offset + $patch.length -gt $end) { throw 'Invalid or overlapping form patch.' }
                $end = $patch.offset
                [string]$translation = Get-Translation ([string]$patch.source) $dictionary
                if ($translation -eq $patch.source) { throw ('Missing form translation: ' + $patch.source) }
                [byte[]]$textBytes = [Text.Encoding]::Unicode.GetBytes($translation)
                [byte[]]$encoded = @([byte]18) + [BitConverter]::GetBytes([int]$translation.Length) + $textBytes
                $rebuilt = [DirectFoldersZhTW.Resources]::Replace($rebuilt, $patch.offset, $patch.length, $encoded)
                $formCount++
            }
        } elseif ($resource.Type -eq 6) {
            $stream = New-Object IO.MemoryStream
            $writer = New-Object IO.BinaryWriter($stream)
            try {
                $offset = 0
                for ($index = 0; $index -lt 16; $index++) {
                    if ($offset + 2 -gt $rebuilt.Length) { throw 'Truncated string table.' }
                    $length = [BitConverter]::ToUInt16($rebuilt, $offset)
                    $offset += 2
                    if ($offset + 2 * $length -gt $rebuilt.Length) { throw 'Truncated string-table text.' }
                    $text = [Text.Encoding]::Unicode.GetString($rebuilt, $offset, 2 * $length)
                    $offset += 2 * $length
                    $translation = $text
                    if ($dictionary.ContainsKey($text)) { $translation = [string]$dictionary[$text] }
                    $writer.Write([uint16]$translation.Length)
                    $writer.Write([Text.Encoding]::Unicode.GetBytes($translation))
                    if ($translation -cne $text) { $buttonCount++ }
                }
                for ($i = $offset; $i -lt $rebuilt.Length; $i++) {
                    if ($rebuilt[$i] -ne 0) { throw 'Unexpected string-table trailer.' }
                    $writer.Write([byte]0)
                }
                $rebuilt = $stream.ToArray()
            } finally { $writer.Dispose(); $stream.Dispose() }
        }
        if (-not [DirectFoldersZhTW.Resources]::Equal($rebuilt, $resource.Data)) {
            $entry = New-Object DirectFoldersZhTW.ResourceEntry
            $entry.Type = $resource.Type; $entry.Id = $resource.Id
            if ($null -ne $resource.Name) { $entry.Name = $resource.Name }
            $entry.Language = $resource.Language; $entry.Data = $rebuilt
            $updates.Add($entry)
        }
    }
    if ($formCount -ne $manifest.expectedCounts.forms -or $runtimeCount -ne $manifest.expectedCounts.runtime -or $buttonCount -ne $manifest.expectedCounts.buttons) {
        throw ('Unexpected translation counts: forms={0}, runtime={1}, buttons={2}' -f $formCount, $runtimeCount, $buttonCount)
    }
    [IO.File]::WriteAllBytes($Destination, $bytes)
    [DirectFoldersZhTW.Resources]::Write($Destination, $updates.ToArray())
    $readback = [DirectFoldersZhTW.Resources]::Read($Destination)
    foreach ($expected in $updates) {
        $resourceReadback = @($readback | Where-Object { $_.Type -eq $expected.Type -and $_.Name -ceq $expected.Name -and $_.Id -eq $expected.Id -and $_.Language -eq $expected.Language })
        if ($resourceReadback.Count -ne 1 -or -not [DirectFoldersZhTW.Resources]::Equal($expected.Data, $resourceReadback[0].Data)) {
            throw ('Translated resource readback failed: type={0}, name={1}, id={2}, language={3}, matches={4}' -f $expected.Type, $expected.Name, $expected.Id, $expected.Language, $resourceReadback.Count)
        }
    }
    [pscustomobject]@{
        SourceHash = $sourceHash; OutputHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
        FormStrings = $formCount; RuntimeStrings = $runtimeCount; ButtonStrings = $buttonCount
    }
}
