# Copyright 2025 HACS Group
# Licensed under the Apache License, Version 2.0
#
# test-referral-load.ps1 — Send a large batch of synthetic referrals with variable timing
# Purpose: Generate enough traffic to produce interesting Grafana charts
# Usage: ./test-referral-load.ps1 -ApiEndpoint <url> -SubscriptionKey <key> [-Rounds 3] [-MaxDelayMs 5000]

param(
    [Parameter(Mandatory = $true)]
    [string]$ApiEndpoint,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionKey,

    [Parameter(Mandatory = $false)]
    [int]$Rounds = 3,

    [Parameter(Mandatory = $false)]
    [int]$MaxDelayMs = 5000
)

$ErrorActionPreference = "Stop"

# ── Synthetic Data Pools ──────────────────────────────────────────────────

$patients = @(
    @{ id = "PT-2025-00142"; name = "Sarah Mitchell" }
    @{ id = "PT-2025-00287"; name = "David Chen" }
    @{ id = "PT-2025-01034"; name = "Maria Gonzalez" }
    @{ id = "PT-2025-01199"; name = "James O'Brien" }
    @{ id = "PT-2025-01455"; name = "Aisha Patel" }
    @{ id = "PT-2025-01678"; name = "Robert Kim" }
    @{ id = "PT-2025-01890"; name = "Linda Thompson" }
    @{ id = "PT-2025-02001"; name = "Michael Johansson" }
    @{ id = "PT-2025-02234"; name = "Fatima Al-Rashid" }
    @{ id = "PT-2025-02567"; name = "Carlos Rivera" }
    @{ id = "PT-2025-02890"; name = "Emily Nakamura" }
    @{ id = "PT-2025-03012"; name = "William Okafor" }
    @{ id = "PT-2025-03345"; name = "Jennifer Kowalski" }
    @{ id = "PT-2025-03567"; name = "Hassan Demir" }
    @{ id = "PT-2025-03890"; name = "Rachel Bernstein" }
)

$referralTypes = @(
    @{ type = "Cardiology";          diagnoses = @(
        @{ code = "I25.10"; desc = "Atherosclerotic heart disease of native coronary artery" },
        @{ code = "I48.91"; desc = "Unspecified atrial fibrillation" },
        @{ code = "I50.9";  desc = "Heart failure, unspecified" }
    )}
    @{ type = "Orthopedics";         diagnoses = @(
        @{ code = "M17.11"; desc = "Primary osteoarthritis, right knee" },
        @{ code = "M75.10"; desc = "Rotator cuff tear, unspecified shoulder" },
        @{ code = "S72.001A"; desc = "Fracture of unspecified part of neck of right femur" }
    )}
    @{ type = "Physical Therapy";    diagnoses = @(
        @{ code = "M54.5";  desc = "Low back pain" },
        @{ code = "M79.3";  desc = "Panniculitis, unspecified" },
        @{ code = "G89.29"; desc = "Other chronic pain" }
    )}
    @{ type = "Neurology";           diagnoses = @(
        @{ code = "G43.909"; desc = "Migraine, unspecified, not intractable" },
        @{ code = "G40.909"; desc = "Epilepsy, unspecified, not intractable" },
        @{ code = "G20";     desc = "Parkinson's disease" }
    )}
    @{ type = "Gastroenterology";    diagnoses = @(
        @{ code = "K21.0";  desc = "Gastro-esophageal reflux disease with esophagitis" },
        @{ code = "K50.90"; desc = "Crohn's disease, unspecified, without complications" },
        @{ code = "K76.0";  desc = "Fatty liver, not elsewhere classified" }
    )}
    @{ type = "Pulmonology";         diagnoses = @(
        @{ code = "J44.1";  desc = "Chronic obstructive pulmonary disease with acute exacerbation" },
        @{ code = "J45.20"; desc = "Mild intermittent asthma, uncomplicated" },
        @{ code = "J84.10"; desc = "Pulmonary fibrosis, unspecified" }
    )}
    @{ type = "Endocrinology";       diagnoses = @(
        @{ code = "E11.65"; desc = "Type 2 diabetes mellitus with hyperglycemia" },
        @{ code = "E05.90"; desc = "Thyrotoxicosis, unspecified" },
        @{ code = "E21.0";  desc = "Primary hyperparathyroidism" }
    )}
    @{ type = "Dermatology";         diagnoses = @(
        @{ code = "L40.0";  desc = "Psoriasis vulgaris" },
        @{ code = "L20.9";  desc = "Atopic dermatitis, unspecified" },
        @{ code = "C43.9";  desc = "Malignant melanoma of skin, unspecified" }
    )}
)

$providers = @(
    "Dr. James Wilson, MD - Internal Medicine"
    "Dr. Emily Rodriguez, DO - Family Medicine"
    "Dr. Anand Krishnamurthy, MD - Emergency Medicine"
    "Dr. Catherine Dubois, MD - Family Medicine"
    "Dr. Omar Hassan, DO - Internal Medicine"
    "Dr. Patricia Yamamoto, MD - Urgent Care"
    "Dr. Steven Blackwell, DO - Family Medicine"
    "Dr. Nadia Volkov, MD - Internal Medicine"
)

# Weighted priority distribution: more normal/low to create realistic mix
$priorities = @(
    "urgent", "urgent",
    "high", "high", "high",
    "normal", "normal", "normal", "normal", "normal", "normal",
    "low", "low", "low", "low"
)

$noteTemplates = @(
    "Patient presents with worsening symptoms over the past {0} weeks. Current medications partially effective. Recommend specialist evaluation."
    "Referred for further workup. Initial labs and imaging reviewed. {0}-week follow-up recommended."
    "Chronic condition management. Patient stable but requires specialist input for treatment optimization. Duration: {0} weeks."
    "New onset symptoms. Patient evaluated in clinic, conservative management attempted for {0} weeks without improvement."
    "Post-hospitalization follow-up. Patient discharged {0} days ago, requires outpatient specialist care."
    "Screening referral per clinical guidelines. Patient has {0} risk factors identified."
    "Acute presentation requiring expedited specialist review. Symptoms duration: {0} days."
)

# ── Helper Functions ──────────────────────────────────────────────────────

function Get-RandomReferral {
    $patient   = $patients | Get-Random
    $specialty = $referralTypes | Get-Random
    $diagnosis = $specialty.diagnoses | Get-Random
    $priority  = $priorities | Get-Random
    $provider  = $providers | Get-Random
    $template  = $noteTemplates | Get-Random
    $duration  = Get-Random -Minimum 1 -Maximum 12

    return @{
        patientId         = $patient.id
        patientName       = $patient.name
        referralType      = $specialty.type
        priority          = $priority
        diagnosis         = @{
            code        = $diagnosis.code
            description = $diagnosis.desc
        }
        referringProvider = $provider
        notes             = ($template -f $duration)
    }
}

function Get-RandomInvalidReferral {
    # Randomly omit different required fields to exercise validation
    $variant = Get-Random -Minimum 1 -Maximum 4
    switch ($variant) {
        1 { return @{ patientId = "PT-2025-99901"; notes = "Missing most required fields" } }
        2 { return @{ patientId = "PT-2025-99902"; patientName = "Test Invalid"; referralType = "Cardiology" } }
        3 { return @{ patientName = "No Patient ID"; priority = "urgent" } }
    }
}

function Send-Referral {
    param(
        [hashtable]$Referral,
        [hashtable]$Headers,
        [string]$Label,
        [bool]$ExpectFailure = $false
    )

    $body = $Referral | ConvertTo-Json -Depth 3
    $priorityColor = switch ($Referral.priority) {
        "urgent" { "Red" }
        "high"   { "Magenta" }
        "normal" { "White" }
        "low"    { "Gray" }
        default  { "Yellow" }
    }

    $priorityTag = if ($Referral.priority) { "[$($Referral.priority.ToUpper())]" } else { "[INVALID]" }
    Write-Host "  $Label " -ForegroundColor Yellow -NoNewline
    Write-Host "$priorityTag " -ForegroundColor $priorityColor -NoNewline
    Write-Host "$($Referral.referralType ?? 'n/a') — $($Referral.patientName ?? 'n/a')" -ForegroundColor White -NoNewline

    try {
        $null = Invoke-RestMethod -Uri $ApiEndpoint -Method Post -Headers $Headers -Body $body -StatusCodeVariable statusCode
        if ($ExpectFailure) {
            Write-Host " -> $statusCode (unexpected success)" -ForegroundColor Yellow
        } else {
            Write-Host " -> 202 OK" -ForegroundColor Green
        }
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($ExpectFailure -and $code -eq 400) {
            Write-Host " -> 400 (expected)" -ForegroundColor Green
        } else {
            Write-Host " -> $code FAILED" -ForegroundColor Red
        }
    }
}

# ── Main Execution ────────────────────────────────────────────────────────

$headers = @{
    "Content-Type"              = "application/json"
    "Ocp-Apim-Subscription-Key" = $SubscriptionKey
}

$totalValid   = $Rounds * $patients.Count
$totalInvalid = $Rounds * 2
$totalAll     = $totalValid + $totalInvalid

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Healthcare Referral Load Test" -ForegroundColor Cyan
Write-Host " Rounds: $Rounds | Referrals per round: $($patients.Count + 2) ($($patients.Count) valid + 2 invalid)" -ForegroundColor Cyan
Write-Host " Total: $totalAll referrals | Max delay: ${MaxDelayMs}ms" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$sent      = 0
$invalid   = 0
$startTime = Get-Date

for ($round = 1; $round -le $Rounds; $round++) {

    Write-Host "── Round $round/$Rounds ──────────────────────────────────" -ForegroundColor Cyan

    # Send valid referrals with variable delays
    foreach ($patient in $patients) {
        $sent++
        $referral = Get-RandomReferral
        # Override patient to ensure all patients appear each round
        $referral.patientId   = $patient.id
        $referral.patientName = $patient.name

        Send-Referral -Referral $referral -Headers $headers -Label "[$sent/$totalAll]"

        # Variable delay: sometimes burst (0ms), sometimes slow (up to MaxDelayMs)
        $delayPattern = Get-Random -Minimum 0 -Maximum 100
        if ($delayPattern -lt 20) {
            # 20% chance: burst — no delay
            $delayMs = 0
        } elseif ($delayPattern -lt 50) {
            # 30% chance: short delay
            $delayMs = Get-Random -Minimum 100 -Maximum ([Math]::Max(500, $MaxDelayMs / 4))
        } elseif ($delayPattern -lt 80) {
            # 30% chance: medium delay
            $delayMs = Get-Random -Minimum 500 -Maximum ([Math]::Max(1000, $MaxDelayMs / 2))
        } else {
            # 20% chance: long delay
            $delayMs = Get-Random -Minimum 1000 -Maximum $MaxDelayMs
        }

        if ($delayMs -gt 0) {
            Start-Sleep -Milliseconds $delayMs
        }
    }

    # Sprinkle in invalid referrals each round
    for ($inv = 1; $inv -le 2; $inv++) {
        $sent++
        $invalid++
        $badReferral = Get-RandomInvalidReferral
        Send-Referral -Referral $badReferral -Headers $headers -Label "[$sent/$totalAll]" -ExpectFailure $true

        $delayMs = Get-Random -Minimum 200 -Maximum 1500
        Start-Sleep -Milliseconds $delayMs
    }

    # Inter-round pause (longer gap to create visible time segments in Grafana)
    if ($round -lt $Rounds) {
        $pauseSec = Get-Random -Minimum 5 -Maximum 15
        Write-Host "`n  Round $round complete — pausing ${pauseSec}s before next round...`n" -ForegroundColor Gray
        Start-Sleep -Seconds $pauseSec
    }
}

# ── Summary ───────────────────────────────────────────────────────────────

$elapsed = (Get-Date) - $startTime

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Load Test Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Total sent:     $sent" -ForegroundColor White
Write-Host "  Valid:          $totalValid" -ForegroundColor Green
Write-Host "  Invalid:        $totalInvalid" -ForegroundColor Yellow
Write-Host "  Elapsed:        $([Math]::Round($elapsed.TotalSeconds, 1))s" -ForegroundColor White
Write-Host "  Avg rate:       $([Math]::Round($sent / $elapsed.TotalSeconds, 1)) req/s" -ForegroundColor White

Write-Host "`n  Priority distribution (approximate):" -ForegroundColor White
Write-Host "    urgent:  ~13%  -> urgent-referrals queue" -ForegroundColor Red
Write-Host "    high:    ~20%  -> urgent-referrals queue" -ForegroundColor Magenta
Write-Host "    normal:  ~40%  -> standard-referrals queue" -ForegroundColor White
Write-Host "    low:     ~27%  -> standard-referrals queue" -ForegroundColor Gray

Write-Host "`n  Grafana tips:" -ForegroundColor Cyan
Write-Host "    - Wait 5-10 min for Log Analytics ingestion" -ForegroundColor Gray
Write-Host "    - Set dashboard time range to 'Last 30 minutes'" -ForegroundColor Gray
Write-Host "    - Run again with -Rounds 5 -MaxDelayMs 8000 for more data" -ForegroundColor Gray
Write-Host ""
