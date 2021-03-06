<#
.SYNOPSIS
Export all Virtual Machine Folders
.DESCRIPTION
 vCenter allows duplicate folders names to exist so unless EVERY folder within vCenter is unique, this
 script is necessary to automate the placement of the VM's into their respective folders.
 Run this script well in advanced to running the DeployVM.ps1 script. It will export a csv of
 all VM folders (blue). The csv will contain folder name, folder path, and folder Id. The folderId
 is key to populating the folderId column within the DeployVM.csv.  the folderId is the only unique
 value one can use to automate deployment to folders.
.PARAMETER vCenter
vCenter Server FQDN or IP
.EXAMPLE
.\ExportVMfolders.ps1 -vcenter my.vcenter.address
Runs ExportVMfolders specifying vCenter address
.NOTES
Author: Todd Ouimet
Created January 2018
Version: 1.0

CREDITS
LucD - Get The Folderpath function
http://www.lucd.info/2010/10/21/get-the-folderpath/
.LINK
#>


# Parameters
param (
    [parameter(Mandatory=$true)]
    [string]$vcenter
)


#--------------------------------------------------------------------
# Static Variables

$scriptName = "ExportVMfolders"
$scriptVer = "1.0"
$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$exportpath = $scriptDir + "\ExportVMfolders.csv"


#--------------------------------------------------------------------
# Load Snap-ins

# Add VMware snap-in if required
If ((Get-PSSnapin -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) -eq $null) {add-pssnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue}

$loaded = Get-Module -Name VMware* -ErrorAction SilentlyContinue | Where-Object {$_.Name -notmatch 'Common$|SDK$'} | Select-Object Name
Get-Module -Name VMware* -ListAvailable | Where-Object {$loaded -notcontains $_.Name} | Foreach-Object {Import-Module -Name $_.Name}

$loadedSnap = Get-PSSnapin -Name VMware* -ErrorAction SilentlyContinue | Where-Object {$_.Name -notmatch 'Core$'} | Select-Object Name
Get-PSSnapin -Name VMware* -Registered -ErrorAction SilentlyContinue | Where-Object {$loadedSnap -notcontains $_.Name} | Foreach-Object {Add-PSSnapin -Name $_.Name -ErrorAction SilentlyContinue}


#--------------------------------------------------------------------
# Functions

Function Out-Log {
    Param(
        [Parameter(Mandatory=$true)][string]$LineValue,
        [Parameter(Mandatory=$false)][string]$fcolor = "White"
    )

#    Add-Content -Path $logfile -Value $LineValue
    Write-Host $LineValue -ForegroundColor $fcolor
}

function Get-FolderPath{
    <#
    .SYNOPSIS
    Returns the folderpath for a folder
    .DESCRIPTION
    The function will return the complete folderpath for
    a given folder, optionally with the "hidden" folders
    included. The function also indicats if it is a "blue"
    or "yellow" folder.
    .NOTES
    Authors:	Luc Dekens
    .PARAMETER Folder
    On or more folders
    .PARAMETER ShowHidden
    Switch to specify if "hidden" folders should be included
    in the returned path. The default is $false.
    .EXAMPLE
       PS> Get-FolderPath -Folder (Get-Folder -Name "MyFolder")
    .EXAMPLE
       PS> Get-Folder | Get-FolderPath -ShowHidden:$true
    #>
    param(
        [parameter(valuefrompipeline = $true,
        position = 0,
        HelpMessage = "Enter a folder")]
        [VMware.VimAutomation.ViCore.Impl.V1.Inventory.FolderImpl[]]$Folder,
        [switch]$ShowHidden = $false
    )
    begin{
        $excludedNames = "Datacenters","vm","host"
    }
    process{
        $Folder | ForEach-Object{
            $fld = $_.Extensiondata
            $fldType = "yellow"
            if($fld.ChildType -contains "VirtualMachine"){
                $fldType = "blue"
            }
            $path = $fld.Name
            while($fld.Parent){
                $fld = Get-View $fld.Parent
                if((!$ShowHidden -and $excludedNames -notcontains $fld.Name) -or $ShowHidden){
                    $path = $fld.Name + "\" + $path
                }
            }
            $row = "" | Select-Object Name,Path,Type
            $row.Name = $_.Name
            $row.Path = $path
            $row.Type = $fldType
            $row
        }
    }
}



# Connect to vCenter server
If ($vcenter -eq "") {$vcenter = Read-Host "`nEnter vCenter server FQDN or IP"}

Try {
    Out-Log "`nConnecting to vCenter - $vcenter`n`n" "Yellow"
    Connect-VIServer $vcenter -EA Stop | Out-Null
} Catch {
    Out-Log "`r`n`r`nUnable to connect to $vcenter" "Red"
    Out-Log "Exiting...`r`n`r`n" "Red"
    Exit
}


#--------------------------------------------------------------------
# Main

# Start Logging
Clear-Host
Out-Log "**************************************************************************************"
Out-Log "$scriptName`tVer:$scriptVer`t`t`t`tStart Time:`t$starttime"
Out-Log "**************************************************************************************`n"

# Get root VM folder object in Datacenter
$dcFolderObj = Get-Datacenter
$dcFolderId = $dcFolderObj.Id
$RootVMfolderObj = Get-Folder vm -Type VM | Where-Object {$_.ParentId -eq $dcFolderId}


## Export all folders
$report = @()
Out-Log "Exporting all Virtual Machine Folders to $exportpath" "Yellow"
$report = $RootVMfolderObj | Get-Folder -Type VM | Select-Object @{N="Name";E={$_.Name}}, @{N="Path";E={ (Get-FolderPath -Folder $_).Path }}, @{N="Id";E={$_.Id}}
$report | Sort-Object -Property Path | Export-Csv $exportpath -NoTypeInformation -UseCulture

Out-Log "Disconnecting from $vcenter" "Yellow"
Disconnect-VIServer "*" -Confirm:$False
Out-Log "Done`n`n" "Yellow"