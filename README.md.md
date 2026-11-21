# TeamsVoice-DialPlanRollback

[![PowerShell](https://img.shields.io/badge/PowerShell-7.2+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Platform](https://img.shields.io/badge/Platform-Microsoft%20Teams%20Phone-0078D4.svg)](https://learn.microsoft.com/microsoftteams/teams-phone)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

An automated **pre-change state capture** and **instant disaster-recovery rollback engine** for Microsoft Teams Phone System **Tenant Dial Plans**, **Voice Normalization Rules**, and **User Dial Plan Policy Assignments**.

---

## 🎯 Project Overview & Why It Exists

Modifying regex-based **Voice Normalization Rules** (e.g., `^(\d{5})$` $\rightarrow$ `+1425555$1`) during live maintenance windows carries high operational risk. A single misplaced quantifier, altered rule priority, or accidentally deleted dial plan can immediately break internal extension dialing, PSTN external access prefixes, or emergency routing across entire branch offices.

`TeamsVoice-DialPlanRollback` eliminates manual reconstruction guesswork by providing a deterministic, two-script safety net:

1. **`src/Backup-TeamsDialPlans.ps1` (Pre-Change State Capture Engine):**
   Captures an exact, lossless JSON snapshot of either **all Tenant Dial Plans** or **a single targeted Dial Plan**, preserving ordered normalization rules, regex patterns, boolean flags (`IsInternalExtension`, `OptimizeDeviceDialing`), `ExternalAccessPrefix` settings, and optional user-level `TenantDialPlan` policy assignments.
2. **`src/Restore-TeamsDialPlans.ps1` (Instant Rollback Engine):**
   Reads the pre-change JSON snapshot, validates Tenant ID matching, reconstructs every normalization rule in exact priority order (`-InMemory`), and atomically overwrites modified dial plans or recreates deleted ones within seconds.

---

## 🚀 Key Engineering & Safety Features

* **Lossless JSON Serialization (`-Depth 10`):** Unlike flat CSV exports, JSON preserves nested rule arrays, exact rule execution order (`Priority`), regex escape characters, and boolean data types without flattening distortion.
* **Single-Plan or Full-Tenant Scope:** Back up or restore your entire tenant's dial plan catalog at once, or isolate a single branch dial plan via `-TargetDialPlanName`.
* **Cross-Tenant Guardrail:** Strictly validates that the connected `TenantId` matches the backup file's `TenantId` before executing any write operations, preventing accidental cross-tenant overwrites.
* **Atomic Rule Replacement:** Uses `Set-CsTenantDialPlan -NormalizationRules @{ Replace = $RebuiltRules }` to revert rule order and regex translations in a single transaction.
* **Deleted Dial Plan Recreation:** Automatically detects if a custom dial plan was deleted during a failed change and recreates it from scratch via `New-CsTenantDialPlan`.
* **Dry-Run Simulation (`-WhatIf`):** Full native PowerShell `SupportsShouldProcess` implementation for risk-free pre-flight verification.

---

## 📂 Repository Structure

```text
TeamsVoice-DialPlanRollback/
├── .gitignore
├── LICENSE
├── README.md
├── backups/                            # Local directory for JSON snapshots (git-ignored)
│   └── README.md                       # Data governance and retention guide
├── docs/
│   ├── ARCHITECTURE.md                 # Serialization design, regex handling & rollback safety
│   └── RUNBOOK.md                      # Step-by-step Change Window SOP
└── src/
    ├── Backup-TeamsDialPlans.ps1       # Script 1: Pre-change exact state capture engine
    └── Restore-TeamsDialPlans.ps1      # Script 2: Instant point-in-time rollback engine
```

---

## 📋 Prerequisites & Permissions

* **PowerShell:** PowerShell 7.2+ Core (Recommended) or Windows PowerShell 5.1
* **Module:** `MicrosoftTeams` PowerShell Module (v4.0.0 or higher)
* **Entra ID Role:** Teams Administrator or Global Administrator

```powershell
# Install or update the MicrosoftTeams module
Install-Module -Name MicrosoftTeams -MinimumVersion 4.0.0 -Scope CurrentUser -Repository PSGallery -Force
```

---

## 💻 Complete Command Reference

### 1. Pre-Change Backup Commands (`src/Backup-TeamsDialPlans.ps1`)

#### A. Back Up ALL Tenant Dial Plans (Dial Plans & Normalization Rules Only)
Saves an auto-timestamped JSON snapshot (`DialPlan_All_YYYYMMDD-HHmmss.json`) inside `.\backups\`:
```powershell
.\src\Backup-TeamsDialPlans.ps1
```

#### B. Back Up ALL Tenant Dial Plans + All User Policy Assignments
Captures every Tenant Dial Plan, all normalization rules, and every user who has an explicit `TenantDialPlan` assigned:
```powershell
.\src\Backup-TeamsDialPlans.ps1 -IncludeUserAssignments
```

#### C. Back Up ONLY 1 Single Dial Plan
Isolates and backs up a single target dial plan (saves as `.\backups\DialPlan_<PlanName>_YYYYMMDD-HHmmss.json`):
```powershell
.\src\Backup-TeamsDialPlans.ps1 -TargetDialPlanName "DP-5Digit-Internal"
```

#### D. Back Up ONLY 1 Single Dial Plan + Users Assigned to That Specific Plan
Captures the target dial plan and filters user assignments to only those users bound to that plan:
```powershell
.\src\Backup-TeamsDialPlans.ps1 -TargetDialPlanName "DP-5Digit-Internal" -IncludeUserAssignments
```

#### E. Custom Change-Request (CRQ) Backup File Name & Directory
Saves the snapshot with a custom ticket identifier for rapid retrieval during a change window:
```powershell
.\src\Backup-TeamsDialPlans.ps1 -BackupDir ".\backups" -BackupFileName "PreChange_CRQ10492.json" -IncludeUserAssignments
```

---

### 2. Instant Rollback & Recovery Commands (`src/Restore-TeamsDialPlans.ps1`)

#### A. Safe Dry-Run Simulation (`-WhatIf`)
Previews every dial plan, normalization rule, and user assignment that would be overwritten or recreated without making live changes:
```powershell
.\src\Restore-TeamsDialPlans.ps1 -BackupFilePath ".\backups\PreChange_CRQ10492.json" -RestoreUserAssignments -WhatIf
```

#### B. Interactive Rollback (With Confirmation Prompts)
Prompts for confirmation before modifying or recreating each dial plan:
```powershell
.\src\Restore-TeamsDialPlans.ps1 -BackupFilePath ".\backups\PreChange_CRQ10492.json"
```

#### C. Instant Emergency Rollback (`-Force` — Zero Prompts)
Reverts all dial plans and normalization rules from the backup file within seconds without interactive confirmation prompts:
```powershell
.\src\Restore-TeamsDialPlans.ps1 -BackupFilePath ".\backups\PreChange_CRQ10492.json" -Force
```

#### D. Instant Full Rollback (Dial Plans + User Assignments)
Restores both the dial plan configurations and all user-level `TenantDialPlan` grants captured in the snapshot:
```powershell
.\src\Restore-TeamsDialPlans.ps1 -BackupFilePath ".\backups\PreChange_CRQ10492.json" -RestoreUserAssignments -Force
```

#### E. Targeted Single Dial Plan Rollback (From a Full-Tenant Backup)
Restores only one specific dial plan out of a multi-plan backup file while leaving all other dial plans untouched:
```powershell
.\src\Restore-TeamsDialPlans.ps1 -BackupFilePath ".\backups\PreChange_CRQ10492.json" -TargetDialPlanName "DP-5Digit-Internal" -Force
```

#### F. One-Liner: Auto-Select Most Recent Backup & Execute Immediate Rollback
Automatically locates the newest `.json` snapshot in `.\backups\` and reverts changes immediately:
```powershell
$latestBackup = (Get-ChildItem .\backups\*.json | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
.\src\Restore-TeamsDialPlans.ps1 -BackupFilePath $latestBackup -Force
```

---

### 3. Pre-Flight & Post-Rollback Verification Commands

#### A. List All Tenant Dial Plans Before Backup
```powershell
Get-CsTenantDialPlan | Select-Object Identity, SimpleName, Description, ExternalAccessPrefix
```

#### B. Inspect Backup Metadata & Captured Rules in PowerShell
```powershell
$snapshot = Get-Content ".\backups\PreChange_CRQ10492.json" -Raw | ConvertFrom-Json
$snapshot.Metadata
$snapshot.DialPlans | Select-Object Identity, ExternalAccessPrefix, RuleCount
```

#### C. Verify Live Dial Plan Normalization After Change or Rollback
Tests how Teams normalizes an internal extension or external dialed number for a specific user:
```powershell
Test-CsEffectiveTenantDialPlan -DialedNumber "54321" -Identity "alex.wilber@contoso.com"
```

---

## 🔄 Standard Change Window Workflow

1. **Capture Baseline:** Run `Backup-TeamsDialPlans.ps1` immediately prior to touching Teams Admin Center or PowerShell.
2. **Apply Changes:** Implement your updated regex normalization rules or dial plan modifications.
3. **Validate:** Test dialing behavior using `Test-CsEffectiveTenantDialPlan` and live test calls.
4. **Rollback (If Needed):** If any regression occurs, run `Restore-TeamsDialPlans.ps1 -BackupFilePath <path> -Force` to revert the tenant back to its exact pre-change state within seconds.

---

## 👤 Author

**Soutik Bera**
* GitHub: [@BeraSoutik7](https://github.com/BeraSoutik7)

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).