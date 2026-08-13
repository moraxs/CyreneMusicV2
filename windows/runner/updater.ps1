# Cyrene Music Standalone Updater
# This script runs after the main program closes to replace files and restart the app

param(
    [Parameter(Mandatory=$true)]
    [string]$InstallDir,      # Installation directory (target directory to update)
    
    [Parameter(Mandatory=$true)]
    [string]$UpdateDir,       # Update files directory (extracted temporary directory)
    
    [Parameter(Mandatory=$true)]
    [string]$ExePath,         # Main program executable path
    
    [Parameter(Mandatory=$false)]
    [int]$WaitSeconds = 3     # Seconds to wait for main program to exit
)

# Ensure log file path
$logPath = Join-Path $InstallDir "updater.log"

# Log function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage
    try {
        Add-Content -Path $logPath -Value $logMessage -ErrorAction Stop
    } catch {
        Write-Host "Warning: Cannot write to log file - $_"
    }
}

Write-Log "========================================="
Write-Log "Cyrene Music Updater Started"
Write-Log "Install Directory: $InstallDir"
Write-Log "Update Directory: $UpdateDir"
Write-Log "Main Program Path: $ExePath"
Write-Log "Log File: $logPath"
Write-Log "========================================="

# Validate parameters
Write-Log "Validating parameters..."
if (-not (Test-Path $InstallDir)) {
    Write-Log "ERROR: Install directory does not exist: $InstallDir"
    exit 1
}

if (-not (Test-Path $UpdateDir)) {
    Write-Log "ERROR: Update directory does not exist: $UpdateDir"
    exit 1
}

Write-Log "OK - Parameters validated"

# Wait for main program to exit
Write-Log "Waiting for main program to exit ($WaitSeconds seconds)..."
Start-Sleep -Seconds $WaitSeconds

# Check if main program process is still running
$processName = [System.IO.Path]::GetFileNameWithoutExtension($ExePath)
$runningProcesses = Get-Process -Name $processName -ErrorAction SilentlyContinue

if ($runningProcesses) {
    Write-Log "Main program still running, attempting to force quit..."
    foreach ($proc in $runningProcesses) {
        try {
            $proc.Kill()
            $proc.WaitForExit(5000)
            Write-Log "Terminated process PID: $($proc.Id)"
        } catch {
            Write-Log "Warning: Cannot terminate process PID: $($proc.Id) - $_"
        }
    }
    Start-Sleep -Seconds 2
}

# Start copying files
Write-Log "Starting file copy..."
Write-Log "Source Directory (UpdateDir): $UpdateDir"
Write-Log "Target Directory (InstallDir): $InstallDir"

$successCount = 0
$failCount = 0
$skippedFiles = @()

try {
    # Recursively copy all files
    Write-Log "Scanning update directory..."
    $updateFiles = Get-ChildItem -Path $UpdateDir -Recurse -File
    $totalFiles = $updateFiles.Count
    Write-Log "Found $totalFiles files to update"
    
    # Show first few file paths for debugging
    if ($updateFiles.Count -gt 0) {
        Write-Log "Sample file paths (first 3):"
        foreach ($file in $updateFiles | Select-Object -First 3) {
            Write-Log "  Source: $($file.FullName)"
            $relativePath = $file.FullName.Substring($UpdateDir.Length).TrimStart('\', '/')
            $targetPath = Join-Path $InstallDir $relativePath
            Write-Log "  Target: $targetPath"
        }
    }
    
    Write-Log "Starting file copy..."
    $current = 0
    foreach ($file in $updateFiles) {
        $current++
        $relativePath = $file.FullName.Substring($UpdateDir.Length).TrimStart('\', '/')
        $targetPath = Join-Path $InstallDir $relativePath
        
        try {
            # Ensure target directory exists
            $targetDir = Split-Path $targetPath -Parent
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            
            # Copy file with force overwrite
            Copy-Item -Path $file.FullName -Destination $targetPath -Force -ErrorAction Stop
            $successCount++
            
            # Log important files specifically
            if ($relativePath -like "*.exe" -or $relativePath -like "*.dll") {
                Write-Log "OK - Copied critical file: $relativePath"
            }
            
            # Output progress every 10 files
            if ($current % 10 -eq 0 -or $current -eq $totalFiles) {
                $percent = [math]::Round(($current / $totalFiles) * 100, 2)
                Write-Log "Progress: $current/$totalFiles ($percent%) - Success: $successCount, Failed: $failCount"
            }
        } catch {
            $failCount++
            $skippedFiles += $relativePath
            Write-Log "Warning: Cannot update file $relativePath"
            Write-Log "  Error details: $_"
            Write-Log "  Source file: $($file.FullName)"
            Write-Log "  Target path: $targetPath"
        }
    }
    
    Write-Log "========================================="
    Write-Log "File update completed"
    Write-Log "Success: $successCount, Failed: $failCount"
    
    if ($skippedFiles.Count -gt 0) {
        Write-Log "Skipped files ($($skippedFiles.Count)):"
        foreach ($file in $skippedFiles | Select-Object -First 20) {
            Write-Log "  - $file"
        }
        if ($skippedFiles.Count -gt 20) {
            Write-Log "  ... and $($skippedFiles.Count - 20) more files"
        }
    }
    
} catch {
    Write-Log "ERROR: Exception occurred during update - $_"
    Write-Log $_.Exception.StackTrace
}

# Clean up temporary update directory
Write-Log "Cleaning up temporary files..."
try {
    if (Test-Path $UpdateDir) {
        Remove-Item -Path $UpdateDir -Recurse -Force -ErrorAction Stop
        Write-Log "Temporary directory deleted: $UpdateDir"
    }
} catch {
    Write-Log "Warning: Cannot delete temporary directory - $_"
}

# Restart application
Write-Log "Preparing to start new version..."
Start-Sleep -Seconds 1

if (Test-Path $ExePath) {
    try {
        Write-Log "Starting: $ExePath"
        # Use cmd /c start to launch application in a completely independent process
        # This ensures the app doesn't close when PowerShell exits or is terminated
        $startCmd = "cmd.exe"
        $startArgs = @("/c", "start", '""', "`"$ExePath`"")
        Start-Process -FilePath $startCmd -ArgumentList $startArgs -WorkingDirectory $InstallDir -WindowStyle Hidden
        Write-Log "Application started (independent process)"
    } catch {
        Write-Log "ERROR: Cannot start application - $_"
        Write-Log "Attempting fallback method..."
        try {
            # Fallback: direct Start-Process
            Start-Process -FilePath $ExePath -WorkingDirectory $InstallDir
            Write-Log "Application started (fallback method)"
        } catch {
            Write-Log "ERROR: Fallback also failed - $_"
            # If unable to start, at least open the install directory for manual start
            Start-Process explorer.exe -ArgumentList $InstallDir
        }
    }
} else {
    Write-Log "ERROR: Main program file not found: $ExePath"
}

Write-Log "Updater task completed"
Write-Log "========================================="

# Exit immediately - no need to delay since the app is now independent
exit 0

