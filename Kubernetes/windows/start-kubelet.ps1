Param(

    [parameter(Mandatory = $true)] 
    [string] $MasterIp,
    
    [parameter(Mandatory = $true)] 
    [String] $InterfaceAlias,

    [parameter(Mandatory = $false)] 
    $KubeDnsSuffix ="svc.cluster.local",

    [parameter(Mandatory = $false)] 
    $KubeDnsServiceIp="11.0.0.10",

    [parameter(Mandatory = $false)]
    $serviceCIDR="11.0.0.0/8", 

    [parameter(Mandatory = $false)]
    [String]$NetworkMode = "L2Bridge", 

    [parameter(Mandatory = $false)] 
    $clusterCIDR="192.168.0.0/16",

    [parameter(Mandatory = $false)]
    $ComputerName = ((Get-WmiObject win32_computersystem).DNSHostName+"."+(Get-WmiObject win32_computersystem).Domain).toLower(),

    [Switch] $Install

)

$WorkingDir = $PSScriptRoot
$CNIPath = [Io.path]::Combine($WorkingDir , "cni")
$CNIConfig = [Io.path]::Combine($CNIPath, "config", "$NetworkMode.conf")

$endpointName = "cbr0"
$vnicName = "vEthernet ($endpointName)"

function Get-PodGateway($podCIDR)
{
    # Current limitation of Platform to not use .1 ip, since it is reserved
    return $podCIDR.substring(0,$podCIDR.lastIndexOf(".")) + ".1"
}

function Get-PodEndpointGateway($podCIDR)
{
    # Current limitation of Platform to not use .1 ip, since it is reserved
    return $podCIDR.substring(0,$podCIDR.lastIndexOf(".")) + ".2"
}

function Get-PodCIDR()
{
    $podCIDR=kubectl.exe --kubeconfig=config get nodes/$($(hostname).ToLower()) -o custom-columns=podCidr:.spec.podCIDR --no-headers
    return $podCIDR
}

function Get-MgmtIpAddress()
{
    $na = Get-NetAdapter | Where-Object Name -Like "*$interfaceAlias*"
    return (Get-NetIPAddress -InterfaceAlias $na.ifAlias -AddressFamily IPv4).IPAddress
}

function ConvertTo-DecimalIP
{
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [Net.IPAddress] $IPAddress
  )
  $i = 3
  $DecimalIP = 0
  $IPAddress.GetAddressBytes() | ForEach-Object {
    $DecimalIP += $_ * [Math]::Pow(256, $i); $i--
  }

  return [UInt32]$DecimalIP
}

function ConvertTo-DottedDecimalIP
{
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [Uint32] $IPAddress
  )

    $DottedIP = $(for ($i = 3; $i -gt -1; $i--)
    {
      $Remainder = $IPAddress % [Math]::Pow(256, $i)
      ($IPAddress - $Remainder) / [Math]::Pow(256, $i)
      $IPAddress = $Remainder
    })

    return [String]::Join(".", $DottedIP)
}

function ConvertTo-MaskLength
{
  param(
    [Parameter(Mandatory = $True, Position = 0)]
    [Net.IPAddress] $SubnetMask
  )
    $Bits = "$($SubnetMask.GetAddressBytes() | ForEach-Object {
      [Convert]::ToString($_, 2)
    } )" -replace "[\s0]"
    return $Bits.Length
}

function Get-MgmtSubnet
{
    $na = Get-NetAdapter | Where-Object Name -Like "*$interfaceAlias*"
    if (!$na) {
      throw "Failed to find a suitable network adapter, check your network settings."
    }
    $addr = (Get-NetIPAddress -InterfaceAlias $na.ifAlias -AddressFamily IPv4).IPAddress
    $mask = (Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object InterfaceIndex -eq $($na.ifIndex)).IPSubnet[0]
    $mgmtSubnet = (ConvertTo-DecimalIP $addr) -band (ConvertTo-DecimalIP $mask)
    $mgmtSubnet = ConvertTo-DottedDecimalIP $mgmtSubnet
    return "$mgmtSubnet/$(ConvertTo-MaskLength $mask)"
}

function Update-CNIConfig($podCIDR)
{
    $jsonSampleConfig = '{
  "cniVersion": "0.2.0",
  "name": "<NetworkMode>",
  "type": "wincni.exe",
  "master": "Ethernet",
  "capabilities": { "portMappings": true },
  "ipam": {
     "environment": "azure",
     "subnet":"<PODCIDR>",
     "routes": [{
        "GW":"<PODGW>"
     }]
  },
  "dns" : {
    "Nameservers" : [ "11.0.0.10" ],
    "Search": [ "svc.cluster.local" ]
  },
  "AdditionalArgs" : [
    {
      "Name" : "EndpointPolicy", "Value" : { "Type" : "OutBoundNAT", "ExceptionList": [ "<ClusterCIDR>", "<ServerCIDR>", "<MgmtSubnet>" ] }
    },
    {
      "Name" : "EndpointPolicy", "Value" : { "Type" : "ROUTE", "DestinationPrefix": "<ServerCIDR>", "NeedEncap" : true }
    },
    {
      "Name" : "EndpointPolicy", "Value" : { "Type" : "ROUTE", "DestinationPrefix": "<MgmtIP>/32", "NeedEncap" : true }
    }
  ]
}'
    #Add-Content -Path $CNIConfig -Value $jsonSampleConfig

    $configJson =  ConvertFrom-Json $jsonSampleConfig
    $configJson.name = $NetworkMode.ToLower()
    $configJson.ipam.subnet=$podCIDR
    $configJson.ipam.routes[0].GW = Get-PodEndpointGateway $podCIDR
    $configJson.dns.Nameservers[0] = $KubeDnsServiceIp
    $configJson.dns.Search[0] = $KubeDnsSuffix

    $configJson.AdditionalArgs[0].Value.ExceptionList[0] = $clusterCIDR
    $configJson.AdditionalArgs[0].Value.ExceptionList[1] = $serviceCIDR
    $configJson.AdditionalArgs[0].Value.ExceptionList[2] = Get-MgmtSubnet

    $configJson.AdditionalArgs[1].Value.DestinationPrefix  = $serviceCIDR
    $configJson.AdditionalArgs[2].Value.DestinationPrefix  = "$(Get-MgmtIpAddress)/32"

    if (Test-Path $CNIConfig) {
        Clear-Content -Path $CNIConfig
    }

    Write-Host "Generated CNI Config [$configJson]"

    Add-Content -Path $CNIConfig -Value (ConvertTo-Json $configJson -Depth 20)
}

function Test-PodCIDR($podCIDR)
{
    return $podCIDR.length -gt 0
}

$podCIDR = Get-PodCIDR 
$podCidrDiscovered = Test-PodCIDR $podCIDR

# if the podCIDR has not yet been assigned to this node, start the kubelet process to get the podCIDR, and then promptly kill it.
if (-not $podCidrDiscovered)
{
    $argList = @("--hostname-override=$(hostname)","--pod-infra-container-image=kubeletwin/pause","--resolv-conf=""""", "--kubeconfig=config")

    $process = Start-Process -FilePath kubelet.exe -PassThru -ArgumentList $argList

    # run kubelet until podCidr is discovered
    Write-Host "waiting to discover pod CIDR"
    while (-not $podCidrDiscovered)
    {
        Write-Host "Sleeping for 10s, and then waiting to discover pod CIDR"
        Start-Sleep -sec 10

        $podCIDR = Get-PodCIDR
        $podCidrDiscovered = Test-PodCIDR $podCIDR
    }

    # stop the kubelet process now that we have our CIDR, discard the process output
    $process | Stop-Process | Out-Null
}

# startup the service
Import-Module hns.psm1
$hnsNetwork = Get-HnsNetwork | Where-Object Name -EQ $NetworkMode.ToLower()

if ($hnsNetwork)
{
    # Cleanup all containers
    docker ps -q | ForEach-Object {docker rm $_ -f} 

    Write-Host "Cleaning up old HNS network found" 
    Remove-HnsNetwork $hnsNetwork
    Start-Sleep 10 
}

$podGW = Get-PodGateway $podCIDR

$hnsNetwork = New-HNSNetwork -Type $NetworkMode -AddressPrefix $podCIDR -Gateway $podGW -Name $NetworkMode.ToLower() -Verbose
$podEndpointGW = Get-PodEndpointGateway $podCIDR

$hnsEndpoint = New-HnsEndpoint -NetworkId $hnsNetwork.Id -Name $endpointName -IPAddress $podEndpointGW -Gateway "0.0.0.0" -Verbose
Register-HnsHostEndpoint -EndpointID $hnsEndpoint.Id -CompartmentID 1
netsh int ipv4 set int "$vnicName" for=en
#netsh int ipv4 set add "vEthernet (cbr0)" static $podGW 255.255.255.0

Start-Sleep 10
# Add route to all other POD networks
Update-CNIConfig $podCIDR


if ($Install) {

    sc.exe create kubelet binPath="$PSScriptRoot\kubelet.exe --service --hostname-override=$($ComputerName) --v=6 --pod-infra-container-image=kubeletwin/pause --resolv-conf='' --allow-privileged=true --enable-debugging-handlers --cluster-dns=$KubeDnsServiceIp --cluster-domain=cluster.local --kubeconfig='$PSScriptRoot\config' --hairpin-mode=promiscuous-bridge --image-pull-progress-deadline=20m --cgroups-per-qos=false --enforce-node-allocatable='' --network-plugin=cni --cni-bin-dir='$PSScriptRoot\cni' --cni-conf-dir '$PSScriptRoot\cni\config'"

}
else {

    kubelet.exe --hostname-override=$($ComputerName) --v=6 `
        --pod-infra-container-image=kubeletwin/pause --resolv-conf="" `
        --allow-privileged=true --enable-debugging-handlers `
        --cluster-dns=$KubeDnsServiceIp --cluster-domain=cluster.local `
        --kubeconfig=$PSScriptRoot\config --hairpin-mode=promiscuous-bridge `
        --image-pull-progress-deadline=20m --cgroups-per-qos=false `
        --enforce-node-allocatable="" `
        --network-plugin=cni --cni-bin-dir="$PSScriptRoot\cni" --cni-conf-dir "$PSScriptRoot\cni\config"

}