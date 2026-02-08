# Chrome River Expense Image Retrieval Script

A high-performance PowerShell automation tool for downloading expense report PDFs from Chrome River's API. This script features parallel downloads using runspaces, intelligent deduplication, and secure credential management.

## 📚 Documentation

- **[Security Guide](docs/README_SECURITY.md)** - Detailed security considerations and best practices
- **[Deployment Guide](docs/DEPLOYMENT_GUIDE.md)** - Enterprise deployment instructions
- **[Contributing](CONTRIBUTING.md)** - How to contribute to this project

## Features

- **Parallel Downloads**: Uses PowerShell Runspaces for concurrent PDF downloads (configurable throttle limit)
- **Smart Deduplication**: Tracks processed expenses to avoid redundant downloads
- **PDF Validation & Retry**: Automatically detects corrupt PDFs and retries downloads (up to 3 attempts)
- **Secure Credentials**: Stores API keys and sensitive data using Windows DPAPI encryption
- **Progress Tracking**: Real-time progress bars and detailed statistics
- **Error Handling**: Thread-safe error logging with detailed diagnostics
- **Persistent State Tracking**: Remembers retry attempts across script executions
- **Configurable**: External JSON configuration for easy customization
- **PowerShell 5.1 Compatible**: Works on Windows systems without requiring PowerShell 7+

## Prerequisites

- **Windows** operating system
- **PowerShell 5.1** or higher
- Valid **Chrome River API credentials** (API Key, Chain ID, Customer Code)
- Network access to Chrome River API endpoints

## Project Structure

```
chrome-river-expense-downloader/
├── .github/                           # GitHub workflows (optional)
├── docs/                              # Additional documentation
│   ├── DEPLOYMENT_GUIDE.md
│   └── README_SECURITY.md
├── examples/
│   └── config.template.json           # Configuration template
├── scripts/
│   ├── Get-ExpenseImages.ps1          # Main download script
│   ├── Test-ExpenseImageIntegrity.ps1 # PDF validation & retry script ⭐ NEW
│   ├── Get-Configuration.ps1          # Configuration loader helper
│   ├── Get-SecureCredentials.ps1      # Credential management helper
│   ├── Setup-SecureCredentials.ps1    # Credential setup utility
│   ├── config.json                    # Your configuration (create from template, not in repo)
│   └── Credentials/
│       └── ChromeRiver.cred           # Encrypted credentials (not in repo)
├── .gitignore                         # Git ignore rules
├── CONTRIBUTING.md                    # Contribution guidelines
├── LICENSE                            # MIT License
└── README.md                          # This file
```

## Setup Instructions

### 1. Clone or Download

Download all project files to a local directory.

### 2. Create Configuration File

1. Copy `examples/config.template.json` to `scripts/config.json`
2. Edit `scripts/config.json` with your company settings:

```json
{
  "CompanyName": "Your Company Name",
  "ChromeRiverAPI": {
    "BaseUrl": "https://api.chromeriver.com/v1",
    "DaysBack": 30,
    "MaxParallelDownloads": 5
  },
  "OutputSettings": {
    "OutputFolder": "C:\\ExpenseReports",
    "MasterListFile": "C:\\ExpenseReports\\master_list.txt",
    "ExpenseListFile": "C:\\ExpenseReports\\expense_list.xml",
    "ErrorLogPrefix": "C:\\ExpenseReports\\error_log"
  },
  "APIParameters": {
    "GetMileageDetails": true,
    "GetImage": true,
    "GetPDFReport": true,
    "GetPDFReportWithNotes": true,
    "ImageFirst": false,
    "FailOnImageFetchError": false
  },
  "ValidationSettings": {
    "MaxRetryAttempts": 3,
    "RetryStateFile": "PDFRetryState.json",
    "ValidationReportFile": "ValidationReport.txt",
    "PermanentFailuresFile": "PermanentFailures.txt"
  }
}
```

### 3. Configure Secure Credentials

Run the setup script to encrypt and store your API credentials:

```powershell
.\scripts\Setup-SecureCredentials.ps1
```

You'll be prompted to enter:
- **API Key**: Your Chrome River API key
- **Chain ID**: Your organization's chain identifier
- **Customer Code**: Your customer code

Credentials are encrypted using Windows DPAPI and can only be decrypted by the same user on the same machine.

### 4. Run the Scripts

**Download expense PDFs:**
```powershell
.\scripts\Get-ExpenseImages.ps1
```

**Validate PDFs and retry corrupt downloads (recommended after each download run):**
```powershell
.\scripts\Test-ExpenseImageIntegrity.ps1
```

## Usage

### Standard Workflow

**Step 1: Download Expense PDFs**

Run the main download script:
```powershell
.\scripts\Get-ExpenseImages.ps1
```

The script will:
1. Load configuration from `config.json`
2. Load encrypted credentials
3. Query Chrome River API for expenses within the date range
4. Filter out already-downloaded expenses
5. Download new expense PDFs in parallel
6. Save successfully downloaded expenses to the master list
7. Display a summary report

**Step 2: Validate PDFs and Retry Failures**

After downloads complete, run the validation script:
```powershell
.\scripts\Test-ExpenseImageIntegrity.ps1
```

The script will:
1. Scan all PDFs in the output folder
2. Validate each PDF for corruption (header, EOF marker, structure)
3. Identify corrupt PDFs
4. Delete corrupt files and remove from master list
5. Automatically retry downloading corrupt PDFs (max 3 attempts)
6. Re-validate retried downloads
7. Generate detailed validation and retry reports

### Sample Output: Get-ExpenseImages.ps1

```
========================================
Chrome River Expense Retrieval - PS5 OPTIMIZED
PowerShell Version: 5.1.19041.5247
========================================

Loading configuration...
[OK] Configuration loaded for: Your Company Name
Loading secure credentials...
OK Credentials loaded successfully (Encrypted by: USERNAME on 2025-01-15)

Compiling list of expenses...
Date Range: 01/07/2026 to 02/06/2026
Expense list retrieved successfully
Found 45 expense(s) in the date range

Loaded 120 previously processed expense(s)

Downloading 12 expense(s) using Runspaces (max 5 concurrent)...

[1/12] ✓ SUCCESS - RPT12345
[2/12] ✓ SUCCESS - RPT12346
[3/12] ✓ SUCCESS - RPT12347
...

========================================
SUMMARY REPORT
========================================
Total Expenses Found:     45
Already Exists (File):    15
Skipped (Master List):    18
Successfully Downloaded:  12
Failed:                   0
Execution Time:           00:23
Max Parallel Downloads:   5
========================================
```

### Sample Output: Test-ExpenseImageIntegrity.ps1

```
ChromeRiver Expense Image Validation & Retry Script
====================================================

Loading configuration...
Company: Your Company Name
Output Folder: C:\ExpenseReports
Max Retry Attempts: 3

==> PHASE 1: PDF Validation

Scanning for PDF files in: C:\ExpenseReports
Found 45 PDF files. Validating...

Validation complete!
Valid PDFs: 43
Corrupt PDFs: 2

==> PHASE 2: Retry Preparation

Loading expense list from: C:\ExpenseReports\ExpenseList.xml
Prepared 2 PDFs for retry
Deleting corrupt PDF: RPT12348
Deleting corrupt PDF: RPT12351
Removing corrupt PDFs from master list...

==> PHASE 3: Retry Download

Retrying 2 corrupt PDF downloads...
[1/2] ✓ RETRY SUCCESS - RPT12348
[2/2] ✓ RETRY SUCCESS - RPT12351

==> PHASE 4: Re-Validation & State Update

✓ RPT12348 - Downloaded and validated successfully
✓ RPT12351 - Downloaded and validated successfully
Retry state saved to: C:\ExpenseReports\PDFRetryState.json

==> PHASE 5: Final Reporting

========================================
  VALIDATION & RETRY SUMMARY
========================================

Total PDFs Scanned:       45
Valid PDFs:               43
Corrupt PDFs Found:       2

Retry Attempts:           2
Retry Successes:          2
Retry Failures:           0
Permanent Failures:       0

Execution Time:           00:15
========================================

Detailed report saved to: C:\ExpenseReports\ValidationReport.txt
Validation and retry process complete!
```

## PDF Validation & Retry System

### Overview

The `Test-ExpenseImageIntegrity.ps1` script provides automatic PDF validation and retry capabilities to ensure all downloaded expense reports are valid and complete.

### Features

- **Multi-Level Validation**: Checks PDF header signature (`%PDF-`), EOF marker (`%%EOF`), file size, and basic structure
- **Automatic Retry**: Re-downloads corrupt PDFs up to 3 times (configurable)
- **Persistent State Tracking**: Remembers retry attempts across script executions via `PDFRetryState.json`
- **Thread-Safe Operations**: Uses mutex locking for concurrent file access
- **Intelligent Recovery**: Removes corrupt PDFs from master list so main script can re-download
- **Comprehensive Reporting**: Generates detailed validation reports and permanent failure logs

### When to Run

Run the validation script **after** the main download script completes:

```powershell
# Standard workflow
.\scripts\Get-ExpenseImages.ps1
.\scripts\Test-ExpenseImageIntegrity.ps1
```

### What Happens During Validation

1. **Validation Phase**: Scans all PDFs in output folder and validates integrity
2. **Retry Preparation**: Links corrupt PDFs to XML data, deletes corrupt files, removes from master list
3. **Retry Download**: Re-downloads corrupt PDFs using parallel downloads (same as main script)
4. **Re-Validation**: Validates retried downloads to confirm they're now valid
5. **Reporting**: Generates comprehensive reports and updates retry state

### Retry State Management

The script maintains a `PDFRetryState.json` file that tracks:
- Which PDFs have been retried and how many times
- Failure reasons and timestamps
- Status: `pending`, `retrying`, `recovered`, or `failed_permanent`

After 3 failed retry attempts, a PDF is marked as `failed_permanent` and added to `PermanentFailures.txt` for manual investigation.

### Output Files

| File | Description |
|------|-------------|
| `PDFRetryState.json` | Persistent retry state tracking across executions |
| `ValidationReport_TIMESTAMP.txt` | Detailed validation results for all PDFs |
| `PermanentFailures.txt` | PDFs that failed all retry attempts |
| `ErrorLog_Validation_TIMESTAMP.txt` | Error log for validation process |

### Edge Cases Handled

- **Output folder doesn't exist**: Script exits gracefully with info message (normal on first run)
- **ExpenseList.xml missing**: Validation proceeds, retry skipped with warning
- **Credentials unavailable**: Validation proceeds, retry disabled
- **State file corrupt**: Automatically recovers from backup or initializes fresh

## Configuration Options

### ChromeRiverAPI

| Setting | Description | Default |
|---------|-------------|---------|
| `BaseUrl` | Chrome River API endpoint | Required |
| `DaysBack` | Number of days to look back for expenses | 30 |
| `MaxParallelDownloads` | Maximum concurrent downloads | 5 |

### OutputSettings

| Setting | Description |
|---------|-------------|
| `OutputFolder` | Directory for downloaded PDF files |
| `MasterListFile` | Text file tracking processed voucher invoices |
| `ExpenseListFile` | XML file with expense list from API |
| `ErrorLogPrefix` | Prefix for error log files (timestamp appended) |

### APIParameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `GetMileageDetails` | Include mileage details | true |
| `GetImage` | Include receipt images | true |
| `GetPDFReport` | Generate PDF report | true |
| `GetPDFReportWithNotes` | Include notes in PDF | true |
| `ImageFirst` | Prioritize images over PDF | false |
| `FailOnImageFetchError` | Fail if image fetch errors | false |

### ValidationSettings ⭐ NEW

| Setting | Description | Default |
|---------|-------------|---------|
| `MaxRetryAttempts` | Maximum retry attempts for corrupt PDFs | 3 |
| `RetryStateFile` | Filename for retry state tracking | PDFRetryState.json |
| `ValidationReportFile` | Filename for validation reports | ValidationReport.txt |
| `PermanentFailuresFile` | Filename for permanent failure log | PermanentFailures.txt |

**Note**: All ValidationSettings files are created in the `OutputFolder` directory.

## Security Considerations

- **Credential Encryption**: API credentials are encrypted using Windows DPAPI (Data Protection API)
- **User-Specific**: Encrypted credentials can only be decrypted by the user who created them
- **Machine-Specific**: Credentials are tied to the specific machine
- **No Plaintext Storage**: Credentials are never stored in plaintext
- **Log Safety**: Error logs do not contain API keys or sensitive credentials

**Important**: Do not share your `credentials.json` file or commit it to version control.

## Performance Optimization

The script includes several optimizations:

1. **In-Memory HashSet**: Master list loaded once into memory for O(1) lookup
2. **Pre-filtering**: Expenses filtered before parallel processing
3. **Runspace Pooling**: Efficient parallel execution without process overhead
4. **Batch Updates**: Master list updated in batches, not per-file
5. **Thread-Safe Operations**: Synchronized hashtables and mutexes for concurrency

## Troubleshooting

### Get-ExpenseImages.ps1 Issues

#### Error: Configuration file not found

**Solution**: Create `config.json` from `config.template.json` and configure it with your settings.

#### Error: Credentials not found

**Solution**: Run `scripts/Setup-SecureCredentials.ps1` to configure your API credentials.

#### Error: API authentication failed

**Solution**: Verify your API key, Chain ID, and Customer Code are correct. Re-run the credential setup if needed.

#### Downloads are slow

**Solution**: Increase `MaxParallelDownloads` in `config.json` (recommended: 5-10, depending on network and API limits).

#### Script hangs or times out

**Solution**: Check network connectivity and Chrome River API status. Reduce `MaxParallelDownloads` if experiencing throttling.

### Test-ExpenseImageIntegrity.ps1 Issues

#### Output folder doesn't exist

**Behavior**: Script exits gracefully with info message stating the folder will be created on first download run.

**Solution**: This is normal if you haven't run `Get-ExpenseImages.ps1` yet. Run the download script first.

#### All PDFs marked as corrupt

**Possible Causes**:
- PDFs are legitimately corrupt (network issues during download)
- Files are not actually PDFs (wrong file extension)

**Solution**: Check the `ValidationReport.txt` for detailed reasons. If false positives, check PDF structure.

#### Retries keep failing

**Possible Causes**:
- API issues (server-side problems)
- Network connectivity problems
- Authentication issues

**Solution**:
1. Check error logs for specific error messages
2. Verify API credentials are still valid
3. Check `PermanentFailures.txt` for failure patterns
4. Manual intervention may be required for permanently failed PDFs

#### State file corrupt

**Behavior**: Script automatically attempts to restore from backup (`.bak` file) or initializes fresh state.

**Solution**: No action needed - script handles this automatically. Previous retry history may be lost.

#### Script can't acquire lock on master list file

**Possible Cause**: Another process (main download script or file explorer) has the file open.

**Solution**: Wait for other operations to complete, or close any programs that might have the file open.

## Error Logging

Failed downloads are logged to timestamped error files in the format:

```
error_log_20260206_143022.txt
```

Each error entry includes:
- Timestamp
- Report ID
- Error message

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on:
- How to report bugs
- How to suggest enhancements
- Code style guidelines
- Pull request process

Quick start:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

**Summary**: You are free to use, modify, and distribute this software. No warranty is provided.

Ensure compliance with your organization's Chrome River API usage policies.

## Changelog

### Version 1.1 ⭐ NEW
- **Added PDF Validation & Retry System** (`Test-ExpenseImageIntegrity.ps1`)
  - Automatic PDF corruption detection
  - Configurable retry mechanism (default: 3 attempts)
  - Persistent state tracking across executions
  - Comprehensive validation reports
  - Permanent failure tracking for manual review
- **Updated Configuration**
  - Added `ValidationSettings` section to config.json
  - Configurable retry limits and output filenames
- **Enhanced Documentation**
  - Added PDF validation workflow documentation
  - Added troubleshooting for validation issues
  - Updated deployment guides

### Version 1.0
- Initial release with PowerShell 5.1 compatibility
- Runspace-based parallel downloads
- Secure credential management
- Configuration file support
- Progress tracking and statistics
- Thread-safe error logging

## Support

For issues, questions, or feature requests, please open an issue on the GitHub repository.

---

**Note**: This script requires valid Chrome River API access. Contact your Chrome River administrator for API credentials and permissions.
