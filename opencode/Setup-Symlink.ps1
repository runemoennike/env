# =============================================================================
# opencode Config Symlink Setup Script
# =============================================================================
# Run this from PowerShell with opencode CLOSED (all sessions/windows).
#
# This script:
# 1. Backs up any existing ~/.config/opencode directory to opencode.bak
# 2. Creates a directory junction pointing to the versioned config in this repo
#
# Directory junctions (mklink /J) do NOT require administrator privileges.
# =============================================================================

$ErrorActionPreference = "Stop"

$oldPath    = Join-Path $env:USERPROFILE ".config\opencode"
$backupPath = Join-Path $env:USERPROFILE ".config\opencode.bak"
$newPath    = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { "C:\rune\env\opencode" } else { $PSScriptRoot }
$didBackup  = $false

Write-Host "opencode Config Symlink Setup" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor Cyan
Write-Host ""

# Check the repo target exists
if (-not (Test-Path -LiteralPath $newPath)) {
    Write-Host "ERROR: Repo config folder not found: $newPath" -ForegroundColor Red
    exit 1
}

# Already a junction to our target?
$existing = Get-Item -LiteralPath $oldPath -Force -ErrorAction SilentlyContinue
if ($existing -and $existing.LinkType -eq 'Junction') {
    $target = @($existing.Target)[0]
    if ($target -and ([IO.Path]::GetFullPath($target).TrimEnd('\') -ieq [IO.Path]::GetFullPath($newPath).TrimEnd('\'))) {
        Write-Host "Junction already exists at: $oldPath" -ForegroundColor Green
        Write-Host "Pointing to: $target" -ForegroundColor Green
        exit 0
    }
}

# Step 1: back up existing directory (if present)
Write-Host "Step 1: Backing up existing config directory..." -ForegroundColor Yellow
if ($existing) {
    if (Test-Path -LiteralPath $backupPath) {
        Write-Host "  ERROR: Backup already exists: $backupPath" -ForegroundColor Red
        Write-Host "  Remove or rename it, then re-run." -ForegroundColor Yellow
        exit 1
    }
    try {
        Rename-Item -LiteralPath $oldPath -NewName "opencode.bak" -Force
        $didBackup = $true
        Write-Host "  Renamed to: $backupPath" -ForegroundColor Green
    }
    catch {
        Write-Host "  ERROR: Could not rename directory. Is opencode still running?" -ForegroundColor Red
        Write-Host "  Close ALL opencode sessions and try again." -ForegroundColor Yellow
        Write-Host "  Error: $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "  No existing directory (nothing to back up)." -ForegroundColor Yellow
}

# Step 2: create the junction
Write-Host "Step 2: Creating directory junction..." -ForegroundColor Yellow
$mklinkFailed = $false
$mklinkExitCode = 0
try {
    cmd /c mklink /J "$oldPath" "$newPath" | Out-Null
    $mklinkExitCode = $LASTEXITCODE
    if ($mklinkExitCode -ne 0) {
        $mklinkFailed = $true
    }
}
catch {
    $mklinkFailed = $true
    $mklinkExitCode = $LASTEXITCODE
}

if ($mklinkFailed) {
    if ($mklinkExitCode -ne 0) {
        Write-Host "  ERROR: Could not create junction (exit $mklinkExitCode)" -ForegroundColor Red
    }
    else {
        Write-Host "  ERROR: Could not create junction" -ForegroundColor Red
    }

    if ($didBackup) {
        Write-Host "  Attempting to restore original config..." -ForegroundColor Yellow
        try {
            Rename-Item -LiteralPath $backupPath -NewName "opencode" -Force
            Write-Host "  Original config restored. Nothing was changed." -ForegroundColor Yellow
        }
        catch {
            Write-Host "  ERROR: Could not restore original config automatically." -ForegroundColor Red
            Write-Host "  Rename this folder back to 'opencode' to restore:" -ForegroundColor Yellow
            Write-Host "  $backupPath" -ForegroundColor White
        }
    }

    exit 1
}
Write-Host "  Junction created successfully!" -ForegroundColor Green

Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Your opencode config now lives in the repo at:" -ForegroundColor Cyan
Write-Host "  $newPath" -ForegroundColor White
Write-Host ""
Write-Host "Restart opencode for the change to take effect." -ForegroundColor Yellow
Write-Host "The old directory was backed up to:" -ForegroundColor Cyan
Write-Host "  $backupPath" -ForegroundColor White
Write-Host "Delete it once you've confirmed everything works." -ForegroundColor Yellow
Write-Host ""
Write-Host "Note: node_modules was not copied (no plugin uses it). If you later" -ForegroundColor DarkGray
Write-Host "add a TypeScript plugin, run 'bun install' here to restore it." -ForegroundColor DarkGray
