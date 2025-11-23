# ============================================
# Script: Actualizar-SSH-Rapido.ps1
# Versión rápida sin análisis DISM
# ============================================

Write-Host "Habilitando el servicio de Windows Update..." -ForegroundColor Cyan
Set-Service wuauserv -StartupType Automatic
Start-Service wuauserv

Write-Host "Buscando actualizaciones..." -ForegroundColor Cyan
usoclient StartInteractiveScan