# 🔐 Chrome River API - Secure Credential Setup

## Overview

This solution uses **Windows Data Protection API (DPAPI)** to securely encrypt your Chrome River API credentials. The API key is encrypted and can only be decrypted by the same user on the same machine.

## 🎯 Security Benefits

✅ **No plain text API keys** in script files
✅ **No API keys in PowerShell logs** or Event Viewer
✅ **Encrypted using Windows DPAPI** (AES-256)
✅ **User and machine specific** encryption
✅ **No cloud dependencies** or external services
✅ **Enterprise-grade security** using built-in Windows features

## 📋 Setup Instructions

### Step 1: Run the Setup Script (ONE TIME)

```powershell
.\Setup-SecureCredentials.ps1
```

You will be prompted for:
- **API Key**: Your Chrome River API key (will be encrypted)
- **Chain ID**: e.g., "LawFirm" *This can be any value you want!
- **Customer Code**: e.g., "ABC1"

The script will create an encrypted file at:
```
.\Credentials\ChromeRiver.cred
```

### Step 2: Run Your Scripts Normally

Both scripts now automatically load encrypted credentials:

**PowerShell 7+:**
```powershell
.\cr_getExpenseImages.ps1
```

**PowerShell 5.1:**
```powershell
.\cr_getExpenseImages_PS5.ps1
```

## 🔒 How It Works

1. **Setup Phase** (`Setup-SecureCredentials.ps1`)
   - Prompts for API key using `Read-Host -AsSecureString`
   - Encrypts API key using Windows DPAPI
   - Saves encrypted credentials to `Credentials\ChromeRiver.cred`

2. **Runtime Phase** (Main scripts)
   - Loads encrypted credential file
   - Decrypts API key in memory (only works for same user/machine)
   - Uses credentials for API calls
   - Credentials never written to logs in plain text

3. **Security Layer**
   - API key encrypted with AES-256
   - Encryption key stored in Windows user profile
   - Cannot be decrypted on different machine or by different user
   - SecureString prevents memory dumps from exposing credentials

## 📁 File Structure

```
ChromeRiver\
├── Setup-SecureCredentials.ps1      # One-time setup (run first)
├── Get-SecureCredentials.ps1        # Helper function (auto-loaded)
├── cr_getExpenseImages.ps1          # PowerShell 7+ version
├── cr_getExpenseImages_PS5.ps1      # PowerShell 5.1 version
└── Credentials\
    └── ChromeRiver.cred             # Encrypted credentials (auto-created)
```

## 🔄 Updating Credentials

If you need to update your API key or other credentials:

```powershell
.\Setup-SecureCredentials.ps1
```

This will overwrite the existing credential file.

## ⚠️ Important Security Notes

### ✅ DO:
- Keep the `Credentials\` folder secure
- Run the setup script as the same user who will run the main scripts
- Back up the credential file if needed (still encrypted)

### ❌ DON'T:
- Share the credential file (it's user/machine specific anyway)
- Commit the credential file to Git (add to `.gitignore`)
- Run the main scripts as a different user than who created the credentials

## 🔧 Troubleshooting

### Error: "Credential file not found"
**Solution:** Run `Setup-SecureCredentials.ps1` first

### Error: "Failed to decrypt credentials"
**Cause:** Credentials were encrypted by a different user or on a different machine
**Solution:** Run `Setup-SecureCredentials.ps1` again on the current machine/user

### Error: "The credentials were encrypted by..."
**Solution:** The current user doesn't match who encrypted the credentials. Re-run setup.

## 🔐 Alternative: Windows Credential Manager (Optional)

If you prefer using Windows Credential Manager instead:

```powershell
# Store credential (one-time)
cmdkey /generic:"ChromeRiver_API" /user:"APIKey" /pass:"your-api-key-here"

# Retrieve in script
$cred = Get-StoredCredential -Target "ChromeRiver_API"
$apiKey = $cred.GetNetworkCredential().Password
```

## 📊 Security Comparison

| Method | Security | Ease of Use | Enterprise Ready |
|--------|----------|-------------|------------------|
| **DPAPI (Current)** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ✅ Yes |
| Credential Manager | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ✅ Yes |
| Plain Text | ⭐ | ⭐⭐⭐⭐⭐ | ❌ No |
| Azure Key Vault | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ✅ Yes (Enterprise) |

## 📝 Git Configuration

Add to your `.gitignore`:

```gitignore
# Chrome River Credentials
Credentials/
*.cred
ErrorLog_*.txt
MasterExpenseList.txt
ExpenseList.xml
```

## ✅ Verification

After setup, you should see:
1. ✓ `Credentials\ChromeRiver.cred` file created
2. ✓ Scripts load credentials without errors
3. ✓ No API key visible in script files
4. ✓ API calls work correctly

---

**Security Best Practice:** Rotate API keys regularly and update using `Setup-SecureCredentials.ps1`
