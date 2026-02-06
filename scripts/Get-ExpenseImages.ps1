###############################
# Chrome River Expense Image Retrieval Script
# PowerShell 5.1 Compatible Version - Optimized
# Uses Runspaces for parallel downloads
###############################

###############################
# Load Configuration
###############################
Write-Host "Loading configuration..." -ForegroundColor Cyan
try {
    # Dot-source the configuration helper function
    . (Join-Path $PSScriptRoot "Get-Configuration.ps1")
    $config = Get-ChromeRiverConfiguration

    # Extract configuration settings
    $companyName = $config.CompanyName
    $baseUrl = $config.ChromeRiverAPI.BaseUrl
    $daysBack = $config.ChromeRiverAPI.DaysBack
    $maxParallelDownloads = $config.ChromeRiverAPI.MaxParallelDownloads
    $outputFolder = $config.OutputSettings.OutputFolder
    $masterListFile = $config.OutputSettings.MasterListFile
    $expenseListFile = $config.OutputSettings.ExpenseListFile
    $errorLogPrefix = $config.OutputSettings.ErrorLogPrefix

    # API Parameters
    $getMileageDetails = $config.APIParameters.GetMileageDetails.ToString().ToLower()
    $getImage = $config.APIParameters.GetImage.ToString().ToLower()
    $getPDFReport = $config.APIParameters.GetPDFReport.ToString().ToLower()
    $getPDFReportWithNotes = $config.APIParameters.GetPDFReportWithNotes.ToString().ToLower()
    $imageFirst = $config.APIParameters.ImageFirst.ToString().ToLower()
    $failOnImageFetchError = $config.APIParameters.FailOnImageFetchError.ToString().ToLower()

    Write-Host "[OK] Configuration loaded for: $companyName" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nPlease create config.json from config.template.json and configure it for your company.`n" -ForegroundColor Yellow
    exit 1
}

###############################
# Load Secure Credentials
###############################
Write-Host "Loading secure credentials..." -ForegroundColor Cyan
try {
    # Dot-source the credential helper function
    . (Join-Path $PSScriptRoot "Get-SecureCredentials.ps1")
    $credentials = Get-ChromeRiverCredentials

    # Extract credentials (these will only exist in memory, not in logs)
    $apiKey = $credentials.ApiKey
    $chainId = $credentials.ChainId
    $customerCode = $credentials.CustomerCode

    Write-Host "OK Credentials loaded successfully (Encrypted by: $($credentials.CreatedBy) on $($credentials.CreatedOn))" -ForegroundColor Green
}
catch {
    Write-Host "X ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nPlease run Setup-SecureCredentials.ps1 first to configure your API credentials.`n" -ForegroundColor Yellow
    exit 1
}

###############################
# Initialize
###############################
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$startTime = Get-Date
$errorLogFile = "$($errorLogPrefix)_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Statistics tracking (using synchronized hashtable for thread safety)
$stats = [hashtable]::Synchronized(@{
    Total = 0
    Downloaded = 0
    Skipped = 0
    Failed = 0
    AlreadyExists = 0
})

###############################
# Validate Output Folder Access
###############################
Write-Host "Validating output folder..." -ForegroundColor Cyan

# Check if the path is valid (not empty, no invalid characters)
if ([string]::IsNullOrWhiteSpace($outputFolder)) {
    Write-Host "[ERROR] Output folder path is empty or invalid in config.json" -ForegroundColor Red
    Write-Host "Please set OutputSettings.OutputFolder to a valid path.`n" -ForegroundColor Yellow
    exit 1
}

# Create output folder if it doesn't exist
if (!(Test-Path $outputFolder)) {
    try {
        Write-Host "Output folder does not exist. Creating: $outputFolder" -ForegroundColor Yellow
        New-Item $outputFolder -ItemType "directory" -Force | Out-Null
        Write-Host "[OK] Output folder created successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to create output folder: $outputFolder" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "`nPossible causes:" -ForegroundColor Yellow
        Write-Host "  - Invalid path or characters in the path" -ForegroundColor Yellow
        Write-Host "  - Insufficient permissions to create the directory" -ForegroundColor Yellow
        Write-Host "  - Parent directory does not exist or is inaccessible`n" -ForegroundColor Yellow
        exit 1
    }
}
else {
    Write-Host "Output folder exists: $outputFolder" -ForegroundColor Green
}

# Test write permissions by creating a temporary test file
$testFile = Join-Path $outputFolder ".write_test_$(Get-Date -Format 'yyyyMMddHHmmss').tmp"
try {
    # Attempt to write to the folder
    [System.IO.File]::WriteAllText($testFile, "write test")

    # If successful, delete the test file
    Remove-Item $testFile -Force -ErrorAction SilentlyContinue

    Write-Host "[OK] Write permissions verified for output folder" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Cannot write to output folder: $outputFolder" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nPossible causes:" -ForegroundColor Yellow
    Write-Host "  - Folder is read-only" -ForegroundColor Yellow
    Write-Host "  - Insufficient permissions (run as administrator if needed)" -ForegroundColor Yellow
    Write-Host "  - Folder is on a network drive that is unavailable" -ForegroundColor Yellow
    Write-Host "  - Disk is full or write-protected`n" -ForegroundColor Yellow
    exit 1
}

# OPTIMIZATION: Load $masterListFile into memory ONCE (HashSet for O(1) lookup)
$processedExpenses = @{}
if (Test-Path "$masterListFile") {
    Get-Content "$masterListFile" | ForEach-Object {
        if ($_ -and $_.Trim()) {
            $processedExpenses[$_.Trim()] = $true
        }
    }
    Write-Host "Loaded $($processedExpenses.Count) previously processed expense(s)" -ForegroundColor Cyan
}
else {
    New-Item $masterListFile -type "file" | Out-Null
}

###############################
# ScriptBlock: Download Expense PDF (for Runspace)
###############################
$downloadScriptBlock = {
    param (
        $voucherInvoice,
        $reportID,
        $apiKey,
        $chainId,
        $customerCode,
        $baseUrl,
        $outputFolder,
        $errorLogFile,
        $getMileageDetails,
        $getImage,
        $getPDFReport,
        $getPDFReportWithNotes,
        $imageFirst,
        $failOnImageFetchError
    )

    # Build the API URL with parameters
    $params = @(
        "voucherInvoice=$voucherInvoice",
        "reportID=$reportID",
        "getMileageDetails=$getMileageDetails",
        "getImage=$getImage",
        "getPDFReport=$getPDFReport",
        "getPDFReportWithNotes=$getPDFReportWithNotes",
        "imageFirst=$imageFirst",
        "failOnImageFetchError=$failOnImageFetchError"
    )
    $uri = "$baseUrl/getReceipts?" + ($params -join "&")

    # Set output filename
    $filename = Join-Path $outputFolder "$reportID.pdf"

    # Set headers
    $headers = @{
        "accept" = "application/pdf"
        "x-api-key" = $apiKey
        "chain-id" = $chainId
        "customer-code" = $customerCode
    }

    try {
        # Download the PDF
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -OutFile $filename -ErrorAction Stop
        return @{
            Success = $true
            ReportID = $reportID
            VoucherInvoice = $voucherInvoice
            Error = $null
        }
    }
    catch {
        $errorMsg = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR: ReportID $reportID - $($_.Exception.Message)"
        # Thread-safe file append using mutex
        $mutex = New-Object System.Threading.Mutex($false, "ErrorLogMutex")
        $mutex.WaitOne() | Out-Null
        try {
            $errorMsg | Out-File $errorLogFile -Append
        }
        finally {
            $mutex.ReleaseMutex()
        }
        return @{
            Success = $false
            ReportID = $reportID
            VoucherInvoice = $voucherInvoice
            Error = $_.Exception.Message
        }
    }
}

###############################
# Function: Get Expense List
###############################
function Get-ExpenseList {
    Write-Host "Compiling list of expenses..."

    # Calculate date range
    $todateString = Get-Date -Format "MM/dd/yyyy"
    $fromdateString = (Get-Date).AddDays(-$daysBack).ToString("MM/dd/yyyy")

    # Build the API URL
    $uri = "$baseUrl/getVoucherInvoices?fromDate=$fromdateString&toDate=$todateString"

    Write-Host "Date Range: $fromdateString to $todateString"
    Write-Host "URI: $uri"

    # Set headers
    $headers = @{
        "x-api-key" = $apiKey
        "chain-id" = $chainId
        "customer-code" = $customerCode
    }

    try {
        # Get the expense list and save to XML file
        Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -OutFile "$expenseListFile"
        Write-Host "Expense list retrieved successfully" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Error retrieving expense list: $_" -ForegroundColor Red
        return $false
    }
}

###############################
# Main Script Execution
###############################
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Chrome River Expense Retrieval - PS5 OPTIMIZED" -ForegroundColor Cyan
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Get the list of expenses
if (!(Get-ExpenseList)) {
    Write-Host "Failed to retrieve expense list. Exiting." -ForegroundColor Red
    exit 1
}

# Parse the XML file
try {
    [xml]$xmlContent = Get-Content "$expenseListFile"
    $xmlProperties = $xmlContent.SelectNodes("/list/com.chromeriver.servlet.VoucherInvoiceTO")

    if ($xmlProperties.Count -eq 0) {
        Write-Host "No expenses found in the date range." -ForegroundColor Yellow
        exit 0
    }

    $stats.Total = $xmlProperties.Count
    Write-Host "Found $($stats.Total) expense(s) in the date range`n" -ForegroundColor Green

    # OPTIMIZATION: Filter expenses that need to be downloaded (pre-filter before parallel processing)
    $expensesToDownload = @()
    $current = 0

    foreach ($node in $xmlProperties) {
        $current++
        $voucherInvoice = $node.SelectSingleNode("voucherInvoice").get_innerXml()
        $reportID = $node.SelectSingleNode("reportID").get_innerXml()

        Write-Progress -Activity "Scanning expenses" -Status "Checking $reportID" -PercentComplete (($current / $stats.Total) * 100)

        # Check if the PDF file already exists in the destination folder
        $pdfFilePath = Join-Path $outputFolder "$reportID.pdf"
        if (Test-Path $pdfFilePath) {
            Write-Host "[$current/$($stats.Total)] Skipping $reportID (file already exists)" -ForegroundColor DarkGray
            $stats.AlreadyExists++
            continue
        }

        # OPTIMIZATION: Check HashSet instead of reading file every time (O(1) lookup)
        if ($processedExpenses.ContainsKey($voucherInvoice)) {
            Write-Host "[$current/$($stats.Total)] Skipping $reportID (in master list)" -ForegroundColor DarkGray
            $stats.Skipped++
            continue
        }

        # Add to download queue
        $expensesToDownload += [PSCustomObject]@{
            VoucherInvoice = $voucherInvoice
            ReportID = $reportID
        }
    }

    Write-Progress -Activity "Scanning expenses" -Completed

    if ($expensesToDownload.Count -eq 0) {
        Write-Host "`nNo new expenses to download." -ForegroundColor Yellow
    }
    else {
        Write-Host "`nDownloading $($expensesToDownload.Count) expense(s) using Runspaces (max $maxParallelDownloads concurrent)...`n" -ForegroundColor Cyan

        ###############################
        # PARALLEL PROCESSING WITH RUNSPACES (PowerShell 5 Compatible)
        ###############################

        # Create runspace pool
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, $maxParallelDownloads)
        $runspacePool.Open()

        # Array to track runspaces
        $runspaces = @()

        # Start all downloads
        foreach ($expense in $expensesToDownload) {
            $powershell = [powershell]::Create()
            $powershell.RunspacePool = $runspacePool

            # Add the script block and parameters
            [void]$powershell.AddScript($downloadScriptBlock)
            [void]$powershell.AddArgument($expense.VoucherInvoice)
            [void]$powershell.AddArgument($expense.ReportID)
            [void]$powershell.AddArgument($apiKey)
            [void]$powershell.AddArgument($chainId)
            [void]$powershell.AddArgument($customerCode)
            [void]$powershell.AddArgument($baseUrl)
            [void]$powershell.AddArgument($outputFolder)
            [void]$powershell.AddArgument($errorLogFile)
            [void]$powershell.AddArgument($getMileageDetails)
            [void]$powershell.AddArgument($getImage)
            [void]$powershell.AddArgument($getPDFReport)
            [void]$powershell.AddArgument($getPDFReportWithNotes)
            [void]$powershell.AddArgument($imageFirst)
            [void]$powershell.AddArgument($failOnImageFetchError)

            # Begin invoke
            $handle = $powershell.BeginInvoke()

            $runspaces += [PSCustomObject]@{
                PowerShell = $powershell
                Handle = $handle
                ReportID = $expense.ReportID
                VoucherInvoice = $expense.VoucherInvoice
            }
        }

        # Monitor progress and collect results
        $completed = 0
        $downloadResults = @()

        while ($runspaces.Count -gt 0) {
            $remaining = @()

            foreach ($runspace in $runspaces) {
                if ($runspace.Handle.IsCompleted) {
                    # Get the result
                    $result = $runspace.PowerShell.EndInvoke($runspace.Handle)
                    $runspace.PowerShell.Dispose()

                    $completed++
                    $downloadResults += $result

                    # Display result
                    if ($result.Success) {
                        Write-Host "[$completed/$($expensesToDownload.Count)] $(([char]0x2713)) SUCCESS - $($result.ReportID)" -ForegroundColor Green
                    }
                    else {
                        Write-Host "[$completed/$($expensesToDownload.Count)] $(([char]0x2717)) FAILED - $($result.ReportID)" -ForegroundColor Red
                    }

                    Write-Progress -Activity "Downloading PDFs" -Status "Completed $completed of $($expensesToDownload.Count)" -PercentComplete (($completed / $expensesToDownload.Count) * 100)
                }
                else {
                    $remaining += $runspace
                }
            }

            $runspaces = $remaining
            Start-Sleep -Milliseconds 100
        }

        Write-Progress -Activity "Downloading PDFs" -Completed

        # Clean up runspace pool
        $runspacePool.Close()
        $runspacePool.Dispose()

        # Process results and update master list
        $newExpenses = @()
        foreach ($result in $downloadResults) {
            if ($result.Success) {
                $stats.Downloaded++
                $newExpenses += $result.VoucherInvoice
            }
            else {
                $stats.Failed++
            }
        }

        # Batch update $masterListFile (more efficient than appending one at a time)
        if ($newExpenses.Count -gt 0) {
            $newExpenses | Out-File $masterListFile -Append
        }
    }

    # Final Summary Report
    $elapsed = (Get-Date) - $startTime
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "SUMMARY REPORT" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Total Expenses Found:     $($stats.Total)" -ForegroundColor White
    Write-Host "Already Exists (File):    $($stats.AlreadyExists)" -ForegroundColor DarkGray
    Write-Host "Skipped (Master List):    $($stats.Skipped)" -ForegroundColor DarkGray
    Write-Host "Successfully Downloaded:  $($stats.Downloaded)" -ForegroundColor Green
    Write-Host "Failed:                   $($stats.Failed)" -ForegroundColor $(if($stats.Failed -gt 0){'Red'}else{'White'})
    Write-Host "Execution Time:           $($elapsed.ToString('mm\:ss'))" -ForegroundColor Cyan
    Write-Host "Max Parallel Downloads:   $maxParallelDownloads" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    if ($stats.Failed -gt 0) {
        Write-Host "Error log saved to: $errorLogFile" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "`nCRITICAL ERROR: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
