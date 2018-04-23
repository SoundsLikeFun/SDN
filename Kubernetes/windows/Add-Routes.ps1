Param(
    [parameter(Mandatory = $true)] [string] $masterIp
)

function Get-MgmtDefaultGatewayAddress()
{
    $na = Get-NetAdapter | Where-Object Name -Like "vEthernet (Ethernet*"
    return  (Get-NetRoute -InterfaceAlias $na.ifAlias -DestinationPrefix "0.0.0.0/0").NextHop
}

function Add-RouteToPodCIDR($nicName)
{
    $podCIDRs=kubectl.exe  --kubeconfig=config get nodes -o=custom-columns=Name:.status.nodeInfo.operatingSystem,PODCidr:.spec.podCIDR --no-headers
    Write-Host "Add-RouteToPodCIDR - available nodes $podCIDRs"
    foreach ($podcidr in $podCIDRs)
    {
        $tmp = $podcidr.Split(" ")
        $os = $tmp | Select-Object -First 1
        $cidr = $tmp | Select-Object -Last 1
        $cidrGw =  $cidr.substring(0,$cidr.lastIndexOf(".")) + ".1"

        if ($os -eq "windows") {
            $cidrGw = $cidr.substring(0,$cidr.lastIndexOf(".")) + ".2"
        }

        Write-Host "Adding route for Remote Pod CIDR $cidr, GW $cidrGw, for node type $os"

        $route = get-netroute -InterfaceAlias "$nicName" -DestinationPrefix $cidr -erroraction Ignore
        if (!$route) {

            New-Netroute -InterfaceAlias "$nicName" -DestinationPrefix $cidr -NextHop  $cidrGw -Verbose
        }
    }
}

$endpointName = "cbr0"
$vnicName = "vEthernet ($endpointName)"

# Add routes to all POD networks on the Bridge endpoint nic
Add-RouteToPodCIDR -nicName $vnicName

$na = Get-NetAdapter | Where-Object Name -Like "vEthernet (Ethernet*"
if (!$na)
{
    Write-Error "Do you have a virtual adapter configured? Couldn't find one!"
    exit 1
}

# Add routes to all POD networks on the Mgmt Nic on the host
Add-RouteToPodCIDR -nicName $na.InterfaceAlias

# Update the route for the POD on current host to be on Link
$podCIDR=kubectl.exe --kubeconfig=config get nodes/$($(hostname).ToLower()) -o custom-columns=podCidr:.spec.podCIDR --no-headers
Get-NetRoute -DestinationPrefix $podCIDR  -InterfaceAlias $na.InterfaceAlias | Remove-NetRoute -Confirm:$false
New-NetRoute -DestinationPrefix $podCIDR -NextHop 0.0.0.0 -InterfaceAlias $na.InterfaceAlias

# Add a route to Master, to override the Remote Endpoint
$route = Get-NetRoute -DestinationPrefix "$masterIp/32" -erroraction Ignore
if (!$route)
{
    $gateway = Get-MgmtDefaultGatewayAddress
    Write-Host "Adding a route for $masterIp with NextHop $gateway"
    New-NetRoute -DestinationPrefix "$masterIp/32" -NextHop $gateway  -InterfaceAlias $na.InterfaceAlias -Verbose
}
