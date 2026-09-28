<#
.SYNOPSIS
    ET script hygiene check: enforce UTF-8 with BOM and validate PowerShell syntax.

.DESCRIPTION
    Constraint C-1 requires every .ps1 / .psm1 / .json / .xaml file that contains
    non-ASCII (Chinese) text to be saved as UTF-8 *with BOM*, because Windows
    PowerShell 5.1 reads .ps1 files using the system ANSI code page by default.

    This script is intentionally pure ASCII so it can run before any encoding fix.

    For each target file it will:
      1. Report whether a BOM is present.
      2. (with -Fix) rewrite the file as UTF-8 with BOM, preserving content exactly.
      3. Parse .ps1 / .psm1 files with the PowerShell language parser and report
         syntax errors with line/column.
      4. Validate .json files with ConvertFrom-Json.
      5. Validate .xaml files with [xml] cast.

.PARAMETER Path
    Root directory to scan. Defaults to the ETWorkbench folder next to this script's parent.

.PARAMETER Fix
    Add the missing BOM to any file that lacks it.

.PARAMETER SkipSyntax
    Only check/fix encodings, do not parse scripts.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-ETScripts.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-ETScripts.ps1 -Fix
#>
[CmdletBinding()]
param(
    [string[]]$Path,
    [switch]$Fix,
    [switch]$SkipSyntax
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Path -or $Path.Count -eq 0) {
    $Path = @((Join-Path $repoRoot 'ETWorkbench'), $PSScriptRoot)
}

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Test-HasBom {
    param([string]$File)
    $bytes = [System.IO.File]::ReadAllBytes($File)
    if ($bytes.Length -lt 3) { return $false }
    return ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function Add-BomPreserving {
    param([string]$File)
    # Read as UTF-8 (works with or without BOM) then rewrite with BOM.
    $text = [System.IO.File]::ReadAllText($File, $utf8NoBom)
    # Strip a leading U+FEFF that ReadAllText may have kept from a BOM'd file.
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    [System.IO.File]::WriteAllText($File, $text, $utf8Bom)
}

$scriptFiles = New-Object System.Collections.ArrayList
$jsonFiles = New-Object System.Collections.ArrayList
$xamlFiles = New-Object System.Collections.ArrayList

foreach ($root in $Path) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue)) {
        switch ($f.Extension.ToLowerInvariant()) {
            '.ps1' { [void]$scriptFiles.Add($f) }
            '.psm1' { [void]$scriptFiles.Add($f) }
            '.json' { [void]$jsonFiles.Add($f) }
            '.xaml' { [void]$xamlFiles.Add($f) }
        }
    }
}

$all = @($scriptFiles) + @($jsonFiles) + @($xamlFiles)
$all = @($all | Sort-Object FullName -Unique)

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '  ET file hygiene check (UTF-8 BOM + syntax)' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ("Scanned: {0} .ps1/.psm1, {1} .json, {2} .xaml" -f $scriptFiles.Count, $jsonFiles.Count, $xamlFiles.Count)
Write-Host ''

# ---------------------------------------------------------------- 1) BOM
$noBom = New-Object System.Collections.ArrayList
foreach ($f in $all) {
    if (-not (Test-HasBom $f.FullName)) { [void]$noBom.Add($f) }
}

if ($noBom.Count -eq 0) {
    Write-Host '[BOM] All files already have a UTF-8 BOM.' -ForegroundColor Green
}
elseif ($Fix) {
    Write-Host ("[BOM] Adding BOM to {0} file(s)..." -f $noBom.Count) -ForegroundColor Yellow
    foreach ($f in $noBom) {
        try {
            Add-BomPreserving $f.FullName
            Write-Host ("  + {0}" -f $f.FullName.Substring($repoRoot.Length + 1)) -ForegroundColor DarkYellow
        }
        catch {
            Write-Host ("  ! FAILED {0}: {1}" -f $f.FullName, $_.Exception.Message) -ForegroundColor Red
        }
    }
}
else {
    Write-Host ("[BOM] {0} file(s) MISSING a BOM (re-run with -Fix):" -f $noBom.Count) -ForegroundColor Red
    foreach ($f in $noBom) { Write-Host ("  - {0}" -f $f.FullName.Substring($repoRoot.Length + 1)) }
}

Write-Host ''

# ---------------------------------------------------------------- 2) syntax
if ($SkipSyntax) {
    Write-Host '[SKIP] Syntax validation skipped.' -ForegroundColor DarkGray
    exit 0
}

$failing = 0

foreach ($f in $scriptFiles) {
    $tokens = $null
    $errors = $null
    try {
        $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    }
    catch {
        Write-Host ("[PS  ] {0} -- PARSER THREW: {1}" -f $f.Name, $_.Exception.Message) -ForegroundColor Red
        $failing++
        continue
    }
    if ($errors -and @($errors).Count -gt 0) {
        $failing++
        Write-Host ("[PS  ] {0} -- {1} syntax error(s)" -f $f.Name, @($errors).Count) -ForegroundColor Red
        foreach ($e in @($errors | Select-Object -First 5)) {
            Write-Host ("        line {0},{1}: {2}" -f $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Message) -ForegroundColor Red
        }
    }
    else {
        Write-Host ("[PS  ] {0} OK" -f $f.Name) -ForegroundColor Green
    }
}

foreach ($f in $jsonFiles) {
    try {
        $null = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Host ("[JSON] {0} OK" -f $f.Name) -ForegroundColor Green
    }
    catch {
        $failing++
        Write-Host ("[JSON] {0} -- {1}" -f $f.Name, $_.Exception.Message) -ForegroundColor Red
    }
}

foreach ($f in $xamlFiles) {
    try {
        $xml = New-Object System.Xml.XmlDocument
        $xml.Load($f.FullName)
        Write-Host ("[XAML] {0} OK" -f $f.Name) -ForegroundColor Green
    }
    catch {
        $failing++
        Write-Host ("[XAML] {0} -- {1}" -f $f.Name, $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host ''
if ($failing -eq 0) {
    Write-Host 'RESULT: ALL CHECKS PASSED' -ForegroundColor Green
    exit 0
}
Write-Host ("RESULT: {0} problem(s) found" -f $failing) -ForegroundColor Red
exit 1
