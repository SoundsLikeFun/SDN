<#
 .SYNOPSIS
 This script installs Kubernetes as service
#>

Param(
    
    [parameter(Mandatory = $true)] 
    [string] $MasterIp,
    
    [parameter(Mandatory = $true)] 
    [String] $InterfaceAlias,

    [parameter(Mandatory = $false)]
    [String]$NetworkMode = "L2Bridge", 

    [parameter(Mandatory = $false)] 
    $clusterCIDR="192.168.0.0/16"


)

# Set location for binaries
Set-Location $PSScriptRoot

# Install Windows images for Kubernetes sandbox
Start-Process powershell $PSScriptRoot\Install-Images.ps1

# Prepare network and install infrastruture services

Start-Process powershell -ArgumentList "-File $PSScriptRoot\Start-Kubelet.ps1 -clusterCIDR $clusterCIDR -NetworkMode $NetworkMode -InterfaceAlias $InterfaceAlias -Install"

Start-Sleep 10

while( !(Get-HnsNetwork -Verbose | Where-Object Name -EQ $NetworkMode.ToLower()) )
{
    Write-Host "Waiting for the Network to be created"
    Start-Sleep 10
}

Start-Process powershell -File $PSScriptRoot\Add-Routes.ps1 -masterIp $MasterIp

Start-Process powershell -ArgumentList " -File $PSScriptRoot\Start-Kubeproxy.ps1 -NetworkMode $NetworkMode -Install"




