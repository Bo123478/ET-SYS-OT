<#
.SYNOPSIS
    Install / remove the ET workbench pre-push gate (one command).

.DESCRIPTION
    Writes a `pre-push` hook into .git/hooks that chains the three existing
    quality gates, so a broken change cannot leave the local machine:

      1/3  tools/Test-ETScripts.ps1 -Fix   BOM (constraint C-1) + PowerShell/JSON/XAML syntax
      2/3  tools/Test-ETIntegration.ps1    module load + entry-point contract smoke test
      3/3  ETWorkbench/Start-ETWorkbench.ps1 -SelfTest   headless readiness check

    Why a hook and not .gitattributes?
      Git cannot enforce a BOM - .gitattributes only controls line endings and the
      text/binary classification. A BOM is a byte-order prefix Git has no concept of.
      Because Windows PowerShell 5.1 reads .ps1 files using the system ANSI code page
      by default, a Chinese .ps1 saved without a BOM fails to parse on the other
      developer's machine. Constraint C-1 exists for exactly this reason, and the
      only place it can be enforced before sharing is this pre-push gate.

    Safety:
      * An existing pre-push hook is backed up to pre-push.bak (never silently lost).
      * The hook is written as pure LF with no BOM - a CRLF shebang line would make
        Git for Windows refuse to run it.
      * Gate 1 runs with -Fix, so a missing BOM is auto-repaired. If that repair
        changes any tracked file, the push is aborted and you are told to re-stage
        and re-commit, so the shared history never carries an unparsable file.

.PARAMETER Uninstall
    Remove the ET hook. A pre-push.bak backup is restored if one exists.

.PARAMETER Status
    Report whether the hook is installed, without changing anything.

.PARAMETER Force
    Overwrite an existing pre-push hook that was not created by this installer,
    without keeping a backup.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-ETHooks.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-ETHooks.ps1 -Status
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-ETHooks.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$Status,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# This script is deliberately pure ASCII: it is the bootstrap for the encoding
# gate, so it must itself run correctly before any BOM fix has been applied.

$Marker = 'ET-SYS-OT-PRE-PUSH-HOOK v1'

function Write-Head {
    param([string]$Text)
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ("  {0}" -f $Text) -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
}

# ---------------------------------------------------------------- locate repo
$repoRoot = $null
try {
    $repoRoot = (& git rev-parse --show-toplevel 2>$null | Select-Object -First 1)
}
catch {
    $repoRoot = $null
}

if (-not $repoRoot -or -not (Test-Path -LiteralPath $repoRoot)) {
    Write-Host '[FAIL] Not inside a Git working tree. Run this from the repository.' -ForegroundColor Red
    exit 1
}
$repoRoot = $repoRoot.Trim().Replace('/', '\')

$gitDir = Join-Path $repoRoot '.git'
if (-not (Test-Path -LiteralPath $gitDir -PathType Container)) {
    # Worktrees / submodules use a .git file that points elsewhere.
    Write-Host ("[FAIL] {0} is not a directory (linked worktree or submodule?)." -f $gitDir) -ForegroundColor Red
    Write-Host '       Install the hook in the primary checkout instead.' -ForegroundColor Yellow
    exit 1
}

$hooksDir = Join-Path $gitDir 'hooks'
$hookPath = Join-Path $hooksDir 'pre-push'
$backupPath = Join-Path $hooksDir 'pre-push.bak'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

Write-Head 'ET workbench pre-push gate'

# ---------------------------------------------------------------- status mode
function Test-HookOwned {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $text = [System.IO.File]::ReadAllText($Path)
    return ($text -like ('*' + $Marker + '*'))
}

if ($Status) {
    Write-Host ("Repository : {0}" -f $repoRoot)
    Write-Host ("Hook path  : {0}" -f $hookPath)
    Write-Host ''
    if (-not (Test-Path -LiteralPath $hookPath)) {
        Write-Host 'Status     : NOT INSTALLED' -ForegroundColor Yellow
        Write-Host 'Install with: powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-ETHooks.ps1'
        exit 1
    }
    if (Test-HookOwned $hookPath) {
        Write-Host 'Status     : INSTALLED (managed by this installer)' -ForegroundColor Green
    }
    else {
        Write-Host 'Status     : PRESENT but NOT managed by this installer' -ForegroundColor Yellow
        Write-Host 'Review it, then re-run with -Force to replace.' -ForegroundColor Yellow
    }
    $hookBytes = [System.IO.File]::ReadAllBytes($hookPath)
    $bom = ($hookBytes.Length -ge 3 -and $hookBytes[0] -eq 0xEF -and $hookBytes[1] -eq 0xBB -and $hookBytes[2] -eq 0xBF)
    $cr = 0
    foreach ($b in $hookBytes) { if ($b -eq 13) { $cr++ } }
    Write-Host ("Encoding   : BOM={0}  CR bytes={1}  (expected BOM=False CR=0)" -f $bom, $cr)
    if ($bom -or $cr -gt 0) {
        Write-Host 'WARNING    : a BOM or CRLF in the hook can stop Git from running it.' -ForegroundColor Yellow
    }
    exit 0
}

# ------------------------------------------------------------ uninstall mode
if ($Uninstall) {
    if (-not (Test-Path -LiteralPath $hookPath)) {
        Write-Host 'Nothing to do: no pre-push hook is present.' -ForegroundColor Yellow
        exit 0
    }
    if (Test-Path -LiteralPath $backupPath) {
        Move-Item -LiteralPath $backupPath -Destination $hookPath -Force
        Write-Host '[OK] Restored the previous hook from pre-push.bak.' -ForegroundColor Green
    }
    else {
        Remove-Item -LiteralPath $hookPath -Force
        Write-Host '[OK] Removed the ET pre-push hook.' -ForegroundColor Green
    }
    exit 0
}

# ------------------------------------------------------------ preflight gates
$toolsDir = Join-Path $repoRoot 'tools'
$gates = @(
    (Join-Path $toolsDir 'Test-ETScripts.ps1'),
    (Join-Path $toolsDir 'Test-ETIntegration.ps1'),
    (Join-Path $repoRoot 'ETWorkbench\Start-ETWorkbench.ps1')
)
$missing = @($gates | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missing.Count -gt 0) {
    Write-Host '[FAIL] Required gate script(s) not found:' -ForegroundColor Red
    foreach ($m in $missing) { Write-Host ("       {0}" -f $m) -ForegroundColor Red }
    exit 1
}
Write-Host 'Gate scripts found (3/3).' -ForegroundColor Green

# ------------------------------------------------------------ existing hook
if (Test-Path -LiteralPath $hookPath) {
    if (Test-HookOwned $hookPath) {
        Write-Host 'Existing ET hook found - it will be replaced.' -ForegroundColor Yellow
    }
    elseif ($Force) {
        Write-Host 'Overwriting a foreign pre-push hook (-Force).' -ForegroundColor Yellow
    }
    else {
        Write-Host '[STOP] A pre-push hook already exists and was NOT created by this installer:' -ForegroundColor Red
        Write-Host ("       {0}" -f $hookPath) -ForegroundColor Red
        Write-Host '       Re-run with -Force to replace it, or move it aside first.' -ForegroundColor Yellow
        exit 1
    }
    if (-not $Force -and -not (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $hookPath -Destination $backupPath -Force
        Write-Host '       Backed up to pre-push.bak.' -ForegroundColor DarkGray
    }
}

# ------------------------------------------------------------ render the hook
# NOTE: built with "`n" only. The repository's .ps1 files use CRLF, so the text
# below must never be taken from a here-string verbatim without normalisation.
$nl = "`n"
$hook = @(
    '#!/bin/sh'
    ('# {0}' -f $Marker)
    '#'
    '# Generated by tools/Install-ETHooks.ps1 -- do not edit by hand.'
    '# Re-run the installer to refresh, or pass -Uninstall to remove.'
    '#'
    '# Gates (all must pass, otherwise the push is aborted):'
    '#   1/3 Test-ETScripts.ps1 -Fix  -> BOM (C-1) + syntax'
    '#   2/3 Test-ETIntegration.ps1   -> module load + contract smoke test'
    '#   3/3 Start-ETWorkbench.ps1 -SelfTest -> headless readiness'
    ''
    'set -u'
    ''
    'REPO_ROOT="$(git rev-parse --show-toplevel)"'
    'PS_EXE="powershell.exe"'
    'if ! command -v "$PS_EXE" >/dev/null 2>&1; then'
    '    echo "!! powershell.exe not found on PATH -- skipping ET gates."'
    '    exit 0'
    'fi'
    ''
    'run_gate() {'
    '    label="$1"'
    '    script="$2"'
    '    shift 2'
    '    echo ""'
    '    echo "----- [$label] $script $* -----"'
    '    "$PS_EXE" -NoProfile -ExecutionPolicy Bypass -File "$script" "$@"'
    '    rc=$?'
    '    if [ "$rc" -ne 0 ]; then'
    '        echo ""'
    '        echo "!! GATE FAILED [$label] exit=$rc -- push aborted."'
    '        echo "   Fix the reported problem and commit the change, then push again."'
    '        exit 1'
    '    fi'
    '}'
    ''
    'snapshot_dirty() {'
    '    if command -v git >/dev/null 2>&1; then'
    '        git -C "$REPO_ROOT" diff --name-only -- "*.ps1" "*.psm1" "*.json" "*.xaml" 2>/dev/null'
    '    fi'
    '}'
    ''
    '# Snapshot the dirty set BEFORE gate 1 runs, then again AFTER. Only a change'
    '# in that set is attributable to the auto-fix. A plain "is anything dirty?"'
    '# test would abort the push for unrelated edits, and git status would also'
    '# flag untracked files that have nothing to do with the commits being pushed.'
    'DIRTY_BEFORE="$(snapshot_dirty)"'
    ''
    'run_gate "1/3 BOM+syntax" "$REPO_ROOT/tools/Test-ETScripts.ps1" -Fix'
    ''
    '# Gate 1 rewrites the WORKING TREE. If it touched a tracked file, the index'
    '# still holds the pre-repair bytes, so the commits being pushed would carry a'
    '# file that cannot be parsed on a machine with a different ANSI code page.'
    'DIRTY_AFTER="$(snapshot_dirty)"'
    'if [ "$DIRTY_AFTER" != "$DIRTY_BEFORE" ]; then'
    '        echo ""'
    '        echo "!! Gate 1 auto-repaired encoding - the working tree changed:"'
    '        echo "$DIRTY_AFTER"'
    '        echo "   Stage and commit the repair, then push again."'
    '        exit 1'
    'fi'
    ''
    'run_gate "2/3 integration" "$REPO_ROOT/tools/Test-ETIntegration.ps1"'
    'run_gate "3/3 self-test"   "$REPO_ROOT/ETWorkbench/Start-ETWorkbench.ps1" -SelfTest'
    ''
    'echo ""'
    'echo "All ET gates passed -- allowing push."'
    'exit 0'
) -join $nl

# Guarantee LF even if an element ever contained CR.
$hook = $hook.Replace("`r`n", "`n").Replace("`r", "`n")
if (-not $hook.EndsWith("`n")) { $hook += "`n" }

if (-not (Test-Path -LiteralPath $hooksDir -PathType Container)) {
    New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
}

[System.IO.File]::WriteAllText($hookPath, $hook, $utf8NoBom)

# ------------------------------------------------------------ verify the write
$bytes = [System.IO.File]::ReadAllBytes($hookPath)
$bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
$cr = 0
foreach ($b in $bytes) { if ($b -eq 13) { $cr++ } }

Write-Host ''
Write-Host ("[OK] Hook written: {0}" -f $hookPath) -ForegroundColor Green
Write-Host ("     size={0} bytes  BOM={1}  CR={2}  (must be BOM=False CR=0)" -f $bytes.Length, $bom, $cr)
if ($bom -or $cr -gt 0) {
    Write-Host '[FAIL] The hook has a BOM or CRLF and will not run.' -ForegroundColor Red
    exit 1
}
Write-Host '     Format is correct: pure LF, no BOM.' -ForegroundColor Green

try {
    & git -C $repoRoot config core.hooksPath $hooksDir | Out-Null
    Write-Host ("     core.hooksPath = {0}" -f $hooksDir)
}
catch {
    Write-Host '     (note: could not set core.hooksPath - the default .git/hooks still applies)' -ForegroundColor DarkGray
}

Write-Head 'Done'
Write-Host 'Push any commit to see the gates run, e.g.:  git push'
Write-Host 'Inspect or remove:'
Write-Host '  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-ETHooks.ps1 -Status'
Write-Host '  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-ETHooks.ps1 -Uninstall'
exit 0
