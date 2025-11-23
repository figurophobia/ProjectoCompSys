$hostname = hostname

# Try Get-NetIPAddress; fallback to WMI-based IP retrieval
$ip = $null
if (Get-Command Get-NetIPAddress -ErrorAction SilentlyContinue) {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { -not ($_.IPAddress.StartsWith('127')) -and $_.IPAddress -ne $null } | Select-Object -First 1 -ExpandProperty IPAddress) -join ''
}
if (-not $ip) {
    # Fallback using WMI
    $nic = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPAddress -ne $null } | Select-Object -First 1
    if ($nic -and $nic.IPAddress) { $ip = $nic.IPAddress[0] }
}
if (-not $ip) { $ip = "N/A" }

$os = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
$uptime = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).LastBootUpTime

Write-Host "Host: $hostname"
Write-Host "IP: $ip"
Write-Host "OS: $os"
Write-Host "Last Boot: $uptime"
