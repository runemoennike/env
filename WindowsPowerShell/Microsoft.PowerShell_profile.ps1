# Change encoding to support special characters in Source Code Pro font (doesn't seem to work.)
[Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8

# Set colours.
. (Join-Path -Path (Split-Path -Parent -Path $PROFILE) -ChildPath $(switch($HOST.UI.RawUI.BackgroundColor.ToString()){'White'{'Set-SolarizedLightColorDefaults.ps1'}'Black'{'Set-SolarizedDarkColorDefaults.ps1'}default{return}}))

# Shortcuts to working directories.
function cdsm { cd "C:\Repos\117-22995 IoT-Structural Monitoring (GIT)\StructuralMonitoring" }
function cdae { cd "C:\Repos\116-26549 IoT-Air Emissions (GIT)\AirEmissions" }
function cdr { cd "C:\Repos" }

# Shortcut to launch Notepad++
function npp { start "C:\Program Files (x86)\Notepad++\notepad++.exe" @args }

# Quickly move back and forth between visited directories.
set-alias cd pushd -option AllScope
set-alias cd- popd -option AllScope

# Dropdown for tab completions.
Install-GuiCompletion -Key Tab

# Posh git.
Import-Module posh-git
$global:GitPromptSettings.EnableWindowTitle = $null
