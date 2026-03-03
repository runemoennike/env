# =============================================================================
# PowerShell Profile Symlink Setup Script
# =============================================================================
# Run this script from an ELEVATED PowerShell prompt (Run as Administrator)
# after closing ALL other PowerShell windows.
#
# This script:
# 1. Renames the old OneDrive PowerShell directory to PowerShell.bak
# 2. Creates a directory junction pointing to the new local profile
# =============================================================================

$ErrorActionPreference = "Stop"

$oldPath = "$env:USERPROFILE\OneDrive - FORCE Technology\Documents\PowerShell"
$backupPath = "$env:USERPROFILE\OneDrive - FORCE Technology\Documents\PowerShell.bak"
$newPath = "C:\rune\env\PowerShell7"

Write-Host "PowerShell Profile Symlink Setup" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

# Check if new profile location exists
if (-not (Test-Path $newPath)) {
    Write-Host "ERROR: New profile location not found: $newPath" -ForegroundColor Red
    exit 1
}

# Check if it's already a junction pointing to our target
$item = Get-Item $oldPath -ErrorAction SilentlyContinue
if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    # Check if it's a junction (not OneDrive reparse point)
    $reparseTag = [uint32](fsutil reparsepoint query $oldPath 2>$null | Select-String "Tag Value\s*:\s*(0x[0-9a-fA-F]+)" | ForEach-Object { $_.Matches.Groups[1].Value })
    
    # 0xA0000003 = Junction, 0x9000601a = OneDrive
    if ($reparseTag -eq 0xA0000003) {
        Write-Host "Junction already exists at: $oldPath" -ForegroundColor Green
        Write-Host "Pointing to: $($item.Target)" -ForegroundColor Green
        exit 0
    }
    elseif ($reparseTag -eq 0x9000601a) {
        Write-Host "Found OneDrive reparse point (not a junction). Will remove and replace." -ForegroundColor Yellow
    }
}

# Step 1: Rename old directory
Write-Host "Step 1: Renaming old profile directory..." -ForegroundColor Yellow
if (Test-Path $oldPath) {
    try {
        Rename-Item -Path $oldPath -NewName "PowerShell.bak" -Force
        Write-Host "  Renamed to: $backupPath" -ForegroundColor Green
    }
    catch {
        Write-Host "  ERROR: Could not rename directory. It may be in use." -ForegroundColor Red
        Write-Host "  Close ALL PowerShell windows and try again." -ForegroundColor Yellow
        Write-Host "  Error: $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "  Old directory not found (already renamed or moved)" -ForegroundColor Yellow
}

# Step 2: Create junction
Write-Host "Step 2: Creating directory junction..." -ForegroundColor Yellow
try {
    cmd /c mklink /J "$oldPath" "$newPath"
    Write-Host "  Junction created successfully!" -ForegroundColor Green
}
catch {
    Write-Host "  ERROR: Could not create junction" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Your PowerShell profile is now located at:" -ForegroundColor Cyan
Write-Host "  $newPath" -ForegroundColor White
Write-Host ""
Write-Host "The old profile was backed up to:" -ForegroundColor Cyan
Write-Host "  $backupPath" -ForegroundColor White
Write-Host ""
Write-Host "You can delete the backup after verifying everything works." -ForegroundColor Yellow
