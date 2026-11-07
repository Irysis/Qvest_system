<#
claude_cli_procs.ps1 - list processes running from the npm-global Claude Code install (2026-11-07)
  Consumer: claude_cli_update.sh (busy check before replacing bin\claude.exe).

  Output: one line per match "<pid><TAB><path or command line>", then a last line "#OK <count>".
          No "#OK" line = the query died; the caller must read that as BUSY, never as "zero processes".
  Match:  ExecutablePath or CommandLine contains -Marker (default \npm\node_modules\@anthropic-ai\claude-code\),
          case-insensitive. Covers the native bin\claude.exe and node + cli-wrapper.cjs/cli.js fallbacks,
          and both the real path and the C:\Users\99922 junction alias (the marker is a path suffix).
          The Claude desktop app does not match: its processes run from WindowsApps\Claude_*\app\Claude.exe
          and Claude-Data\...\claude-code\<version>\...\claude.exe (measured 2026-11-07 on MAINCOMPUTER).
  Self:   lines whose command line names this script are skipped (this process and its bash parent).
  Keep this file ASCII-only: Windows PowerShell 5.1 reads a BOM-less script in the ANSI code page.
#>
param([string]$Marker = '\npm\node_modules\@anthropic-ai\claude-code\')
$ErrorActionPreference = 'Stop'
try {
  $n = 0
  foreach ($p in @(Get-CimInstance -ClassName Win32_Process -Property ProcessId, ExecutablePath, CommandLine)) {
    $e = [string]$p.ExecutablePath
    $c = [string]$p.CommandLine
    if ($c.IndexOf('claude_cli_procs.ps1', [StringComparison]::OrdinalIgnoreCase) -ge 0) { continue }
    if ($e.IndexOf($Marker, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $c.IndexOf($Marker, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
      $n++
      $what = $(if ($e) { $e } else { $c })
      Write-Output ("{0}`t{1}" -f $p.ProcessId, $what)
    }
  }
  Write-Output "#OK $n"
  exit 0
} catch {
  Write-Output "#ERR $($_.Exception.Message)"
  exit 2
}
