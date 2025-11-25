# Copilot Instructions for LinuxWelcomeScreen

## Project Overview
- Goal: PowerShell Core login banner for Linux servers; prints host/network/system stats in Russian per `README.MD` example.
- Entrypoint `LinuxWelcomeScreen.ps1` runs end-to-end; no modules or supporting files yet.
- Keep output format backwards compatible: header/footer separators, aligned labels, and `N/A` fallbacks for missing metrics.

## Key Script Details
- `LinuxWelcomeScreen.ps1` sets `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`; new code must respect strict mode.
- Helper layout: `Format-InfoLine` aligns labels, `Convert-ToSizeString` renders bytes (B→PB) without locale-specific decimals.
- Data collection helpers:
	- `Get-PublicIPAddress` tries `api.ipify.org` then `ifconfig.me`; maintain short timeouts and graceful degradation.
	- `Get-LocalIPAddress` filters active NICs, ignores loopback/169.254.*.
	- `Get-OsPrettyName`, `Get-MemoryReport`, `Get-DiskReport` read `/etc/os-release`, `/proc/*`, and `df -B1 /`; keep Linux-first approach.
	- `Get-ReadableUptime` prefers `uptime -p`, falls back to `/proc/uptime` + humanized TimeSpan.
- Display strings mix Russian labels with English metric names (`Load Average`, `Uptime`); keep consistent terminology.

## Environment & Dependencies
- Target PowerShell 7+ on Debian-based hosts; script assumes `/proc`, `df`, and `uptime` exist. Add Windows/macOS branching only with maintainer approval.
- Network calls require outbound HTTPS; guard changes with retries/timeouts similar to existing implementation.
- When extending metrics (e.g., new disks), prefer native Linux utilities or `/proc` data to avoid additional dependencies.

## Workflow & Testing
- Run locally with `pwsh ./LinuxWelcomeScreen.ps1`; expect formatted table matching README.MD sample.
- For manual verification, compare output with `hostname`, `ip addr`, `uptime`, `free -m`, and `df -h /` on target host.
- No automated tests; document manual validation steps in PR descriptions when altering metrics or formatting.

## Collaboration Notes
- Clarify desired columns/order with maintainer before altering banner layout to avoid breaking user muscle memory.
- Surface OS compatibility questions early (e.g., alternative filesystems, containerized environments) to guide fallback logic.
- Preserve ASCII where possible; Russian labels already require UTF-8, so keep encoding consistent across new strings.
