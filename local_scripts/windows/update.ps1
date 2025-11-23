# ============================================
# Script: Actualizar-SSH-Rapido.ps1
# Versión rápida sin análisis DISM
# ============================================

Write-Host "Enabling Windows Update service..." -ForegroundColor Cyan
Set-Service wuauserv -StartupType Automatic
Start-Service wuauserv

Write-Host "Searching for updates..." -ForegroundColor Cyan
UsoClient.exe StartInteractiveScan

#Showing update status
Write-Host "Showing update status..." -ForegroundColor Cyan
UsoClient.exe ScanInstallWait
Write-Host "Updates completed." -ForegroundColor Green
