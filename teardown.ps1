# SPDX-License-Identifier: MIT

<#
.SYNOPSIS
    Tears down the Azure Healthcare Referral SFI Demo environment.

.DESCRIPTION
    Deletes all resources created by the deploy script in the correct order:
    1. Flow log in NetworkWatcherRG (references VNet in main RG)
    2. Primary resource group (cascades all contained resources)
    3. Purges soft-deleted Key Vault (purge protection enabled)

.PARAMETER ResourceGroupName
    Name of the resource group to delete. Default: rg-healthcare-referral-sfi-demo

.PARAMETER Location
    Azure region where resources are deployed. Default: eastus2

.PARAMETER Force
    Skip confirmation prompts.

.PARAMETER WhatIf
    Dry-run mode — show what would be deleted without deleting anything.

.EXAMPLE
    .\teardown.ps1
    .\teardown.ps1 -Force
    .\teardown.ps1 -WhatIf
    .\teardown.ps1 -ResourceGroupName my-rg -Location eastus2 -Force
#>

[CmdletBinding(SupportsShouldProcess = $false)]
param(
    [Parameter()]
    [string]$ResourceGroupName = 'rg-healthcare-referral-sfi-demo',

    [Parameter()]
    [string]$Location = 'eastus2',

    [switch]$Force,

    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$startTime = Get-Date

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Status  { param([string]$Message) Write-Host "[INFO]  $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[OK]    $Message" -ForegroundColor Green }
function Write-Warn    { param([string]$Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-Err     { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }
function Write-DryRun  { param([string]$Message) Write-Host "[DRY-RUN] $Message" -ForegroundColor Magenta }

function Get-ElapsedTime {
    $elapsed = (Get-Date) - $startTime
    return '{0:mm\:ss}' -f $elapsed
}

# ---------------------------------------------------------------------------
# 1. Validate Azure login
# ---------------------------------------------------------------------------
Write-Status 'Validating Azure CLI login...'
$account = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Err 'Not logged in to Azure CLI. Run "az login" first.'
    exit 1
}
$accountInfo = $account | ConvertFrom-Json
Write-Success "Logged in as $($accountInfo.user.name) | Subscription: $($accountInfo.name)"

# ---------------------------------------------------------------------------
# 2. Verify the resource group exists
# ---------------------------------------------------------------------------
Write-Status "Checking resource group '$ResourceGroupName'..."
$rgExists = az group exists --name $ResourceGroupName 2>&1
if ($rgExists -ne 'true') {
    Write-Warn "Resource group '$ResourceGroupName' does not exist. Nothing to tear down."
    exit 0
}
Write-Success "Resource group '$ResourceGroupName' found."

# ---------------------------------------------------------------------------
# 3. Discover baseName from resources in the RG
# ---------------------------------------------------------------------------
Write-Status 'Discovering baseName from deployed resources...'
$baseName = $null

# Try Log Analytics workspace first — name pattern: ${baseName}-law
$laws = az monitor log-analytics workspace list --resource-group $ResourceGroupName --query '[].name' -o tsv 2>&1
if ($LASTEXITCODE -eq 0 -and $laws) {
    $lawName = ($laws -split "`n" | Select-Object -First 1).Trim()
    if ($lawName -match '^(.+)-law$') {
        $baseName = $Matches[1]
    }
}

# Fallback: try Key Vault — name pattern: ${baseName}-kv (truncated to 24 chars)
if (-not $baseName) {
    $vaults = az keyvault list --resource-group $ResourceGroupName --query '[].name' -o tsv 2>&1
    if ($LASTEXITCODE -eq 0 -and $vaults) {
        $vaultName = ($vaults -split "`n" | Select-Object -First 1).Trim()
        if ($vaultName -match '^(.+)-kv$') {
            $baseName = $Matches[1]
        }
    }
}

# Fallback: try VNet — name pattern: ${baseName}-vnet
if (-not $baseName) {
    $vnets = az network vnet list --resource-group $ResourceGroupName --query '[].name' -o tsv 2>&1
    if ($LASTEXITCODE -eq 0 -and $vnets) {
        $vnetName = ($vnets -split "`n" | Select-Object -First 1).Trim()
        if ($vnetName -match '^(.+)-vnet$') {
            $baseName = $Matches[1]
        }
    }
}

if ($baseName) {
    Write-Success "Discovered baseName: $baseName"
} else {
    Write-Warn 'Could not discover baseName. Flow log and Key Vault purge steps will be skipped.'
}

# ---------------------------------------------------------------------------
# 4. Discover resources for summary
# ---------------------------------------------------------------------------
Write-Status 'Enumerating resources in resource group...'
$resources = az resource list --resource-group $ResourceGroupName --query '[].{name:name, type:type}' -o json 2>&1 | ConvertFrom-Json
$resourceCount = ($resources | Measure-Object).Count

$flowLogName = if ($baseName) { "$baseName-flowlog-vnet" } else { $null }
$vaultName   = if ($baseName) { "$baseName-kv".Substring(0, [Math]::Min("$baseName-kv".Length, 24)) } else { $null }

# ---------------------------------------------------------------------------
# 5. Show summary
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '============================================================' -ForegroundColor Yellow
Write-Host '  TEARDOWN SUMMARY' -ForegroundColor Yellow
Write-Host '============================================================' -ForegroundColor Yellow
Write-Host "  Resource Group : $ResourceGroupName"
Write-Host "  Location       : $Location"
Write-Host "  Base Name      : $(if ($baseName) { $baseName } else { '(unknown)' })"
Write-Host "  Resources      : $resourceCount resource(s) in the RG"
Write-Host ''
Write-Host '  Deletion order:' -ForegroundColor White
if ($flowLogName) {
    Write-Host "    1. Flow log        : $flowLogName (in NetworkWatcherRG)" -ForegroundColor White
} else {
    Write-Host '    1. Flow log        : (skipped — baseName unknown)' -ForegroundColor DarkGray
}
Write-Host "    2. Resource group  : $ResourceGroupName (cascades $resourceCount resources)" -ForegroundColor White
if ($vaultName) {
    Write-Host "    3. Key Vault purge : $vaultName" -ForegroundColor White
} else {
    Write-Host '    3. Key Vault purge : (skipped — baseName unknown)' -ForegroundColor DarkGray
}
Write-Host '============================================================' -ForegroundColor Yellow
Write-Host ''

if ($resources -and $resourceCount -gt 0) {
    Write-Host '  Resources that will be deleted:' -ForegroundColor White
    $resources | ForEach-Object {
        $shortType = $_.type -replace '^Microsoft\.', ''
        Write-Host "    - $($_.name)  ($shortType)" -ForegroundColor Gray
    }
    Write-Host ''
}

# ---------------------------------------------------------------------------
# 6. Confirm (unless -Force)
# ---------------------------------------------------------------------------
if ($WhatIf) {
    Write-DryRun 'Dry-run mode — no resources will be deleted.'
    Write-Host ''
    exit 0
}

if (-not $Force) {
    $confirm = Read-Host 'Are you sure you want to delete ALL of the above? (yes/no)'
    if ($confirm -notin @('yes', 'y')) {
        Write-Warn 'Teardown cancelled.'
        exit 0
    }
}

# ---------------------------------------------------------------------------
# 7. Delete flow log in NetworkWatcherRG
# ---------------------------------------------------------------------------
if ($flowLogName) {
    Write-Status "[$(Get-ElapsedTime)] Deleting flow log '$flowLogName' in NetworkWatcherRG..."
    $flowLogResult = az network watcher flow-log delete `
        --location $Location `
        --name $flowLogName 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "[$(Get-ElapsedTime)] Flow log deleted."
    } else {
        Write-Warn "[$(Get-ElapsedTime)] Flow log deletion returned an error (may not exist): $flowLogResult"
    }
} else {
    Write-Warn 'Skipping flow log deletion — baseName not discovered.'
}

# ---------------------------------------------------------------------------
# 8. Delete resource group (cascades all resources)
# ---------------------------------------------------------------------------
Write-Status "[$(Get-ElapsedTime)] Deleting resource group '$ResourceGroupName'... (this may take several minutes)"
$rgResult = az group delete --name $ResourceGroupName --yes --no-wait 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Success "[$(Get-ElapsedTime)] Resource group deletion initiated (--no-wait)."
    Write-Status 'Waiting for resource group deletion to complete...'
    az group wait --deleted --resource-group $ResourceGroupName --timeout 1800 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "[$(Get-ElapsedTime)] Resource group '$ResourceGroupName' deleted."
    } else {
        Write-Err "[$(Get-ElapsedTime)] Timed out waiting for resource group deletion. Check the Azure portal."
    }
} else {
    Write-Err "[$(Get-ElapsedTime)] Failed to delete resource group: $rgResult"
}

# ---------------------------------------------------------------------------
# 9. Purge soft-deleted Key Vault
# ---------------------------------------------------------------------------
if ($vaultName) {
    Write-Status "[$(Get-ElapsedTime)] Purging soft-deleted Key Vault '$vaultName'..."
    # Verify the vault is in the deleted list
    $deletedVault = az keyvault list-deleted --query "[?name=='$vaultName'].name" -o tsv 2>&1
    if ($LASTEXITCODE -eq 0 -and $deletedVault) {
        $purgeResult = az keyvault purge --name $vaultName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "[$(Get-ElapsedTime)] Key Vault '$vaultName' purged."
        } else {
            Write-Err "[$(Get-ElapsedTime)] Failed to purge Key Vault: $purgeResult"
        }
    } else {
        Write-Warn "[$(Get-ElapsedTime)] Key Vault '$vaultName' not found in soft-deleted list. May already be purged."
    }
} else {
    Write-Warn 'Skipping Key Vault purge — baseName not discovered.'
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
$elapsed = (Get-Date) - $startTime
Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host "  TEARDOWN COMPLETE  (elapsed: $($elapsed.ToString('hh\:mm\:ss')))" -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
