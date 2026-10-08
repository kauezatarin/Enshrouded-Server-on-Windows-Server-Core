# Enshrouded Dedicated Server installation script for Windows Server Core
# Written by TripodGG

# Check the version of Windows Server to confirm it is a supported version
$osVersion = (Get-CimInstance Win32_OperatingSystem).Version

# Check if the OS is Windows Server 2016/2019
if ($osVersion -match '10\.0\.(14393|17763)') {
    Write-Host "Windows Server 2016/2019 detected."
}
# Check if the OS is Windows Server 2022
elseif ($osVersion -match '10\.0\.(20348)') {
    Write-Host "Windows Server 2022 detected."
}
# Check if the OS is Windows Server 2025
elseif ($osVersion -match '10\.0\.(26100)') {
    Write-Host "Windows Server 2025 detected."
}
else {
    Write-Host "Unsupported Windows Server version ($osVersion). Supported versions: Windows Server 2016, 2019, 2022, 2025."
	exit 1
}

# Enforce TLS 1.2 and TLS 1.3 for secure downloads
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13


# Function for error logging
function Log-Error {
    param (
        [string]$ErrorMessage
    )

    $LogPath = Join-Path $env:USERPROFILE -ChildPath "enshrouded\errorlog.txt"

    try {
        # Create the logs directory if it doesn't exist
        $LogsDirectory = Join-Path $env:USERPROFILE -ChildPath "enshrouded"
        if (-not (Test-Path $LogsDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $LogsDirectory -Force | Out-Null
        }

        # Append the error message with timestamp to the log file
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $LogMessage = "[$Timestamp] $ErrorMessage"
        $LogMessage | Out-File -Append -FilePath $LogPath

        # Inform the user about the error and the log location
        Write-Host "An error occurred. Check the log file for details: $LogPath"
    } catch {
        Write-Host "Failed to log the error. Please check the log file manually: $LogPath"
    }
}

# Function to check for an active Internet connection
function Test-InternetConnection {
    $pingResult = Test-Connection -ComputerName "www.google.com" -Count 1 -ErrorAction SilentlyContinue

    if ($pingResult -eq $null) {
        Log-Error "No active internet connection detected. Please ensure that you are connected to the internet before running this script."
        exit 1
    } else {
        Write-Host "Internet connection detected. Proceeding with the script..."
    }
}

# Call the function to check for an active internet connection
Test-InternetConnection

# Check if NuGet package provider is installed
if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
    try {
        # NuGet is not installed, so install it silently
        Write-Host "Installing NuGet package provider..."
        Install-PackageProvider -Name NuGet -Force -ForceBootstrap -Scope CurrentUser -Confirm:$false
    } catch {
        $errorMessage = "Failed to install NuGet package provider. Error: $_"
        Log-Error $errorMessage
        exit 1
    }
}

# Make sure all Windows updates have been applied - This can also be done from sconfig under option 6
# Install the PSWindowsUpdate module
Install-Module -Name PSWindowsUpdate -Force

# Import the module
Import-Module PSWindowsUpdate

# Set the execution policy
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# Check for and install KB5009608 only on Windows Server 2022 (fixes RDP issue with App Compatibility)
if ($osVersion -match '10\.0\.20348') {
    $kbNumber = 'KB5009608'
    $installedUpdate = Get-HotFix | Where-Object {$_.HotFixID -eq $kbNumber}

    if ($installedUpdate) {
        Write-Host "$kbNumber is already installed on this system."
    } else {
        # Prompt the user to install KB5009608
        $userChoice = Read-Host -Prompt "$kbNumber is recommended for Windows Server 2022 compatibility. Do you want to install $kbNumber? (Y/N)"

        if ($userChoice -eq 'Y' -or $userChoice -eq 'Yes') {
            Get-WindowsUpdate -KBArticleID $kbNumber -Install -AcceptAll
            Write-Host "Installing $kbNumber..."
        } else {
            Write-Host "Installation of $kbNumber canceled."
        }
    }
}

# Check for and install any additional updates
Get-WindowsUpdate -Install -AcceptAll

# Function to check if a reboot is pending due to updates
function Check-And-RebootIfNeeded {
    $pendingReboot = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' -ErrorAction SilentlyContinue).RebootRequired

    if ($pendingReboot) {
        # Reboot is required, prompt the user and proceed with reboot if agreed
        $rebootChoice = Read-Host -Prompt "A reboot is required to install updates. Would you like to reboot now? (Y/N)"

        if ($rebootChoice -eq 'Y' -or $rebootChoice -eq 'y') {
            Write-Host "Rebooting the machine. Please run the script again after the server reboot."
            Restart-Computer -Force
        } else {
            Write-Host "You chose not to reboot. The script will now exit. Please manually reboot the server and run the script again."
            return $false
        }
    } else {
        # No reboot is required
        Write-Host "No reboot is required at the moment."
    }

    return $true
}

# Check and reboot if needed
$rebootCompleted = Check-And-RebootIfNeeded

# Check the version of Windows Server and add the correct Windows desktop application compatibility files
$osVersion = (Get-CimInstance Win32_OperatingSystem).Version

# Check if the OS is Windows Server 2016/2019
if ($osVersion -match '10\.0\.(14393|17763)') {
    Write-Host "Installing App Compatibility Tools for Windows Server 2016/2019."
    # Run the command for Server 2016 or 2019
    Add-WindowsCapability -Online -Name ServerCore.AppCompatibility
}
# Check if the OS is Windows Server 2022 or 2025
elseif ($osVersion -match '10\.0\.(20348|26100)') {
    $serverNameVer = if ($osVersion -match '26100') { "Windows Server 2025" } else { "Windows Server 2022" }
    Write-Host "Checking App Compatibility Tools for $serverNameVer..."
    $appCompat = Get-WindowsCapability -Online -Name "ServerCore.AppCompatibility~~~~0.0.1.0" -ErrorAction SilentlyContinue
    if ($appCompat -and $appCompat.State -eq 'Installed') {
        Write-Host "App Compatibility Tools are already installed."
    } else {
        Write-Host "Installing App Compatibility Tools for $serverNameVer..."
        Add-WindowsCapability -Online -Name ServerCore.AppCompatibility~~~~0.0.1.0
    }
}
else {
    Write-Host "Continuing with installation..."
}

# Install DirectX Configuration Database if not already present
$dxCompat = Get-WindowsCapability -Online -Name "DirectX.Configuration.Database~~~~0.0.1.0" -ErrorAction SilentlyContinue
if ($dxCompat -and $dxCompat.State -eq 'Installed') {
    Write-Host "DirectX Configuration Database is already installed."
} else {
    Write-Host "Installing DirectX Configuration Database..."
    try {
        Add-WindowsCapability -Online -Name DirectX.Configuration.Database~~~~0.0.1.0 -ErrorAction Stop
    } catch {
        Write-Host "DirectX Configuration Database capability installation skipped or not required: $_"
    }
}

# Check to see if apps are already installed and install them if they are not
# Function to check if a command is available
function CommandExists($command) {
    Get-Command $command -ErrorAction SilentlyContinue
}

# Check if Scoop is installed
if (-not (CommandExists 'scoop')) {
    try {
        # Scoop is not installed, so install it
        Write-Host "Scoop is not installed. Installing Scoop..."
        
        # Run the Scoop installation command with elevated privileges
        iex "& {$(irm get.scoop.sh)} -RunAsAdmin"

        # Check if Scoop installation was successful
        if (CommandExists 'scoop') {
            Write-Host "Scoop installed successfully."
        } else {
            $errorMessage = "Failed to install Scoop. Please check your internet connection and try again."
            Log-Error $errorMessage
            exit 1
        }
    } catch {
        $errorMessage = "An unexpected error occurred during Scoop installation. Error: $_"
        Log-Error $errorMessage
        exit 1
    }
} else {
    # Scoop is already installed
    Write-Host "Scoop is already installed. Skipping installation."
}

# Check if Chocolatey is installed
if (-not (CommandExists 'choco')) {
    try {
        # Chocolatey is not installed, so install it
        Write-Host "Chocolatey is not installed. Installing Chocolatey..."
        
        # Run the Chocolatey installation command with elevated privileges
        Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

        # Check if Chocolatey installation was successful
        if (CommandExists 'choco') {
            Write-Host "Chocolatey installed successfully."
        } else {
            $errorMessage = "Failed to install Chocolatey. Please check your internet connection and try again."
            Log-Error $errorMessage
            exit 1
        }
    } catch {
        $errorMessage = "An unexpected error occurred during Chocolatey installation. Error: $_"
        Log-Error $errorMessage
        exit 1
    }
} else {
    # Chocolatey is already installed
    Write-Host "Chocolatey is already installed. Skipping installation."
}

# Check if Git is installed
if (-not (CommandExists 'git')) {
    try {
        # Git is not installed, so install it using Chocolatey
        Write-Host "Git is not installed. Installing Git..."
        scoop install git

        # Check if Git installation was successful
        if (CommandExists 'git') {
            Write-Host "Git installed successfully."
        } else {
            $errorMessage = "Failed to install Git. Please check your internet connection and try again."
            Log-Error $errorMessage
            exit 1
        }
    } catch {
        $errorMessage = "An unexpected error occurred during Git installation. Error: $_"
        Log-Error $errorMessage
        exit 1
    }
} else {
    # Git is already installed
    Write-Host "Git is already installed. Skipping installation."
}

# Check if Scoop Extras bucket is added
if (-not (Test-Path "$env:USERPROFILE\scoop\buckets\extras")) {
    try {
        # Scoop Extras bucket is not added, so add it
        Write-Host "Scoop Extras bucket is not added. Adding Scoop Extras bucket..."
        
        # Run the Scoop command to add the Extras bucket
        scoop bucket add extras

        # Check if Scoop Extras bucket addition was successful
        if (Test-Path "$env:USERPROFILE\scoop\buckets\extras") {
            Write-Host "Scoop Extras bucket added successfully."
        } else {
            $errorMessage = "Failed to add Scoop Extras bucket. Please check your internet connection and try again."
            Log-Error $errorMessage
            exit 1
        }
    } catch {
        $errorMessage = "An unexpected error occurred during Scoop Extras bucket addition. Error: $_"
        Log-Error $errorMessage
        exit 1
    }
} else {
    # Scoop Extras bucket is already added
    Write-Host "Scoop Extras bucket is already added. Skipping addition."
}

# Check if Nano for Windows is installed
if (-not (CommandExists 'nano')) {
    try {
        # Nano for Windows is not installed, so install it using Scoop
        Write-Host "Nano for Windows is not installed. Installing Nano for Windows..."
        scoop install nano

        # Check if Nano for Windows installation was successful
        if (CommandExists 'nano') {
            Write-Host "Nano for Windows installed successfully."
        } else {
            $errorMessage = "Failed to install Nano for Windows. Please check your internet connection and try again."
            Log-Error $errorMessage
            exit 1
        }
    } catch {
        $errorMessage = "An unexpected error occurred during Nano for Windows installation. Error: $_"
        Log-Error $errorMessage
        exit 1
    }
} else {
    # Nano for Windows is already installed
    Write-Host "Nano for Windows is already installed. Skipping installation."
}

# Check if NSSM is installed
if (-not (Get-Command nssm -ErrorAction SilentlyContinue)) {
    try {
        # NSSM is not installed, so install it using Chocolatey
        Write-Host "NSSM is not installed. Installing NSSM..."
        choco install nssm -y

        # Check if NSSM installation was successful
        if (Get-Command nssm -ErrorAction SilentlyContinue) {
            Write-Host "NSSM installed successfully."
        } else {
            $errorMessage = "Failed to install NSSM. Please check the Chocolatey logs for more information."
            Log-Error $errorMessage
            exit 1
        }
    } catch {
        $errorMessage = "An unexpected error occurred during NSSM installation. Error: $_"
        Log-Error $errorMessage
        exit 1
    }
} else {
    # NSSM is already installed
    Write-Host "NSSM is already installed. Skipping installation."
}

# Check if SteamCMD is installed
if (-not (CommandExists 'steamcmd')) {
    try {
        # SteamCMD is not installed, so install it using Scoop
        Write-Host "SteamCMD is not installed. Installing SteamCMD..."
        scoop install steamcmd

        # Check if SteamCMD installation was successful
        if (CommandExists 'steamcmd') {
            Write-Host "SteamCMD installed successfully."
        } else {
            $errorMessage = "Failed to install SteamCMD. Please check your internet connection and try again."
            Log-Error $errorMessage
            exit 1
        }
    } catch {
        $errorMessage = "An unexpected error occurred during SteamCMD installation. Error: $_"
        Log-Error $errorMessage
        exit 1
    }
} else {
    # SteamCMD is already installed
    Write-Host "SteamCMD is already installed. Skipping installation."
}

# Function to check if Visual C++ Redistributable 2015-2022 is installed
function Check-VCRedist2022Installed {
    $redistVersion = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -ErrorAction SilentlyContinue
    return ($null -ne $redistVersion)
}

# Function to check if Visual C++ Redistributable is installed
function Check-VCRedist {
    if (Check-VCRedist2022Installed) {
        Write-Host "Visual C++ 2015-2022 Redistributable (x64) is already installed."
    } else {
        Install-VCRedist
    }
}

# Function to install Visual C++ Redistributable using Chocolatey
function Install-VCRedist {
    try {
        Write-Host "Installing Visual C++ Redistributable using Chocolatey..."
        choco install vcredist-all -y
        Write-Host "Visual C++ Redistributable installed successfully."
    } catch {
        # Handle unexpected error during installation
        $errorMessage = "An unexpected error occurred while installing Visual C++ Redistributable. Error: $_"
        Log-Error $errorMessage
        exit 1
    }
}

# Check if Visual C++ Redistributable is installed
Check-VCRedist

# Function to prompt user for install path
function Get-ValidDirectory {
    $attempts = 0

    do {
        # Prompt user for the installation directory
        $installPath = Read-Host "Enter the directory where you would like to install the dedicated server. (i.e. 'C:\EnshroudedServer')"

        # Check if the path is valid
        if (Test-Path $installPath -IsValid) {
            # Check if the path is a container (directory)
            if (-not (Test-Path $installPath -PathType Container)) {
                # Prompt user to create the directory
                $createDirectory = Read-Host "The directory does not exist. Would you like to create it? (yes/no)"
                if ($createDirectory -eq 'y' -or $createDirectory -eq 'yes') {
                    try {
                        # Attempt to create the directory
                        New-Item -ItemType Directory -Path $installPath -Force | Out-Null
                        Write-Host "Directory created successfully at $installPath"
                    } catch {
                        # Handle unexpected error during directory creation
                        $errorMessage = "An unexpected error occurred while creating the installation directory. Error: $_"
                        Log-Error $errorMessage
                        exit 1
                    }
                } elseif ($createDirectory -eq 'n' -or $createDirectory -eq 'no') {
                    # User chose not to create the directory
                    Write-Host "Installation directory not created. Please choose a valid directory."
                    continue
                } else {
                    # Invalid input for createDirectory
                    Write-Host "Invalid input. Please enter 'yes' or 'no'."
                    continue
                }
            }
            # Return the validated installation path
            return $installPath
        } else {
            # Invalid path entered by the user
            Write-Host "Invalid path. Please enter a valid directory path."
        }

        # Increment attempts and exit if reached the limit
        $attempts++
        if ($attempts -eq 3) {
            Write-Host "Failed after 3 attempts. Exiting script."
            exit 1
        }
    } while ($true)
}

# Success message
try {
    # Call the Get-ValidDirectory function
    $installDirectory = Get-ValidDirectory
    Write-Host "Success! The dedicated server will be installed to $installDirectory"
} catch {
    # Handle unexpected error during the installation directory prompt
    $errorMessage = "An unexpected error occurred during the installation directory prompt. Error: $_"
    Log-Error $errorMessage
    exit 1
}

# Install Enshrouded dedicated server 
& steamcmd "+force_install_dir" "$installDirectory" "+login" "anonymous" "+app_update" "2278520" "validate" "+quit"

# Create the Enshrouded config file and write the contents of the file
# Prompt the user for server name
$serverName = Read-Host -Prompt "Enter the name you would like to use for your game server"

# Prompt the user for server password
$serverPassword = Read-Host -Prompt "Enter the password you would like to use for your game server"

# Prompt the user for the game port with default value 15636
$defaultGamePort = 15636
$gamePort = Read-Host -Prompt "Enter the game port to be used (press enter to use default port: $defaultGamePort)"
if (-not $gamePort) {
    $gamePort = $defaultGamePort
}

# Prompt the user for the query port with default value 15637
$defaultQueryPort = 15637
$queryPort = Read-Host -Prompt "Enter the query port to be used (press enter to use default port: $defaultQueryPort)"
if (-not $queryPort) {
    $queryPort = $defaultQueryPort
}

# Ensure that the query port is not more than 1 higher than the game port
while ($queryPort -gt ($gamePort + 1)) {
    Write-Host "Error: The query cannot be more than one port number higher than the game port."
    $gamePort = Read-Host -Prompt "Enter the game port (press enter to use default port: $defaultGamePort)"
    if (-not $gamePort) {
        $gamePort = $defaultGamePort
    }
    $queryPort = Read-Host -Prompt "Enter the query port (press enter to use default port: $defaultQueryPort)"
    if (-not $queryPort) {
        $queryPort = $defaultQueryPort
    }
}

# Prompt the user for the number of players allowed (with a maximum of 16)
$maxPlayers = Read-Host -Prompt "Enter the maximum number of players (up to 16)"
$maxPlayers = [math]::Min(16, [math]::Max(1, [int]$maxPlayers)) # Ensure the value is between 1 and 16

# Define the JSON object
$jsonObject = @{
    "name"          = $serverName
    "password"      = $serverPassword
    "saveDirectory" = "./savegame"
    "logDirectory"  = "./logs"
    "ip"            = "0.0.0.0"
    "gamePort"      = $gamePort
    "queryPort"     = $queryPort
    "slotCount"     = $maxPlayers
}

# Convert the JSON object to a JSON string
$jsonString = $jsonObject | ConvertTo-Json

# Set the file path
$filePath = "$installDirectory\enshrouded_server.json"

# Save the JSON string to the file
$jsonString | Set-Content -Path $filePath

Write-Host "Configuration saved to $filePath"

# Function to check and create firewall rules
function CheckAndCreateFirewallRule($port, $protocol, $ruleName) {
    $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

    if (-not $existingRule) {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol $protocol -LocalPort $port
        Write-Host "Firewall rule for $protocol port $port created."
    } else {
        Write-Host "Firewall rule for $protocol port $port already exists. Skipping creation."
    }
}

# Check and create firewall rules (Enshrouded uses UDP for game and query traffic, TCP can also be allowed)
CheckAndCreateFirewallRule $gamePort "UDP" "EnshroudedGamePortUDP"
CheckAndCreateFirewallRule $gamePort "TCP" "EnshroudedGamePortTCP"
CheckAndCreateFirewallRule $queryPort "UDP" "EnshroudedQueryPort"

# Create a shortcut link to the Enshrouded server application in the home directory. This will allow you to run the server at logon by typing '.\enserver.lnk' 
$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$Home\enserver.lnk")
$Shortcut.TargetPath = "$installDirectory\enshrouded_server.exe"
$Shortcut.Save()

# Function to create a scheduled backup
function Create-ServerBackupScheduledTask {
    param (
        [string]$installDirectory,
        [string]$defaultBackupDirectory
    )

    # Prompt for backup directory location
    do {
        $backupDirectory = Read-Host "Enter the location for the backup directory (default: $defaultBackupDirectory)"
        if (-not $backupDirectory) {
            $backupDirectory = $defaultBackupDirectory
        }

        # Check if the directory exists
        if (Test-Path $backupDirectory) {
            $createNewDirectory = $null
            # Directory exists, ask for confirmation to use it
            while ($createNewDirectory -notin @('Y', 'N')) {
                $createNewDirectory = Read-Host "The directory '$backupDirectory' already exists. Do you want to use it? (Y/N)"
            }
            if ($createNewDirectory -eq 'N') {
                continue
            }
        } else {
            $createNewDirectory = $null
            # Directory doesn't exist, ask for confirmation to create it
            while ($createNewDirectory -notin @('Y', 'N')) {
                $createNewDirectory = Read-Host "The directory '$backupDirectory' does not exist. Do you want to create it? (Y/N)"
            }
            if ($createNewDirectory -eq 'Y') {
                New-Item -ItemType Directory -Path $backupDirectory | Out-Null
            } else {
                continue
            }
        }
    } while (-not (Test-Path $backupDirectory))

    # Ensure $backupDirectory is not inside $installDirectory
    if ($backupDirectory -like "$installDirectory*") {
        Write-Host "Error: Backup directory cannot be inside the install directory."
        return
    }

    # Prompt for task frequency
    $taskFrequencyInput = Read-Host "How often should the backup run? (Daily, Weekly, Bi-weekly, Monthly) [Default: Daily]"
    switch -Regex ($taskFrequencyInput) {
        "Weekly"    { $sc = "WEEKLY"; $mo = 1 }
        "Bi-weekly" { $sc = "WEEKLY"; $mo = 2 }
        "Monthly"   { $sc = "MONTHLY"; $mo = 1 }
        Default     { $sc = "DAILY"; $mo = 1 }
    }

    # Prompt for task execution time
    $taskExecutionTime = $null
    while (-not $taskExecutionTime) {
        $taskExecutionTime = Read-Host "What time should the backup run? (24-hour format, e.g., 14:30)"
    }

    # Create the scheduled task using schtasks.exe with properly escaped quotes and valid schedule parameters
    $robocopyCmd = "robocopy `"$installDirectory`" `"$backupDirectory`" /MIR /R:0 /W:0 /NFL /NDL /NP"
    $taskName = "Enshrouded Server Backup"
    if ($sc -eq "WEEKLY" -and $mo -eq 2) {
        schtasks.exe /Create /TN $taskName /TR $robocopyCmd /SC WEEKLY /MO 2 /ST $taskExecutionTime /F
    } else {
        schtasks.exe /Create /TN $taskName /TR $robocopyCmd /SC $sc /ST $taskExecutionTime /F
    }

    Write-Host "Scheduled task '$taskName' created successfully."
}

# Create the scheduled task
$defaultBackupDirectory = "C:\EnshroudedBackups"
Create-ServerBackupScheduledTask -installDirectory $installDirectory -defaultBackupDirectory $defaultBackupDirectory

# Create a new service to auto-start the Enshrouded server
# Define the executable path
$executablePath = Join-Path $installDirectory "enshrouded_server.exe"

# Define the service name
$serviceName = "EnshroudedServer"

# Use NSSM to create a new service
$arguments = @(
    "install", $serviceName, $executablePath,
    "-DelayedAutoStart", # Enable delayed startup
    "-DisplayName", "Enshrouded Server", # Display name for the service
    "-Description", "Service for the Enshrouded Server application" # Description for the service
)

try {
    Start-Process "nssm.exe" -ArgumentList $arguments -Wait -NoNewWindow
    Write-Host "Service 'Enshrouded Server' created successfully."
} catch {
    $errorMessage = "An error occurred while creating the service. Error: $_"
    Log-Error $errorMessage
    exit 1
}

# Echo the completion of the script and provide the command to start the server app.
Write-Output "Enshrouded dedicated server has successfully been installed. Use '.\enserver.lnk' to start the game server app."

# Prompt the user to reboot the server
$userChoice = Read-Host -Prompt "A reboot is required for changes to take effect. The Enshrouded server will not run until a reboot is completed. Do you want to reboot now? (Y/N)"

if ($userChoice -eq 'Y' -or $userChoice -eq 'Yes') {
    Write-Host "Rebooting the server..."
    # Invoke the restart command
    Restart-Computer -Force
} else {
    Write-Host "The Enshrouded server will not run until a reboot is completed. Please reboot at your earliest convenience."
}