# =============================================================================
# PowerShell 7 Profile - Optimized for fast startup
# =============================================================================

# Oh-my-posh custom theme (pre-cached for speed).
# Run Update-OhMyPoshCache after modifying your theme to regenerate the cache.
. "$PSScriptRoot\oh-my-posh-init.ps1"

set-alias -name vim -value "nvim-qt"
set-alias cd Push-LocationAndSetTitle -option AllScope
set-alias cd- Pop-LocationAndSetTitle -option AllScope
set-alias csi "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\Roslyn\csi.exe" -option AllScope

# Shortcuts to working directories.
function cddh
{ param([string]$subDirInfix = $null); cdTwice "D:\Repos\DataHub" $subDirInfix; 
}
function cdmt
{ param([string]$subDirInfix = $null); cdTwice  "D:\Repos\Multitenancy" $subDirInfix; 
}
function cdml
{ param([string]$subDirInfix = $null); cd "D:\Repos\MachineLearning"; ./Cli/.venv/Scripts/Activate; cdTwice  "." $subDirInfix; 
}
function cdr
{ cd "D:\Repos" 
}

function cdTwice
{ param([string]$base, [string]$subDirInfix = $null); cd $base; if ($subDirInfix)
        { cd (ls "*$subDirInfix*")[0]; 
        } 
}

# Shortcut to open solution from current directory in VSTS
function vs
{ start $(ls *.sln)[0] 
}

# Shortcut to check for dirty git repos in sub directories
function Get-GitDirtySubDirs
{ ls -dir | % { cd $_; echo $_.Name; git status --short; cd ..} 
}

# Shortcut to list git branches in sub directories
function Get-GitSubDirBranches
{ ls -dir | % { cd $_; echo $_.Name; git branch --format '%(HEAD) %(align:15,left)%(refname:short)%(end) --> %(align:20,right)%(upstream:short)%(end) %(upstream:track)'; echo ""; cd .. }
}

# Shortcut to switch git branch in sub directories
function Switch-GitSubDirBranch
{ param([string]$branch); ls -dir | % { cd $_; echo $_.Name; git checkout $branch; git pull; cd ..} 
}

# Shortcut to merge a branch into the current one.
function Merge-FromGitBranch
{ param([string]$branch); git stash; git checkout $branch; git pull; git checkout -; git merge $branch; git stash pop; 
}

function title
{
        Param(
                [Parameter(Mandatory=$true, Position=0)]
                [string]$Title
        )
    
        $Host.UI.RawUI.WindowTitle = $Title
}

function Push-LocationAndSetTitle
{
        pushd @args
    
        #Set-TitleFromCwd
}

function Pop-LocationAndSetTitle
{
        popd @args
    
        #Set-TitleFromCwd
}

function Set-TitleFromCwd
{
        $maxLength = 30
        $cwd = (Get-Location).Path
        $parts = $cwd.Split('\')
        if ($cwd.Length -gt $maxLength -and $parts.Length -ne 0)
        {
                title "$($parts[$parts.Length - 1])"
        } else
        {
                title $cwd
        }
}

# Remove git branches that do not exist on remote.
function Remove-GitGoneBranches
{
        git fetch --prune
        git branch --list --format "%(if:equals=[gone])%(upstream:track)%(then)%(refname)%(end)" | 
                ? { $_ -ne "" } | 
                % { $_ -replace '^refs/heads/', '' } | 
                % { git branch -D $_ }
}

function freedom()
{
        Get-Process -Name "pending" | Stop-Process
}

function elevate()
{
        Start-Process powershell -Verb runAs
}

function br
{
        param (
                [int]$brightness
        )
        lux set --monitor 0 --brightness $brightness
        Write-Output "Setting brightness to $brightness%."
}

# -----------------------------------------------------------------------------
# Profile Maintenance
# -----------------------------------------------------------------------------

# Regenerates the oh-my-posh init cache. Run this after modifying your theme
# configuration at c:\rune\env\oh-my-posh\rune.minimal.omp.yaml
function Update-OhMyPoshCache
{
        $cacheFile = "$PSScriptRoot\oh-my-posh-init.ps1"
        $configFile = "c:\rune\env\oh-my-posh\rune.minimal.omp.yaml"
    
        Write-Host "Regenerating oh-my-posh cache..." -ForegroundColor Cyan
        oh-my-posh init pwsh --config $configFile --print > $cacheFile
        Write-Host "Cache updated at: $cacheFile" -ForegroundColor Green
        Write-Host "Restart PowerShell to apply changes." -ForegroundColor Yellow
}
