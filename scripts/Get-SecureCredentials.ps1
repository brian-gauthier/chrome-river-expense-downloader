###############################
# Helper Function: Load Secure Credentials
# Returns decrypted credentials from encrypted file
###############################

function Get-ChromeRiverCredentials {
    [CmdletBinding()]
    param(
        [string]$CredentialPath = (Join-Path $PSScriptRoot "Credentials\ChromeRiver.cred")
    )

    if (!(Test-Path $CredentialPath)) {
        throw @"
Credential file not found: $CredentialPath

Please run Setup-SecureCredentials.ps1 first to create encrypted credentials.
"@
    }

    try {
        # Load encrypted credential file
        $credentialObject = Get-Content $CredentialPath -Raw | ConvertFrom-Json

        # Decrypt API key using DPAPI
        $secureApiKey = $credentialObject.ApiKey | ConvertTo-SecureString
        $apiKeyPlainText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureApiKey)
        )

        # Return credential object
        return [PSCustomObject]@{
            ApiKey = $apiKeyPlainText
            ChainId = $credentialObject.ChainId
            CustomerCode = $credentialObject.CustomerCode
            CreatedBy = $credentialObject.CreatedBy
            CreatedOn = $credentialObject.CreatedOn
        }
    }
    catch {
        throw @"
Failed to decrypt credentials: $($_.Exception.Message)

This could happen if:
  1. The credentials were encrypted by a different user
  2. The credentials were encrypted on a different machine
  3. The credential file is corrupted

Please run Setup-SecureCredentials.ps1 again to recreate the credentials.
"@
    }
}
