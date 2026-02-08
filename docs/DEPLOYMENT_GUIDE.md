# 🚀 Chrome River Expense Retrieval - Deployment Guide

This guide will help you deploy the Chrome River Expense Retrieval scripts to a new company.

## 📋 Prerequisites

- Windows Server or Windows 10/11
- PowerShell 5.1 or higher (PowerShell 7+ recommended for better performance)
- Network access to Chrome River API
- Chrome River API credentials (API Key, Chain ID, Customer Code)
- Access to destination folder for PDFs

## 🔧 Initial Setup (One-Time)

### Step 1: Copy Files

Copy all files from this folder to your target location:
```
C:\ExpenseAutomation\ChromeRiver\
```

### Step 2: Create Configuration File

1. Copy `examples/config.template.json` to `scripts/config.json`:
   ```powershell
   Copy-Item examples\config.template.json scripts\config.json
   ```

2. Edit `scripts/config.json` with your company settings:

```json
{
  "CompanyName": "Your Company Name",
  "ChromeRiverAPI": {
    "BaseUrl": "https://service.chromeriver.com/expense-image-api",
    "DaysBack": 30,
    "MaxParallelDownloads": 5
  },
  "OutputSettings": {
    "OutputFolder": "C:\\ExpenseReports\\YourCompany",
    "MasterListFile": "MasterExpenseList.txt",
    "ExpenseListFile": "ExpenseList.xml",
    "ErrorLogPrefix": "ErrorLog"
  },
  "APIParameters": {
    "GetMileageDetails": false,
    "GetImage": true,
    "GetPDFReport": true,
    "GetPDFReportWithNotes": false,
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

**Configuration Options:**

| Setting | Description | Recommended Value |
|---------|-------------|-------------------|
| `CompanyName` | Your company name (for logging) | Your company name |
| `BaseUrl` | Chrome River API URL | Don't change unless instructed |
| `DaysBack` | How many days back to retrieve | 30 |
| `MaxParallelDownloads` | Concurrent downloads | 5-10 (adjust based on network) |
| `OutputFolder` | Where to save PDFs | Network path or local folder |
| `GetPDFReport` | Download PDF reports | true |
| `GetPDFReportWithNotes` | Include notes in PDF | true/false |

### Step 3: Configure API Credentials

Run the credential setup script:

```powershell
cd C:\ExpenseAutomation\ChromeRiver
.\scripts\Setup-SecureCredentials.ps1
```

Enter when prompted:
- **API Key**: Your Chrome River API key
- **Chain ID**: Your chain identifier (e.g., "CompanyName")
- **Customer Code**: Your customer code (e.g., "ABC123")

This creates an encrypted credential file that only works for:
- The current Windows user
- The current computer

**IMPORTANT**: Run this script as the same user account that will run the main scripts (e.g., service account for scheduled tasks).

### Step 4: Test the Setup

Run a test execution:

**Step 4a: Download Expense PDFs**
```powershell
.\scripts\Get-ExpenseImages.ps1
```

You should see:
- ✅ Configuration loaded
- ✅ Credentials loaded
- ✅ Expenses retrieved and downloaded

**Step 4b: Validate PDFs and Retry Failures ⭐ NEW**
```powershell
.\scripts\Test-ExpenseImageIntegrity.ps1
```

You should see:
- ✅ PDFs scanned and validated
- ✅ Corrupt PDFs identified (if any)
- ✅ Automatic retry downloads (if corrupt PDFs found)
- ✅ Validation report generated

**Note**: On first run before any PDFs are downloaded, the validation script will exit gracefully with an info message that the output folder doesn't exist yet.

## 📅 Schedule Automated Execution

### Option 1: Windows Task Scheduler (Recommended)

#### Task 1: Download Expense PDFs

1. Open Task Scheduler (`taskschd.msc`)
2. Create a new task:
   - **Name**: Chrome River Expense Retrieval - Download
   - **Run whether user is logged on or not**: ✓
   - **Run with highest privileges**: ✓

3. **Triggers**: Daily at desired time (e.g., 6:00 AM)

4. **Actions**: Start a program
   - **Program**: `powershell.exe`
   - **Arguments**:
     ```
     -ExecutionPolicy Bypass -File "C:\ExpenseAutomation\ChromeRiver\scripts\Get-ExpenseImages.ps1"
     ```
   - **Start in**: `C:\ExpenseAutomation\ChromeRiver`

5. **Settings**:
   - ✓ Allow task to be run on demand
   - ✓ If the task fails, restart every 10 minutes

#### Task 2: Validate PDFs and Retry ⭐ NEW

1. Create a second task:
   - **Name**: Chrome River Expense Retrieval - Validation
   - **Run whether user is logged on or not**: ✓
   - **Run with highest privileges**: ✓

2. **Triggers**:
   - **Option A (Recommended)**: Daily at 10 minutes after download task (e.g., 6:10 AM)
   - **Option B**: Trigger on completion of Task 1 (requires additional configuration)

3. **Actions**: Start a program
   - **Program**: `powershell.exe`
   - **Arguments**:
     ```
     -ExecutionPolicy Bypass -File "C:\ExpenseAutomation\ChromeRiver\scripts\Test-ExpenseImageIntegrity.ps1"
     ```
   - **Start in**: `C:\ExpenseAutomation\ChromeRiver`

4. **Settings**:
   - ✓ Allow task to be run on demand
   - ✓ If the task fails, restart every 5 minutes

**Alternative: Single Task with Sequential Execution**

You can also create a wrapper script to run both sequentially:

**Create `RunBothScripts.ps1`:**
```powershell
# Download PDFs
.\scripts\Get-ExpenseImages.ps1

# Validate and retry
.\scripts\Test-ExpenseImageIntegrity.ps1
```

Then schedule this single script in Task Scheduler.

### Option 2: Manual Execution

Run both scripts sequentially:
```powershell
# Download expense PDFs
.\scripts\Get-ExpenseImages.ps1

# Validate and retry corrupt PDFs
.\scripts\Test-ExpenseImageIntegrity.ps1
```

## 🔐 Security Best Practices

### ✅ DO:
- Run setup script as the service account that will execute the task
- Keep `scripts/config.json` and `scripts/Credentials/` folder secure
- Use a dedicated service account with minimal permissions
- Store credentials encrypted (done automatically)
- Review error logs regularly

### ❌ DON'T:
- Share the `Credentials/` folder or `.cred` files
- Commit `config.json` to version control
- Hardcode API keys in scripts
- Run as a highly privileged account unless necessary

## 📊 Monitoring & Troubleshooting

### Check Execution Results

After each run, review:

1. **Console Output** (if running interactively):

   **Download Script:**
   ```
   ========================================
   SUMMARY REPORT
   ========================================
   Total Expenses Found:     150
   Already Exists (File):    75
   Skipped (Master List):    25
   Successfully Downloaded:  48
   Failed:                   2
   Execution Time:           02:15
   ========================================
   ```

   **Validation Script ⭐ NEW:**
   ```
   ========================================
     VALIDATION & RETRY SUMMARY
   ========================================

   Total PDFs Scanned:       150
   Valid PDFs:               148
   Corrupt PDFs Found:       2

   Retry Attempts:           2
   Retry Successes:          2
   Retry Failures:           0
   Permanent Failures:       0

   Execution Time:           00:15
   ========================================
   ```

2. **Error Logs** (if failures occurred):
   ```
   ErrorLog_20260206_083022.txt              # Download errors
   ErrorLog_Validation_20260206_083522.txt   # Validation errors
   ```

3. **Validation Reports ⭐ NEW**:
   ```
   ValidationReport.txt       # Detailed validation results
   PermanentFailures.txt     # PDFs that failed all retry attempts
   PDFRetryState.json        # Retry state tracking
   ```

4. **Downloaded PDFs**:
   Check the `OutputFolder` specified in `scripts/config.json`

### Common Issues

| Issue | Solution |
|-------|----------|
| "Credential file not found" | Run `scripts\Setup-SecureCredentials.ps1` first |
| "Failed to decrypt credentials" | Re-run setup as the correct user |
| "Configuration file not found" | Copy `examples\config.template.json` to `scripts\config.json` |
| "Access denied" to output folder | Check folder permissions |
| No new expenses found | Normal if already downloaded recently |
| Validation script: "Output folder doesn't exist" | Normal on first run - run download script first |
| Validation script: PDFs keep failing retries | Check `PermanentFailures.txt` for details; may require manual intervention |
| Validation script: State file corrupt | Script auto-recovers from backup; no action needed |

## 📁 File Structure

```
ChromeRiver/
├── docs/                             # Documentation
│   ├── DEPLOYMENT_GUIDE.md
│   └── README_SECURITY.md
├── examples/
│   └── config.template.json          # Template for new deployments
├── scripts/
│   ├── Get-ExpenseImages.ps1   # Main script (PowerShell 5.1+)
│   ├── Get-Configuration.ps1         # Config loader (auto-loaded)
│   ├── Get-SecureCredentials.ps1     # Credential loader (auto-loaded)
│   ├── Setup-SecureCredentials.ps1   # One-time credential setup
│   ├── config.json                   # Your configuration (DO NOT COMMIT)
│   ├── Credentials/
│   │   └── ChromeRiver.cred          # Encrypted credentials (DO NOT COMMIT)
│   ├── MasterExpenseList.txt         # Tracking file (auto-created)
│   ├── ExpenseList.xml               # Temp file (auto-created)
│   └── ErrorLog_*.txt                # Error logs (auto-created)
├── .gitignore
├── CONTRIBUTING.md
├── LICENSE
└── README.md
```

## 🔄 Updating for New Companies

1. Copy all files to new location
2. Create new `scripts/config.json` from `examples/config.template.json`
3. Run `scripts\Setup-SecureCredentials.ps1` with new company's API credentials
4. Update `OutputFolder` in `scripts/config.json`
5. Test execution
6. Schedule task

**Each company needs:**
- ✅ Their own `scripts/config.json`
- ✅ Their own encrypted credentials
- ✅ Their own output folder
- ✅ Separate scheduled task (if automated)

## 📞 Support

For issues:
1. Check error logs: `ErrorLog_*.txt`
2. Verify configuration: `scripts/config.json`
3. Test credentials: Run setup script again
4. Review permissions: Output folder, network access
5. Check Chrome River API status

---

**Version**: 2.0 (Configuration-Based)
**Last Updated**: 2026-02-06
