##Add vmware
Import-Module VMware.VimAutomation.Core
asnp vmware*
##Add Citrix Snapins.  You need both Delivery controllers and PVS snapins
asnp citrix*

##Variables to Change as Needed
##Delivery Controller
$AdminAddress="DELIVERYCONTROLLER.contoso.com"

##Vcenter
$vsphereserver="vsphere.contoso.com"

##PVS Server
$PVSServer="PVS.contoso.com"

##Use Out-GridView to select the proper Delivery Group name from a list
$DeliveryGroups = Get-BrokerDesktopGroup | Select-Object Name 
$DeliveryGroup = $DeliveryGroups | Select-Object Name | Out-GridView -PassThru
if ($DeliveryGroup){
    write-host $DeliveryGroup.Name " was selected"
}
else{
    write-host "No selection made.  Script Exiting"
    exit
}

##uncomment to allow untrusted certs
##set-powercliconfiguration -invalidcertificateaction Ignore -Confirm:false
##Connect to vcenter by prompting for creds to bypass current bug https://knowledge.broadcom.com/external/article/317470/pass-through-authentication-via-powercli.html
connect-viserver $vsphereserver -Credential(Get-Credential)

##Configure PVS Connection
Set-PvsConnection -Server $PVSServer
Write-Host "$PVSServer has been set as the active PVS Server"

##get initial list of machines in DG
$machines = Get-BrokerMachine -MaxRecordCount 2000 -AdminAddress $AdminAddress -DesktopGroupName $DeliveryGroup.Name

##Building UEFI vmware object so it doesn't constantly get rebuilt during any loops
##Inspiration cgutz https://community.broadcom.com/vmware-cloud-foundation/discussion/powercli-find-bios-or-efi-boot-option
$uefi = New-Object VMware.Vim.VirtualMachineConfigSpec
$uefi.Firmware = New-Object VMware.Vim.GuestOSDescriptor
$uefi.Firmware = "efi"

##Loop machines to get info and then do work
ForEach($machine in $machines){
    ##$vm is shorter and easier to type.  we also need the machine name and hosted machine names at different points
    $vm = $machine.MachineName
    ##Get the vm variable for user later
    $vsphervm = get-vm -Name $machine.HostedMachineName
    ##Get the value of the boot config firmware for challenge later
    $vmFirmare  = get-vm -name $machine.HostedMachineName | select Name,@(N='Firmware';E={$_.ExtensionData.Config.Firmware})
    ## Have to get the status of the session again because it may differ from earlier.  Do this last so it's most up to date before IF below
    $CurrentStates=get-brokermachine -MachineName $vm

    ##Validate the machiens require the work and can be modified
    If(($machine.PowerState -eq "On") -and ($CurrentStates.SessionCount -eq 0) -and ($vmFirmware.Firmware -eq "bios"))
    {
        ##Maintenance Mode the machine so citrix doesn't try and power it back on while we're working on it and prevent user connections
        Write-Host "Turning on Maintenance Mode for $vm"
        Get-BrokerMachine -MachineName $vm -AdminAddress $AdminAddress | Set-BrokerMachineMaintenanceMode -MaintenanceMode $true -AdminAddress $AdminAddress

        ##Machines must be off in order to reconfigure their boot bios to UEFI.  Hard Power off because these are non persistent
        Write-Host "Shutting down $vm"
        New-BrokerHostingPowerAction -MachineName $vm -Action TurnOff -AdminAddress $AdminAddress

        ##sleep for 3s to make sure machine is off actually
        start-sleep -s 3

        ##Reconfigure bios to uefi
        Write-Host "Reconfiguring $vm to boot with efi"
        $vsphervm.ExtensionData.ReconfigVM_task($uefi)

        ##Sleep for 10s to make sure the reconfigure is done
        start-seleep -s 10

        write-host "Updating BDM for VM in PVS"
        ##Getting pvs device, markint it down in case it hasn't been detected as down and then updating bdm
        $pvsDevice = Get-PvsDevice -Name $machine.HostedMachineName
        $pvsDevice | invoke-PvsMarkDown

        ##Create a PVS Task to update the bdm and loop until done
        $pvsTask = $pvsDevice | Start-PvsDeviceUpdateBdm
        while($pvsTask.State -eq 0
        {
            $percentFinished = Get-PvsTaskStatus -Object $pvsTask
            $percentFinished.ToString() + "% Finished"
            start-sleep -s 3
            $pvsTask = Get-PvsTask -Object $pvsTask
        }
        if ($pvsTask.State -eq 2)
        {
            write-host "Successful"
        }
        else
        {
            write-host "Failed"
        }

        write-host "Taking $vm out of Maintenance Mode"
        get-brokermachine -MachineName $VM -AdminAddress | Set-BrokerMachineMaintenanceMode -MaintenanceMode $false -AdminAddress $AdminAddress

        write-host "Turning $vm back on"
        New-BrokerHostingPowerAction -MachineName $vm -Action TurnOn -AdminAddress $AdminAddress

        ##Log time and machine name to file
        $time=Get-date
        echo "Date:$time machine:$vm was attempted to be reconfigured for UEFI boot" >>.\UEFI-Reconfig.txt
        start-sleep -s 3
    }
    
    ##Don't interrupt a user
    If (($machine.PowerState -eq "On") -and ($CurrentStates.SessionCount -eq 1))
    {
        write-host "$vm has an active user, will not modify"
        $time=Get-Date
        echo "Date:$time machine:$vm had an active user.  Will not modify" >>.\UEFI-Reconfig.txt
    }

    ##If it's already UEFI, do not reconfigure it
    If ($vmFirmware.Firmware -eq "uefi")
    {
        write-host "$vm is already configured for uefi boot"
        $time=Get-Date
        echo "Date:$time machine:$vm already has uefi boot configured.  Will not modify" >>.\UEFI-Reconfig.txt
    }
}

