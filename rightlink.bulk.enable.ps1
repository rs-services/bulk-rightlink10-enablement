# This script, when run on a running unmanaged (raw) instance, will install and run RightScale's
# RightLink agent to turn it into a "RightScale Server". Turning it into a RightScale Server
# allows management via the RightScale platform.
#
# It does this in 4 steps:
#  (1) locate the RightScale ServerTemplate and Deployment to use
#  (2) locate a unique identifier about this instance (such as instance ID)
#  (3) associate that ServerTemplate and Deployment with the instance by making a wrap_instance API
#      calls to RightScale's API service
#  (4) install RightLink
#
# This script is deliberately written in Powershell to be easy to customize
# and modify. For example, to supply custom inputs to servertemplates or hardcode in alternate
# defaults. This script is designed to be "idempotent", meaning you can rerun it multiple
# times with no ill effect.

# If a Username/Password to a local or domain user is supplied, this install script
# will attempt to run RightLink as that user. If no Username/Password is supplied,
# a local Administrator called "RightLink" with a randomly generated password will be created
# for RightLink to run under.
Param(
  $targetServers,
  [Parameter(Mandatory=$true)]
  [System.Management.Automation.CredentialAttribute()]
  $Credential,
  [alias('k')][string]$refreshToken,
  [alias('d')][string]$deploymentName,
  [alias('e')][string]$deploymentHref,
  [alias('t')][string]$serverTemplateName,
  [alias('r')][string]$serverTemplateHref,
  [alias('n')][string]$serverName,
  [alias('p')][string]$inputs,
  [alias('c')][string]$cloudType,
  [alias('f')][string]$cloudName,
  [alias('i')][string]$instanceHref,
  [alias('s')][string]$instanceType,
  [alias('a')][string]$apiServer,
  [alias('x')][string]$proxy,
  [alias('y')][string]$noProxy,
  [alias('u')][string]$Username,
  [alias('w')][string]$Password,
  [alias('h')][switch]$help
)

function GetHelp
{
  Write-Host "This script will take unmanaged instances and turn them into RightScale servers."
  Write-Host "Parameters:"
  Write-Host "  -TargetServers        Comma-separated list of hostnames or IP addresses to RL-enable."
  Write-Host "  -Credential           PSCredential to establish PSRemoting Session with Target Servers"
  Write-Host "  -RefreshToken         RightScale API refresh token from the dash Settings>API Credentials (required)"
  Write-Host "  -DeploymentName       Name of the pre-existing deployment into which to put the server"
  Write-Host "  -DeploymentHref       HREF of the deployment to put the server. alternate to the name of the deployment (ex. /api/deployments/123456789)"
  Write-Host "  -ServerTemplateName   Name of the ServerTemplate to associate with this instance"
  Write-Host "  -ServerTemplateHref   Alternate to ServerTemplateName. HREF of the ServerTemplate to associate with this instance (ex. /api/server_templates/123456789)"
  Write-Host "  -ServerName           Name to call the server. Default is current Instance name or $DEFAULT_SERVER_NAME"
  Write-Host "  -Inputs               Server inputs in the form of NAME=key:value, separate multiple inputs with commas"
  Write-Host "  -CloudType            Cloud type the instance is in. Supported values are amazon, azure, cloud_stack, google, open_stack_v2, rackspace_next_gen, soft_layer, vscale, uca"
  Write-Host "  -CloudName            The name of the cloud the instance is located"
  Write-Host "  -InstanceHref         RightScale API instance HREF (disables self-detection) (ex. /api/clouds/1/instances/123456ABCDEF)"
  Write-Host "  -InstanceType         The name of the instances type (for UCA clouds only), Default: $DEFAULT_INSTANCE_TYPE"
  Write-Host "  -ApiServer            Hostname for the RightScale API, Default: $DEFAULT_SERVER"
  Write-Host "  -Proxy                Have RightLink use HTTP proxy. Will also install RightLink through proxy"
  Write-Host "  -NoProxy              A list of hosts to not proxy. List is inherited by scripts/recipes as an environment variable"
  Write-Host "  -Username             RightLink Service User Name (default: RightLink)"
  Write-Host "  -Password             RightLink Service User Password (default: Randomly generated password)"
  Write-Host "  -Help                 Display help"
  Write-Host ""
  Write-Host "Required Inputs: -RefreshToken"
  Write-Host "                 -TargetServers"
  Write-Host "                 -Credential"
  Write-Host "                 -ServerTemplateName or -ServerTemplateHref"
  Write-Host "                 -DeploymentName or -DeploymentHref"
  Write-Host "                 -CloudType or -InstanceHref or -CloudName"
  Write-Host ""
}

[System.Management.Automation.ScriptBlock]$ScriptBlock = {
} #end ScriptBlock

if ($targetServers.GetType().Name -eq "Object[]") { $ServersArr = $targetServers }
elseif ($targetServers.GetType().Name -eq "String") {
    $ServersArr = $targetServers.Split(",")
}
else {
    write-host "Invalid TargetServers parameter set"
}


$allsessions = Get-PSSession
if ($AllSessions) { $AllSessions | foreach { Remove-PSSession -Session $_ } }

Foreach ($targetServer in $ServersArr) {
    $session = $null
    New-PSSession -ComputerName $targetServer -Credential $Credential
    $Session = Get-PSSession -ComputerName $targetServer -Credential $Credential
    Invoke-Command -Session $session -ScriptBlock {
        Set-ExecutionPolicy Bypass -Scope Process
        $argslist = $null
        if ($Using:refreshToken) {
          $argslist = $argslist + "-refreshToken $Using:refreshToken"
        }
        if ($Using:deploymentName) {
          $argslist = $argslist + " -deploymentName $Using:deploymentName"
        }
        if ($Using:deploymentHref) {
          $argslist = $argslist + " -deploymentHref $Using:deploymentHref"
        }
        if ($Using:serverTemplateName) {
          $argslist = $argslist + " -serverTemplateName $Using:serverTemplateName"
        }
        if ($Using:serverTemplateHref) {
          $argslist = $argslist + " -serverTemplateHref $Using:serverTemplateHref"
        }
        if ($Using:serverName) {
          $argslist = $argslist + " -serverName $Using:serverName"
        }
        if ($Using:inputs) {
          $argslist = $argslist + " -inputs $Using:inputs"
        }
        if ($Using:cloudType) {
          $argslist = $argslist + " -cloudType $Using:cloudType"
        }
        if ($Using:cloudName) {
          $argslist = $argslist + " -cloudName $Using:cloudName"
        }
        if ($Using:instanceHref) {
          $argslist = $argslist + " -instanceHref $Using:instanceHref"
        }
        if ($Using:instanceType) {
          $argslist = $argslist + " -instanceType $Using:instanceType"
        }
        if ($Using:apiServer) {
          $argslist = $argslist + " -apiServer $Using:apiServer"
        }
        if ($Using:proxy) {
          $argslist = $argslist + " -proxy $Using:proxy"
        }
        if ($Using:noProxy) {
          $argslist = $argslist + " -noProxy $Using:noProxy"
        }
        if ($Using:Username) {
          $argslist = $argslist + " -username $Using:Username"
        }
        if ($Using:Password) {
          $argslist = $argslist + " -password $Using:password"
        }
        
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile("https://rightlink.rightscale.com/rll/10/rightlink.enable.ps1", "$pwd\rightlink.enable.ps1")
        Invoke-Expression "$pwd\rightlink.enable.ps1 $argslist"
    }
    Remove-PSSession -Session $session

}