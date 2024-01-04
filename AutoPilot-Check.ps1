#
###############################################################################################################################################
#
# ABOUT THIS PROGRAM
#
#	AutoPilot-Check.ps1
#	https://github.com/Headbolt/AutoPilot-Tools
#
#   This Script is designed to read a CSV of Serial Numbers and then check the tennant to see if their hashes exist in Autopilot
#
###############################################################################################################################################
#
#	Usage
#		AutoPilot-Check.ps1 -CSVFile <full file path>
#
#		eg. AutoPilot-Check.ps1 -CSVFile C:\temp\autopilot-devices.csv
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
Function Get-AutoPilotDevice(){
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$True)] $id,
        [Parameter(Mandatory=$false)] $serial,
        [Parameter(Mandatory=$false)] [Switch]$expand = $false
    )

    Process {

        # Defining Variables
        $graphApiVersion = "beta"
        $Resource = "deviceManagement/windowsAutopilotDeviceIdentities"
    
        if ($id -and $expand) {
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)/$($id)?`$expand=deploymentProfile,intendedDeploymentProfile"
        }
        elseif ($id) {
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)/$id"
        }
        elseif ($serial) {
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)?`$filter=contains(serialNumber,'$serial')"
        }
        else {
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
        }
        try {
            $response = Invoke-MSGraphRequest -Url $uri -HttpMethod Get
            if ($id) {
                $response
            }
            else {
                $devices = $response.value
                $devicesNextLink = $response."@odata.nextLink"
    
                while ($devicesNextLink -ne $null){
                    $devicesResponse = (Invoke-MSGraphRequest -Url $devicesNextLink -HttpMethod Get)
                    $devicesNextLink = $devicesResponse."@odata.nextLink"
                    $devices += $devicesResponse.value
                }
    
                if ($expand) {
                    $devices | Get-AutopilotDevice -Expand
                }
                else
                {
                    $devices
                }
            }
        }
        catch {
            Write-Error $_.Exception 
            break
        }
    }
}
#
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Connect-MSGraph | Out-Null
# Check if all Autopilot devices are successfully deleted
$serialNumbers = Import-Csv $CsvFile | Select-Object -Unique 'Device Serial Number' | Select-Object -ExpandProperty 'Device Serial Number'
#
Write-Output "`nChecking devices in the Tennant"
foreach ($serialNumber in $serialNumbers){
    $device = Get-AutoPilotDevice -serial $serialNumber
	if ($device.serialNumber)
	{
		Write-Output "$serialNumber - Exists"
	}
	else
	{
		Write-Output "$serialNumber - Does Not Exist"
	}
}
