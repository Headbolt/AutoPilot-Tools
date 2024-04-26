#
###############################################################################################################################################
#
# ABOUT THIS PROGRAM
#
#	AutoPilot-Wipe.ps1
#	https://github.com/Headbolt/AutoPilot-Tools
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
#   Version: 1.1 - 26/04/2024
#
#	04/01/2024 - V1.0 - Created by Headbolt
#				Using references adapted from 
# 					https://www.powershellgallery.com/packages/WindowsAutoPilotIntune
# 					https://github.com/microsoft/Intune-PowerShell-SDK
#
#	26/04/2024 - V1.1 - Updated by Headbolt
#				Allows for Wiping Mac's which need a Wipe Code
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
	$operatingsystem = (Get-IntuneManagedDevice -filter "serialNumber eq '$serialNumber'").operatingSystem
	#
	if ($operatingsystem -eq 'macOS')
	{
		Write-Host 'Sending Wipe to Device with Serial Number "'$serialNumber '" and DeviceID "'$Device '" Unlock Code "123456"' -ForegroundColor Yellow	
		Invoke-IntuneManagedDeviceWipeDevice -managedDeviceId $Device -macOsUnlockCode 123456
		Write-Host ''
	}
	else
	{
		Write-Host 'Sending Wipe to Device with Serial Number "'$serialNumber '" with DeviceID "'$Device '"' -ForegroundColor Yellow	
		Invoke-IntuneManagedDeviceWipeDevice -managedDeviceId $Device
		Write-Host ''
	}
}
