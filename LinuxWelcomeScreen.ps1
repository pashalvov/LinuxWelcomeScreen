#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Width used to align the left labels
[int]$labelWidth = 15
$separator = '-' * 41

function Format-InfoLine {
    param(
        [string]$Label,
        [string]$Value
    )

    ($Label.PadRight($labelWidth)) + ' : ' + $Value
}

function Convert-ToSizeString {
    param(
        [double]$Bytes
    )

    if ($Bytes -lt 0) {
        $Bytes = 0
    }

    $units = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
    $index = 0

    while ($Bytes -ge 1024 -and $index -lt $units.Length - 1) {
        $Bytes /= 1024
        $index++
    }

    $rounded = if ($Bytes -ge 100 -or $index -eq 0) {
        [math]::Round($Bytes, 0)
    } else {
        [math]::Round($Bytes, 1)
    }

    $roundedString = if ([math]::Abs($rounded - [math]::Round($rounded, 0)) -lt 0.0001) {
        [math]::Round($rounded, 0).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    } else {
        $rounded.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)
    }

    "{0}{1}" -f $roundedString, $units[$index]
}

function Get-PublicIPAddress {
    $resolvers = @(
        { (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 3).ip },
        { (Invoke-RestMethod -Uri 'https://ifconfig.me/ip' -TimeoutSec 3).Trim() }
    )

    foreach ($resolver in $resolvers) {
        try {
            $result = & $resolver
            if ($result) {
                return $result
            }
        } catch {
            continue
        }
    }

    'N/A'
}

function Get-LocalIPAddress {
    try {
        $interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
            Where-Object { $_.OperationalStatus -eq [System.Net.NetworkInformation.OperationalStatus]::Up }

        foreach ($interface in $interfaces) {
            foreach ($addressInfo in $interface.GetIPProperties().UnicastAddresses) {
                if ($addressInfo.Address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
                    continue
                }

                $addressString = $addressInfo.Address.ToString()

                if ($addressString -match '^(127\.|169\.254\.)') {
                    continue
                }

                return $addressString
            }
        }
    } catch {
        return 'N/A'
    }

    'N/A'
}

function Get-OsPrettyName {
    if (Test-Path '/etc/os-release') {
        try {
            $pretty = Get-Content '/etc/os-release' |
                Where-Object { $_ -match '^PRETTY_NAME=' } |
                Select-Object -First 1

            if ($pretty) {
                return $pretty.Split('=')[1].Trim('"')
            }
        } catch {
        }
    }

    [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
}

function Get-CurrentUserName {
    if ($env:USER) {
        return $env:USER
    }

    if ($env:USERNAME) {
        return $env:USERNAME
    }

    try {
        $whoami = & whoami 2>$null
        if ($whoami) {
            return $whoami.Trim()
        }
    } catch {
    }

    'N/A'
}

function Get-LoadAverage {
    if (Test-Path '/proc/loadavg') {
        try {
            $parts = (Get-Content '/proc/loadavg' -ErrorAction Stop).Split(' ') |
                Where-Object { $_ }

            if ($parts.Length -ge 3) {
                return ('{0} {1} {2}' -f $parts[0], $parts[1], $parts[2])
            }
        } catch {
        }
    }

    if (Get-Command uptime -ErrorAction SilentlyContinue) {
        try {
            $uptimeOutput = & uptime 2>$null
            if ($uptimeOutput -match 'load average[s]?:\s*(?<loads>.*)$') {
                return ($Matches['loads'] -replace ',', '').Trim()
            }
        } catch {
        }
    }

    'N/A'
}

function Convert-TimeSpanToWords {
    param(
        [TimeSpan]$TimeSpan
    )

    $parts = @()
    $totalDays = $TimeSpan.Days

    if ($totalDays -ge 7) {
        $weeks = [math]::Floor($totalDays / 7)
        $daysRemainder = $totalDays % 7
        if ($weeks -gt 0) {
            $parts += ('{0} week{1}' -f $weeks, $(if ($weeks -eq 1) { '' } else { 's' }))
        }
        if ($daysRemainder -gt 0) {
            $parts += ('{0} day{1}' -f $daysRemainder, $(if ($daysRemainder -eq 1) { '' } else { 's' }))
        }
    } elseif ($totalDays -gt 0) {
        $parts += ('{0} day{1}' -f $totalDays, $(if ($totalDays -eq 1) { '' } else { 's' }))
    }

    if ($TimeSpan.Hours -gt 0) {
        $parts += ('{0} hour{1}' -f $TimeSpan.Hours, $(if ($TimeSpan.Hours -eq 1) { '' } else { 's' }))
    }

    if ($TimeSpan.Minutes -gt 0) {
        $parts += ('{0} minute{1}' -f $TimeSpan.Minutes, $(if ($TimeSpan.Minutes -eq 1) { '' } else { 's' }))
    }

    if ($parts.Count -eq 0) {
        $parts += '0 minutes'
    }

    $parts -join ', '
}

function Get-ReadableUptime {
    if (Get-Command uptime -ErrorAction SilentlyContinue) {
        try {
            $pretty = & uptime -p 2>$null
            if ($pretty) {
                return ($pretty -replace '^up\s+', '').Trim()
            }
        } catch {
        }
    }

    if (Test-Path '/proc/uptime') {
        try {
            $raw = (Get-Content '/proc/uptime' -ErrorAction Stop).Split(' ')[0]
            $seconds = [double]::Parse($raw, [System.Globalization.CultureInfo]::InvariantCulture)
            $span = [TimeSpan]::FromSeconds([math]::Round($seconds))
            return Convert-TimeSpanToWords -TimeSpan $span
        } catch {
        }
    }

    'N/A'
}

function Get-MemoryReport {
    if (-not (Test-Path '/proc/meminfo')) {
        return $null
    }

    try {
        $memInfo = @{}
        foreach ($line in Get-Content '/proc/meminfo' -ErrorAction Stop) {
            if ($line -match '^(?<Key>\w+):\s+(?<Value>\d+)') {
                $memInfo[$Matches['Key']] = [double]$Matches['Value']
            }
        }

        if ($memInfo.Count -eq 0 -or -not $memInfo.ContainsKey('MemTotal')) {
            return $null
        }

        $totalMb = [math]::Round($memInfo['MemTotal'] / 1024)

        $availableKb = if ($memInfo.ContainsKey('MemAvailable')) {
            $memInfo['MemAvailable']
        } else {
            $memFree = if ($memInfo.ContainsKey('MemFree')) { $memInfo['MemFree'] } else { 0 }
            $buffers = if ($memInfo.ContainsKey('Buffers')) { $memInfo['Buffers'] } else { 0 }
            $cached = if ($memInfo.ContainsKey('Cached')) { $memInfo['Cached'] } else { 0 }
            $memFree + $buffers + $cached
        }

        $freeMb = [math]::Round($availableKb / 1024)
        $freePercent = if ($totalMb -gt 0) { [math]::Round(($freeMb / $totalMb) * 100) } else { 0 }

        [pscustomobject]@{
            TotalMb     = [int]$totalMb
            FreeMb      = [int]$freeMb
            FreePercent = [int]$freePercent
        }
    } catch {
        $null
    }
}

function Get-DiskReport {
    param(
        [string]$Path = '/'
    )

    if (-not (Get-Command df -ErrorAction SilentlyContinue)) {
        return $null
    }

    try {
        $output = & df -B1 $Path 2>$null
        if (-not $output) {
            return $null
        }

        $line = ($output | Select-Object -Skip 1 | Select-Object -First 1).Trim()
        if (-not $line) {
            return $null
        }

        $tokens = $line -split '\s+'
        if ($tokens.Length -lt 5) {
            return $null
        }

        $totalBytes = [double]$tokens[1]
        $availableBytes = [double]$tokens[3]
        $freePercent = if ($totalBytes -gt 0) {
            [math]::Round(($availableBytes / $totalBytes) * 100)
        } else {
            0
        }

        [pscustomobject]@{
            TotalDisplay = Convert-ToSizeString -Bytes $totalBytes
            FreeDisplay  = Convert-ToSizeString -Bytes $availableBytes
            FreePercent  = [int]$freePercent
        }
    } catch {
        $null
    }
}

$publicIp = Get-PublicIPAddress
$localIp = Get-LocalIPAddress
$hostName = [System.Net.Dns]::GetHostName()
$osPrettyName = Get-OsPrettyName
$currentUser = Get-CurrentUserName
$loadAverage = Get-LoadAverage
$uptime = Get-ReadableUptime
$cpuSummary = ('{0} CPU' -f [Environment]::ProcessorCount)
$memoryReport = Get-MemoryReport
if (-not $memoryReport) {
    $memoryReport = [pscustomobject]@{
        TotalMb    = 'N/A'
        FreeMb     = 'N/A'
        FreePercent = 'N/A'
    }
}

$diskReport = Get-DiskReport -Path '/'
if (-not $diskReport) {
    $diskReport = [pscustomobject]@{
        TotalDisplay = 'N/A'
        FreeDisplay  = 'N/A'
        FreePercent  = 'N/A'
    }
}

$uptimeDisplay = if ($uptime -and $uptime -ne 'N/A') {
    'up ' + $uptime
} else {
    'N/A'
}

$lines = @(
    $separator,
    Format-InfoLine -Label 'IP' -Value $publicIp,
    Format-InfoLine -Label 'Локальный IP' -Value $localIp,
    Format-InfoLine -Label 'Имя хоста' -Value $hostName,
    Format-InfoLine -Label 'ОС' -Value $osPrettyName,
    Format-InfoLine -Label 'Пользователь' -Value $currentUser,
    Format-InfoLine -Label 'Load Average' -Value $loadAverage,
    Format-InfoLine -Label 'Uptime' -Value $uptimeDisplay,
    $separator,
    Format-InfoLine -Label 'CPU' -Value $cpuSummary,
    Format-InfoLine -Label 'RAM' -Value ('{0} MB, {1} MB ({2}%) free' -f $memoryReport.TotalMb, $memoryReport.FreeMb, $memoryReport.FreePercent),
    Format-InfoLine -Label 'Диск (/)' -Value ('{0}, {1} ({2}%) free' -f $diskReport.TotalDisplay, $diskReport.FreeDisplay, $diskReport.FreePercent),
    $separator
)

$lines | ForEach-Object { Write-Output $_ }
