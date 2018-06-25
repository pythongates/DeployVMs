<#
.SYNOPSIS
Deploy Multiple VMs to vCenter
.DESCRIPTION
VMs are deployed asynchronously based on a pre-configured csv file (DeployVM.csv)
Designed to run from Powershell ISE
.PARAMETER csvfile
Path to DeployVM.csv file with new VM info
.PARAMETER vCenter
vCenter Server FQDN or IP
.PARAMETER auto
Will allow script to run with no review or confirmation
.PARAMETER createcsv
Generates a blank csv file - DeployVM.csv
.EXAMPLE
.\DeployVM.ps1
Runs DeployVM
.EXAMPLE
.\DeployVM.ps1 -vcenter my.vcenter.address
Runs DeployVM specifying vCenter address
.EXAMPLE
.\DeployVM.ps1 -csvfile "E:\Scripts\Deploy\DeployVM.csv" -vcenter my.vcenter.address -auto
Runs DeployVM specifying path to csv file, vCenter address and no confirmation
.EXAMPLE
.\DeployVM.ps1 -createcsv
Creates a new/blank DeployVM.csv file in same directory as script
.NOTES
Author: Shawn Masterson
Created: May 2014
Version: 1.2
Author: JJ Vidanez
Created: Nov 2014
Version: 1.3
Add creation onthefly for customization Spec for linux systems
Ability to create machines names and guest hostname using different names
Added a value to find out the kind of disk because powercli bug for SDRS reported at https://communities.vmware.com/message/2442684#2442684
Remove the dependency for an already created OScustomization Spec
Author: JJ Vidanez
Created: Jul 2015
Version: 1.4
Adding domain credential request for Windows systems
Author Simon Davies - Everything-Virtual.com
Created May 2016
Version: 1.5
Adding AD Computer Account Creation in specified OU's for VM's at start of deployment - Yes even Linux as that was a requirement
It's possible to restrict this to just Windows VM's by removing the comment at line #261
####################################
Author: Todd Ouimet
Version: 1.6, January 2018
- Added error checking for ActiveDirectory Module.
- Added ability to create VM in subfolders based on folder Id
- Added ability to populate Custom Attribute CreatedOn and CreatedBy
Version: 1.7
Added convert network vlanid to portgroup name
Version: 1.8, April
- Handle up to 8 additional disks
- Updated New-ADComputer to pass creds to domain
- Now handles non-domain
- added timezone
- handle multiple domains in same csv and adding the computer objects to the domains
- check for existing VMs in vCenter
Version: 1.9, April
- 
Version: 2.0, June
- Updated to handle Disk1 - Disk9 (added Disk1 back)
- Added Description CustomAttributesand used Notes in spreadsheet to populate

REQUIREMENTS
PowerShell v3 or greater
vCenter (tested on 5.1/5.5/6.5)
PowerCLI 5.5 R2 or later
CSV File - VM info with the following headers
    NameVM, Name, Boot, OSType, Template, CustSpec, FolderId, ResourcePool, CPU, RAM, Disk2, Disk3, Disk4, Disk5, Disk6, Disk7, Disk8, Disk9,
    SDRS, Datastore, DiskStorageFormat, vSwitchName, NetType, Network, DHCP, IPAddress, SubnetMask, Gateway, pDNS, sDNS, Notes, POC, Domain
    Must be named DeployVM.csv
    Can be created with -createcsv switch
CSV Field Definitions
    NameVM - Name of VM in vCenter
	Name - Name of guest OS VM
	Boot - Determines whether or not to boot the VM - Must be 'true' or 'false'
	OSType - Must be 'Windows' or 'Linux'
	Template - Name of existing template to clone
	FolderId - FolderId in which to place VM in vCenter (optional)
	ResourcePool - VM placement - can be a reasource pool, host or a cluster
	CPU - Number of vCPU
	RAM - Amount of RAM (GB)
	Disk2 - Size of additional disk to add (GB)(optional)
	Disk3 - Size of additional disk to add (GB)(optional)
	Disk4 - Size of additional disk to add (GB)(optional)
    SDRS - Mark to use a SDRS or not - Must be 'true' or 'false'
         - If false The Datastore value CANNOT be a Datastore Cluster!!!
	Datastore - Datastore placement - Can be a datastore or datastore cluster
	DiskStorageFormat - Disk storage format - Must be 'Thin', 'Thick' or 'EagerZeroedThick' - Only funcional when SDRS = true
	NetType - vSwitch type - Must be 'vSS' or 'vDS'
	Network - VLAN ID to be converted to Network/Port Group to connect NIC
	DHCP - Use DHCP - Must be 'true' or 'false'
	IPAddress - IP Address for NIC
	SubnetMask - Subnet Mask for NIC (255.255.255.0)
	Gateway - Gateway for NIC
	pDNS - Primary DNS must be populated
	sDNS - Secondary NIC must be populated
	Notes - Description applied to the vCenter Notes field on VM
    Domain - DNS Domain must be populated
	OU - OU to create new computer accounts, must be the distinguished name eg "OU=TestOU1,OU=Servers,DC=my-homelab,DC=local"
CREDITS
Handling New-VM Async - LucD - @LucD22
http://www.lucd.info/2010/02/21/about-async-tasks-the-get-task-cmdlet-and-a-hash-table/
http://blog.smasterson.com/2014/05/21/deploying-multiple-vms-via-powercli-updated-v1-2/
http://blogs.vmware.com/PowerCLI/2014/05/working-customization-specifications-powercli-part-1.html
http://blogs.vmware.com/PowerCLI/2014/06/working-customization-specifications-powercli-part-2.html
http://blogs.vmware.com/PowerCLI/2014/06/working-customization-specifications-powercli-part-3.html
USE AT YOUR OWN RISK!
.LINK
http://blog.smasterson.com/2014/05/21/deploying-multiple-vms-via-powercli-updated-v1-2/
http://www.vidanez.com/2014/11/02/crear-multiples-linux-vms-de-un-fichero-csv-usando-powercli-deploying-multiple-linux-vms-using-powercli/
#>

#requires -Version 3

#--------------------------------------------------------------------
# Parameters
param (
    [parameter(Mandatory=$false)]
    [string]$csvfile,
    [parameter(Mandatory=$false)]
    [string]$vcenter,
    [parameter(Mandatory=$false)]
    [switch]$auto,
    [parameter(Mandatory=$false)]
    [switch]$createcsv
    )

#--------------------------------------------------------------------
# User Defined Variables

#--------------------------------------------------------------------
# Static Variables

$scriptName = "DeployVM"
$scriptVer = "2.0"
$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$starttime = Get-Date -uformat "%m-%d-%Y %I:%M:%S"
$logDir = $scriptDir + "\Logs\"
$logfile = $logDir + $scriptName + "_" + (Get-Date -uformat %m-%d-%Y_%I-%M-%S) + "_" + $env:username + ".txt"
$deployedDir = $scriptDir + "\Deployed\"
$deployedFile = $deployedDir + "DeployVM_" + (Get-Date -uformat %m-%d-%Y_%I-%M-%S) + "_" + $env:username  + ".csv"
$exportpath = $scriptDir + "\DeployVM.csv"
$headers = "" | Select-Object NameVM, Name, Boot, OSType, Timezone, Template, FolderId, ResourcePool, CPU, RAM, Disk1, Disk2, Disk3, Disk4, Disk5, Disk6, Disk7, Disk8, Disk9, SDRS, Datastore, DiskStorageFormat, vSwitchName, NetType, Network, DHCP, IPAddress, SubnetMask, Gateway, pDNS, sDNS, Notes, POC, Domain, OU
$taskTab = @{}
$credentials = @{}
$failDeploy = @()
$successVMs = @()
$failReconfig = @()
$updatedVMs = @()

#--------------------------------------------------------------------
# Load Snap-ins

# Add VMware snap-in if required
If ((Get-PSSnapin -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) -eq $null) {
    add-pssnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue
}

# Add ActiveDirectory Module
add-pssnapin ActiveDirectory -ErrorAction SilentlyContinue | Out-Null
Import-Module ActiveDirectory

$loaded = Get-Module -Name VMware* -ErrorAction SilentlyContinue | Where-Object {$_.Name -notmatch 'Common$|SDK$'} | Select-Object  Name
Get-Module -Name VMware* -ListAvailable | Where-Object {$loaded -notcontains $_.Name} | ForEach-Object {Import-Module -Name $_.Name}

$loadedSnap = Get-PSSnapin -Name VMware* -ErrorAction SilentlyContinue | Where-Object {$_.Name -notmatch 'Core$'} | Select-Object  Name
Get-PSSnapin -Name VMware* -Registered -ErrorAction SilentlyContinue | Where-Object {$loadedSnap -notcontains $_.Name} | ForEach-Object {Add-PSSnapin -Name $_.Name -ErrorAction SilentlyContinue}


#--------------------------------------------------------------------
# Functions

Function Out-Log {
    Param(
        [Parameter(Mandatory=$true)][string]$LineValue,
        [Parameter(Mandatory=$false)][string]$fcolor = "White"
    )

    Add-Content -Path $logfile -Value $LineValue
    Write-Host $LineValue -ForegroundColor $fcolor
}


Function Read-OpenFileDialog([string]$WindowTitle, [string]$InitialDirectory, [string]$Filter = "All files (*.*)|*.*", [switch]$AllowMultiSelect) {
    Add-Type -AssemblyName System.Windows.Forms
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Title = $WindowTitle
    if (![string]::IsNullOrWhiteSpace($InitialDirectory)) { $openFileDialog.InitialDirectory = $InitialDirectory }
    $openFileDialog.Filter = $Filter
    if ($AllowMultiSelect) { $openFileDialog.MultiSelect = $true }
    $openFileDialog.ShowHelp = $true    # Without this line the ShowDialog() function may hang depending on system configuration and running from console vs. ISE.
    $openFileDialog.ShowDialog() > $null
    if ($AllowMultiSelect) { return $openFileDialog.Filenames } else { return $openFileDialog.Filename }
}



Function Convert-VlanIdToPortgroupName {
    Param(
        [Parameter(Mandatory=$true)][string]$Network,
        [Parameter(Mandatory=$true)][string]$NetType,
        [Parameter(Mandatory=$true)][string]$vSwitchName
    )
    If ($NetType -match "vDS") {
        $Portgroup = (Get-VDPortgroup -VDSwitch $vSwitchName | Where-Object {$_.ExtensionData.Config.DefaultPortConfig.vlan.VlanId -eq $Network}).Name
    } else {
        $Portgroup = (Get-VirtualPortGroup -VirtualSwitch $vSwitchName | Where-Object {$_.ExtensionData.Spec.VlanID -eq $Network}).Name
    }
    Return $Portgroup
}



#--------------------------------------------------------------------
# Main Procedures

Disconnect-VIServer * -Confirm:$false

# Start Logging
Clear-Host
If (!(Test-Path $logDir)) {New-Item -ItemType directory -Path $logDir | Out-Null}
Out-Log "**************************************************************************************"
Out-Log "$scriptName`tVer:$scriptVer`t`t`t`tStart Time:`t$starttime"
Out-Log "**************************************************************************************`n"

# If requested, create DeployVM.csv and exit
If ($createcsv) {
    If (Test-Path $exportpath) {
        Out-Log "`n$exportpath Already Exists!`n" "Red"
        Exit
    } Else {
        Out-Log "`nCreating $exportpath`n" "Yellow"
        $headers | Export-Csv $exportpath -NoTypeInformation
		Out-Log "Done!`n"
        Exit
    }
}

# Ensure PowerCLI is at least version 5.5 R2 (Build 1649237)
If ((Get-PowerCLIVersion).Build -lt 1649237) {
    Out-Log "Error: DeployVM script requires PowerCLI version 5.5 R2 (Build 1649237) or later" "Red"
	Out-Log "PowerCLI Version Detected: $((Get-PowerCLIVersion).UserFriendlyVersion)" "Red"
    Out-Log "Exiting...`n`n" "Red"
    Exit
}

# Test to ensure csv file is available
If ($csvfile -eq "" -or !(Test-Path $csvfile) -or !$csvfile.EndsWith("DeployVM.csv")) {
    Out-Log "Path to DeployVM.csv not specified...prompting`n" "Yellow"
    $csvfile = Read-OpenFileDialog "Locate DeployVM.csv" "C:\Temp\" # "DeployVM.csv|DeployVM.csv"
}

#If ($csvfile -eq "" -or !(Test-Path $csvfile) -or !$csvfile.EndsWith("DeployVM.csv")) {
If ($csvfile -eq "" -or !(Test-Path $csvfile)) {
    Out-Log "`nStill can't find it...I give up" "Red"
    Out-Log "Exiting..." "Red"
    Exit
}

Out-Log "Using $csvfile`n" "Yellow"
# Make copy of DeployVM.csv
If (!(Test-Path $deployedDir)) {New-Item -ItemType directory -Path $deployedDir | Out-Null}
Copy-Item $csvfile -Destination $deployedFile | Out-Null

# Import VMs from csv
$newVMs = Import-Csv $csvfile
$newVMs = $newVMs | Where-Object {$_.Name -ne ""}
[INT]$totalVMs = @($newVMs).count
Out-Log "New VMs to create: $totalVMs" "Yellow"

# Check to ensure csv is populated
If ($totalVMs -lt 1) {
    Out-Log "`nError: No enough entries found in DeployVM.csv Minimal 1" "Red"
    Out-Log "Exiting...`n" "Red"
    Exit
}

# Show input and ask for confirmation, unless -auto was used
If (!$auto) {
    $newVMs | Out-GridView -Title "VMs to be Created"
    $continue = Read-Host "`nContinue (y/n)?"
    If ($continue -notmatch "y") {
        Out-Log "Exiting..." "Red"
        Exit
    }
}

# Check OU column in csvfile. If populated verify the
# ActiveDirectory snapin is loaded.
Foreach ($VM in $newVMs) {
    $Error.Clear()
    If ( !$VM.OU -eq "") {
        if ( (Get-Module -Name ActiveDirectory -ErrorAction SilentlyContinue) -eq $null )
        {
            Out-Log "`nError: ActiveDirectory module not loaded." "Red"
            Out-Log "Exiting...`n" "Red"
            Exit
        } else {
            Break
        }
    }
}

# Connect to vCenter server
If ($vcenter -eq "") {$vcenter = Read-Host "`nEnter vCenter server FQDN or IP"}
$vcenter_creds = Get-Credential -Message "Load Admin credentials for vCenter - $vcenter"
Try {
    Out-Log "`nConnecting to vCenter - $vcenter`n`n" "Yellow"
    Connect-VIServer $vcenter -Credential $vcenter_creds -EA Stop | Out-Null
} Catch {
    Out-Log "`r`n`r`nUnable to connect to $vcenter" "Red"
    Out-Log "Exiting...`r`n`r`n" "Red"
    Exit
}


# Check for existing VMs in vCenter and exclude them from list of New VMs to create
Foreach ($VM in $newVMs) {
    $VMExists = ""
    $vmName = $VM.Name
    try{ $VMExists = Get-VM $vmName -ErrorAction Stop } catch{}
    If ($VMExists) {
        Out-Log "`n$vmName already exists in $vcenter!!" "Red"
    } Else {
        # Add non-existing VM to list of VMs to create
        $updatedVMs += $VM
    }
}
$newVMs = @()
$newVMs = $updatedVMs
# If ($newVMs -ne $updatedVMs) {
    #$newVMs | Out-GridView -Title "New list of VMs to be Created"
    #$continue = Read-Host "`nContinue (y/n)?"
#    If ($continue -notmatch "y") {
#        Out-Log "Exiting..." "Red"
#        Exit
#    }
# }


Out-Log "`nRequesting Domain Creds necessary to add VMs to AD" "Yellow"
Out-Log "`nNo computer objects will be created for existing VM's!!!"
$continue = Read-Host "`nDo you want to add VM computer objects to AD? (y/n)?"
If ($continue -match "y") {
    # Reading VMs to deploy and if they are windows asking to load credentials per Domain
    Foreach ($VM in $newVMs) {
        $Error.Clear()
        $DomainName = $VM.Domain
        If ($VM.OSType -eq "Windows") {
            If ( (!$credentials.ContainsKey($DomainName)) -and ($DomainName -ne "")) {
                Out-Log "`Load Admin credentials for domain - $DomainName`n`n" "Yellow"
                $new_cred = Get-Credential -Message "Load Admin credentials for domain - $DomainName"
                $credentials.Add($DomainName,$new_cred)
            }
        }
    }

    # Reading VMs to pre-create AD accounts
    Foreach ($VM in $newVMs) {
        $Error.Clear()
        $VMName = $VM.Name
        $VM_OU = $Vm.OU
        $DomainName = $VM.Domain
        $DNSHostName = "$VMName.$DomainName"
        $Notes = $VM.Notes

        # Add to domain is specific OU
        If ( (!$VM_OU -eq "") -and (!$DomainName -eq "") ) {
            New-ADComputer -Name $VMName -Path $VM_OU -Description "$Notes" -DNSHostName $DNSHostName -Server $DomainName -Credential $credentials.Get_Item($DomainName) -Verbose -Confirm:$false
        }

        # Add to domain in default Computers OU
        If ( $VM_OU -eq "" ) {
            New-ADComputer -Name $VMName -Description "$Notes" -DNSHostName $DNSHostName -Server $DomainName -Credential $credentials.Get_Item($DomainName) -Verbose -Confirm:$false
        }
    }
} else {
    Out-Log "`nSkipping adding computer objects to AD" "Yellow"
}


# Remove any OSCustomizationSpec that may already exist from previous runs
Foreach ($VM in $newVMs) {
	$vmName = $VM.Name
    try {Remove-OSCustomizationSpec -OSCustomizationSpec temp$vmName -Confirm:$false -ErrorAction SilentlyContinue} catch {}
}


# Start provisioning VMs
$v = 0
Out-Log "Deploying VMs`n" "Yellow"
Foreach ($VM in $newVMs) {
    $Error.Clear()
	$vmName = $VM.Name
    $DomainName = $VM.Domain
    $fullname = $VM.POC
    $timezone = $VM.timezone
    $v++
	$vmStatus = "[{0} of {1}] {2}" -f $v, $newVMs.count, $vmName

	Write-Progress -Activity "Deploying VMs" -Status $vmStatus -PercentComplete (100*$v/($newVMs.count))
    # Create custom OS Custumization spec
    If ($vm.DHCP -match "true") {
        If ($VM.OSType -eq "Windows") {

            If ($DomainName -ne "") {
                #$fullname = $credential.UserName.Split('\')[1]  # Use POC for fullname
                $orgname = $credential.UserName.Split('\')[0]
                 If ($orgname -eq "") {$orgname = "ORG"}  # If blank set the value
                $credential = $credentials.Get_Item($VM.domain)
                $tempSpec = New-OSCustomizationSpec -Name temp$vmName -NamingScheme fixed `
                -NamingPrefix $VM.Name -Domain $DomainName -FullName $fullname -OrgName $orgname `
                -DomainCredentials $credential -TimeZone $timezone -ChangeSid -OSType Windows
	              $tempSpec | Get-OSCustomizationNicMapping | Set-OSCustomizationNicMapping `
	              -IpMode UseDhcp | Out-Null
            } Else {

                $tempSpec = New-OSCustomizationSpec -Name temp$vmName -NamingScheme fixed `
                -NamingPrefix $VM.Name -FullName $fullname -OrgName $VM.Name `
                -TimeZone $timezone -ChangeSid -OSType Windows -Workgroup "WORKGROUP"
	              $tempSpec | Get-OSCustomizationNicMapping | Set-OSCustomizationNicMapping `
	              -IpMode UseDhcp | Out-Null
            }

	    } ElseIF ($VM.OSType -eq "Linux") {

            $tempSpec = New-OSCustomizationSpec -Name temp$vmName -NamingScheme fixed `
            -NamingPrefix $VM.Name -Domain $DomainName -OSType Linux -DnsServer $VM.pDNS,$VM.sDNS
            $tempSpec | Get-OSCustomizationNicMapping | Set-OSCustomizationNicMapping `
            -IpMode UseDhcp | Out-Null
          }

    } Else {
        If ($VM.OSType -eq "Windows") {

            If ($DomainName -ne "") {
                $credential = $credentials.Get_Item($VM.domain)
                # $fullname = $credential.UserName.Split('\')[1]  # Use POC for fullname
                $orgname = $credential.UserName.Split('\')[0]
                 If ($orgname -eq "") {$orgname = "ORG"}  # If blank set the value

                $tempSpec = New-OSCustomizationSpec -Name temp$vmName -NamingScheme fixed `
                -NamingPrefix $VM.Name -Domain $DomainName -FullName $fullname -OrgName $orgname `
                -DomainCredentials $credential -TimeZone $timezone -ChangeSid -OSType Windows
                 $tempSpec | Get-OSCustomizationNicMapping | Set-OSCustomizationNicMapping `
	             -IpMode UseStaticIP -IpAddress $VM.IPAddress -SubnetMask $VM.SubnetMask `
	             -Dns $VM.pDNS,$VM.sDNS -DefaultGateway $VM.Gateway | Out-Null
            } Else {

                $tempSpec = New-OSCustomizationSpec -Name temp$vmName -NamingScheme fixed `
                -NamingPrefix $VM.Name -FullName $fullname -OrgName $VM.Name `
                -TimeZone $timezone -ChangeSid -OSType Windows -Workgroup "WORKGROUP"
                 $tempSpec | Get-OSCustomizationNicMapping | Set-OSCustomizationNicMapping `
	             -IpMode UseStaticIP -IpAddress $VM.IPAddress -SubnetMask $VM.SubnetMask `
	             -Dns $VM.pDNS,$VM.sDNS -DefaultGateway $VM.Gateway | Out-Null
            }
	    } ElseIF ($VM.OSType -eq "Linux") {

            $tempSpec = New-OSCustomizationSpec -Name temp$vmName -NamingScheme fixed `
            -NamingPrefix $VM.Name -Domain $VM.domain -OSType Linux -DnsServer $VM.pDNS,$VM.sDNS
            $tempSpec | Get-OSCustomizationNicMapping | Set-OSCustomizationNicMapping `
            -IpMode UseStaticIP -IpAddress $VM.IPAddress -SubnetMask $VM.SubnetMask -DefaultGateway $VM.Gateway | Out-Null
          }
	}

    # Create VM depeding on the parameter SDRS true or false
    Out-Log "Deploying $vmName"
    If ($VM.SDRS -match "true") {
        Out-Log "SDRS Cluster disk on $vmName - removing DiskStorageFormat parameter " "Yellow"
        $VMFolder = Get-Folder -Id $VM.FolderId

        If ($VMFolder -ne "") {
            $taskTab[(New-VM -Name $VM.NameVM -ResourcePool $VM.ResourcePool -Location $VMFolder -Datastore $VM.Datastore `
            -Notes $VM.Notes -Template $VM.Template -OSCustomizationSpec temp$vmName -RunAsync -EA SilentlyContinue).Id] = $VM.Name
        } Else {
            $taskTab[(New-VM -Name $VM.NameVM -ResourcePool $VM.ResourcePool -Datastore $VM.Datastore `
            -Notes $VM.Notes -Template $VM.Template -OSCustomizationSpec temp$vmName -RunAsync -EA SilentlyContinue).Id] = $VM.Name
        }

      } Else {
        Out-Log "NON SDRS Cluster disk on $vmName - using DiskStorageFormat parameter " "Yellow"
        $VMFolder = Get-Folder -Id $VM.FolderId
        If ($VMFolder -ne "") {
            $taskTab[(New-VM -Name $VM.NameVM -ResourcePool $VM.ResourcePool -Location $VMFolder -Datastore $VM.Datastore `
            -DiskStorageFormat $VM.DiskStorageFormat -Notes $VM.Notes -Template $VM.Template -OSCustomizationSpec temp$vmName -RunAsync -EA SilentlyContinue).Id] = $VM.Name
        } Else {
            $taskTab[(New-VM -Name $VM.NameVM -ResourcePool $VM.ResourcePool -Datastore $VM.Datastore `
            -DiskStorageFormat $VM.DiskStorageFormat -Notes $VM.Notes -Template $VM.Template -OSCustomizationSpec temp$vmName -RunAsync -EA SilentlyContinue).Id] = $VM.Name

        }
    }
    # Log errors
    If ($Error.Count -ne 0) {
        If ($Error.Count -eq 1 -and $Error.Exception -match "'Location' expects a single value") {
            $vmLocation = $VM.Folder
            Out-Log "Unable to place $vmName in desired location, multiple $vmLocation folders exist, check root folder" "Red"
        } Else {
            Out-Log "`n$vmName failed to deploy!" "Red"
            Foreach ($err in $Error) {
                Out-Log "$err" "Red"
            }
            $failDeploy += @($vmName)
        }
    }
}

Out-Log "`n`nAll Deployment Tasks Created" "Yellow"
Out-Log "`n`nMonitoring Task Processing" "Yellow"

# When finished deploying, reconfigure new VMs
$totalTasks = $taskTab.Count
$runningTasks = $totalTasks
while($runningTasks -gt 0){
    $vmStatus = "[{0} of {1}] {2}" -f $runningTasks, $totalTasks, "Tasks Remaining"
	Write-Progress -Activity "Monitoring Task Processing" -Status $vmStatus -PercentComplete (100*($totalTasks-$runningTasks)/$totalTasks)
	Get-Task | ForEach-Object {
    if($taskTab.ContainsKey($_.Id) -and $_.State -eq "Success"){
      #Deployment completed
      $Error.Clear()
      $vmName = $taskTab[$_.Id]
      Out-Log "`n`nReconfiguring $vmName" "Yellow"
      $VM = Get-VM $vmName
      $VMconfig = $newVMs | Where-Object {$_.Name -eq $vmName}

	  # Set CPU and RAM
      Out-Log "Setting vCPU(s) and RAM on $vmName" "Yellow"
      $VM | Set-VM -NumCpu $VMconfig.CPU -MemoryGB $VMconfig.RAM -Confirm:$false | Out-Null

	  # Set port group on virtual adapter
      Out-Log "Setting Port Group on $vmName" "Yellow"
      If ($VMconfig.NetType -match "vSS") {
        $PortgroupName = Convert-VlanIdToPortgroupName -Network $VMconfig.Network -NetType $VMconfig.NetType -vSwitchName $VMconfig.vSwitchName
        $network = @{
			  'NetworkName' = $PortgroupName
			  'Confirm' = $false
		  }
	  } Else {
        $PortgroupName = Convert-VlanIdToPortgroupName -Network $VMconfig.Network -NetType $VMconfig.NetType -vSwitchName $VMconfig.vSwitchName
        $network = @{
			  'Portgroup' = $PortgroupName
			  'Confirm' = $false
		  }
	  }
	  $VM | Get-NetworkAdapter | Set-NetworkAdapter @network | Out-Null

	  # Add additional disks if needed
      If ($VMConfig.Disk1 -gt 1) {
        Out-Log "Adding additional disk on $vmName - don't forget to format within the OS" "Yellow"
        $VM | New-HardDisk -CapacityGB $VMConfig.Disk1 -StorageFormat $VMConfig.DiskStorageFormat -Persistence persistent | Out-Null
      }
      If ($VMConfig.Disk2 -gt 1) {
        Out-Log "Adding additional disk on $vmName - don't forget to format within the OS" "Yellow"
        $VM | New-HardDisk -CapacityGB $VMConfig.Disk2 -StorageFormat $VMConfig.DiskStorageFormat -Persistence persistent | Out-Null
      }
      If ($VMConfig.Disk3 -gt 1) {
        Out-Log "Adding additional disk on $vmName - don't forget to format within the OS" "Yellow"
        $VM | New-HardDisk -CapacityGB $VMConfig.Disk3 -StorageFormat $VMConfig.DiskStorageFormat -Persistence persistent | Out-Null
      }
      If ($VMConfig.Disk4 -gt 1) {
        Out-Log "Adding additional disk on $vmName - don't forget to format within the OS" "Yellow"
        $VM | New-HardDisk -CapacityGB $VMConfig.Disk4 -StorageFormat $VMConfig.DiskStorageFormat -Persistence persistent | Out-Null
      }
      If ($VMConfig.Disk5 -gt 1) {
        Out-Log "Adding additional disk on $vmName - don't forget to format within the OS" "Yellow"
        $VM | New-HardDisk -CapacityGB $VMConfig.Disk5 -StorageFormat $VMConfig.DiskStorageFormat -Persistence persistent | Out-Null
      }
      If ($VMConfig.Disk6 -gt 1) {
        Out-Log "Adding additional disk on $vmName - don't forget to format within the OS" "Yellow"
        $VM | New-HardDisk -CapacityGB $VMConfig.Disk6 -StorageFormat $VMConfig.DiskStorageFormat -Persistence persistent | Out-Null
      }
      If ($VMConfig.Disk7 -gt 1) {
        Out-Log "Adding additional disk on $vmName - don't forget to format within the OS" "Yellow"
        $VM | New-HardDisk -CapacityGB $VMConfig.Disk7 -StorageFormat $VMConfig.DiskStorageFormat -Persistence persistent | Out-Null
      }
      If ($VMConfig.Disk8 -gt 1) {
        Out-Log "Adding additional disk on $vmName - don't forget to format within the OS" "Yellow"
        $VM | New-HardDisk -CapacityGB $VMConfig.Disk8 -StorageFormat $VMConfig.DiskStorageFormat -Persistence persistent | Out-Null
      }
      If ($VMConfig.Disk9 -gt 1) {
        Out-Log "Adding additional disk on $vmName - don't forget to format within the OS" "Yellow"
        $VM | New-HardDisk -CapacityGB $VMConfig.Disk9 -StorageFormat $VMConfig.DiskStorageFormat -Persistence persistent | Out-Null
      }

      # Check if CreatedOn, CreatedBy, POC & Description CustomAttributes exist and create if not
      $CustomAttributes = Get-CustomAttribute -TargetType VirtualMachine

      If ($CustomAttributes.Name -notcontains "CreatedBy") {
        New-CustomAttribute -Name "CreatedBy" -TargetType VirtualMachine -Confirm:$false
      }
      If ($CustomAttributes.Name -notcontains "CreatedOn") {
        New-CustomAttribute -Name "CreatedOn" -TargetType VirtualMachine -Confirm:$false
      }
      If ($CustomAttributes.Name -notcontains "POC") {
        New-CustomAttribute -Name "POC" -TargetType VirtualMachine -Confirm:$false
      }
      If ($CustomAttributes.Name -notcontains "Description") {
        New-CustomAttribute -Name "Description" -TargetType VirtualMachine -Confirm:$false
      }

      # Set CreatedOn Annotation
      $CreatedOnDateTime = Get-Date -format u
      Out-Log "Setting CreatedOn Attribute value to $CreatedOnDateTime for $vmName" "Yellow"
      Set-Annotation -Entity $VM -CustomAttribute "CreatedOn" -Value $CreatedOnDateTime -Confirm:$false | Out-Null

      # Set CreatedBy Annotation
      $UserName = (Get-ADUser $env:UserName).GivenName + " " + (Get-ADUser $env:UserName).Surname
      Out-Log "Setting CreatedBy Attribute value to $UserName for $vmName" "Yellow"
      Set-Annotation -Entity $VM -CustomAttribute "CreatedBy" -Value $UserName -Confirm:$false | Out-Null

      # Set POC Annotation
      $POC = $VMConfig.POC
      Out-Log "Setting POC Attribute value to $POC" "Yellow"
      Set-Annotation -Entity $VM -CustomAttribute "POC" -Value $POC -Confirm:$false | Out-Null

      # Set Description Annotation
      $VMDescription = $VMConfig.Notes
      Out-Log "Setting Description Attribute value to $VMDescription" "Yellow"
      Set-Annotation -Entity $VM -CustomAttribute "Description" -Value $VMDescription -Confirm:$false | Out-Null


	  # Boot VM
	  If ($VMconfig.Boot -match "true") {
      	Out-Log "Booting $vmName" "Yellow"
      	$VM | Start-VM -EA SilentlyContinue | Out-Null
	  }
      $taskTab.Remove($_.Id)
      $runningTasks--
      If ($Error.Count -ne 0) {
        Out-Log "$vmName completed with errors" "Red"
        Foreach ($err in $Error) {
            Out-Log "$Err" "Red"
        }
        $failReconfig += @($vmName)
      } Else {
        Out-Log "$vmName is Complete" "Green"
        $successVMs += @($vmName)
      }
    }
    elseif($taskTab.ContainsKey($_.Id) -and $_.State -eq "Error"){
      # Deployment failed
      $failed = $taskTab[$_.Id]
      Out-Log "`n$failed failed to deploy!`n" "Red"
      $taskTab.Remove($_.Id)
      $runningTasks--
      $failDeploy += @($failed)
    }
  }
  Start-Sleep -Seconds 10
}

# Wait 10 minutes for all VMs to boot and apply OS Custumization specs before removing
Out-Log "Waiting 10 minutes for all VMs to boot and apply OS Custumization specs" "Yellow"
Start-Sleep 600

# Remove temp OS Custumization specs
Foreach ($VM in $newVMs) {
	$vmName = $VM.Name
    try {Remove-OSCustomizationSpec -OSCustomizationSpec temp$vmName -Confirm:$false -ErrorAction SilentlyContinue} catch {}
}


#--------------------------------------------------------------------
# Close Connections

Disconnect-VIServer -Server $vcenter -Force -Confirm:$false

#--------------------------------------------------------------------
# Outputs

Out-Log "`n**************************************************************************************"
Out-Log "Processing Complete" "Yellow"

If ($successVMs -ne $null) {
    Out-Log "`nThe following VMs were successfully created:" "Yellow"
    Foreach ($success in $successVMs) {Out-Log "$success" "Green"}
}
If ($failReconfig -ne $null) {
    Out-Log "`nThe following VMs failed to reconfigure properly:" "Yellow"
    Foreach ($reconfig in $failReconfig) {Out-Log "$reconfig" "Red"}
}
If ($failDeploy -ne $null) {
    Out-Log "`nThe following VMs failed to deploy:" "Yellow"
    Foreach ($deploy in $failDeploy) {Out-Log "$deploy" "Red"}
}

$finishtime = Get-Date -uformat "%m-%d-%Y %I:%M:%S"
Out-Log "`n`n"
Out-Log "**************************************************************************************"
Out-Log "$scriptName`t`t`t`t`tFinish Time:`t$finishtime"
Out-Log "**************************************************************************************"

