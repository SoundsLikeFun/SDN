<#
 .SYNOPSIS
 This script start Kubernetes services for testing purpose
#>


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
    $clusterCIDR="192.168.0.0/16"
)

Set-Location $PSScriptRoot

# Prepare POD infra Images
Start-Process powershell $PSScriptRoot\Install-Images.ps1

# Prepare Network and start infrastruture services
Start-Process powershell -ArgumentList "-File $PSScriptRoot\Start-Kubelet.ps1 -clusterCIDR $clusterCIDR -NetworkMode $NetworkMode -InterfaceAlias $InterfaceAlias -KubeDnsSuffix $KubeDnsSuffix -KubeDnsServiceIp $KubeDnsServiceIp -serviceCIDR $serviceCIDR"

Start-Sleep 10

while( !(Get-HnsNetwork -Verbose | Where-Object Name -EQ $NetworkMode.ToLower()) )
{
    Write-Host "Waiting for the Network to be created"
    Start-Sleep 10
}

Start-Process powershell -File $PSScriptRoot\Add-Routes.ps1 -masterIp $MasterIp

Start-Process powershell -ArgumentList " -File $PSScriptRoot\Start-Kubeproxy.ps1 -NetworkMode $NetworkMode"

