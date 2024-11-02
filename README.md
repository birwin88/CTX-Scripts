# CTX-Scripts
Collection of Citrix Scripts that have saved me time.

# BIOStoUEFI.ps1
This script is used to take a BIOS boot PVS Device using BDM and convert it to UEFI. First, assign a UEFI vdisk to the PVS Device Collection and then run the script. It will put the machine in maintenance mode, shut it down, update bios to efi in vsphere, update the bdm disk, take machine out of maintenance mode, and then power it back on.  

Dependencies:
PVS Console/Powershell modules, Delivery Controller Console/Powershell modules, and PowerCLI/vmware modules

Room for improvement:
Removing the sleeps and replacing each item with a task that waits until each step is done.  Already has a 99% ish success rate in the environment it's deployed in.  

