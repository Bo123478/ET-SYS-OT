$ErrorActionPreference = 'Stop'

# NOTE: intentionally NO non-ASCII characters in this file.
# PowerShell 5.1 reads .ps1 as system ANSI (no UTF-8 BOM), so a hard-coded
# CJK path would be mangled. Repo root is derived from $PSScriptRoot instead.
#
# Window capture is done entirely in C# because PowerShell marshalling of
# `out RECT` from GetWindowRect proved unreliable (returned 0x0).

$repoRoot = Split-Path $PSScriptRoot -Parent
$entry = Join-Path $repoRoot 'ETWorkbench\Start-ETWorkbench.ps1'
$out = Join-Path $env:TEMP 'workbench-ui.png'

if (-not (Test-Path $entry)) {
    throw "Entry script not found: $entry"
}

# WPF needs an interactive desktop. A remote agent / service host usually runs in
# session 0, which has no visible desktop: the window is created and ShowDialog()
# blocks forever, but nothing can be captured. Detect it up front and say so
# instead of failing with a confusing 15s timeout.
if ([System.Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) {
    Write-Host 'SKIPPED: running in session 0 (no interactive desktop).'
    Write-Host '         The WPF window cannot be captured from here.'
    Write-Host '         Run this script from an interactive user session instead.'
    exit 2
}
Remove-Item $out -Force -ErrorAction SilentlyContinue

$src = @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Threading;

public class UiShot {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);

    public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);

    // The entry point is a PowerShell script, so the launched process is
    // powershell.exe and its MainWindowHandle is the console window -- not the
    // WPF window. Find the WPF window by picking the largest visible top-level
    // window owned by that process.
    static IntPtr _best;
    static uint _pid;
    static int _area;

    public static IntPtr FindLargestWindow(int pid) {
        _best = IntPtr.Zero; _area = 0; _pid = (uint)pid;
        EnumWindows(new EnumWindowsProc(Visit), IntPtr.Zero);
        return _best;
    }

    static bool Visit(IntPtr h, IntPtr l) {
        uint p;
        GetWindowThreadProcessId(h, out p);
        if (p != _pid) return true;
        if (!IsWindowVisible(h) || IsIconic(h)) return true;
        RECT r;
        if (!GetWindowRect(h, out r)) return true;
        int a = (r.Right - r.Left) * (r.Bottom - r.Top);
        if (a > _area) { _area = a; _best = h; }
        return true;
    }

    public static string Capture(IntPtr hWnd, string path) {
        ShowWindow(hWnd, 9);            // SW_RESTORE
        SetForegroundWindow(hWnd);

        int w = 0, ht = 0, left = 0, top = 0;
        for (int i = 0; i < 40; i++) {
            RECT r;
            if (GetWindowRect(hWnd, out r)) {
                w = r.Right - r.Left;
                ht = r.Bottom - r.Top;
                left = r.Left;
                top = r.Top;
                if (w > 0 && ht > 0 && IsWindowVisible(hWnd) && !IsIconic(hWnd)) break;
            }
            Thread.Sleep(250);
        }
        if (w <= 0 || ht <= 0) return "FAILED size=" + w + "x" + ht;

        Thread.Sleep(800);              // let WPF finish first render
        using (var bmp = new Bitmap(w, ht, PixelFormat.Format32bppArgb))
        using (var g = Graphics.FromImage(bmp)) {
            // capture the window's own screen region, not the screen origin
            g.CopyFromScreen(left, top, 0, 0, bmp.Size, CopyPixelOperation.SourceCopy);
            bmp.Save(path, ImageFormat.Png);
        }
        return "OK size=" + w + "x" + ht + " at " + left + "," + top;
    }
}
'@
Add-Type -TypeDefinition $src -ReferencedAssemblies 'System.Drawing'

$p = Start-Process -FilePath 'powershell.exe' -PassThru -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$entry`"")

# Wait for the WPF window to appear (module import + XAML load takes a moment).
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 250
    $p.Refresh()
    if ($p.HasExited) { throw "Entry point exited early with code $($p.ExitCode)" }
    $h = [UiShot]::FindLargestWindow($p.Id)
    if ($h -ne [IntPtr]::Zero) { break }
}

Write-Host "pid=$($p.Id) hwnd=$h"
if ($h -eq [IntPtr]::Zero) { throw 'No visible window appeared within 15s.' }

$result = [UiShot]::Capture($h, $out)
Write-Host "capture=$result"

if (Test-Path $out) {
    Write-Host "saved=$out bytes=$((Get-Item $out).Length)"
} else {
    Write-Host "no file produced"
}
Write-Host "APP_LEFT_RUNNING pid=$($p.Id)"
