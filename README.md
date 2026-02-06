# Chrome River Expense Image Retrieval Script

A high-performance PowerShell automation tool for downloading expense report PDFs from Chrome River's API. This script features parallel downloads using runspaces, intelligent deduplication, and secure credential management.

## 📚 Documentation

- **[Security Guide](docs/README_SECURITY.md)** - Detailed security considerations and best practices
- **[Deployment Guide](docs/DEPLOYMENT_GUIDE.md)** - Enterprise deployment instructions
- **[Contributing](CONTRIBUTING.md)** - How to contribute to this project

## Features

- **Parallel Downloads**: Uses PowerShell Runspaces for concurrent PDF downloads (configurable throttle limit)
- **Smart Deduplication**: Tracks processed expenses to avoid redundant downloads
- **Secure Credentials**: Stores API keys and sensitive data using Windows DPAPI encryption
- **Progress Tracking**: Real-time progress bars and detailed statistics
- **Error Handling**: Thread-safe error logging with detailed diagnostics
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
│   ├── Get-ExpenseImages.ps1    # Main script
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

### 4. Run the Script

```powershell
.\scripts\Get-ExpenseImages.ps1
```

## Usage

The script will:

1. Load configuration from `config.json`
2. Load encrypted credentials
3. Query Chrome River API for expenses within the date range
4. Filter out already-downloaded expenses
5. Download new expense PDFs in parallel
6. Save successfully downloaded expenses to the master list
7. Display a summary report

### Sample Output

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

### Error: Configuration file not found

**Solution**: Create `config.json` from `config.template.json` and configure it with your settings.

### Error: Credentials not found

**Solution**: Run `scripts/Setup-SecureCredentials.ps1` to configure your API credentials.

### Error: API authentication failed

**Solution**: Verify your API key, Chain ID, and Customer Code are correct. Re-run the credential setup if needed.

### Downloads are slow

**Solution**: Increase `MaxParallelDownloads` in `config.json` (recommended: 5-10, depending on network and API limits).

### Script hangs or times out

**Solution**: Check network connectivity and Chrome River API status. Reduce `MaxParallelDownloads` if experiencing throttling.

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
