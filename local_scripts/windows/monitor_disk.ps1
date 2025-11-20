# Prefer logical disk since it provides size and free space
if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
} else {
$disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
}

if ($null -eq $disk) {
Write-Host "Disk: Unknown" -ForegroundColor Yellow
exit
}

$totalGB = [math]::Round($disk.Size/1GB, 2)
$freeGB = [math]::Round($disk.FreeSpace/1GB, 2)
$usedGB = [math]::Round($totalGB - $freeGB, 2)
$percent = if ($totalGB -gt 0) { [math]::Round(($usedGB/$totalGB)*100, 0) } else { 0 }

Write-Host "Size: ${totalGB}GB | Used: ${usedGB}GB | Free: ${freeGB}GB | Usage: ${percent}%"