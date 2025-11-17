# ============================================
# Script: Actualizar-SSH-Rapido.ps1
# Versión rápida sin análisis DISM
# ============================================

Write-Host "Habilitando el servicio de Windows Update..." -ForegroundColor Cyan
Set-Service wuauserv -StartupType Automatic
Start-Service wuauserv

Write-Host "Buscando actualizaciones..." -ForegroundColor Cyan
usoclient startscan

Write-Host "Descargando actualizaciones..." -ForegroundColor Cyan
usoclient startdownload

Start-Sleep -Seconds 3

Write-Host "Instalando actualizaciones..." -ForegroundColor Green
usoclient startinstall

Write-Host "`nProceso lanzado. Windows continuará en segundo plano." -ForegroundColor Yellow
