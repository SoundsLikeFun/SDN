kubectl --kubeconfig config delete deployment --all

Stop-Service KubeProxy
Stop-Service Kubelet

Get-hnsendpoints | Remove-HNSEndpoint 
Get-HNSPolicyLists | Remove-HnsPolicyList

$na = Get-NetAdapter | Where-Object Name -Like "vEthernet (Ethernet*"
netsh in ipv4 set int $na.ifIndex fo=en

Write-Host "Modify KubeproxyStartup.ps1 to Userspace"
pause

$hnsnetwork =get-hnsnetworks | Where-Object Name -EQ l2tunnel
$hnsendpoint = new-hnsendpoint -NetworkId $hnsnetwork.Id -Name forwarder
Register-HnsHostEndpoint -EndpointID $hnsendpoint.Id  -CompartmentID 1

Start-Service KubeProxy

Start-Sleep 5 
New-HnsLoadBalancer -Endpoints $hnsendpoint.Id -InternalPort 60000 -ExternalPort 60000 -Vip 1.1.1.1

ipconfig /all
