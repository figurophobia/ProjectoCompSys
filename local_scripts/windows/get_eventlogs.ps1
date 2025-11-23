<#
get_eventlogs.ps1
Retrieve recent Windows Event Logs (System and Application).
#>

param(
    [int]$MaxEvents = 100
)

Write-Host "=== Windows Event Logs (last $MaxEvents entries) ==="

Write-Host "-- System Log --"
try {
    Get-WinEvent -LogName System -MaxEvents $MaxEvents | ForEach-Object {
        $ts = $_.TimeCreated
        $lvl = $_.LevelDisplayName
        $src = $_.ProviderName
        $msg = $_.Message -replace '\r','' -replace '\n',' '
        Write-Host "$ts [$lvl] $src - $msg"
    }
} catch {
    # Fallback to Get-EventLog if Get-WinEvent unavailable
    Get-EventLog -LogName System -Newest $MaxEvents | ForEach-Object { Write-Host "$(\.TimeGenerated) [$(\.EntryType)] $(\.Source) - $(\.Message)" }
}

Write-Host ""
Write-Host "-- Application Log --"
try {
    Get-WinEvent -LogName Application -MaxEvents $MaxEvents | ForEach-Object {
        $ts = $_.TimeCreated
        $lvl = $_.LevelDisplayName
        $src = $_.ProviderName
        $msg = $_.Message -replace '\r','' -replace '\n',' '
        Write-Host "$ts [$lvl] $src - $msg"
    }
} catch {
    Get-EventLog -LogName Application -Newest $MaxEvents | ForEach-Object { Write-Host "$(\.TimeGenerated) [$(\.EntryType)] $(\.Source) - $(\.Message)" }
}
