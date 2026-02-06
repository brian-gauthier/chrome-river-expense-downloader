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

1. Copy `config.template.json` to `config.json`:
   ```powershell
   Copy-Item config.template.json config.json
   ```

2. Edit `config.json` with your company settings:

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
.\Setup-SecureCredentials.ps1
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

**PowerShell 7+:**
```powershell
.\cr_getExpenseImages.ps1
```

**PowerShell 5.1:**
```powershell
.\cr_getExpenseImages_PS5.ps1
```

You should see:
- ✅ Configuration loaded
- ✅ Credentials loaded
- ✅ Expenses retrieved and downloaded

## 📅 Schedule Automated Execution

### Option 1: Windows Task Scheduler (Recommended)

1. Open Task Scheduler (`taskschd.msc`)
2. Create a new task:
   - **Name**: Chrome River Expense Retrieval
   - **Run whether user is logged on or not**: ✓
   - **Run with highest privileges**: ✓

3. **Triggers**: Daily at desired time (e.g., 6:00 AM)

4. **Actions**: Start a program
   - **Program**: `powershell.exe`
   - **Arguments**:
     ```
     -ExecutionPolicy Bypass -File "C:\ExpenseAutomation\ChromeRiver\cr_getExpenseImages_PS5.ps1"
     ```
   - **Start in**: `C:\ExpenseAutomation\ChromeRiver`

5. **Settings**:
   - ✓ Allow task to be run on demand
   - ✓ If the task fails, restart every 10 minutes

### Option 2: Manual Execution

Simply double-click the script or run from PowerShell:
```powershell
.\cr_getExpenseImages_PS5.ps1
```

## 🔐 Security Best Practices

### ✅ DO:
- Run setup script as the service account that will execute the task
- Keep `config.json` and `Credentials/` folder secure
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

2. **Error Log** (if failures occurred):
   ```
   ErrorLog_20260206_083022.txt
   ```

3. **Downloaded PDFs**:
   Check the `OutputFolder` specified in `config.json`

### Common Issues

| Issue | Solution |
|-------|----------|
| "Credential file not found" | Run `Setup-SecureCredentials.ps1` first |
| "Failed to decrypt credentials" | Re-run setup as the correct user |
| "Configuration file not found" | Create `config.json` from template |
| "Access denied" to output folder | Check folder permissions |
| No new expenses found | Normal if already downloaded recently |

## 📁 File Structure

```
ChromeRiver/
├── config.json                    # Your company configuration (DO NOT COMMIT)
├── config.template.json           # Template for new deployments
├── cr_getExpenseImages.ps1        # PowerShell 7+ version
├── cr_getExpenseImages_PS5.ps1    # PowerShell 5.1 version
├── Setup-SecureCredentials.ps1    # One-time credential setup
├── Get-Configuration.ps1          # Config loader (auto-loaded)
├── Get-SecureCredentials.ps1      # Credential loader (auto-loaded)
├── Credentials/
│   └── ChromeRiver.cred          # Encrypted credentials (DO NOT COMMIT)
├── MasterExpenseList.txt         # Tracking file (auto-created)
├── ExpenseList.xml               # Temp file (auto-created)
└── ErrorLog_*.txt                # Error logs (auto-created)
```

## 🔄 Updating for New Companies

1. Copy all files to new location
2. Create new `config.json` from template
3. Run `Setup-SecureCredentials.ps1` with new company's API credentials
4. Update `OutputFolder` in `config.json`
5. Test execution
6. Schedule task

**Each company needs:**
- ✅ Their own `config.json`
- ✅ Their own encrypted credentials
- ✅ Their own output folder
- ✅ Separate scheduled task (if automated)

## 📞 Support

For issues:
1. Check error logs: `ErrorLog_*.txt`
2. Verify configuration: `config.json`
3. Test credentials: Run setup script again
4. Review permissions: Output folder, network access
5. Check Chrome River API status

---

**Version**: 2.0 (Configuration-Based)
**Last Updated**: 2026-02-06
