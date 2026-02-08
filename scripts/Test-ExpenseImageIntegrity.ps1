###############################
# Test-ExpenseImageIntegrity.ps1
# PDF Validation and Retry Script for ChromeRiver Expense Images
# PowerShell 5.1 Compatible
#
# This script validates PDF files after they have been downloaded by Get-ExpenseImages.ps1
# It detects corrupt PDFs, tracks retry attempts, and automatically re-downloads them.
###############################

#Requires -Version 5.1

###############################
# CONFIGURATION
###############################
Write-Host "`nChromeRiver Expense Image Validation & Retry Script" -ForegroundColor Cyan
Write-Host "====================================================`n" -ForegroundColor Cyan

# Load configuration helper
Write-Host "Loading configuration..." -ForegroundColor Cyan
. (Join-Path $PSScriptRoot "Get-Configuration.ps1")
$config = Get-ChromeRiverConfiguration

# Extract settings
$companyName = $config.CompanyName
$baseUrl = $config.ChromeRiverAPI.BaseUrl
$maxParallelDownloads = $config.ChromeRiverAPI.MaxParallelDownloads
$outputFolder = $config.OutputSettings.OutputFolder
$masterListFile = Join-Path $outputFolder $config.OutputSettings.MasterListFile
$expenseListFile = Join-Path $outputFolder $config.OutputSettings.ExpenseListFile
$errorLogPrefix = Join-Path $outputFolder $config.OutputSettings.ErrorLogPrefix

# Validation settings (with defaults if not in config)
$maxRetryAttempts = if ($config.ValidationSettings -and $config.ValidationSettings.MaxRetryAttempts) {
    $config.ValidationSettings.MaxRetryAttempts
} else {
    3
}
$retryStateFile = if ($config.ValidationSettings -and $config.ValidationSettings.RetryStateFile) {
    Join-Path $outputFolder $config.ValidationSettings.RetryStateFile
} else {
    Join-Path $outputFolder "PDFRetryState.json"
}
$validationReportFile = if ($config.ValidationSettings -and $config.ValidationSettings.ValidationReportFile) {
    Join-Path $outputFolder $config.ValidationSettings.ValidationReportFile
} else {
    Join-Path $outputFolder "ValidationReport.txt"
}
$permanentFailuresFile = if ($config.ValidationSettings -and $config.ValidationSettings.PermanentFailuresFile) {
    Join-Path $outputFolder $config.ValidationSettings.PermanentFailuresFile
} else {
    Join-Path $outputFolder "PermanentFailures.txt"
}

# API parameters
$getMileageDetails = $config.APIParameters.GetMileageDetails
$getImage = $config.APIParameters.GetImage
$getPDFReport = $config.APIParameters.GetPDFReport
$getPDFReportWithNotes = $config.APIParameters.GetPDFReportWithNotes
$imageFirst = $config.APIParameters.ImageFirst
$failOnImageFetchError = $config.APIParameters.FailOnImageFetchError

Write-Host "Company: $companyName" -ForegroundColor White
Write-Host "Output Folder: $outputFolder" -ForegroundColor White
Write-Host "Max Retry Attempts: $maxRetryAttempts" -ForegroundColor White
Write-Host ""

###############################
# INITIALIZATION
###############################
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$startTime = Get-Date
$validationLogFile = "$($errorLogPrefix)_Validation_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Statistics tracking (synchronized hashtable for thread safety)
$stats = [hashtable]::Synchronized(@{
    TotalPDFs = 0
    ValidPDFs = 0
    CorruptPDFs = 0
    RetriesAttempted = 0
    RetriesSucceeded = 0
    RetriesFailed = 0
    PermanentFailures = 0
})

###############################
# FUNCTION: Test-PDFIntegrity
# Validates individual PDF file integrity
###############################
function Test-PDFIntegrity {
    <#
    .SYNOPSIS
        Validates PDF file integrity using multiple checks
    .PARAMETER FilePath
        Path to PDF file to validate
    .RETURNS
        PSCustomObject with Success (bool), FilePath (string), FileSize (int), Reason (string)
    #>
    param([string]$FilePath)

    try {
        # Check 1: File exists and size > 0
        if (!(Test-Path $FilePath)) {
            return [PSCustomObject]@{
                Success = $false
                FilePath = $FilePath
                FileSize = 0
                Reason = "File does not exist"
            }
        }

        $fileInfo = Get-Item $FilePath
        if ($fileInfo.Length -eq 0) {
            return [PSCustomObject]@{
                Success = $false
                FilePath = $FilePath
                FileSize = 0
                Reason = "File size is 0 bytes"
            }
        }

        # Check 2: PDF header signature (%PDF-)
        # Read first 512 bytes for header check
        $headerBytes = [System.IO.File]::ReadAllBytes($FilePath) | Select-Object -First 512
        $headerString = [System.Text.Encoding]::ASCII.GetString($headerBytes)

        if ($headerString -notmatch '%PDF-') {
            return [PSCustomObject]@{
                Success = $false
                FilePath = $FilePath
                FileSize = $fileInfo.Length
                Reason = "Invalid PDF header - missing %PDF- signature"
            }
        }

        # Check 3: EOF marker (%%EOF) - read last 1024 bytes
        $fileLength = $fileInfo.Length
        $startPosition = [Math]::Max(0, $fileLength - 1024)
        $bytesToRead = [Math]::Min(1024, $fileLength)

        $stream = [System.IO.File]::OpenRead($FilePath)
        try {
            $stream.Seek($startPosition, [System.IO.SeekOrigin]::Begin) | Out-Null
            $endBytes = New-Object byte[] $bytesToRead
            $stream.Read($endBytes, 0, $bytesToRead) | Out-Null
            $endString = [System.Text.Encoding]::ASCII.GetString($endBytes)

            if ($endString -notmatch '%%EOF') {
                return [PSCustomObject]@{
                    Success = $false
                    FilePath = $FilePath
                    FileSize = $fileInfo.Length
                    Reason = "Invalid PDF structure - missing %%EOF marker"
                }
            }
        }
        finally {
            $stream.Close()
            $stream.Dispose()
        }

        # Check 4: Basic structure (xref or /Type)
        # Read full file for structure check (only for small files < 10MB)
        if ($fileInfo.Length -lt 10MB) {
            $allBytes = [System.IO.File]::ReadAllBytes($FilePath)
            $contentString = [System.Text.Encoding]::ASCII.GetString($allBytes)

            if ($contentString -notmatch 'xref' -and $contentString -notmatch '/Type') {
                return [PSCustomObject]@{
                    Success = $false
                    FilePath = $FilePath
                    FileSize = $fileInfo.Length
                    Reason = "Invalid PDF structure - missing xref table or /Type catalog"
                }
            }
        }

        # All checks passed
        return [PSCustomObject]@{
            Success = $true
            FilePath = $FilePath
            FileSize = $fileInfo.Length
            Reason = "Valid PDF"
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            FilePath = $FilePath
            FileSize = 0
            Reason = "Exception during validation: $($_.Exception.Message)"
        }
    }
}

###############################
# FUNCTION: Get-PDFValidationReport
# Scans all PDFs in output folder and validates them
###############################
function Get-PDFValidationReport {
    <#
    .SYNOPSIS
        Scans all PDFs in output folder and validates them
    .PARAMETER OutputFolder
        Folder containing expense PDFs
    .RETURNS
        Array of validation results
    #>
    param([string]$OutputFolder)

    Write-Host "Scanning for PDF files in: $OutputFolder" -ForegroundColor Cyan

    $pdfFiles = Get-ChildItem -Path $OutputFolder -Filter "*.pdf" -ErrorAction SilentlyContinue

    if ($pdfFiles.Count -eq 0) {
        Write-Host "No PDF files found in output folder." -ForegroundColor Yellow
        return @()
    }

    Write-Host "Found $($pdfFiles.Count) PDF files. Validating..." -ForegroundColor Cyan

    $results = @()
    $current = 0

    foreach ($pdf in $pdfFiles) {
        $current++
        Write-Progress -Activity "Validating PDFs" -Status "Validating $($pdf.Name)" -PercentComplete (($current / $pdfFiles.Count) * 100)

        $validationResult = Test-PDFIntegrity -FilePath $pdf.FullName
        $results += $validationResult

        # Update stats
        $stats.TotalPDFs++
        if ($validationResult.Success) {
            $stats.ValidPDFs++
        }
        else {
            $stats.CorruptPDFs++
        }
    }

    Write-Progress -Activity "Validating PDFs" -Completed

    return $results
}

###############################
# FUNCTION: Get-RetryState
# Loads retry state from persistent JSON file
###############################
function Get-RetryState {
    <#
    .SYNOPSIS
        Loads retry state from persistent JSON file
    .PARAMETER StateFilePath
        Path to retry state file
    .RETURNS
        Hashtable of retry state
    #>
    param([string]$StateFilePath)

    # Try primary file
    if (Test-Path $StateFilePath) {
        try {
            $content = Get-Content $StateFilePath -Raw | ConvertFrom-Json
            Write-Host "Loaded existing retry state from: $StateFilePath" -ForegroundColor Green
            return $content
        }
        catch {
            Write-Host "WARNING: Retry state file is corrupt. Checking for backup..." -ForegroundColor Yellow
        }
    }

    # Try backup
    $backupFile = "$StateFilePath.bak"
    if (Test-Path $backupFile) {
        try {
            Write-Host "Restoring from backup state file..." -ForegroundColor Yellow
            $content = Get-Content $backupFile -Raw | ConvertFrom-Json
            Copy-Item $backupFile $StateFilePath -Force
            return $content
        }
        catch {
            Write-Host "WARNING: Backup state file also corrupt." -ForegroundColor Yellow
        }
    }

    # Initialize new state
    Write-Host "Initializing new retry state..." -ForegroundColor Cyan
    $newState = @{
        version = "1.0"
        lastRun = (Get-Date -Format "o")
        statistics = @{
            totalTracked = 0
            activeRetries = 0
            permanentFailures = 0
            recovered = 0
        }
        retries = @{}
    }

    return ($newState | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
}

###############################
# FUNCTION: Save-RetryState
# Saves retry state with atomic write pattern
###############################
function Save-RetryState {
    <#
    .SYNOPSIS
        Saves retry state to JSON file with atomic write pattern
    .PARAMETER StateFilePath
        Path to retry state file
    .PARAMETER StateObject
        State object to save
    #>
    param(
        [string]$StateFilePath,
        $StateObject
    )

    $tempFile = "$StateFilePath.tmp"
    $backupFile = "$StateFilePath.bak"

    try {
        # Update lastRun timestamp
        $StateObject.lastRun = Get-Date -Format "o"

        # Write to temp file
        $StateObject | ConvertTo-Json -Depth 10 | Out-File $tempFile -Encoding UTF8

        # Backup existing if present
        if (Test-Path $StateFilePath) {
            Copy-Item $StateFilePath $backupFile -Force
        }

        # Atomic replace
        Move-Item $tempFile $StateFilePath -Force

        # Clean up backup if successful
        if (Test-Path $backupFile) {
            Remove-Item $backupFile -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Host "ERROR saving state: $($_.Exception.Message)" -ForegroundColor Red
        # Attempt recovery from backup
        if (Test-Path $backupFile) {
            Copy-Item $backupFile $StateFilePath -Force
        }
        throw
    }
}

###############################
# FUNCTION: Update-RetryState
# Updates retry state for a specific report
###############################
function Update-RetryState {
    <#
    .SYNOPSIS
        Updates retry state for a specific report
    .PARAMETER State
        State object to update
    .PARAMETER ReportID
        Report ID to update
    .PARAMETER VoucherInvoice
        Voucher invoice ID
    .PARAMETER Success
        Whether retry was successful
    .PARAMETER ErrorMessage
        Error message if failed
    #>
    param(
        $State,
        [string]$ReportID,
        [string]$VoucherInvoice,
        [bool]$Success,
        [string]$ErrorMessage
    )

    $now = Get-Date -Format "o"

    if (-not $State.retries.$ReportID) {
        # New entry
        $State.retries | Add-Member -NotePropertyName $ReportID -NotePropertyValue ([PSCustomObject]@{
            reportID = $ReportID
            voucherInvoice = $VoucherInvoice
            retryCount = 0
            firstFailure = $now
            lastAttempt = $now
            status = "pending"
            failures = @()
        })
    }

    $entry = $State.retries.$ReportID
    $entry.lastAttempt = $now

    if ($Success) {
        $entry.status = "recovered"
    }
    else {
        $entry.retryCount++
        $entry.failures += [PSCustomObject]@{
            timestamp = $now
            reason = $ErrorMessage
        }

        if ($entry.retryCount -ge $maxRetryAttempts) {
            $entry.status = "failed_permanent"
        }
        else {
            $entry.status = "retrying"
        }
    }
}

###############################
# FUNCTION: Remove-FromMasterList
# Removes voucher invoices from MasterExpenseList.txt (thread-safe)
###############################
function Remove-FromMasterList {
    <#
    .SYNOPSIS
        Removes voucher invoices from MasterExpenseList.txt
    .PARAMETER MasterListPath
        Path to master list file
    .PARAMETER VoucherInvoices
        Array of voucher invoices to remove
    #>
    param(
        [string]$MasterListPath,
        [string[]]$VoucherInvoices
    )

    if (!(Test-Path $MasterListPath)) {
        Write-Host "Master list file does not exist: $MasterListPath" -ForegroundColor Yellow
        return
    }

    # Thread-safe removal using mutex
    $mutex = New-Object System.Threading.Mutex($false, "MasterListMutex")
    $acquired = $false

    try {
        # Try to acquire mutex with timeout (3 attempts with 500ms delay)
        for ($i = 0; $i -lt 3; $i++) {
            $acquired = $mutex.WaitOne(500)
            if ($acquired) { break }
            Start-Sleep -Milliseconds 500
        }

        if (-not $acquired) {
            Write-Host "WARNING: Could not acquire lock on master list file after 3 attempts" -ForegroundColor Yellow
            return
        }

        # Load entire file
        $allLines = Get-Content $MasterListPath

        # Filter out specified invoices
        $filtered = $allLines | Where-Object { $_ -notin $VoucherInvoices }

        # Write back atomically
        $filtered | Out-File $MasterListPath -Encoding UTF8

        $removedCount = $allLines.Count - $filtered.Count
        Write-Host "Removed $removedCount entries from master list" -ForegroundColor Cyan
    }
    finally {
        if ($acquired) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

###############################
# FUNCTION: Write-ThreadSafeLog
# Thread-safe log writing with mutex
###############################
function Write-ThreadSafeLog {
    param(
        [string]$LogFile,
        [string]$Message
    )

    $mutex = New-Object System.Threading.Mutex($false, "ValidationLogMutex")
    $mutex.WaitOne() | Out-Null
    try {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message" | Out-File $LogFile -Append -Encoding UTF8
    }
    finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

###############################
# ScriptBlock: Download Expense PDF (for Runspace - reused from Get-ExpenseImages.ps1)
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
# FUNCTION: Invoke-PDFRetryDownload
# Re-downloads corrupt PDFs using parallel runspaces
###############################
function Invoke-PDFRetryDownload {
    <#
    .SYNOPSIS
        Downloads corrupt PDFs using parallel runspaces
    .PARAMETER RetryList
        Array of expenses to retry
    .PARAMETER Config
        Configuration object
    .PARAMETER Credentials
        Credentials object
    .RETURNS
        Array of download results
    #>
    param(
        $RetryList,
        $Config,
        $Credentials
    )

    if ($RetryList.Count -eq 0) {
        return @()
    }

    Write-Host "`nRetrying $($RetryList.Count) corrupt PDF downloads..." -ForegroundColor Cyan

    # Create runspace pool
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $maxParallelDownloads)
    $runspacePool.Open()

    # Array to track runspaces
    $runspaces = @()

    # Start all downloads
    foreach ($item in $RetryList) {
        $powershell = [powershell]::Create()
        $powershell.RunspacePool = $runspacePool

        # Add the script block and parameters
        [void]$powershell.AddScript($downloadScriptBlock)
        [void]$powershell.AddArgument($item.VoucherInvoice)
        [void]$powershell.AddArgument($item.ReportID)
        [void]$powershell.AddArgument($Credentials.ApiKey)
        [void]$powershell.AddArgument($Credentials.ChainId)
        [void]$powershell.AddArgument($Credentials.CustomerCode)
        [void]$powershell.AddArgument($baseUrl)
        [void]$powershell.AddArgument($outputFolder)
        [void]$powershell.AddArgument($validationLogFile)
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
            ReportID = $item.ReportID
            VoucherInvoice = $item.VoucherInvoice
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
                    Write-Host "[$completed/$($RetryList.Count)] $(([char]0x2713)) RETRY SUCCESS - $($result.ReportID)" -ForegroundColor Green
                    $stats.RetriesSucceeded++
                }
                else {
                    Write-Host "[$completed/$($RetryList.Count)] $(([char]0x2717)) RETRY FAILED - $($result.ReportID)" -ForegroundColor Red
                    $stats.RetriesFailed++
                }

                Write-Progress -Activity "Retrying Downloads" -Status "Completed $completed of $($RetryList.Count)" -PercentComplete (($completed / $RetryList.Count) * 100)
            }
            else {
                $remaining += $runspace
            }
        }

        $runspaces = $remaining
        Start-Sleep -Milliseconds 100
    }

    Write-Progress -Activity "Retrying Downloads" -Completed

    # Clean up runspace pool
    $runspacePool.Close()
    $runspacePool.Dispose()

    return $downloadResults
}

###############################
# FUNCTION: Write-ValidationSummary
# Generates and displays validation summary report
###############################
function Write-ValidationSummary {
    param(
        $ValidationResults,
        $RetryResults,
        $State,
        $OutputFolder
    )

    $endTime = Get-Date
    $duration = $endTime - $startTime

    Write-Host "`n" -NoNewline
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  VALIDATION & RETRY SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Total PDFs Scanned:       $($stats.TotalPDFs)" -ForegroundColor White
    Write-Host "Valid PDFs:               $($stats.ValidPDFs)" -ForegroundColor Green
    Write-Host "Corrupt PDFs Found:       $($stats.CorruptPDFs)" -ForegroundColor $(if ($stats.CorruptPDFs -eq 0) { "Green" } else { "Yellow" })
    Write-Host ""
    Write-Host "Retry Attempts:           $($stats.RetriesAttempted)" -ForegroundColor White
    Write-Host "Retry Successes:          $($stats.RetriesSucceeded)" -ForegroundColor Green
    Write-Host "Retry Failures:           $($stats.RetriesFailed)" -ForegroundColor $(if ($stats.RetriesFailed -eq 0) { "Green" } else { "Yellow" })
    Write-Host "Permanent Failures:       $($stats.PermanentFailures)" -ForegroundColor $(if ($stats.PermanentFailures -eq 0) { "Green" } else { "Red" })
    Write-Host ""
    Write-Host "Execution Time:           $($duration.ToString('mm\:ss'))" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Write detailed validation report
    $reportContent = @"
ChromeRiver PDF Validation Report
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Company: $companyName
Output Folder: $outputFolder

SUMMARY
========================================
Total PDFs Scanned:       $($stats.TotalPDFs)
Valid PDFs:               $($stats.ValidPDFs)
Corrupt PDFs Found:       $($stats.CorruptPDFs)

Retry Attempts:           $($stats.RetriesAttempted)
Retry Successes:          $($stats.RetriesSucceeded)
Retry Failures:           $($stats.RetriesFailed)
Permanent Failures:       $($stats.PermanentFailures)

Execution Time:           $($duration.ToString('mm\:ss'))

CORRUPT PDFs DETAILS
========================================
"@

    $corruptPDFs = $ValidationResults | Where-Object { -not $_.Success }
    foreach ($pdf in $corruptPDFs) {
        $reportContent += "`n$($pdf.FilePath)"
        $reportContent += "`n  Size: $($pdf.FileSize) bytes"
        $reportContent += "`n  Reason: $($pdf.Reason)"
        $reportContent += "`n"
    }

    $reportContent | Out-File $validationReportFile -Encoding UTF8
    Write-Host "Detailed report saved to: $validationReportFile" -ForegroundColor Green

    # Write permanent failures file if any
    if ($stats.PermanentFailures -gt 0) {
        $permFailContent = @"
ChromeRiver PDF Permanent Failures
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

The following PDFs failed all $maxRetryAttempts retry attempts and require manual intervention:

"@

        foreach ($key in $State.retries.PSObject.Properties.Name) {
            $entry = $State.retries.$key
            if ($entry.status -eq "failed_permanent") {
                $permFailContent += "`nReport ID: $($entry.reportID)"
                $permFailContent += "`nVoucher Invoice: $($entry.voucherInvoice)"
                $permFailContent += "`nRetry Count: $($entry.retryCount)"
                $permFailContent += "`nFirst Failure: $($entry.firstFailure)"
                $permFailContent += "`nLast Attempt: $($entry.lastAttempt)"
                $permFailContent += "`nFailure History:"
                foreach ($failure in $entry.failures) {
                    $permFailContent += "`n  - $($failure.timestamp): $($failure.reason)"
                }
                $permFailContent += "`n"
            }
        }

        $permFailContent | Out-File $permanentFailuresFile -Encoding UTF8
        Write-Host "Permanent failures saved to: $permanentFailuresFile" -ForegroundColor Yellow
    }
}

###############################
# MAIN SCRIPT EXECUTION
###############################

try {
    # Check if output folder exists
    if (!(Test-Path $outputFolder)) {
        Write-Host "INFO: Output folder does not exist yet: $outputFolder" -ForegroundColor Yellow
        Write-Host "This is normal if you haven't run Get-ExpenseImages.ps1 yet." -ForegroundColor Yellow
        Write-Host "The folder will be created when you run the download script for the first time." -ForegroundColor Yellow
        Write-Host "`nExiting gracefully - nothing to validate." -ForegroundColor Cyan
        exit 0
    }

    ###############################
    # PHASE 1: VALIDATION
    ###############################
    Write-Host "==> PHASE 1: PDF Validation" -ForegroundColor Cyan
    Write-Host ""

    $validationResults = Get-PDFValidationReport -OutputFolder $outputFolder

    if ($validationResults.Count -eq 0) {
        Write-Host "`nNo PDFs found to validate. Exiting." -ForegroundColor Yellow
        exit 0
    }

    Write-Host "`nValidation complete!" -ForegroundColor Green
    Write-Host "Valid PDFs: $($stats.ValidPDFs)" -ForegroundColor Green
    Write-Host "Corrupt PDFs: $($stats.CorruptPDFs)" -ForegroundColor $(if ($stats.CorruptPDFs -eq 0) { "Green" } else { "Yellow" })

    # If no corrupt PDFs, exit early
    if ($stats.CorruptPDFs -eq 0) {
        Write-Host "`nAll PDFs are valid! No retries needed." -ForegroundColor Green

        # Still write a summary report
        Write-ValidationSummary -ValidationResults $validationResults -RetryResults @() -State @{retries=@{}} -OutputFolder $outputFolder
        exit 0
    }

    ###############################
    # PHASE 2: RETRY PREPARATION
    ###############################
    Write-Host "`n==> PHASE 2: Retry Preparation" -ForegroundColor Cyan
    Write-Host ""

    # Load retry state
    $state = Get-RetryState -StateFilePath $retryStateFile

    # Check if ExpenseList.xml exists
    if (!(Test-Path $expenseListFile)) {
        Write-Host "WARNING: ExpenseList.xml not found: $expenseListFile" -ForegroundColor Yellow
        Write-Host "Cannot link corrupt PDFs to voucher invoices for retry." -ForegroundColor Yellow
        Write-Host "Validation completed, but retry functionality is disabled." -ForegroundColor Yellow

        Write-ValidationSummary -ValidationResults $validationResults -RetryResults @() -State $state -OutputFolder $outputFolder
        exit 0
    }

    # Load ExpenseList.xml for mapping
    Write-Host "Loading expense list from: $expenseListFile" -ForegroundColor Cyan
    [xml]$xmlContent = Get-Content $expenseListFile

    # Create mapping: ReportID -> VoucherInvoice
    $reportMapping = @{}
    foreach ($expense in $xmlContent.list.'com.chromeriver.servlet.VoucherInvoiceTO') {
        $reportMapping[$expense.reportID] = $expense.voucherInvoice
    }

    # Build retry list
    $corruptPDFs = $validationResults | Where-Object { -not $_.Success }
    $retryList = @()
    $invoicesToRemove = @()

    foreach ($corrupt in $corruptPDFs) {
        # Extract ReportID from filename (assuming format: ReportID.pdf)
        $reportID = [System.IO.Path]::GetFileNameWithoutExtension($corrupt.FilePath)
        $voucherInvoice = $reportMapping[$reportID]

        if (-not $voucherInvoice) {
            Write-Host "WARNING: Could not find voucher invoice for ReportID: $reportID" -ForegroundColor Yellow
            continue
        }

        # Check retry count
        $currentRetryCount = 0
        if ($state.retries.$reportID) {
            $currentRetryCount = $state.retries.$reportID.retryCount
        }

        if ($currentRetryCount -ge $maxRetryAttempts) {
            Write-Host "Skipping $reportID - max retries ($maxRetryAttempts) reached" -ForegroundColor Yellow
            $stats.PermanentFailures++
            Update-RetryState -State $state -ReportID $reportID -VoucherInvoice $voucherInvoice -Success $false -ErrorMessage "Max retries exceeded"
            continue
        }

        # Add to retry list
        $retryList += [PSCustomObject]@{
            ReportID = $reportID
            VoucherInvoice = $voucherInvoice
            CurrentRetryCount = $currentRetryCount
            Reason = $corrupt.Reason
        }

        $invoicesToRemove += $voucherInvoice

        # Delete corrupt PDF
        Write-Host "Deleting corrupt PDF: $reportID" -ForegroundColor Yellow
        Remove-Item $corrupt.FilePath -Force -ErrorAction SilentlyContinue
    }

    if ($retryList.Count -eq 0) {
        Write-Host "`nNo PDFs eligible for retry (all have reached max attempts)." -ForegroundColor Yellow
        Save-RetryState -StateFilePath $retryStateFile -StateObject $state
        Write-ValidationSummary -ValidationResults $validationResults -RetryResults @() -State $state -OutputFolder $outputFolder
        exit 0
    }

    Write-Host "Prepared $($retryList.Count) PDFs for retry" -ForegroundColor Cyan

    # Remove from master list
    if (Test-Path $masterListFile) {
        Write-Host "Removing corrupt PDFs from master list..." -ForegroundColor Cyan
        Remove-FromMasterList -MasterListPath $masterListFile -VoucherInvoices $invoicesToRemove
    }

    ###############################
    # PHASE 3: LOAD CREDENTIALS & RETRY DOWNLOAD
    ###############################
    Write-Host "`n==> PHASE 3: Retry Download" -ForegroundColor Cyan
    Write-Host ""

    # Load secure credentials
    try {
        Write-Host "Loading secure credentials..." -ForegroundColor Cyan
        . (Join-Path $PSScriptRoot "Get-SecureCredentials.ps1")
        $credentials = Get-ChromeRiverCredentials
    }
    catch {
        Write-Host "ERROR: Could not load credentials: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Retry functionality is disabled." -ForegroundColor Yellow
        Save-RetryState -StateFilePath $retryStateFile -StateObject $state
        Write-ValidationSummary -ValidationResults $validationResults -RetryResults @() -State $state -OutputFolder $outputFolder
        exit 1
    }

    $stats.RetriesAttempted = $retryList.Count

    # Execute retry downloads
    $retryResults = Invoke-PDFRetryDownload -RetryList $retryList -Config $config -Credentials $credentials

    ###############################
    # PHASE 4: RE-VALIDATE & UPDATE STATE
    ###############################
    Write-Host "`n==> PHASE 4: Re-Validation & State Update" -ForegroundColor Cyan
    Write-Host ""

    $newExpenses = @()

    foreach ($result in $retryResults) {
        if ($result.Success) {
            # Re-validate the downloaded PDF
            $pdfPath = Join-Path $outputFolder "$($result.ReportID).pdf"
            $revalidation = Test-PDFIntegrity -FilePath $pdfPath

            if ($revalidation.Success) {
                Write-Host "$(([char]0x2713)) $($result.ReportID) - Downloaded and validated successfully" -ForegroundColor Green
                Update-RetryState -State $state -ReportID $result.ReportID -VoucherInvoice $result.VoucherInvoice -Success $true -ErrorMessage ""
                $newExpenses += $result.VoucherInvoice
            }
            else {
                Write-Host "$(([char]0x2717)) $($result.ReportID) - Downloaded but still corrupt: $($revalidation.Reason)" -ForegroundColor Red
                Update-RetryState -State $state -ReportID $result.ReportID -VoucherInvoice $result.VoucherInvoice -Success $false -ErrorMessage $revalidation.Reason
            }
        }
        else {
            Write-Host "$(([char]0x2717)) $($result.ReportID) - Download failed: $($result.Error)" -ForegroundColor Red
            Update-RetryState -State $state -ReportID $result.ReportID -VoucherInvoice $result.VoucherInvoice -Success $false -ErrorMessage $result.Error
        }
    }

    # Save updated retry state
    Save-RetryState -StateFilePath $retryStateFile -StateObject $state
    Write-Host "`nRetry state saved to: $retryStateFile" -ForegroundColor Green

    # Update master list with successful recoveries
    if ($newExpenses.Count -gt 0 -and (Test-Path $masterListFile)) {
        Write-Host "Adding $($newExpenses.Count) recovered PDFs to master list..." -ForegroundColor Cyan
        $newExpenses | Out-File $masterListFile -Append -Encoding UTF8
    }

    # Count permanent failures
    foreach ($key in $state.retries.PSObject.Properties.Name) {
        if ($state.retries.$key.status -eq "failed_permanent") {
            $stats.PermanentFailures++
        }
    }

    ###############################
    # PHASE 5: REPORTING
    ###############################
    Write-Host "`n==> PHASE 5: Final Reporting" -ForegroundColor Cyan
    Write-Host ""

    Write-ValidationSummary -ValidationResults $validationResults -RetryResults $retryResults -State $state -OutputFolder $outputFolder

    Write-Host "Validation and retry process complete!" -ForegroundColor Green

    # Exit with appropriate code
    if ($stats.PermanentFailures -gt 0) {
        Write-Host "`nWARNING: Some PDFs failed permanently and require manual intervention." -ForegroundColor Yellow
        exit 1
    }
    else {
        exit 0
    }
}
catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
