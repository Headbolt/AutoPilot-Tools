#
###############################################################################################################################################
#
# ABOUT THIS PROGRAM
#
#	AutoPilot-Cleanup.ps1
#	https://github.com/Headbolt/AutoPilot-Tools/AutoPilot-Cleanup
#
#   This Script is designed to read a CSV of Serial Numbers and then delete their hashes from the tennant
#
###############################################################################################################################################
#
#	Usage
#		AutoPilot-Cleanup.ps1 -CSVFile <full file path>
#
#		eg. AutoPilot-Cleanup.ps1 -CSVFile C:\temp\autopilot-devices.csv
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
Function Start-AutopilotCleanupCSV(){
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)][String] $CsvFile,
        [Parameter(Mandatory=$false)][Switch] $IntuneCleanup,
        [Parameter(Mandatory=$false,DontShow)][Switch] $ShowCleanupRequestOnly
    )

    $graphApiVersion = "Beta"
    $graphUrl = "https://graph.microsoft.com/$graphApiVersion"

    # get all unique Device Serial Numbers from the CSV file (column must be named 'Device Serial Number')
    $serialNumbers = Import-Csv $CsvFile | Select-Object -Unique 'Device Serial Number' | Select-Object -ExpandProperty 'Device Serial Number'

    # collection for the batch job deletion requests
    $requests = @()

    # according to the docs the current max batch count is 20
    # https://github.com/microsoftgraph/microsoft-graph-docs/blob/master/concepts/known-issues.md#limit-on-batch-size
    $batchMaxCount = 20;
    $batchCount = 0

    if ($serialNumbers.Count -gt 0){
        # loop through all serialNumbers and build batches of requests with max of $batchMaxCount
        for ($i = 0; $i -le $serialNumbers.Count; $i++) {
            # reaches batch count or total requests invoke graph call
            if ($batchCount -eq $batchMaxCount -or $i -eq $serialNumbers.Count){
                if ($requests.count -gt 0){
                    # final deletion batch job request collection
                    $content = [pscustomobject]@{
                        requests = $requests
                    }
            
                    # convert request data to proper format for graph request 
                    $jsonContent = ConvertTo-Json $content -Compress
        
                    if ($ShowCleanupRequestOnly){
                        Write-Host $(ConvertTo-Json $content)
                    }
                    else{
                        try{
                            # delete the Autopilot devices as batch job
                            $result = Invoke-MSGraphRequest -Url "$graphUrl/`$batch" `
                                                            -HttpMethod POST `
                                                            -Content "$jsonContent"
                            
                            # display some deletion job request results (status=200 equals successfully transmitted, not successfully deleted!)
                            Write-Host 
                            $result.responses | Select-Object @{Name="Device Serial Number";Expression={$_.id}},@{Name="Deletion Request Status";Expression={$_.status}}
                            # according to the docs response might have a nextLink property in the batch response... I didn't saw this in this scenario so taking no care of it here
                        }
                        catch{
                            Write-Error $_.Exception 
                            break
                        }
                    }
                    # reset batch requests collection
                    $requests = @()
                    $batchCount = 0
                }
            }
            # add current serial number to request batch
            if ($i -ne $serialNumbers.Count){
                try{
                    # check if device with serial number exists otherwise it will be skipped
                    if ($serialNumbers.Count -eq 1) {
                        $serial = $serialNumbers
                    }
                    else {
                        $serial = $serialNumbers[$i]
                    }
                    $device = Get-AutoPilotDevice -serial $serial
    
                    if ($device.id){
                        # building the request batch job collection with the device id
                        $requests += [pscustomobject]@{
                            id = $serial
                            method = "DELETE"
                            url = "/deviceManagement/windowsAutopilotDeviceIdentities/$($device.id)"
                        }

                        # try to delete the managed Intune device object, otherwise the Autopilot record can't be deleted (enrolled devices can't be deleted)
                        # under normal circumstances the Intune device object should already be deleted, devices should be retired and wiped before off-lease or disposal
                        if ($IntuneCleanup -and -not $ShowCleanupRequestOnly){
                            Get-IntuneManagedDevice | Where-Object serialNumber -eq $serial | Remove-DeviceManagement_ManagedDevices

                            # enhancement option: delete AAD record as well
                            # side effect: all BitLocker keys will be lost, maybe delete the AAD record at later time separately
                        }
                    }
                    else{
                        Write-Host "$($serial) not found, skipping device entry"
                    }
                }
                catch{
                    Write-Error $_.Exception 
                    break
                }
            }
            $batchCount++
        }
    }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Connect-MSGraph | Out-Null

Start-AutopilotCleanupCSV -CsvFile $CsvFile

Write-Output "`nWaiting 60 seconds to re-check if devices are deleted..."
Start-Sleep -Seconds 60

# Check if all Autopilot devices are successfully deleted
$serialNumbers = Import-Csv $CsvFile | Select-Object -Unique 'Device Serial Number' | Select-Object -ExpandProperty 'Device Serial Number'

Write-Output "`nThese devices couldn't be deleted (if no device is listed, everything went well):"
foreach ($serialNumber in $serialNumbers){
    $device = Get-AutoPilotDevice -serial $serialNumber
    $device.serialNumber
}
