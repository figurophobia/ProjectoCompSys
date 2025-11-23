# ============================================================================
# BACKUP SCRIPT FOR WINDOWS (PowerShell)
# ============================================================================
# This script creates a compressed archive of specified paths
# and returns the path of the generated file
# ============================================================================

param(
    [string]$Paths,      # Paths separated by spaces (e.g.: "C:\Users\Admin\Documents C:\inetpub")
    [string]$DestFolder  # Destination folder for the backup
)

# Validate parameters
if ([string]::IsNullOrEmpty($Paths) -or [string]::IsNullOrEmpty($DestFolder)) {
    Write-Error "Usage: .\backup.ps1 -Paths '<paths>' -DestFolder '<destination>'"
    exit 1
}

# Configuration
$timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
$hostname = $env:COMPUTERNAME
$tempFile = "C:\Windows\Temp\backup-$hostname-$timestamp.tar.gz"

# Separate the paths
$pathArray = $Paths -split ' '

Write-Host "Starting Windows backup..."
Write-Host "Paths to backup: $Paths"

# Verify that paths exist
$validPaths = @()
foreach ($path in $pathArray) {
    if (Test-Path $path) {
        $validPaths += $path
        Write-Host "✓ Valid path: $path"
    } else {
        Write-Warning "✗ Path not found: $path (will be skipped)"
    }
}

if ($validPaths.Count -eq 0) {
    Write-Error "ERROR: No valid paths to backup"
    exit 1
}

# Create tar.gz file using Windows 10/11 native tar
# (Windows 10 1803+ includes tar.exe natively)
try {
    # Change to root directory to avoid issues with absolute paths
    Push-Location C:\
    
    # Create list of relative paths
    $relativePaths = @()
    foreach ($path in $validPaths) {
        # Convert C:\Users\Admin to Users\Admin
        $relativePath = $path -replace '^[A-Za-z]:\\', ''
        $relativePaths += $relativePath
    }
    
    Write-Host "Compressing files..."
    
    # Use Windows native tar
    $tarArgs = @('-czf', $tempFile) + $relativePaths
    & tar.exe $tarArgs
    
    Pop-Location
    
    if (Test-Path $tempFile) {
        $fileSize = (Get-Item $tempFile).Length / 1MB
        Write-Host "✓ Backup completed successfully"
        Write-Host "File: $tempFile"
        Write-Host "Size: $([math]::Round($fileSize, 2)) MB"
        
        # Return the file path (this is what the bash script captures)
        Write-Output $tempFile
    } else {
        Write-Error "ERROR: Could not create backup file"
        exit 1
    }
    
} catch {
    Write-Error "ERROR during compression: $_"
    exit 1
}
