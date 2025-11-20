# Simple, plain-text memory summary so SSH captures it reliably in the menu UI.
# Outputs a single line like: Total: XGB | Used: YGB | Free: ZGB | Used: P%

$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
if (-not $os) {
	Write-Host "Memory: Unknown"
	exit
}

# Values are in kilobytes
$totalKB = [double]$os.TotalVisibleMemorySize
$freeKB = [double]$os.FreePhysicalMemory

$totalGB = [math]::Round($totalKB / 1MB, 2)
$freeGB = [math]::Round($freeKB / 1MB, 2)
$usedGB = [math]::Round($totalGB - $freeGB, 2)
$usedPct = 0
if ($totalKB -gt 0) { $usedPct = [math]::Round((($totalKB - $freeKB)/$totalKB)*100, 2) }

Write-Host "Total: ${totalGB}GB | Used: ${usedGB}GB | Free: ${freeGB}GB | Used: ${usedPct}%"
