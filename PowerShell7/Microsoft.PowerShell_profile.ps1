# -----------------------------------------------------------------------------
# Lazy-loaded oh-my-posh
# -----------------------------------------------------------------------------
$script:OhMyPoshLoaded = $false
$script:LastCheckedPath = ""
$script:IsInGitRepo = $false

function Test-GitRepo {
    param([string]$Path)
    while ($Path) {
        if (Test-Path (Join-Path $Path ".git")) { return $true }
        $parent = Split-Path $Path -Parent
        if ($parent -eq $Path) { return $false }
        $Path = $parent
    }
    return $false
}

function prompt {
    $realExitCode = $global:LASTEXITCODE
    $currentPath = $PWD.Path

    if ($currentPath -ne $script:LastCheckedPath) {
        $script:LastCheckedPath = $currentPath
        $script:IsInGitRepo = Test-GitRepo $currentPath
    }

    if ($script:IsInGitRepo -and -not $script:OhMyPoshLoaded) {
        $script:OhMyPoshLoaded = $true
        . "$PSScriptRoot\oh-my-posh-init.ps1"
        return (& $function:prompt)
    }

    if ($script:OhMyPoshLoaded) { return }

    $prompt = "`e[94mPS`e[0m `e[96m$currentPath`e[0m "
    if ($realExitCode -ne 0 -and $null -ne $realExitCode) {
        $prompt += "`e[91m($realExitCode)`e[0m "
    }
    $global:LASTEXITCODE = $realExitCode
    return "$prompt> "
}

# -----------------------------------------------------------------------------
# Aliases
# -----------------------------------------------------------------------------
Set-Alias -Name vim -Value "nvim-qt"
Set-Alias -Name cd -Value Push-LocationAndSetTitle -Option AllScope
Set-Alias -Name cd- -Value Pop-LocationAndSetTitle -Option AllScope
Set-Alias -Name csi -Value "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\Roslyn\csi.exe" -Option AllScope

# -----------------------------------------------------------------------------
# Directory Navigation
# -----------------------------------------------------------------------------
function cddh { param([string]$subDirInfix); cdTwice "D:\Repos\DataHub" $subDirInfix }
function cdmt { param([string]$subDirInfix); cdTwice "D:\Repos\Multitenancy" $subDirInfix }
function cdml { param([string]$subDirInfix); cd "D:\Repos\MachineLearning"; ./Cli/.venv/Scripts/Activate; cdTwice "." $subDirInfix }
function cdr { cd "D:\Repos" }

function cdTwice {
    param([string]$base, [string]$subDirInfix)
    cd $base
    if ($subDirInfix) { cd (Get-ChildItem "*$subDirInfix*")[0] }
}

function Push-LocationAndSetTitle { Push-Location @args }
function Pop-LocationAndSetTitle { Pop-Location @args }

function title {
    param([Parameter(Mandatory)][string]$Title)
    $Host.UI.RawUI.WindowTitle = $Title
}

# -----------------------------------------------------------------------------
# Git Helpers
# -----------------------------------------------------------------------------
function Get-GitDirtySubDirs {
    Get-ChildItem -Directory | ForEach-Object {
        Push-Location $_
        Write-Output $_.Name
        git status --short
        Pop-Location
    }
}

function Get-GitSubDirBranches {
    Get-ChildItem -Directory | ForEach-Object {
        Push-Location $_
        Write-Output $_.Name
        git branch --format '%(HEAD) %(align:15,left)%(refname:short)%(end) --> %(align:20,right)%(upstream:short)%(end) %(upstream:track)'
        Write-Output ""
        Pop-Location
    }
}

function Switch-GitSubDirBranch {
    param([string]$branch)
    Get-ChildItem -Directory | ForEach-Object {
        Push-Location $_
        Write-Output $_.Name
        git checkout $branch
        git pull
        Pop-Location
    }
}

function Merge-FromGitBranch {
    param([string]$branch)
    git stash
    git checkout $branch
    git pull
    git checkout -
    git merge $branch
    git stash pop
}

function Remove-GitGoneBranches {
    git fetch --prune
    git branch --list --format "%(if:equals=[gone])%(upstream:track)%(then)%(refname)%(end)" |
        Where-Object { $_ -ne "" } |
        ForEach-Object { $_ -replace '^refs/heads/', '' } |
        ForEach-Object { git branch -D $_ }
}

# -----------------------------------------------------------------------------
# Application Shortcuts
# -----------------------------------------------------------------------------
function vs { Start-Process (Get-ChildItem *.sln)[0] }

# -----------------------------------------------------------------------------
# System Utilities
# -----------------------------------------------------------------------------
function freedom { Get-Process -Name "pending" -ErrorAction SilentlyContinue | Stop-Process }
function elevate { Start-Process pwsh -Verb runAs }

function br {
    param([int]$brightness)
    lux set --monitor 0 --brightness $brightness
    Write-Output "Setting brightness to $brightness%."
}
