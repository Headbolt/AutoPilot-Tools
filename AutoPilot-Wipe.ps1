#
###############################################################################################################################################
#
# ABOUT THIS PROGRAM
#
#	AutoPilot-Wipe.ps1
#	https://github.com/Headbolt/AutoPilot-Tools/AutoPilot-Wipe
#
#   This Script is designed to read a CSV of Serial Numbers and then send an autopilot wipe to them
#
###############################################################################################################################################
#
#	Usage
#		AutoPilot-Wipe.ps1 -CSVFile <full file path>
#
#		eg. AutoPilot-Wipe.ps1 -CSVFile C:\temp\autopilot-devices.csv
#
###############################################################################################################################################
#
# HISTORY
#
#   Version: 1.0 - 04/01/2024
#
#	04/01/2024 - V1.0 - Created by Headbolt
#				Using references adapted from 
# 					https://www.powershellgallery.com/packages/WindowsAutoPilotIntune
# 					https://github.com/microsoft/Intune-PowerShell-SDK
#
###############################################################################################################################################
#
#   DEFINE VARIABLES & READ IN PARAMETERS
#
###############################################################################################################################################
#
param (
	[string]$CSVFile
)
#
#region Initialization code
$m = Get-Module -Name Microsoft.Graph.Intune -ListAvailable
if (-not $m)
{
    Install-Module NuGet -Force
    Install-Module Microsoft.Graph.Intune
}
Import-Module Microsoft.Graph.Intune -Global
#endregion
#
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Connect-MSGraph | Out-Null

$serialNumbers = Import-Csv $CsvFile | Select-Object -Unique 'Device Serial Number' | Select-Object -ExpandProperty 'Device Serial Number'

Write-Output "`nChecking devices in the Tennant"

foreach ($serialNumber in $serialNumbers){

$device = (Get-IntuneManagedDevice -filter "serialNumber eq '$serialNumber'").id
	Write-Host 'Sending Wipe to Device with Serial Number "'$serialNumber '" with DeviceID "'$Device '"' -ForegroundColor Yellow	
	Invoke-IntuneManagedDeviceWipeDevice -managedDeviceId $Device
	Write-Host ''
}
