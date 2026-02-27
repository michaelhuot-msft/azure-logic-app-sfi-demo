# Licensed under the Apache License, Version 2.0
#
# test-referral.ps1 — Send synthetic test referrals through the demo pipeline
# Usage: ./test-referral.ps1 -ApiEndpoint <url> -SubscriptionKey <key>

param(
    [Parameter(Mandatory = $true)]
    [string]$ApiEndpoint,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionKey
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Healthcare Referral Test Suite" -ForegroundColor Cyan
Write-Host " Sending 3 synthetic test referrals" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$headers = @{
    "Content-Type"              = "application/json"
    "Ocp-Apim-Subscription-Key" = $SubscriptionKey
}

# ── Test 1: Urgent Cardiology Referral ──────────────────────────────────

Write-Host "[Test 1/3] Urgent Cardiology Referral" -ForegroundColor Yellow
Write-Host "  Expected: 202 Accepted -> routes to urgent-referrals queue" -ForegroundColor Gray

$urgentReferral = @{
    patientId        = "PT-2025-00142"
    patientName      = "Sarah Mitchell"
    referralType     = "Cardiology"
    priority         = "urgent"
    diagnosis        = @{
        code        = "I25.10"
        description = "Atherosclerotic heart disease of native coronary artery without angina pectoris"
    }
    referringProvider = "Dr. James Wilson, MD - Internal Medicine"
    notes            = "Patient presents with exertional dyspnea and chest tightness. ECG shows ST-segment changes. Recommend urgent cardiology evaluation within 48 hours."
} | ConvertTo-Json -Depth 3

try {
    $response = Invoke-RestMethod -Uri $ApiEndpoint -Method Post -Headers $headers -Body $urgentReferral -StatusCodeVariable statusCode
    Write-Host "  Status: 202 Accepted" -ForegroundColor Green
    Write-Host "  Correlation ID: $($response.correlationId)" -ForegroundColor Green
    Write-Host "  Message: $($response.message)" -ForegroundColor Green
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Write-Host "  Status: $code" -ForegroundColor Red
    Write-Host "  Error: $($_.ErrorDetails.Message)" -ForegroundColor Red
}

Write-Host "`n  Waiting 3 seconds for demo pacing...`n" -ForegroundColor Gray
Start-Sleep -Seconds 3

# ── Test 2: Normal Physical Therapy Referral ──────────────────────────────

Write-Host "[Test 2/3] Normal Physical Therapy Referral" -ForegroundColor Yellow
Write-Host "  Expected: 202 Accepted -> routes to standard-referrals queue" -ForegroundColor Gray

$normalReferral = @{
    patientId        = "PT-2025-00287"
    patientName      = "David Chen"
    referralType     = "Physical Therapy"
    priority         = "normal"
    diagnosis        = @{
        code        = "M54.5"
        description = "Low back pain"
    }
    referringProvider = "Dr. Emily Rodriguez, DO - Family Medicine"
    notes            = "Chronic low back pain, 6-week duration. Conservative management with NSAIDs partially effective. Recommend PT evaluation for core strengthening program."
} | ConvertTo-Json -Depth 3

try {
    $response = Invoke-RestMethod -Uri $ApiEndpoint -Method Post -Headers $headers -Body $normalReferral -StatusCodeVariable statusCode
    Write-Host "  Status: 202 Accepted" -ForegroundColor Green
    Write-Host "  Correlation ID: $($response.correlationId)" -ForegroundColor Green
    Write-Host "  Message: $($response.message)" -ForegroundColor Green
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Write-Host "  Status: $code" -ForegroundColor Red
    Write-Host "  Error: $($_.ErrorDetails.Message)" -ForegroundColor Red
}

Write-Host "`n  Waiting 3 seconds for demo pacing...`n" -ForegroundColor Gray
Start-Sleep -Seconds 3

# ── Test 3: Invalid Payload (validation error) ──────────────────────────

Write-Host "[Test 3/3] Invalid Payload (missing required fields)" -ForegroundColor Yellow
Write-Host "  Expected: 400 Bad Request -> schema validation failure" -ForegroundColor Gray

$invalidReferral = @{
    patientId = "PT-2025-00999"
    notes     = "This referral is intentionally missing required fields to demonstrate validation."
} | ConvertTo-Json -Depth 3

try {
    $response = Invoke-RestMethod -Uri $ApiEndpoint -Method Post -Headers $headers -Body $invalidReferral -StatusCodeVariable statusCode
    Write-Host "  Status: $statusCode" -ForegroundColor Yellow
    Write-Host "  Response: $($response | ConvertTo-Json -Compress)" -ForegroundColor Yellow
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code -eq 400) {
        Write-Host "  Status: 400 Bad Request (expected)" -ForegroundColor Green
        Write-Host "  Validation correctly rejected incomplete referral" -ForegroundColor Green
    } else {
        Write-Host "  Status: $code" -ForegroundColor Red
        Write-Host "  Error: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
}

# ── Summary ──────────────────────────────────────────────

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Test Complete — Verify in Azure Portal" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`n  1. Logic Apps > Run history" -ForegroundColor White
Write-Host "     - Intake: 3 runs (2 succeeded, 1 failed)" -ForegroundColor Gray
Write-Host "     - Router: 2 runs (both succeeded)" -ForegroundColor Gray

Write-Host "`n  2. Service Bus > Queues" -ForegroundColor White
Write-Host "     - urgent-referrals:   1 message (Sarah Mitchell)" -ForegroundColor Gray
Write-Host "     - standard-referrals: 1 message (David Chen)" -ForegroundColor Gray

Write-Host "`n  3. Log Analytics (may take 5-10 min)" -ForegroundColor White
Write-Host "     - KQL: AzureDiagnostics | where ResourceProvider == 'MICROSOFT.LOGIC'" -ForegroundColor Gray
Write-Host ""
