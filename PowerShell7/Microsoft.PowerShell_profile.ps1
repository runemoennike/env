# ------
# Prompt
# ------
$script:LastCheckedPath = ""
$script:IsInGitRepo = $false

function Test-GitRepo
{
        param([string]$Path)
        while ($Path)
        {
                if (Test-Path (Join-Path $Path ".git"))
                { 
                        return $true 
                }
                $parent = Split-Path $Path -Parent
                if ($parent -eq $Path)
                { 
                        return $false 
                }
                $Path = $parent
        }
        return $false
}

function prompt
{
        # Colors for use in escape codes below (`e[NNm where NN is the code).
        # There are also codes 1-9 for text effects (bold etc)
        #
        #               Foreground     Background
        # No Color     normal bright  normal bright
        # 0  black       30     90      40    100
        # 1  red         31     91      41    101
        # 2  green       32     92      42    102
        # 3  yellow      33     93      43    103
        # 4  blue        34     94      44    104
        # 5  violet      35     95      45    105
        # 6  turqoise    36     96      46    106
        # 7  grey        37     97      47    107

        $realExitCode = $global:LASTEXITCODE
        $currentPath = $PWD.Path

        # PS identifier.
        $prompt = "`e[37mPS` "

        # Path.
        $prompt += "`e[96m$currentPath "

        # Git.
        if ($currentPath -ne $script:LastCheckedPath)
        {
                $script:LastCheckedPath = $currentPath
                $script:IsInGitRepo = Test-GitRepo $currentPath
        }

        if ($script:IsInGitRepo)
        {
                $status = $(git status --branch --porcelain=v2)
               
                $branch = ($status | Select-String '# branch\.head' -Raw) -replace '# branch.head (.*)$', '$1'
                $ahead = ($status | Select-String '# branch\.ab' -Raw) -replace '.*\+(\d+).*', '$1'
                $behind = ($status | Select-String '# branch\.ab' -Raw) -replace '.*-(\d+)$', '$1'
                $untracked = ($status | Where-Object { $_ -match '^\?' }).Count
                $unstagedModified = ($status | Where-Object { $_ -match '^\d .M ' }).Count
                $unstagedDeleted = ($status | Where-Object { $_ -match '^\d .D ' }).Count
                $stagedAdded = ($status | Where-Object { $_ -match '^\d A. ' }).Count
                $stagedModified = ($status | Where-Object { $_ -match '^\d (M|R). ' }).Count
                $stagedDeleted = ($status | Where-Object { $_ -match '^\d D. ' }).Count

                $prompt += "`e[95m`u{1F33F}$branch "
                if ($ahead -gt 0) { $prompt += "`e[34m`u{2197}$ahead " } 
                if ($behind -gt 0) { $prompt += "`e[34m`u{2197}$behind " } 
                if ($stagedAdded -gt 0) { $prompt += "`e[92m`e[1m`u{002B}`e[0m$stagedAdded " } 
                if ($stagedModified -gt 0) { $prompt += "`e[92m`u{270E}$stagedModified " } 
                if ($stagedDeleted -gt 0) { $prompt += "`e[92m`u{2718}$stagedDeleted " } 
                if ($unstagedModified -gt 0) { $prompt += "`e[93m`u{270E}$unstagedModified " } 
                if ($unstagedDeleted -gt 0) { $prompt += "`e[93m`u{2718}$unstagedDeleted " } 
                if ($untracked -gt 0) { $prompt += "`e[93m`e[1m`u{003F}`e[0m$untracked " } 
        }
        
        # Exit code.
        if ($realExitCode -ne 0 -and $null -ne $realExitCode)
        {
                $prompt += "`e[91m`u{1F6A9}$realExitCode`e[0m "
        }

        # Restore exitcode in case git ops failed.
        $global:LASTEXITCODE = $realExitCode

        # Return with final caret and text reset.
        return "$prompt`u{25B7} `e[0m"
}

# -----------------------------------------------------------------------------
# Aliases
# -----------------------------------------------------------------------------
# Set-Alias -Name vim -Value "neovide"
function vim
{ neovide --wsl $args 
}
Set-Alias -Name cd -Value Push-LocationAndSetTitle -Option AllScope
Set-Alias -Name cd- -Value Pop-LocationAndSetTitle -Option AllScope
Set-Alias -Name csi -Value "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\Roslyn\csi.exe" -Option AllScope

# -----------------------------------------------------------------------------
# Directory Navigation
# -----------------------------------------------------------------------------
function cddh
{ param([string]$subDirInfix); cdTwice "D:\Repos\DataHub" $subDirInfix 
}
function cdmt
{ param([string]$subDirInfix); cdTwice "D:\Repos\Multitenancy" $subDirInfix 
}
function cdml
{ param([string]$subDirInfix); cd "D:\Repos\MachineLearning"; ./Cli/.venv/Scripts/Activate; cdTwice "." $subDirInfix 
}
function cdr
{ cd "D:\Repos" 
}

function cdTwice
{
        param([string]$base, [string]$subDirInfix)
        cd $base
        if ($subDirInfix)
        { cd (Get-ChildItem "*$subDirInfix*")[0] 
        }
}

function Push-LocationAndSetTitle
{ Push-Location @args 
}
function Pop-LocationAndSetTitle
{ Pop-Location @args 
}

function title
{
        param([Parameter(Mandatory)][string]$Title)
        $Host.UI.RawUI.WindowTitle = $Title
}

# -----------------------------------------------------------------------------
# Git Helpers
# -----------------------------------------------------------------------------
function Get-GitDirtySubDirs
{
        Get-ChildItem -Directory | ForEach-Object {
                Push-Location $_
                Write-Output $_.Name
                git status --short
                Pop-Location
        }
}

function Get-GitSubDirBranches
{
        Get-ChildItem -Directory | ForEach-Object {
                Push-Location $_
                Write-Output $_.Name
                git branch --format '%(HEAD) %(align:15,left)%(refname:short)%(end) --> %(align:20,right)%(upstream:short)%(end) %(upstream:track)'
                Write-Output ""
                Pop-Location
        }
}

function Switch-GitSubDirBranch
{
        param([string]$branch)
        Get-ChildItem -Directory | ForEach-Object {
                Push-Location $_
                Write-Output $_.Name
                git checkout $branch
                git pull
                Pop-Location
        }
}

function Merge-FromGitBranch
{
        param([string]$branch)
        git stash
        git checkout $branch
        git pull
        git checkout -
        git merge $branch
        git stash pop
}

function Remove-GitGoneBranches
{
        git fetch --prune
        git branch --list --format "%(if:equals=[gone])%(upstream:track)%(then)%(refname)%(end)" |
                Where-Object { $_ -ne "" } |
                ForEach-Object { $_ -replace '^refs/heads/', '' } |
                ForEach-Object { git branch -D $_ }
}

# -----------------------------------------------------------------------------
# Application Shortcuts
# -----------------------------------------------------------------------------
function vs
{ Start-Process (Get-ChildItem *.sln)[0] 
}

# -----------------------------------------------------------------------------
# System Utilities
# -----------------------------------------------------------------------------
function freedom
{ Get-Process -Name "pending" -ErrorAction SilentlyContinue | Stop-Process 
}
function elevate
{ Start-Process pwsh -Verb runAs 
}

function br
{
        param([int]$brightness)
        lux set --monitor 0 --brightness $brightness
        Write-Output "Setting brightness to $brightness%."
}
