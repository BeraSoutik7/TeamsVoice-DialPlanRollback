<#
================================================================================
SCRIPT NAME : Backup-TeamsDialPlans.ps1
DESCRIPTION : Captures an exact, lossless JSON snapshot of Microsoft Teams Tenant
              Dial Plans (all or a single target plan), ordered Normalization
              Rules, and user-level dial plan assignments prior to change windows.
AUTHOR      : Soutik Bera
REPOSITORY  : TeamsVoice-DialPlanRollback
MODULES REQ : MicrosoftTeams (v4.0.0+)
================================================================================
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false, HelpMessage = "Optional: Backup only a single Dial Plan by Identity or SimpleName")]
    [string]$TargetDialPlanName,

    [Parameter(Mandatory = $false)]
    [string]$BackupDir = ".\backups",

    [Parameter(Mandatory = $false)]
    [string]$BackupFileName,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeUserAssignments
)

$ErrorActionPreference = 'Stop'

# Ensure backup directory exists
if (-not (Test-Path -Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

# Auto-generate descriptive filename if not manually provided
if (-not $BackupFileName) {
    $prefix = if ($TargetDialPlanName) {
        $safeName = $TargetDialPlanName -replace '[^a-zA-Z0-9_-]', '_'
        "DialPlan_$safeName"
    } else {
        "DialPlan_All"
    }
    $BackupFileName = "${prefix}_$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
}

$OutputPath = Join-Path $BackupDir $BackupFileName

# ------------------------------------------------------------------------------
# STEP 1: AUTHENTICATE TO MICROSOFT TEAMS
# ------------------------------------------------------------------------------
Write-Host "[*] Verifying Microsoft Teams session..." -ForegroundColor Cyan
try {
    $tenant = Get-CsTenant -ErrorAction Stop
    Write-Host "[+] Connected to Tenant: $($tenant.DisplayName) ($($tenant.TenantId))" -ForegroundColor Green
} catch {
    Write-Host "[*] Launching Connect-MicrosoftTeams..." -ForegroundColor Yellow
    Connect-MicrosoftTeams
    $tenant = Get-CsTenant
}

# ------------------------------------------------------------------------------
# STEP 2: EXTRACT TARGET OR ALL TENANT DIAL PLANS
# ------------------------------------------------------------------------------
if ($TargetDialPlanName) {
    Write-Host "[*] Searching for single Dial Plan: '$TargetDialPlanName'..." -ForegroundColor Cyan
    $RawDialPlans = Get-CsTenantDialPlan | Where-Object {
        $_.Identity -eq $TargetDialPlanName -or $_.SimpleName -eq $TargetDialPlanName
    }

    if (-not $RawDialPlans) {
        throw "Dial Plan '$TargetDialPlanName' was not found in the tenant. Run 'Get-CsTenantDialPlan | Select Identity, SimpleName' to verify."
    }
} else {
    Write-Host "[*] Extracting ALL Tenant Dial Plans and Normalization Rules..." -ForegroundColor Cyan
    $RawDialPlans = Get-CsTenantDialPlan
}

$SerializedDialPlans = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($dp in $RawDialPlans) {
    $rulesList = [System.Collections.Generic.List[PSCustomObject]]::new()

    if ($dp.NormalizationRules) {
        $priorityIndex = 0
        foreach ($rule in $dp.NormalizationRules) {
            $rulesList.Add([PSCustomObject]@{
                Priority            = $priorityIndex
                Name                = $rule.Name
                Description         = $rule.Description
                Pattern             = $rule.Pattern
                Translation         = $rule.Translation
                IsInternalExtension = [bool]$rule.IsInternalExtension
            })
            $priorityIndex++
        }
    }

    $SerializedDialPlans.Add([PSCustomObject]@{
        Identity             = $dp.Identity
        SimpleName           = $dp.SimpleName
        Description          = $dp.Description
        ExternalAccessPrefix = $dp.ExternalAccessPrefix
        OptimizeDeviceDialing = [bool]$dp.OptimizeDeviceDialing
        RuleCount            = $rulesList.Count
        NormalizationRules   = $rulesList
    })
}

Write-Host "[+] Captured $($SerializedDialPlans.Count) Tenant Dial Plan(s)." -ForegroundColor Green

# ------------------------------------------------------------------------------
# STEP 3: OPTIONAL USER ASSIGNMENT CAPTURE
# ------------------------------------------------------------------------------
$UserAssignments = [System.Collections.Generic.List[PSCustomObject]]::new()

if ($IncludeUserAssignments) {
    Write-Host "[*] Capturing explicit user-level TenantDialPlan assignments..." -ForegroundColor Cyan
    $UsersWithExplicitDP = Get-CsOnlineUser -Filter {TenantDialPlan -ne $null} |
        Select-Object UserPrincipalName, DisplayName, TenantDialPlan

    # If backing up a single dial plan, filter user assignments to only that plan
    if ($TargetDialPlanName) {
        $targetSimpleNames = $SerializedDialPlans.SimpleName
        $targetIdentities  = $SerializedDialPlans.Identity
        $UsersWithExplicitDP = $UsersWithExplicitDP | Where-Object {
            $_.TenantDialPlan -in $targetSimpleNames -or $_.TenantDialPlan -in $targetIdentities
        }
    }

    foreach ($u in $UsersWithExplicitDP) {
        $UserAssignments.Add([PSCustomObject]@{
            UserPrincipalName = $u.UserPrincipalName
            DisplayName       = $u.DisplayName
            TenantDialPlan    = $u.TenantDialPlan
        })
    }
    Write-Host "[+] Captured $($UserAssignments.Count) explicit user dial plan assignment(s)." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# STEP 4: ASSEMBLE & EXPORT GOLDEN BACKUP PAYLOAD
# ------------------------------------------------------------------------------
$BackupPayload = [PSCustomObject]@{
    Metadata = [PSCustomObject]@{
        BackupTimestamp         = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        BackupScope             = if ($TargetDialPlanName) { "SinglePlan ($TargetDialPlanName)" } else { "FullTenant" }
        TenantId                = $tenant.TenantId
        TenantName              = $tenant.DisplayName
        IncludedUserAssignments = [bool]$IncludeUserAssignments
        TotalDialPlans          = $SerializedDialPlans.Count
        TotalUserAssignments    = $UserAssignments.Count
    }
    DialPlans       = $SerializedDialPlans
    UserAssignments = $UserAssignments
}

$BackupPayload | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding utf8

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host "[SUCCESS] Exact Dial Plan Backup saved to:" -ForegroundColor Green
Write-Host "          $OutputPath" -ForegroundColor White
Write-Host "=======================================================" -ForegroundColor Green