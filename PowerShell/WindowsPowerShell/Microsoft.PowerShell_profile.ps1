# Change encoding to support special characters in Source Code Pro font (doesn't seem to work.)
[Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8

# Set colours. Source: https://github.com/neilpa/cmd-colors-solarized
# . (Join-Path -Path (Split-Path -Parent -Path $PROFILE) -ChildPath $(switch($HOST.UI.RawUI.BackgroundColor.ToString()){'White'{'Set-SolarizedLightColorDefaults.ps1'}'Black'{'Set-SolarizedDarkColorDefaults.ps1'}default{return}}))

# Set colours using ColorTool
if($(get-process -pid $pid).MainWindowTitle -eq "Windows PowerShell") {
    #c:\rune\utils\colortool\colortool -q solarized_light
} else {
    #c:\rune\utils\colortool\colortool -x -q solarized_light
}

# Shortcuts to working directories.
function cdsm { cd "C:\Repos\117-22995 IoT-Structural Monitoring (GIT)\StructuralMonitoring" }
function cdae { cd "C:\Repos\116-26549 IoT-Air Emissions (GIT)\AirEmissions" }
function cddh { param([string]$subDirInfix = $null); cdTwice "C:\Repos\117-21220 DataHub" $subDirInfix; }
function cdmt { param([string]$subDirInfix = $null); cdTwice  "C:\Repos\Multitenancy" $subDirInfix; }
function cdml { param([string]$subDirInfix = $null); cdTwice  "C:\Repos\MachineLearning" $subDirInfix; activate MachineLearning}
function cdr { cd "C:\Repos" }

set-alias -name csi -value "C:\Program Files (x86)\MSBuild\14.0\Bin\csi.exe"
set-alias -name vim -value "nvim-qt"

function cdTwice { param([string]$base, [string]$subDirInfix = $null); cd $base; if ($subDirInfix) { cd (ls "*$subDirInfix*")[0]; } }

# Shortcut to launch Notepad++
function npp { start "C:\Program Files\Notepad++\notepad++.exe" @args }

# Shortcut to open solution from current directory in VSTS
function vs { start $(ls *.sln)[0] }

# Shortcut to check for dirty git repos in sub directories
function Get-GitDirtySubDirs { ls -dir | % { cd $_; echo $_.Name; git status --short; cd ..} }

# Shortcut to list git branches in sub directories
function Get-GitSubDirBranches { ls -dir | % { cd $_; echo $_.Name; git branch --format '%(HEAD) %(align:15,left)%(refname:short)%(end) --> %(align:20,right)%(upstream:short)%(end) %(upstream:track)'; echo ""; cd .. }}

# Shortcut to switch git branch in sub directories
function Switch-GitSubDirBranch { param([string]$branch); ls -dir | % { cd $_; echo $_.Name; git checkout $branch; git pull; cd ..} }

# Shortcut to merge a branch into the current one.
function Merge-FromGitBranch { param([string]$branch); git stash; git checkout $branch; git pull; git checkout -; git merge $branch; git stash pop; }

# Quickly move back and forth between visited directories.
set-alias cd Push-LocationAndSetTitle -option AllScope
set-alias cd- Pop-LocationAndSetTitle -option AllScope

# Dropdown for tab completions.
Install-GuiCompletion -Key Tab

$GuiCompletionConfig.Colors.BorderTextColor   = 'Black'
$GuiCompletionConfig.Colors.TextColor         = 'Black'
$GuiCompletionConfig.Colors.SelectedTextColor = 'Black'
$GuiCompletionConfig.Colors.SelectedBackColor = 'Gray'
$GuiCompletionConfig.Colors.BackColor         = 'Cyan'
$GuiCompletionConfig.Colors.FilterColor       = 'DarkGray'
$GuiCompletionConfig.Colors.BorderBackColor   = 'Cyan'
$GuiCompletionConfig.Colors.BorderColor       = 'Black'

# Posh git.
Import-Module posh-git
$global:GitPromptSettings.EnableWindowTitle = $null

# Chocolatey profile
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
  Import-Module "$ChocolateyProfile"
} 

function title {
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Title
    )
    
    $Host.UI.RawUI.WindowTitle = $Title
}

function debug {
    #$env:_NT_SYMBOL_PATH="srv*C:\tmp\symbols*http://msdl.microsoft.com/download/symbols;"
    $env:PATH="$($env:PATH);C:\Program Files (x86)\Windows Kits\10\Debuggers\x64"
}

# Function to autoset proxy
function proxy {
	Write-Host "Proxy setting was HTTP=$env:HTTP_PROXY and HTTPS=$env:HTTPS_PROXY"

	if (Test-Connection proxy1.ft.corp -Count 1 -ErrorAction SilentlyContinue) {
		Write-Host "Proxy detected"

		$env:HTTP_PROXY = "http://proxy1.ft.corp:3128"
		$env:HTTPS_PROXY = "http://proxy1.ft.corp:3128"
	} else {
		Write-Host "Proxy not detected"

		Remove-Item Env:\HTTP_PROXY
		Remove-Item Env:\HTTPS_PROXY
	}

	Write-Host "Proxy setting is HTTP=$env:HTTP_PROXY and HTTPS=$env:HTTPS_PROXY"
}

function Push-LocationAndSetTitle {
    pushd @args
    
    Set-TitleFromCwd
}

function Pop-LocationAndSetTitle {
    popd @args
    
    Set-TitleFromCwd
}

function Set-TitleFromCwd {
    $maxLength = 30
    $cwd = (Get-Location).Path
    $parts = $cwd.Split('\')
    if ($cwd.Length -gt $maxLength -and $parts.Length -ne 0) {
        #$title = $parts[$parts.Length - 1]
        #$n = $parts.Length - 2
        #while($title.Length -lt $maxLength -and $n -ge 0) {
        #    $title = "$($parts[$n])\$($title)"
        #}
        #title "$([char]0x2026)$($title)"
        title "$($parts[$parts.Length - 1])"
    } else {
        title $cwd
    }
}

# Remove git branches that do not exist on remote.
function Remove-GitGoneBranches {
	git fetch --prune
	git branch --list --format "%(if:equals=[gone])%(upstream:track)%(then)%(refname)%(end)" | 
		? { $_ -ne "" } | 
		% { $_ -replace '^refs/heads/', '' } | 
		% { git branch -D $_ }
}

# Create VSTS PR and assign reviewer by name
function Create-VstsPr {
	Param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Reviewer,
        [Parameter()]
        [string]$Target = "develop"
	)
	
	$createOutput = $(git pr create -t $Target)	
	$createObject = ConvertFrom-Json("$createOutput")
	
	echo "PR created with ID $($createObject.pullRequestId)"
	
	$reviewerOut = $(git pr reviewers add --id $createObject.pullRequestId --reviewers `"$Reviewer`")
	
	echo "Assigned $Reviewer."	
}

function freedom() {
	Get-Process -Name "pending" | Stop-Process
}

function elevate() {
    Start-Process powershell -Verb runAs
}

function wallpaper() {
 Set-WallPaper "~\Pictures\wallpaper.jpg" -Style Span
}

function Set-WallPaper { 
    param (
        [parameter(Mandatory=$True)]
        [string]$Image,
        [parameter(Mandatory=$False)]
        [ValidateSet('Fill', 'Fit', 'Stretch', 'Tile', 'Center', 'Span')]
        [string]$Style
    )
 
    $WallpaperStyle = Switch ($Style) {"Fill" {"10"} "Fit" {"6"} "Stretch" {"2"} "Tile" {"0"} "Center" {"0"} "Span" {"22"}}
  
    New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -PropertyType String -Value $WallpaperStyle -Force
    New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -PropertyType String -Value (&{if ($Style -eq "Tile") {1} else {0}}) -Force
 
Add-Type -TypeDefinition @" 
    using System; 
    using System.Runtime.InteropServices;
      
    public class Params
    { 
        [DllImport("User32.dll",CharSet=CharSet.Unicode)] 
        public static extern int SystemParametersInfo (Int32 uAction, Int32 uParam, String lpvParam, Int32 fuWinIni);
    }
"@ 
    $path = Resolve-Path $Image
    $ret = [Params]::SystemParametersInfo(0x0014, 0, $path, 0x03)
}

function br {
    param (
        [int]$brightness
    )
    lux set --monitor 0 --brightness $brightness
    Write-Output "Setting brightness to $brightness%."
}
