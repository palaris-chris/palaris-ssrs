#------------------------------------------------------
# Prerequisites: Ensure SSRS REST API is enabled on your SSRS server.
#------------------------------------------------------

param (
    [string]$SourceServer = "PAL-NTL-SQL01",
    [string]$SourceInstance = "ReportServer",
    [string]$DestServer = "PMNTLMAN2",
    [string]$DestPath = "D$\Shares\SQLBackups\SQLReports\2019",
    [string]$LogFileName = "BackupSSRSReportServer.html"
)

# Prompt for credentials (this will securely prompt for username and password)
$credential = Get-Credential

# Define base URI for the SSRS REST API
$baseUri = "http://$SourceServer/$SourceInstance/api/v2.0"

# Functions to generate timestamps for logs and folders
function getTimestamp() {
    Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
}

function getFolderTimestamp() {
    Get-Date -Format "yyyy-MM-ddTHHmmss"
}

#  Log file time stamp:
$Timestamp = getTimestamp
#  Date for folder
$FolderTimestamp = getFolderTimestamp

# Set logfile path
$LogFile = "\\$DestServer\$DestPath\logs\$LogFileName"

# Create backup directory
$BackupPath = "\\$DestServer\$DestPath\$FolderTimestamp\"

if (-not (Test-Path $BackupPath)) {
    New-Item -ItemType directory -Path $BackupPath
}

# Ensure logs directory exists
$LogsPath = "\\$DestServer\$DestPath\logs"
if (-not (Test-Path $LogsPath)) {
    New-Item -ItemType directory -Path $LogsPath
}

# Create log file:
if (-not (Test-Path $LogFile)) {
    "$Timestamp New log created" | Out-File $LogFile -Append -Force
}

# Function to download report content (RDL file) via REST API
function Download-Report {
    param (
        [string]$ReportPath,
        [string]$DestPath
    )

    $encodedReportPath = [System.Web.HttpUtility]::UrlEncode($ReportPath)
    $reportUri = "$baseUri/reports(path='$encodedReportPath')/content"

    try {
        $response = Invoke-RestMethod -Uri $reportUri -Method Get -Credential $credential -OutFile $DestPath

        if ($response.StatusCode -eq 200) {
            "<br />$Timestamp Report $ReportPath downloaded successfully" | Out-File $LogFile -Append -Force
        }
    } catch {
        $ErrorMessage = $_.Exception.Message
        "<br />$Timestamp Error downloading report $ReportPath: $ErrorMessage" | Out-File $LogFile -Append -Force
    }
}

# Function to retrieve all folders and reports recursively
function Backup-FolderContent {
    param (
        [string]$FolderPath
    )

    # Encode folder path for the API request
    $encodedFolderPath = [System.Web.HttpUtility]::UrlEncode($FolderPath)

    # Retrieve folders and reports under the current folder
    $folderUri = "$baseUri/folders(path='$encodedFolderPath')/contents"
    $folderContents = Invoke-RestMethod -Uri $folderUri -Method Get -Credential $credential

    foreach ($item in $folderContents.value) {
        if ($item.type -eq "Folder") {
            # If it's a folder, recursively call this function
            Backup-FolderContent $item.path
        } elseif ($item.type -eq "Report") {
            # If it's a report, download it
            $reportDestPath = Join-Path $BackupPath -ChildPath "$($item.name).rdl"
            Download-Report $item.path $reportDestPath
        }
    }
}

# Perform backup of all folder contents starting at the root
try {
    Backup-FolderContent "/"
    "<br />$Timestamp Backup completed" | Out-File $LogFile -Append -Force
} catch {
    $ErrorMessage = $_.Exception.Message
    "<br />$Timestamp $ErrorMessage" | Out-File $LogFile -Append -Force
}
