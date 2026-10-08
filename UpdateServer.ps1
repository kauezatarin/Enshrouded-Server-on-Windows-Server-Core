# Enshrouded Dedicated Server update script for Windows Server Core
# Written by TripodGG

$attempts = 0

# Set the path for the error log
$errorLogFolder = "$env:USERPROFILE\enshrouded"
$errorLogPath = Join-Path -Path $errorLogFolder -ChildPath "update-error.log"

# Function to log errors
function Log-Error {
    param(
        [string]$ErrorMessage
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $errorLogPath -Value "$Timestamp - ERROR: $ErrorMessage"
}

do {
    # Increment the attempt counter
    $attempts++

    try {
        # Prompt the user for the search path
        $searchPath = Read-Host "Enter the directory where you installed your Enshrouded server"

        # Start transcript to capture console output
        Start-Transcript -Path $errorLogPath -Append

        # Search for enshrouded_server.exe
        $fileToSearch = "enshrouded_server.exe"
        $foundFile = Get-ChildItem -Path $searchPath -Filter $fileToSearch -Recurse | Select-Object -First 1

        # Check if the file is found
        if ($foundFile -ne $null) {
            $installDirectory = $foundFile.Directory.FullName

            # Run the specified SteamCMD command
            Write-Host "Updating Enshrouded Dedicated Server at $installDirectory..."
            & steamcmd "+force_install_dir" "$installDirectory" "+login" "anonymous" "+app_update" "2278520" "validate" "+quit"
            Write-Host "Enshrouded Server update executed successfully!"
        } else {
            throw "$fileToSearch not found in $searchPath or its subdirectories. Please try again."
        }
    }
    catch {
        Log-Error -ErrorMessage $_
        Write-Host "An error occurred: $_"
        
        # Check if the maximum number of attempts is reached
        if ($attempts -eq 3) {
            Write-Host "Maximum number of attempts reached. Please verify the install directory and run the update script again."
            break
        }
    }
    finally {
        # Stop transcript to close the log file
        Stop-Transcript
    }
} while ($foundFile -eq $null)
