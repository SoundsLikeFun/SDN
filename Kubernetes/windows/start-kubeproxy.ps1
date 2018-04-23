<#
 .SYNOPSIS
 This script starts or installs Kube-Proxy

#>

Param(
    
    [parameter(Mandatory = $false)]
    $ComputerName = ((Get-WmiObject win32_computersystem).DNSHostName+"."+(Get-WmiObject win32_computersystem).Domain).toLower(),

    [parameter(Mandatory = $false)]   
    [String] $NetworkMode = "L2Bridge",

    [Switch] $Install
)

# Do some preparations
$env:KUBE_NETWORK=$NetworkMode.ToLower()
Import-Module hns.psm1
Get-HnsPolicyList | Remove-HnsPolicyList

# Check, if install switch is set
if ($Install) {

    # Install Kube-Proxy as service
    sc.exe create kube-proxy binPath="$PSScriptRoot\kube-proxy.exe --windows-service --v=4 --proxy-mode=kernelspace --hostname-override=$($ComputerName) --kubeconfig="$PSScriptRoot\config""

    # Set dependency
    sc config kube-proxy depend=kubelet
    
}
else {

    # Start Kube-Proxy as process
    kube-proxy.exe --v=4 --proxy-mode=kernelspace --hostname-override=$($ComputerName) --kubeconfig=$PSScriptRoot\config

}
