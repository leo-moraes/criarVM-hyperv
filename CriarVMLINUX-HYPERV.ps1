#requires -Modules Hyper-V
	[CmdletBinding(SupportsShouldProcess=$true)]
	param
	(
		[Parameter(Mandatory=$true, Position=1)][String]$VMName,
		[Parameter()][String]$VHDXName = '',
		[Parameter()][String]$VMStoragePath = '',
		[Parameter()][String]$VHDStoragePath = '',
		[Parameter()][String]$InstallISOPath = '',
		[Parameter()][Switch]$Cluster,
		[Parameter()][String]$VMSwitchName = '',
		[Parameter()][Uint32]$StartupMemory = 512MB,
		[Parameter()][Uint32]$MinimumMemory = 256MB,
		[Parameter()][Uint32]$MaximumMemory = 1GB,
		[Parameter()][Uint64]$VHDXSizeBytes = 40GB
	)
 
	if([String]::IsNullOrEmpty($VHDXName))
        {
            $VHDXName = '{0}.vhdx' -f $VMName
        }
	if($VHDXName -notmatch '\.vhdx$')
        {
            $VHDXName += '.vhdx'
        }
	if([String]::IsNullOrEmpty($VMStoragePath))
        {
            $VMStoragePath = (Get-VMHost).VirtualMachinePath
        }
	if(-not (Test-Path -Path $VMStoragePath))
        {
            Write-Error -Message ('O caminho da VM {0} não existe.' -f $VMStoragePath)
            return
        }
	if([String]::IsNullOrEmpty($VHDStoragePath))
        {
            $VHDStoragePath = (Get-VMHost).VirtualHardDiskPath
        }
	if(-not (Test-Path -Path $VHDStoragePath))
        {
            Write-Error -Message ('O caminho do armazenamento {0} não existe.' -f $VHDStoragePath)
            return
        }
	$VHDStoragePath = Join-Path -Path $VHDStoragePath -ChildPath $VHDXName
	if([String]::IsNullOrEmpty($InstallISOPath) -or -not (Test-Path -Path $InstallISOPath -PathType Leaf))
        {
            Write-Error -Message ('Imagem ISO {0} não existe' -f $InstallISOPath)
            return
        }
	if([String]::IsNullOrEmpty($VMSwitchName))
        {
            $VMSwitchName = (Get-VMSwitch | ? SwitchType -eq 'External')[0].Name
        }
	if([String]::IsNullOrEmpty($VMSwitchName))
        {
            Write-Error -Message ('No virtual switch specified')
            return
        }
 
	$VM = New-VM -Name $VMName -MemoryStartupBytes $StartupMemory -SwitchName $VMSwitchName -Path $VMStoragePath -Generation 2 -NoVHD
	Set-VMMemory -VM $VM -DynamicMemoryEnabled $true -MinimumBytes $MinimumMemory -MaximumBytes $MaximumMemory
	Set-VMProcessor -VM $VM -Count 2
	Start-VM -VM $VM
	Stop-VM -VM $VM -Force
	New-VHD -Path $VHDStoragePath -SizeBytes $VHDXSizeBytes -Dynamic -BlockSizeBytes 1MB
	$VMVHD = Add-VMHardDiskDrive -VM $VM -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -Path $VHDStoragePath -Passthru
	$VMDVDDrive = Add-VMDvdDrive -VM $VM -ControllerNumber 0 -ControllerLocation 1 -Passthru
	$VMNetAdapter = Get-VMNetworkAdapter -VM $VM
	Set-VMNetworkAdapter -VMNetworkAdapter $VMNetAdapter -StaticMacAddress ($VMNetAdapter.MacAddress)
	Set-VMFirmware -VM $VM -BootOrder $VMDVDDrive, $VMVHD, $VMNetAdapter -EnableSecureBoot On -SecureBootTemplate 'MicrosoftUEFICertificateAuthority'
	Set-VMDvdDrive -VMDvdDrive $VMDVDDrive -Path $InstallISOPath
    
    if($Cluster)
        {
            Add-ClusterVirtualMachineRole -VMName $VMName
        }
#}