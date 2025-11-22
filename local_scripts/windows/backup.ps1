# ============================================================================
# SCRIPT DE BACKUP PARA WINDOWS (PowerShell)
# ============================================================================
# Este script crea un archivo comprimido de las rutas especificadas
# y retorna la ruta del archivo generado
# ============================================================================

param(
    [string]$Paths,      # Rutas separadas por espacios (ej: "C:\Users\Admin\Documents C:\inetpub")
    [string]$DestFolder  # Carpeta de destino para el backup
)

# Validar parámetros
if ([string]::IsNullOrEmpty($Paths) -or [string]::IsNullOrEmpty($DestFolder)) {
    Write-Error "Uso: .\backup.ps1 -Paths '<rutas>' -DestFolder '<destino>'"
    exit 1
}

# Configuración
$timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
$hostname = $env:COMPUTERNAME
$tempFile = "C:\Windows\Temp\backup-$hostname-$timestamp.tar.gz"

# Separar las rutas
$pathArray = $Paths -split ' '

Write-Host "Iniciando backup de Windows..."
Write-Host "Rutas a respaldar: $Paths"

# Verificar que las rutas existan
$validPaths = @()
foreach ($path in $pathArray) {
    if (Test-Path $path) {
        $validPaths += $path
        Write-Host "✓ Ruta válida: $path"
    } else {
        Write-Warning "✗ Ruta no encontrada: $path (se omitirá)"
    }
}

if ($validPaths.Count -eq 0) {
    Write-Error "ERROR: Ninguna ruta válida para respaldar"
    exit 1
}

# Crear el archivo tar.gz usando tar nativo de Windows 10/11
# (Windows 10 1803+ incluye tar.exe nativamente)
try {
    # Cambiar al directorio raíz para evitar problemas con rutas absolutas
    Push-Location C:\
    
    # Crear lista de rutas relativas
    $relativePaths = @()
    foreach ($path in $validPaths) {
        # Convertir C:\Users\Admin a Users\Admin
        $relativePath = $path -replace '^[A-Za-z]:\\', ''
        $relativePaths += $relativePath
    }
    
    Write-Host "Comprimiendo archivos..."
    
    # Usar tar nativo de Windows
    $tarArgs = @('-czf', $tempFile) + $relativePaths
    & tar.exe $tarArgs
    
    Pop-Location
    
    if (Test-Path $tempFile) {
        $fileSize = (Get-Item $tempFile).Length / 1MB
        Write-Host "✓ Backup completado exitosamente"
        Write-Host "Archivo: $tempFile"
        Write-Host "Tamaño: $([math]::Round($fileSize, 2)) MB"
        
        # Retornar la ruta del archivo (esto es lo que captura el script bash)
        Write-Output $tempFile
    } else {
        Write-Error "ERROR: No se pudo crear el archivo de backup"
        exit 1
    }
    
} catch {
    Write-Error "ERROR durante la compresión: $_"
    exit 1
}
