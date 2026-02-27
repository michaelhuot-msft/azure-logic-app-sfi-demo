# Copilot Instructions — Azure Logic Apps Healthcare Referral Routing Demo

## Project Overview

This is an **Azure Infrastructure-as-Code** project that deploys a healthcare patient referral intake and priority-based routing pipeline using **Bicep**, **PowerShell**, and Azure PaaS services. There is no application code — the entire solution is declarative Bicep templates and PowerShell automation scripts.

**License**: Apache 2.0 — Copyright 2025 HACS Group  
**Copyright header**: Every source file starts with `// Copyright 2025 HACS Group` (Bicep) or `# Copyright 2025 HACS Group` (PowerShell). Preserve this in new files.

---

## Architecture (Data Flow)

```
HTTP POST → API Management (rate-limited) → Intake Logic App (validate + enrich) → Service Bus (incoming-referrals queue) → Router Logic App (priority check) → urgent-referrals OR standard-referrals queue
```

Supporting services: Key Vault (secrets), Log Analytics (diagnostics), Managed Grafana (dashboards), Managed Identity + RBAC (auth).

---

## Technology Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| IaC | **Bicep** (`.bicep`, `.bicepparam`) | All infrastructure defined as modular Bicep |
| Scripting | **PowerShell 7+** (`.ps1`) | Deployment, testing, demo helper |
| Cloud | **Azure** (Logic Apps, Service Bus, APIM, Key Vault, Log Analytics, Grafana) | All PaaS — no VMs, no containers |
| Auth | **Managed Identity + RBAC** | No passwords or connection strings at runtime |

---

## Project Structure

```
main.bicep                  # Orchestrator — calls all modules in dependency order
deploy.ps1                  # Full deployment script (prereq check → deploy → validate → Grafana import)
test-referral.ps1           # Sends 3 synthetic test referrals (urgent, normal, invalid)
demo-helper.ps1             # Pre-demo validation, Portal links, cheat sheet
parameters/
  dev.bicepparam            # Dev environment parameters (uses main.bicep)
modules/
  log-analytics.bicep       # Log Analytics workspace (30-day retention, PerGB2018)
  service-bus.bicep         # Standard namespace + 3 queues
  key-vault.bicep           # Key Vault (RBAC mode) + SB connection string secret
  api-connections.bicep     # Service Bus API connection (managed identity auth)
  logic-app-intake.bicep    # HTTP trigger → validate → enrich → enqueue
  logic-app-router.bicep    # Queue trigger → priority check → route to urgent/standard
  role-assignments.bicep    # RBAC: SB Data Sender/Receiver + KV Secrets User
  apim.bicep                # API Management Consumption tier + rate limiting
  grafana.bicep             # Managed Grafana (Essential) + self-assigned roles
  diagnostics.bicep         # Diagnostic settings for all resources → Log Analytics
docs/
  demo-script.md            # 15-minute presenter walkthrough
  grafana-dashboard.json    # Auto-imported Grafana dashboard
  architecture.excalidraw   # Visual diagram (Excalidraw)
  architecture.mermaid      # Mermaid diagram source
```

---

## Bicep Conventions (MUST FOLLOW)

### Module Interface Pattern

Most modules accept a standard triplet of parameters:

```bicep
@description('Azure region for resources')
param location string

@description('Base name for resources')
param baseName string

@description('Resource tags')
param tags object
```

Exceptions:
- `role-assignments.bicep` and `diagnostics.bicep` don't need `location` or `tags` (control-plane only).
- `api-connections.bicep` doesn't use `baseName` (hardcoded connection name).

### Naming Convention

All resource names follow: **`${baseName}-<suffix>`**

| Suffix | Resource |
|--------|----------|
| `-law` | Log Analytics Workspace |
| `-sbns` | Service Bus Namespace |
| `-kv` | Key Vault |
| `-intake` | Logic App (Intake) |
| `-router` | Logic App (Router) |
| `-apim` | API Management |
| `-grafana` | Managed Grafana |

The `baseName` is constructed in `main.bicep` as: `'hlth-${environment}-${uniqueString(resourceGroup().id)}'`

When adding new modules, follow this same naming pattern with a descriptive suffix.

### Tags

- Pass the `tags` object to every module that creates Azure resources.
- Apply tags at the top-level resource only (not child resources like queues).
- Control-plane-only modules (role assignments, diagnostics) do NOT accept tags.

### Decorators

- **Every** parameter and output MUST have a `@description()` decorator.
- Use `@secure()` for sensitive parameter values (connection strings, keys).
- Use `@description()` on outputs to document what downstream consumers should expect.

### Variables

- Use variables for resource names: `var workspaceName = '${baseName}-law'`
- Use variables for role definition GUIDs — never inline magic strings.
- Use variables to precompute complex expressions (e.g., URL parsing in APIM module).

### `existing` Keyword

Used to reference resources created by other modules:
- `service-bus.bicep` — references built-in `RootManageSharedAccessKey` auth rule
- `role-assignments.bicep` — references Service Bus namespace and Key Vault for scoped role assignments
- `diagnostics.bicep` — references all 5 target resources to attach diagnostic settings

### Role Assignments

- Use `guid(scopeResourceId, principalId, roleDefinitionId)` for deterministic, idempotent role assignment names.
- Scope to the specific resource (not the resource group) unless the role logically applies group-wide.
- Centralized in `role-assignments.bicep`, except Grafana which self-assigns its roles.

### Identity Pattern

- Logic Apps use **SystemAssigned managed identity**.
- API connections use **ManagedServiceIdentity** authentication type.
- Key Vault uses **RBAC authorization** mode (`enableRbacAuthorization: true`), not access policies.

### Dependency Wiring

Modules communicate via **outputs → parameters** in `main.bicep`. Key chains:

1. `service-bus` → `connectionString` → `key-vault`
2. `service-bus` → `namespaceName` → `api-connections` (as FQDN), `role-assignments`, `diagnostics`
3. `api-connections` → `connectionId`/`connectionName` → both Logic Apps
4. `logic-app-intake` → `callbackUrl` → `apim`
5. Both Logic Apps → `principalId` → `role-assignments`
6. `log-analytics` → `workspaceId` → `diagnostics`

When adding a new module, wire it through `main.bicep` following this pattern. Use `dependsOn` only when there's no implicit dependency through parameter references.

### Diagnostic Settings

All diagnostics follow the same pattern in `diagnostics.bicep`:

```bicep
resource existingResource '...' existing = { name: resourceName }
resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-law'
  scope: existingResource
  properties: {
    workspaceId: workspaceId
    logs: [{ category: '...', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}
```

When adding a new resource, add its diagnostic setting to this module.

---

## PowerShell Conventions (MUST FOLLOW)

### Script Structure

- Use `param()` block at the top with typed, defaulted parameters.
- Set `$ErrorActionPreference = "Stop"` at the top.
- Use numbered progress sections: `[1/N] Step description...`
- Use color-coded output: Yellow = in progress, Green = success, Red = error, Gray = detail, Cyan = headers.

### Azure CLI Usage

- All Azure operations use `az` CLI (not Az PowerShell cmdlets for resource operations).
- Always check `$LASTEXITCODE` after `az` commands.
- Parse JSON output with `ConvertFrom-Json`.
- Use `--output json` explicitly when parsing results.
- Use `--output none` when output is not needed.

### Error Handling

- Check prerequisites before any operations (Azure login, required modules, Bicep CLI).
- Exit with code 1 on any failure.
- Use `try/catch` for REST API calls (`Invoke-RestMethod`).

### Test Data

All test data is **synthetic** — no real PHI. Test referrals use:
- ICD-10 diagnosis codes (e.g., `I25.10`, `M54.5`)
- Fake patient IDs (format: `PT-YYYY-NNNNN`)
- Fake provider names

---

## Referral Schema

The intake Logic App validates incoming referrals:

```json
{
  "patientId": "string (required)",
  "patientName": "string (required)",
  "referralType": "string (required) — e.g., Cardiology, Physical Therapy",
  "priority": "enum (required) — urgent | high | normal | low",
  "diagnosis": {
    "code": "string (required) — ICD-10 code",
    "description": "string (required)"
  },
  "referringProvider": "string (required)",
  "notes": "string (optional)"
}
```

### Routing Rules

| Priority | Destination Queue |
|----------|------------------|
| `urgent` or `high` | `urgent-referrals` |
| `normal` or `low` | `standard-referrals` |

### Enrichment (added by Intake Logic App)

| Field | Value |
|-------|-------|
| `correlationId` | New GUID |
| `receivedAt` | ISO 8601 UTC timestamp |
| `status` | `"received"` |

---

## Service Bus Queue Configuration

All three queues use identical settings:
- `maxDeliveryCount`: 10
- `lockDuration`: PT1M
- `defaultMessageTimeToLive`: P14D
- `deadLetteringOnMessageExpiration`: true

Queue names: `incoming-referrals`, `urgent-referrals`, `standard-referrals`

---

## Parameters

Environment parameters are in `parameters/dev.bicepparam`:

```bicep
using '../main.bicep'
param environment = 'dev'
param publisherEmail = 'admin@healthcaredemo.com'
param publisherName = 'Healthcare Referral Demo'
```

For new environments, create `parameters/<env>.bicepparam` using the same structure.

---

## Deployment

```powershell
# Deploy everything (creates resource group + all resources)
./deploy.ps1 [-ResourceGroupName "rg-healthcare-referral-demo"] [-Location "eastus2"]

# Test with synthetic referrals
./test-referral.ps1 -ApiEndpoint "<url>" -SubscriptionKey "<key>"

# Pre-demo validation and portal links
./demo-helper.ps1 [-ResourceGroupName "rg-healthcare-referral-demo"]

# Cleanup
az group delete --name rg-healthcare-referral-demo --yes --no-wait
```

---

## Adding New Resources — Checklist

When adding a new Azure resource to this project:

1. **Create a module** in `modules/<resource>.bicep` accepting `location`, `baseName`, `tags` (if applicable).
2. **Follow naming**: `var resourceName = '${baseName}-<suffix>'`
3. **Add `@description()`** to all parameters and outputs.
4. **Use managed identity** if the resource supports it (SystemAssigned).
5. **Wire in `main.bicep`**: add module call in dependency order, pass outputs as parameters.
6. **Add RBAC** in `role-assignments.bicep` if the resource needs identity-based access.
7. **Add diagnostics** in `diagnostics.bicep` (reference via `existing`, add diagnostic setting scoped to the resource).
8. **Update `deploy.ps1`** validation if the resource type should be checked post-deployment.
9. **Preserve the copyright header** at the top of the file.
10. **Add to the deployment order comment** in `main.bicep`.

---

## Common Pitfalls

- **Key Vault naming**: Azure Key Vault names are globally unique and limited to 24 characters. The `baseName` + `-kv` must stay within limits.
- **APIM Consumption tier**: Limited diagnostics categories available. Don't expect full gateway logs.
- **Grafana role assignments**: Grafana self-assigns Monitoring Reader and Log Analytics Reader at the resource group scope — these are NOT in the centralized `role-assignments.bicep`.
- **API connection auth**: The Service Bus API connection uses `ManagedServiceIdentity` — if the Logic App's managed identity doesn't have the `Azure Service Bus Data Sender/Receiver` role, workflows will fail at runtime.
- **URL decomposition in APIM**: The APIM module uses `uri()` and `replace()` to split the Logic App callback URL into base URL and SAS-signed path for the XML policy. This is fragile if the URL format changes.
- **Queue duplication**: The three Service Bus queues share identical config but are defined separately (not via a loop). This is intentional for clarity in a demo project.

---

## Do NOT

- Do not use access policies for Key Vault — this project uses RBAC authorization mode.
- Do not store credentials in code — use Managed Identity and Key Vault.
- Do not use connection strings at runtime — the API connection uses Managed Identity auth.
- Do not add real patient data — all test data must be synthetic.
- Do not use `dependsOn` when parameter references already create implicit dependencies.
- Do not create resources outside of Bicep modules — all infrastructure is defined in `modules/`.
