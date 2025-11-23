# ============================================
# Script: Update-SSH-Quick.ps1
# Quick version without DISM analysis
# ============================================

Write-Host "Enabling Windows Update service..." -ForegroundColor Cyan
Set-Service wuauserv -StartupType Automatic
Start-Service wuauserv

Write-Host "Searching for updates..." -ForegroundColor Cyan
usoclient StartInteractiveScan