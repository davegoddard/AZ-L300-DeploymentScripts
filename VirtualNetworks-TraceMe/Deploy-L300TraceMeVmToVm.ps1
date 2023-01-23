Write-Host -ForegroundColor Cyan "L300 TraceMe VM to VM Practice Deployment Script"

$resourceGroup = Read-Host "Lab Resource Group Name"
$region = Read-Host "Region to Deploy to (example: West US 2)"
$vmPassword = Read-Host "VM Password"

$asName = "AS1"
$serverName = "L300PktCapSrv"
$clientName = "L300PktCapCli"

$rg = Get-AzResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue
if ($null -eq $rg)
{
    $rg = New-AzResourceGroup -Name $resourceGroup -Location $region
}

$nsgSshRule = New-AzNetworkSecurityRuleConfig -Name ssh-rule -Description "Allow SSH from corp" -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix "131.107.0.0/16" -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22
$nsgHttpRule = New-AzNetworkSecurityRuleConfig -Name http-rule -Description "Allow HTTP" -Access Allow -Protocol Tcp -Direction Inbound -Priority 200 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 80
$nsgHttpRule2 = New-AzNetworkSecurityRuleConfig -Name http-rule2 -Description "Allow HTTP 8080" -Access Allow -Protocol Tcp -Direction Inbound -Priority 201 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8080
$defaultNsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroup -Location $region -Name "DefaultNSG" -SecurityRules $nsgSshRule,$nsgHttpRule,$nsgHttpRule2
$defaultSubnet = New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix "10.23.122.0/26" -NetworkSecurityGroup $defaultNsg

$vnetObj = Get-AzVirtualNetwork -Name L300TraceMeVmToVm-VNet -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
if ($null -eq $vnetObj)
{
    $vnetObj = New-AzVirtualNetwork -Name L300TraceMeVmToVm-VNet -ResourceGroupName $resourceGroup -Location $region -AddressPrefix "10.23.122.0/24" -Subnet $defaultSubnet
}

# Create Server VM:
$vmName = $serverName
$vmSize = "Standard_B1s"
$nicName = $vmName + "nic1"

$asObj = Get-AzAvailabilitySet -Name $asName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
if ($null -eq $asObj)
{
    $asObj = New-AzAvailabilitySet -Name $asName -ResourceGroupName $resourceGroup -Location $region
}

$subnetObj = Get-AzVirtualNetworkSubnetConfig -Name "default" -VirtualNetwork $vnetObj
$ipv4config = New-AzNetworkInterfaceIpConfig -Name "IPConfigV4" -PrivateIpAddressVersion IPv4 -Primary -SubnetId $SubnetObj.Id -PrivateIpAddress "10.23.122.4"
#$ipv6config = New-AzNetworkInterfaceIpConfig -Name "IPConfigV6" -PrivateIpAddressVersion IPv6 -SubnetId $SubnetObj.Id
$nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
if ($null -eq $nic)
{
    $nic= New-AzNetworkInterface -Name $nicName -ResourceGroupName $resourceGroup -Location $region -IpConfiguration $ipv4config #$ipv4config,$ipv6config 
}

$SecurePassword = ConvertTo-SecureString $vmPassword -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ("azureuser", $SecurePassword); 

$VirtualMachine = New-AzVMConfig -VMName $vmName -VMSize $vmSize -AvailabilitySetID $asObj.Id
$VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Linux -ComputerName $vmName -Credential $Credential -PatchMode "AutomaticByPlatform"
$VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName "Canonical" -Offer "0001-com-ubuntu-server-jammy" -Skus "22_04-lts" -Version "latest"
$nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $resourceGroup
$VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $nic.Id

# Specify the OS disk name and create the VM
$diskName="OSDisk"

#random storage account name to avoid conflict
$storageAcctName = "sa" + $(New-Guid).ToString().Substring(0,8)
$storageAcctObj = Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAcctName -ErrorAction SilentlyContinue
if ($null -eq $storageAcctObj)
{
    $storageAcctObj = New-AzStorageAccount -Name $storageAcctName -Location $region -ResourceGroupName $resourceGroup -SkuName Standard_LRS
}

if ($null -ne $storageAcctObj)
{
	$osDiskUri=$storageAcctObj.PrimaryEndpoints.Blob.ToString() + "vhds/" + $vmName + "-" + $diskName  + ".vhd"
	$VirtualMachine=Set-AzVMOSDisk -VM $VirtualMachine -Name $diskName -VhdUri $osDiskUri -CreateOption fromImage
	New-AzVM -ResourceGroupName $resourceGroup -Location $region -VM $VirtualMachine
}

### Make client VM:
$vmName = $clientName
$vmSize = "Standard_B1s"
$nicName = $vmName + "nic1"

$subnetObj = Get-AzVirtualNetworkSubnetConfig -Name "default" -VirtualNetwork $vnetObj
$ipv4config = New-AzNetworkInterfaceIpConfig -Name "IPConfigV4" -PrivateIpAddressVersion IPv4 -Primary -SubnetId $SubnetObj.Id -PrivateIpAddress "10.23.122.5"
#$ipv6config = New-AzNetworkInterfaceIpConfig -Name "IPConfigV6" -PrivateIpAddressVersion IPv6 -SubnetId $SubnetObj.Id
$nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
if ($null -eq $nic)
{
    $nic= New-AzNetworkInterface -Name $nicName -ResourceGroupName $resourceGroup -Location $region -IpConfiguration $ipv4config #$ipv4config,$ipv6config 
}

$VirtualMachine = New-AzVMConfig -VMName $vmName -VMSize $vmSize -AvailabilitySetID $asObj.Id
$VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Linux -ComputerName $vmName -Credential $Credential -PatchMode "AutomaticByPlatform"
$VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName "Canonical" -Offer "0001-com-ubuntu-server-jammy" -Skus "22_04-lts" -Version "latest"
$nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $resourceGroup
$VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $nic.Id

# Specify the OS disk name and create the VM
$diskName="OSDisk"

if ($null -ne $storageAcctObj)
{
	$osDiskUri=$storageAcctObj.PrimaryEndpoints.Blob.ToString() + "vhds/" + $vmName + "-" + $diskName  + ".vhd"
	$VirtualMachine=Set-AzVMOSDisk -VM $VirtualMachine -Name $diskName -VhdUri $osDiskUri -CreateOption fromImage
	New-AzVM -ResourceGroupName $resourceGroup -Location $region -VM $VirtualMachine
}

Write-Host "Preping Server Guest OS with WebServer code and resource"
$srvPrepOutput = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -Name $serverName -CommandId 'RunShellScript' -ScriptString "curl https://gist.githubusercontent.com/davegoddard/faa7920e399373987c4f15c2bada0b6e/raw/prep-srv.sh > prep-srv.sh ; bash prep-srv.sh"

Write-Host "Preping Client Guest OS with Client code starting them as scheduled tasks"
$cliPrepOutput = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -Name $clientName -CommandId 'RunShellScript' -ScriptString "curl https://gist.githubusercontent.com/davegoddard/e38e7779d1d620129e75ea3cc01d6553/raw/prep-client.sh > /tmp/prep-client.sh ; su -c 'bash /tmp/prep-client.sh' azureuser"

