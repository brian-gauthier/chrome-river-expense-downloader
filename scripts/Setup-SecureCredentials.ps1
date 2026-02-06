###############################
# Setup Secure Credentials for Chrome River API
# Run this ONCE to create encrypted credential file
###############################

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Chrome River API - Secure Credential Setup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Create credentials folder if it doesn't exist
$credentialFolder = Join-Path $PSScriptRoot "Credentials"
if (!(Test-Path $credentialFolder)) {
    New-Item $credentialFolder -ItemType Directory | Out-Null
    Write-Host "Created credentials folder: $credentialFolder" -ForegroundColor Green
}

# File path for encrypted credentials
$credentialFile = Join-Path $credentialFolder "ChromeRiver.cred"

Write-Host "This script will securely encrypt and store your Chrome River API credentials.`n" -ForegroundColor Yellow
Write-Host "IMPORTANT: The encrypted file will only work for:" -ForegroundColor Yellow
Write-Host "  - Current User: $env:USERNAME" -ForegroundColor Yellow
Write-Host "  - Current Machine: $env:COMPUTERNAME`n" -ForegroundColor Yellow

# Prompt for credentials
$apiKey = Read-Host "Enter your Chrome River API Key" -AsSecureString
$chainId = Read-Host "Enter your Chain ID (e.g., LawFirm) This can be anything you want, it's for troubleshooting with support"
$customerCode = Read-Host "Enter your Customer Code"

# Create credential object
$credentialObject = [PSCustomObject]@{
    ApiKey = $apiKey | ConvertFrom-SecureString  # Encrypted using DPAPI
    ChainId = $chainId
    CustomerCode = $customerCode
    CreatedBy = $env:USERNAME
    CreatedOn = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    MachineName = $env:COMPUTERNAME
}

# Save to encrypted file
try {
    $credentialObject | ConvertTo-Json | Out-File $credentialFile -Force
    Write-Host "`n[SUCCESS] Credentials encrypted and saved to:" -ForegroundColor Green
    Write-Host "  $credentialFile`n" -ForegroundColor Green

    Write-Host "Security Details:" -ForegroundColor Cyan
    Write-Host "  - API Key: Encrypted using Windows DPAPI" -ForegroundColor White
    Write-Host "  - Chain ID & Customer Code: Stored in plain text (not sensitive)" -ForegroundColor White
    Write-Host "  - Encryption is user and machine specific" -ForegroundColor White
    Write-Host "`nYou can now run the main scripts without hardcoded credentials!`n" -ForegroundColor Green
}
catch {
    Write-Host "`n[ERROR] Failed to save credentials: $_" -ForegroundColor Red
    exit 1
}

# Test reading the credentials
Write-Host "Testing credential retrieval..." -ForegroundColor Cyan
try {
    $testCred = Get-Content $credentialFile | ConvertFrom-Json
    $testApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR(
            ($testCred.ApiKey | ConvertTo-SecureString)
        )
    )

    if ($testApiKey) {
        Write-Host "[OK] Test successful: Credentials can be decrypted`n" -ForegroundColor Green
    }
}
catch {
    Write-Host "[ERROR] Test failed: $_`n" -ForegroundColor Red
}

Write-Host "========================================`n" -ForegroundColor Cyan
