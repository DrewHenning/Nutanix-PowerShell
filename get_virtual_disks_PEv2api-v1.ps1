################################################
# Configure the variables below for the Nutanix Cluster
################################################
$RESTAPIServer = "10.20.30.40"

# Prompting for credentials
#$Credentials = Get-Credential -Credential $null
#$RESTAPIUser = $Credentials.UserName
#$Credentials.Password | ConvertFrom-SecureString
#$RESTAPIPassword = $Credentials.GetNetworkCredential().password

# Hardset credentials
$RESTAPIUser = "User.Name@domain.dom"
$RESTAPIPassword = "ChangeMe123"


# Define Output CSV Export path
$datetimestring = (Get-Date).Tostring("s").Replace(":","-").Replace("T","-") 
$filepath = "c:\temp\"
$filename = $filepath + "AHV_vDisk_Info_" + $datetimestring + ".csv"

################################################
# Nothing to configure below this line - Starting the main function of the script
################################################
# Adding certificate exception to prevent API errors
################################################
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

################################################
# Building Nutanix API Auth Header & Base URL
################################################
$BaseURL = "https://" + $RESTAPIServer + ":9440/api/nutanix/v2.0/"
$Header = @{"Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($RESTAPIUser+":"+$RESTAPIPassword))}
$Type = "application/json"

###############################################
# Getting Virtual Disks, Volume Groups from REST API
###############################################

# Get Virtual Disks
$VirtualDiskListURL = $BaseURL+"virtual_disks/"
Write-host "Fetching Virtual Disks via REST API via $VirtualDiskListURL"
Try 
{
$VirtualDiskListJSON = Invoke-RestMethod -Uri $VirtualDiskListURL -TimeoutSec 100 -Headers $Header -ContentType $Type
$VirtualDiskList = $VirtualDiskListJSON.entities
Write-host "Fetched" $VirtualDiskList.entitities.count "Virtual Disks" -ForegroundColor Green
}
Catch 
{
$_.Exception.ToString()
$error[0] | Format-List -Force
}
write-host "----------"

# Get Volume Groups
$VolumeGroupsListURL = $BaseURL+"volume_groups/"
Write-host "Fetching Volume Groups via REST API via $VolumeGroupsListURL"
Try 
{
$VolumeGroupsListJSON = Invoke-RestMethod -Uri $VolumeGroupsListURL -TimeoutSec 100 -Headers $Header -ContentType $Type
$VolumeGroupsList = $VolumeGroupsListJSON.entities
Write-host "Fetched" $VolumeGroupsList.entitities.count "Volume Groups" -ForegroundColor Green
}
Catch 
{
$_.Exception.ToString()
$error[0] | Format-List -Force
}
write-host "----------"

# Get Storage Containers
$StorageContainersListURL = $BaseURL+"storage_containers/"
Write-host "Fetching Storage Containers via REST API via $StorageContainersListURL"
Try 
{
$StorageContainersListJSON = Invoke-RestMethod -Uri $StorageContainersListURL -TimeoutSec 100 -Headers $Header -ContentType $Type
$StorageContainersList = $StorageContainersListJSON.entities
Write-host "Fetched" $StorageContainersList.entitities.count "Storage Containers" -ForegroundColor Green
}
Catch 
{
$_.Exception.ToString()
$error[0] | Format-List -Force
}
write-host "----------"

###############################################
# Functions - Volume Group and Storage Container lookup
###############################################

# Get Volume Group Name from UUID
function VolumeGroupNameLookup ($param) {
        #write-host "Searching for " $param
        
        foreach ($VolumeGroup in $VolumeGroupsList) {
        
           if ($VolumeGroup.uuid -eq $param) {
              
               #write-host "Volume Group UUID Match Found"
               return $VolumeGroup.name
            }
        }
}

# Get Storage Container Name from UUID
function StorageContainerNameLookup ($param) {
        #write-host "Searching for " $param
        
        foreach ($StorageContainer in $StorageContainersList) {
                  
           if ($StorageContainer.storage_container_uuid -eq $param) {
               
               #write-host "Storage Container UUID Match Found"
               return $StorageContainer.name
            }
        }
}

###############################################
# Parse Virtual disks
###############################################


write-host "Starting to parse Virtual Disks"

$FullReport=@()

$counter = 1

foreach ($VirtualDisk in $VirtualDiskList) {
    
    $VirtualDiskProperties = [ordered]@{
        "vDisk Storage Container" = StorageContainerNameLookup $VirtualDisk.storage_container_uuid
        "vDisk NFS File Path" = $VirtualDisk.nutanix_nfsfile_path
        "vDisk Provisioned Capacity (GB)" = $VirtualDisk.disk_capacity_in_bytes/1GB
        "vDisk Used Capacity (GB)" =  [math]::Round($VirtualDisk.stats.controller_user_bytes/1GB,2)
        "Attached VM Name" = $VirtualDisk.attached_vmname
        "Disk Address" = $VirtualDisk.disk_address
        "Volume Group Name" = VolumeGroupNameLookup $VirtualDisk.attached_volume_group_id
        "Attached Volume Group ID" = $VirtualDisk.attached_volume_group_id
    } #end properties
    
    write-host "Parsing virtual disk "$counter " of " $VirtualDiskList.entities.count -ForegroundColor Yellow
    $counter += 1

    $ReportObject = new-object PSObject -Property $VirtualDiskProperties
    $FullReport += $ReportObject
}

# Export Report to CSV and display to GridView
$FullReport | Out-GridView
$FullReport | Export-CSV -NoTypeInformation -Path $filename
Write-host "Output saved to:" $filename


###############################################
# End of script
###############################################