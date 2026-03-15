# Licensed under the Apache License, Version 2.0
#
# deploy.ps1 — Deploy Azure Logic Apps Healthcare Referral Demo
# Usage: ./deploy.ps1 [-ResourceGroupName <name>] [-Location <region>]

param(
    [string]$ResourceGroupName = "rg-healthcare-referral-demo",
    [string]$Location = "eastus2"
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Healthcare Referral Routing Demo" -ForegroundColor Cyan
Write-Host " Azure Logic Apps Deployment" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ── Prerequisites Check ──────────────────────────────────────────────

Write-Host "[1/6] Checking prerequisites..." -ForegroundColor Yellow

# Check Az module
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Error "Azure PowerShell module (Az) is not installed. Run: Install-Module -Name Az -Scope CurrentUser"
    exit 1
}
Write-Host "  Az module: OK" -ForegroundColor Green

# Check Bicep
$bicepVersion = az bicep version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Bicep CLI is not installed. Run: az bicep install"
    exit 1
}
Write-Host "  Bicep CLI: OK" -ForegroundColor Green

# Check Azure login
$accountRaw = az account show --output json 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Not logged in to Azure. Run: az login"
    exit 1
}
$account = $accountRaw | ConvertFrom-Json
Write-Host "  Azure login: OK (subscription: $($account.name))" -ForegroundColor Green

# Best-effort: assign signed-in user Grafana Admin role during deployment
$grafanaAdminPrincipalId = az ad signed-in-user show --query id -o tsv 2>$null
if ([string]::IsNullOrWhiteSpace($grafanaAdminPrincipalId) -or $LASTEXITCODE -ne 0) {
    $grafanaAdminPrincipalId = ""
    Write-Host "  Grafana user RBAC: SKIPPED (could not resolve signed-in user object ID)" -ForegroundColor Yellow
} else {
    Write-Host "  Grafana user RBAC: will assign Grafana Admin role to current user" -ForegroundColor Green
}

# ── Create Resource Group ──────────────────────────────────────────────

Write-Host "`n[2/6] Creating resource group '$ResourceGroupName' in '$Location'..." -ForegroundColor Yellow

az group create `
    --name $ResourceGroupName `
    --location $Location `
    --tags project=healthcare-referral-demo environment=dev managedBy=bicep `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create resource group."
    exit 1
}
Write-Host "  Resource group: OK" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Check for soft-deleted Key Vault (redeploy after teardown scenario)
# ---------------------------------------------------------------------------
Write-Host "`n[2b/6] Checking for soft-deleted Key Vault..." -ForegroundColor Cyan
$keyVaultCreateMode = 'default'
$deletedVaults = az keyvault list-deleted `
    --query "[?contains(properties.vaultId, '$ResourceGroupName')].[name]" `
    -o tsv 2>$null
if ($deletedVaults) {
    Write-Host "  Found soft-deleted Key Vault(s): $deletedVaults" -ForegroundColor Yellow
    Write-Host "  Will use createMode=recover to restore the vault" -ForegroundColor Yellow
    $keyVaultCreateMode = 'recover'
} else {
    Write-Host "  No soft-deleted vaults found for this resource group" -ForegroundColor Green
}

# If Grafana already exists and the current user already has Grafana Admin,
# skip passing the admin principal parameter to avoid RoleAssignmentExists on reruns.
if (-not [string]::IsNullOrWhiteSpace($grafanaAdminPrincipalId)) {
    $existingGrafanaId = az resource list --resource-group $ResourceGroupName --resource-type Microsoft.Dashboard/grafana --query "[0].id" -o tsv 2>$null
    if (-not [string]::IsNullOrWhiteSpace($existingGrafanaId)) {
        $existingAdminRole = az role assignment list `
            --assignee-object-id $grafanaAdminPrincipalId `
            --scope $existingGrafanaId `
            --query "[?roleDefinitionName=='Grafana Admin'] | [0].id" `
            -o tsv 2>$null

        if (-not [string]::IsNullOrWhiteSpace($existingAdminRole)) {
            Write-Host "  Grafana user RBAC: Grafana Admin already assigned; skipping reassignment" -ForegroundColor Yellow
            $grafanaAdminPrincipalId = ""
        }
    }
}

# ── Deploy Bicep Template ──────────────────────────────────────────────

Write-Host "`n[3/6] Deploying infrastructure (this takes ~5-6 minutes)..." -ForegroundColor Yellow
Write-Host "  Deploying: Log Analytics, VNet, Service Bus (Premium), Key Vault," -ForegroundColor Gray
Write-Host "             Private Endpoints, Logic App Standard (VNet-integrated)," -ForegroundColor Gray
Write-Host "             APIM (StandardV2), Grafana, Diagnostics, Alerts" -ForegroundColor Gray

$deploymentName = "healthcare-demo-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$deployArgs = @(
    'deployment', 'group', 'create',
    '--resource-group', $ResourceGroupName,
    '--name', $deploymentName,
    '--template-file', 'main.bicep',
    '--parameters', 'parameters/dev.bicepparam',
    '--output', 'json',
    '--only-show-errors'
)

if (-not [string]::IsNullOrWhiteSpace($grafanaAdminPrincipalId)) {
    $deployArgs += @('--parameters', "grafanaAdminPrincipalId=$grafanaAdminPrincipalId")
}

if ($keyVaultCreateMode -ne 'default') {
    $deployArgs += @('--parameters', "keyVaultCreateMode=$keyVaultCreateMode")
}

Write-Host "  Deployment name: $deploymentName" -ForegroundColor Gray
$deploymentOutput = az @deployArgs 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed. Check the Azure Portal for details."
    Write-Host $deploymentOutput -ForegroundColor Red

    $failedOps = az deployment operation group list `
        --resource-group $ResourceGroupName `
        --name $deploymentName `
        --query "[?properties.provisioningState=='Failed'].{resource:properties.targetResource.resourceName, code:properties.statusMessage.error.code, message:properties.statusMessage.error.message}" `
        --output table 2>$null

    if (-not [string]::IsNullOrWhiteSpace($failedOps)) {
        Write-Host "`n  Failed deployment operations:" -ForegroundColor Red
        Write-Host $failedOps -ForegroundColor Red
    }

    exit 1
}

$outputsJson = az deployment group show `
    --resource-group $ResourceGroupName `
    --name $deploymentName `
    --query properties.outputs `
    --output json 2>$null

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($outputsJson)) {
    Write-Error "Deployment completed but failed to retrieve outputs."
    exit 1
}

$outputs = $outputsJson | ConvertFrom-Json
Write-Host "  Deployment: OK" -ForegroundColor Green

# ── Deploy Workflow Definitions ──────────────────────────────────────────────

Write-Host "`n[3b/6] Deploying workflow definitions to Logic App Standard..." -ForegroundColor Yellow

$logicAppName = $outputs.logicAppStandardName.value

# Create ZIP package from workflows directory
$workflowZipPath = Join-Path $env:TEMP "logic-app-workflows-$deploymentName.zip"
if (Test-Path $workflowZipPath) { Remove-Item $workflowZipPath -Force }

# Build the content package: host.json + connections.json + workflow folders at root
$stagingDir = Join-Path $env:TEMP "logic-app-staging-$deploymentName"
if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

Copy-Item -Path "workflows/host.json" -Destination $stagingDir
Copy-Item -Path "workflows/connections.json" -Destination $stagingDir
Copy-Item -Path "workflows/intake" -Destination "$stagingDir/intake" -Recurse
Copy-Item -Path "workflows/router" -Destination "$stagingDir/router" -Recurse

Compress-Archive -Path "$stagingDir/*" -DestinationPath $workflowZipPath -Force

az webapp deployment source config-zip `
    --resource-group $ResourceGroupName `
    --name $logicAppName `
    --src $workflowZipPath `
    --output none 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Warning "Workflow ZIP deploy failed. You may need to deploy workflows manually."
} else {
    Write-Host "  Workflow definitions deployed: OK" -ForegroundColor Green
}

# Cleanup staging
Remove-Item $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $workflowZipPath -Force -ErrorAction SilentlyContinue

# ── Post-Deploy Validation ──────────────────────────────────────────────

Write-Host "`n[4/6] Validating deployed resources..." -ForegroundColor Yellow

$resources = az resource list --resource-group $ResourceGroupName --output json | ConvertFrom-Json
$resourceTypes = $resources | ForEach-Object { $_.type } | Sort-Object -Unique

$expectedTypes = @(
    "Microsoft.OperationalInsights/workspaces",
    "Microsoft.ServiceBus/namespaces",
    "Microsoft.KeyVault/vaults",
    "Microsoft.Web/sites",
    "Microsoft.Web/serverfarms",
    "Microsoft.Storage/storageAccounts",
    "Microsoft.ApiManagement/service",
    "Microsoft.Dashboard/grafana",
    "Microsoft.Network/virtualNetworks",
    "Microsoft.Network/privateEndpoints",
    "Microsoft.Network/privateDnsZones",
    "Microsoft.Insights/metricAlerts",
    "Microsoft.Insights/actionGroups"
)

$allFound = $true
foreach ($type in $expectedTypes) {
    $found = $resourceTypes -contains $type
    $status = if ($found) { "OK" } else { "MISSING" }
    $color = if ($found) { "Green" } else { "Red" }
    $shortType = $type.Split("/")[-1]
    Write-Host "  $shortType : $status" -ForegroundColor $color
    if (-not $found) { $allFound = $false }
}

# Check Logic App Standard site exists
$logicAppSites = $resources | Where-Object { $_.type -eq "Microsoft.Web/sites" -and $_.kind -like "*workflowapp*" }
if ($logicAppSites.Count -ge 1) {
    Write-Host "  Logic App Standard: OK" -ForegroundColor Green
} else {
    Write-Host "  Logic App Standard: MISSING" -ForegroundColor Red
}

if (-not $allFound) {
    Write-Warning "Some resources are missing. Check the deployment in the Azure Portal."
}

# ── Output Summary ──────────────────────────────────────────────

Write-Host "`n[5/6] Deployment complete!" -ForegroundColor Green
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Deployment Outputs" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$apimEndpoint = $outputs.referralEndpoint.value
$grafanaEndpoint = $outputs.grafanaEndpoint.value

$apimName = ($resources | Where-Object { $_.type -eq "Microsoft.ApiManagement/service" } | Select-Object -First 1).name
$subscriptionSecrets = az rest --method post `
    --uri "https://management.azure.com/subscriptions/$($account.id)/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$apimName/subscriptions/referral-subscription/listSecrets?api-version=2023-05-01-preview" `
    --output json 2>$null | ConvertFrom-Json

$apimKey = $subscriptionSecrets.primaryKey

Write-Host "`n  APIM Endpoint    : $apimEndpoint" -ForegroundColor White
Write-Host "  Subscription Key : $apimKey" -ForegroundColor White
Write-Host "  Grafana Dashboard: $grafanaEndpoint" -ForegroundColor White
Write-Host "  Resource Group   : $ResourceGroupName" -ForegroundColor White

# ── Import Grafana Dashboard ──────────────────────────────────────────────

Write-Host "`n[6/6] Importing Grafana dashboard..." -ForegroundColor Yellow

$grafanaName = $outputs.grafanaName.value
$dashboardFile = "docs/grafana-dashboard.json"

if (Test-Path $dashboardFile) {
    # Grafana needs a moment to be fully ready after deployment
    Start-Sleep -Seconds 10

    try {
        $serviceBusNamespaceName = ($resources | Where-Object { $_.type -eq "Microsoft.ServiceBus/namespaces" } | Select-Object -First 1).name
        $apimServiceName = ($resources | Where-Object { $_.type -eq "Microsoft.ApiManagement/service" } | Select-Object -First 1).name
        $logAnalyticsWorkspaceResourceId = ($resources | Where-Object { $_.type -eq "Microsoft.OperationalInsights/workspaces" } | Select-Object -First 1).id
        $azureMonitorDatasourceUid = az grafana data-source list `
            --name $grafanaName `
            --resource-group $ResourceGroupName `
            --query "[?type=='grafana-azure-monitor-datasource' && isDefault].uid | [0]" `
            --output tsv 2>$null

        if ([string]::IsNullOrWhiteSpace($azureMonitorDatasourceUid)) {
            $azureMonitorDatasourceUid = "azure-monitor-oob"
        }

        $resolvedDashboardPath = Join-Path $env:TEMP "grafana-dashboard-resolved-$deploymentName.json"
        $dashboardTemplate = Get-Content $dashboardFile -Raw
        $resolvedDashboard = $dashboardTemplate.Replace('${RG}', $ResourceGroupName)
        $resolvedDashboard = $resolvedDashboard.Replace('${SB_NAMESPACE}', $serviceBusNamespaceName)
        $resolvedDashboard = $resolvedDashboard.Replace('${APIM_NAME}', $apimServiceName)
        $resolvedDashboard = $resolvedDashboard.Replace('${DS_AZURE_MONITOR}', $azureMonitorDatasourceUid)
        $resolvedDashboard = $resolvedDashboard.Replace('${LAW_WORKSPACE_RESOURCE_ID}', $logAnalyticsWorkspaceResourceId)
        Set-Content -Path $resolvedDashboardPath -Value $resolvedDashboard -Encoding UTF8

        az grafana dashboard import `
            --name $grafanaName `
            --resource-group $ResourceGroupName `
            --definition $resolvedDashboardPath `
            --overwrite true `
            --output none

        Remove-Item $resolvedDashboardPath -Force -ErrorAction SilentlyContinue

        Write-Host "  Grafana dashboard imported: OK" -ForegroundColor Green
    } catch {
        Write-Host "  Grafana dashboard import: SKIPPED (import manually via $grafanaEndpoint)" -ForegroundColor Yellow
        Write-Host "  You can import docs/grafana-dashboard.json from the Grafana UI" -ForegroundColor Gray
    }
} else {
    Write-Host "  Dashboard file not found at $dashboardFile — skipping import" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Next Steps" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`n  Run the test script:" -ForegroundColor White
Write-Host "  ./test-referral.ps1 -ApiEndpoint '$apimEndpoint' -SubscriptionKey '$apimKey'" -ForegroundColor Yellow

Write-Host "`n  Open Grafana dashboard:" -ForegroundColor White
Write-Host "  $grafanaEndpoint" -ForegroundColor Yellow

Write-Host "`n  Tear down when done:" -ForegroundColor White
Write-Host "  az group delete --name $ResourceGroupName --yes --no-wait" -ForegroundColor Yellow
Write-Host ""
