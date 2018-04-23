<#
 .SYNOPSIS
 This script creates the Kubernetes sandbox

#>

# Get Windows version
$WindowsVersion = $(Get-ComputerInfo).WindowsVersion

# Set image names
switch ($WindowsVersion) {

    1607    {
    
                $ImageNameNano = "microsoft/nanoserver:latest"
                $ImageNameCore = "microsoft/windowsservercore:latest"
        
            }
    default {

                $ImageNameNano = "microsoft/nanoserver:$WindowsVersion"
                $ImageNameCore = "microsoft/windowsservercore:$WindowsVersion"
            
            }

}


# Check, if docker image exist and prepare
if (!(docker images $ImageNameNano -q)) {
    docker pull $ImageNameNano
    docker tag (docker images $ImageNameNano -q) microsoft/nanoserver
}

if (!(docker images $ImageNameCore -q)) {
    docker pull $ImageNameCore
    docker tag (docker images $ImageNameCore -q) microsoft/windowsservercore
}

# Create Kubernetes sandbox
$infraPodImage=docker images kubeletwin/pause -q
if (!$infraPodImage)
{
    pushd
    cd $PSScriptRoot
    docker build -t kubeletwin/pause .
    popd
}

