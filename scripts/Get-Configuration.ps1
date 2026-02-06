###############################
# Helper Function: Load Configuration
# Returns configuration object from config.json
###############################

function Get-ChromeRiverConfiguration {
    [CmdletBinding()]
    param(
        # Look for config.json in the parent directory (root level)
        [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "config.json")
    )

    # Check if config file exists
    if (!(Test-Path $ConfigPath)) {
        throw @"
Configuration file not found: $ConfigPath

Please create config.json from the template:
1. Copy examples/config.template.json to config.json (in the root directory)
2. Update the settings for your company
3. Run scripts/Setup-SecureCredentials.ps1 to configure API credentials
"@
    }

    try {
        # Load and parse JSON
        $configContent = Get-Content $ConfigPath -Raw | ConvertFrom-Json

        # Validate required fields
        $requiredFields = @('CompanyName', 'ChromeRiverAPI', 'OutputSettings', 'APIParameters')
        foreach ($field in $requiredFields) {
            if (-not ($configContent.PSObject.Properties.Name -contains $field)) {
                throw "Missing required field in config.json: $field"
            }
        }

        # Validate ChromeRiverAPI settings
        if (-not $configContent.ChromeRiverAPI.BaseUrl) {
            throw "Missing required field: ChromeRiverAPI.BaseUrl"
        }

        # Validate OutputSettings
        if (-not $configContent.OutputSettings.OutputFolder) {
            throw "Missing required field: OutputSettings.OutputFolder"
        }

        # Set defaults if not specified
        if (-not $configContent.ChromeRiverAPI.DaysBack) {
            $configContent.ChromeRiverAPI | Add-Member -NotePropertyName DaysBack -NotePropertyValue 30
        }

        if (-not $configContent.ChromeRiverAPI.MaxParallelDownloads) {
            $configContent.ChromeRiverAPI | Add-Member -NotePropertyName MaxParallelDownloads -NotePropertyValue 5
        }

        return $configContent
    }
    catch {
        throw "Failed to load configuration from $ConfigPath : $($_.Exception.Message)"
    }
}
