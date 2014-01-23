<#
.SYNOPSIS
    OpenShift Windows Node installation script.
.DESCRIPTION
    This script installs all the components of the OpenShift Windows Node.
    It does not install prerequisites such as Internet Information Services or Microsoft Sql Server.
    Before the installation is started this script will verify that all prerequisites are present and properly installed.
.PARAMETER binLocation
    Target bin directory. This is where all the OpenShift binaries will be copied.

.PARAMETER publicHostname
    Public hostname of the machine. This should resolve to the public IP of this node.
    
.PARAMETER brokerHost
    Hostname of the OpenShift broker.
    
.PARAMETER cloudDomain
    The domain of the cloud (e.g. mycloud.com).
    
.PARAMETER externalEthDevice
    Public ethernet device.
    
.PARAMETER internalEthDevice
    Internal ethernet device.
    
.PARAMETER publicIp
    Public IP of the machine (default is 'the first IP on the public ethernet card').
    
.PARAMETER gearBaseDir
    Gear base directory. This is the where application files will live.
    
.PARAMETER gearShell
    Gear shell. This is the shell that will be run when users ssh to the gear.
    
.PARAMETER gearGecos
    Gecos information. This will be the same for all gears.
    
.PARAMETER cartridgeBasePath
    Cartridge base path. This is where cartridge files will be copied.
    
.PARAMETER platformLogFile
    Log file path. This is where the OpenShift Windows Node will log information.
    
.PARAMETER platformLogLevel
    Log level. The level of detail to use when logging information.
    
.PARAMETER containerizationPlugin
    Container used for securing OpenShift gears on Windows.

.PARAMETER rubyDownloadLocation
    Ruby 1.9.3 msi package download location. The installer will download this msi and install it.
    
.PARAMETER rubyInstallLocation
    Ruby installation location. This is where ruby will be installed on the local machine.
    
.PARAMETER rubyDevKitDownloadLocation
    Devkit download location. The installer will download this self extracting archive and set it up.
    
.PARAMETER rubyDevKitInstallLocation
    Ruby devkit installation location. The ruby devkit will be unpacked at this location.

.PARAMETER mcollectiveActivemqServer
    ActiveMQ Host. This is where the ActiveMQ messaging service is installed. It is usually setup in the same place as your broker.
    
.PARAMETER mcollectiveActivemqPort
    ActiveMQ Port. The port to use when connecting to ActiveMQ.
    
.PARAMETER mcollectiveActivemqUser
    ActiveMQ Username. The default ActiveMQ username for an OpenShift installation is 'mcollective'.
    
.PARAMETER mcollectiveActivemqPassword
    ActiveMQ Password. The default ActiveMQ password for an ActiveMQ installation is 'marionette'.

.PARAMETER sshdCygwinDir
    Location of sshd installation. This is where cygwin will be installed.

.PARAMETER sshdListenAddress
    This specifies on which interface should the SSHD service listen. By default it will listen on all interfaces.
    
.PARAMETER sshdPort
    SSHD listening port.

.PARAMETER skipRuby
    This is a switch parameter that allows the user to skip downloading and installing Ruby. 
    This is useful for testing, when the caller is sure Ruby is already installed in the directory specified by the -rubyInstallLocation parameter.

.PARAMETER skipCygwin
    This is a switch parameter that allows the user to skip downloading and installing Cygwin. 
    This is useful for testing, when the caller is sure Cygwin is present in the directory specified by the -sshdCygwinDir parameter.
    Note that sshd will NOT be re-configured if you skip this step.

.PARAMETER skipMCollective
    This is a switch parameter that allows the user to skip downloading and installing MCollective.
    This is useful for testing, when the caller is sure MCollective is already present in c:\openshift\mcollective. 
    Configuration of MCollective will still happen, even if this parameter is present.

.NOTES
    Author: Vlad Iovanov
    Date:   January 17, 2014

.EXAMPLE
.\install.ps1 -publicHostname winnode-001.mycloud.com -brokerHost broker.mycloud.com -cloudDomain mycloud.com
Install the node by passing the minimum information required. 
.EXAMPLE
.\install.ps1 -publicHostname winnode-001.mycloud.com -brokerHost broker.mycloud.com -cloudDomain mycloud.com -publicIP 10.2.0.104
Install the node by also passing the public IP address of the machine.
#>
[CmdletBinding()]
param (
    # parameters used for setting up the OpenShift Windows Node binaries
    [string] $binLocation = 'c:\openshift\bin\',
    # parameters used for setting ip node configuration file
    [string] $publicHostname = $( Read-Host "Public hostname of the machine" ),
    [string] $brokerHost = $( Read-Host "Hostname of the broker" ),
    [string] $cloudDomain = $( Read-Host "Cloud domain" ),
    [string] $externalEthDevice = 'Ethernet',
    [string] $internalEthDevice = 'Ethernet',
    [string] $publicIp = @((get-wmiobject -class "Win32_NetworkAdapterConfiguration" | Where { $_.Index -eq (get-wmiobject -class "Win32_NetworkAdapter" | Where { $_.netConnectionId -eq $externalEthDevice }).DeviceID }).IPAddress | where { $_ -notmatch ':' })[0],
    [string] $gearBaseDir = 'c:\openshift\gears\',
    [string] $gearShell = (Join-Path $binLocation 'oo-trap-user.exe'),
    [string] $gearGecos = 'OpenShift guest',
    [string] $cartridgeBasePath = 'c:\openshift\cartridges\',
    [string] $platformLogFile = 'c:\openshift\log\platform.log',
    [ValidateSet('TRACE','DEBUG','WARNING','ERROR')]
    [string] $platformLogLevel = 'DEBUG',
    [string] $containerizationPlugin = 'uhuru-prison',
    # parameters used for ruby installation
    [string] $rubyDownloadLocation ='http://dl.bintray.com/oneclick/rubyinstaller/rubyinstaller-1.9.3-p448.exe?direct',
    [string] $rubyInstallLocation = 'c:\openshift\ruby\',
    [string] $rubyDevKitDownloadLocation = 'https://github.com/downloads/oneclick/rubyinstaller/DevKit-tdm-32-4.5.2-20111229-1559-sfx.exe',
    [string] $rubyDevKitInstallLocation = 'c:\openshift\ruby\devkit\',
    # parameters used for mcollective setup
    [string] $mcollectiveActivemqServer = $brokerHost,
    [int] $mcollectiveActivemqPort = 61613,
    [string] $mcollectiveActivemqUser = 'mcollective',
    [string] $mcollectiveActivemqPassword = 'marionette',
    # parameters used for setting up sshd
    [string] $sshdCygwinDir = 'c:\openshift\cygwin',
    [string] $sshdListenAddress = '0.0.0.0',
    [int] $sshdPort = 22,
    # parameters used for skipping some installation steps
    [Switch] $skipRuby = $false,
    [Switch] $skipCygwin = $false,
    [Switch] $skipMCollective = $false
)

$currentDir = split-path $SCRIPT:MyInvocation.MyCommand.Path -parent

Write-Verbose 'Loading modules and scripts ...'
Import-Module (Join-Path $currentDir '..\..\common\openshift-common.psd1') -DisableNameChecking
. (Join-Path $currentDir 'validation-helpers.ps1')
. (Join-Path $currentDir 'setup-helpers.ps1')
. (Join-Path $currentDir 'ruby-helpers.ps1')
. (Join-Path $currentDir 'service-helpers.ps1')


Write-Host 'Installation logs will be written in the c:\openshift\setup_logs'
New-Item -path 'C:\openshift\setup_logs' -type directory -Force | out-Null


# TODO: stop existing services?


# Be verbose and print all settings
Write-Verbose "Target binary location used is '$binLocation'"
Write-Verbose "Public hostname used is '$publicHostname'"
Write-Verbose "Broker host used is '$brokerHost'"
Write-Verbose "Cloud domain used is '$cloudDomain'"
Write-Verbose "External ethernet device used is '$externalEthDevice'"
Write-Verbose "Internal ethernet device used is '$internalEthDevice'"
Write-Verbose "Public IP used is '$publicIp'"
Write-Verbose "Target gear directory used is '$gearBaseDir'"
Write-Verbose "Ger shell used is '$gearShell'"
Write-Verbose "Gecos information used is '$gearGecos'"
Write-Verbose "Target cartridge path used is '$cartridgeBasePath'"
Write-Verbose "Target platform log file used is '$platformLogFile'"
Write-Verbose "Target log level used is '$platformLogLevel'"
Write-Verbose "Container used is '$containerizationPlugin'"
Write-Verbose "Ruby download location used is '$rubyDownloadLocation'"
Write-Verbose "Target ruby installation directory used is '$rubyInstallLocation'"
Write-Verbose "Ruby devkit download location used is '$rubyDevKitDownloadLocation'"
Write-Verbose "Target ruby devkit installation directory used is '$rubyDevKitInstallLocation'"
Write-Verbose "ActiveMQ server used is '$mcollectiveActivemqServer'"
Write-Verbose "ActiveMQ port used is '$mcollectiveActivemqPort'"
Write-Verbose "ActiveMQ user used is '$mcollectiveActivemqUser'"
Write-Verbose "Target cygwin installation dir used is '$sshdCygwinDir'"
Write-Verbose "SSHD listen address used is '$sshdListenAddress'"
Write-Verbose "SSHD listening port used is '$sshdPort'"


Write-Verbose "Verifying required variables are not empty ..."
if ([string]::IsNullOrWhitespace($publicHostname)) { Write-Error "Public hostname cannot be empty."; exit 1; }
if ([string]::IsNullOrWhitespace($brokerHost)) { Write-Error "Broker host cannot be empty."; exit 1; }
if ([string]::IsNullOrWhitespace($cloudDomain)) { Write-Error "Cloud domain cannot be empty."; exit 1; }


Write-Host 'Verifying prerequisites ...'
Check-Elevation
Check-WindowsVersion
$windowsFeatures = @('NET-Framework-Features', 'NET-Framework-Core', 'NET-Framework-45-Features', 'NET-Framework-45-Core', 'NET-Framework-45-ASPNET', 'NET-WCF-Services45', 'NET-WCF-TCP-PortSharing45') 
$windowsFeatures | ForEach-Object { Check-WindowsFeature $_ }
$iisFeatures = @('Web-Server', 'Web-WebServer', 'Web-Common-Http', 'Web-Default-Doc', 'Web-Dir-Browsing', 'Web-Http-Errors', 'Web-Static-Content', 'Web-Http-Redirect', 'Web-DAV-Publishing', 'Web-Health', 'Web-Http-Logging', 'Web-Custom-Logging', 'Web-Log-Libraries', 'Web-ODBC-Logging', 'Web-Request-Monitor', 'Web-Http-Tracing', 'Web-Performance', 'Web-Stat-Compression', 'Web-Dyn-Compression', 'Web-Security', 'Web-Filtering', 'Web-Basic-Auth', 'Web-CertProvider', 'Web-Client-Auth', 'Web-Digest-Auth', 'Web-Cert-Auth', 'Web-IP-Security', 'Web-Url-Auth', 'Web-Windows-Auth', 'Web-App-Dev', 'Web-Net-Ext', 'Web-Net-Ext45', 'Web-AppInit', 'Web-Asp-Net', 'Web-Asp-Net45', 'Web-CGI', 'Web-ISAPI-Ext', 'Web-ISAPI-Filter', 'Web-Includes', 'Web-WebSockets', 'Web-Mgmt-Tools', 'Web-Scripting-Tools', 'Web-Mgmt-Service', 'Web-WHC')
$iisFeatures | ForEach-Object { Check-WindowsFeature $_ }
Check-SQLServer2008


# TODO: stop all services, gears, etc., or tell the user to do it

Write-Host 'Generating node.conf file ...'
Write-Verbose 'Creating directory c:\openshift ...'
New-Item -path 'C:\openshift\' -type directory -Force | Out-Null
Write-Template (Join-Path $currentDir "node.conf.template") "c:\openshift\node.conf" @{
    publicHostname = $publicHostname
    publicIp = $publicIp
    brokerHost = $brokerHost
    sshBaseDir = (Join-Path $sshdCygwinDir "installation")
    cloudDomain = $cloudDomain
    externalEthDev = $externalEthDevice
    internalEthDev = $internalEthDevice
    gearBaseDir = $gearBaseDir
    gearShell = $gearShell
    gearGecos = $gearGecos
    cartridgeBasePath = $cartridgeBasePath
    platformLogFile = $platformLogFile
    platformLogLevel = $platformLogLevel
    containerizationPlugin = $containerizationPlugin
}

# copy binaries
Write-Host 'Copying binaries ...'
Cleanup-Directory $binLocation
Write-Verbose "Creating bin directory '${binLocation}' ..."
New-Item -path $binLocation -type directory -Force | Out-Null
$sourceItems = (Join-Path $currentDir '..\..\..\*')
Copy-Item -Recurse -Force -Verbose:($PSBoundParameters['Verbose'] -eq $true) -Exclude 'cartridges' -Path $sourceItems $binLocation

# setup ruby
if ($skipRuby -eq $false)
{
    Setup-Ruby $rubyDownloadLocation $rubyInstallLocation
}
# Setup-RubyDevkit $rubyDevKitDownloadLocation $rubyDevKitInstallLocation

# setup agent - run bundler
#Run-RubyCommand $rubyInstallLocation $rubyDevKitInstallLocation 'gem install bundler' $rubyInstallLocation
#Run-RubyCommand $rubyInstallLocation $rubyDevKitInstallLocation 'bundle install' (Join-Path $binLocation 'mcollective\openshift')


Write-Host 'Setting up SSHD ...'
if ($skipCygwin -eq $false)
{
    Setup-SSHD $sshdCygwinDir  $sshdListenAddress $sshdPort
}
$cygpath = (Join-Path $sshdCygwinDir 'installation\bin\cygpath.exe')
$chmod = (Join-Path $sshdCygwinDir 'installation\bin\chmod.exe')


Write-Host 'Setting up MCollective ...'
if ($skipMCollective -eq $false)
{
    Setup-MCollective 'c:\openshift\mcollective' (Join-Path $sshdCygwinDir 'installation') $rubyInstallLocation
}
Configure-MCollective $mcollectiveActivemqServer $mcollectiveActivemqPort $mcollectiveActivemqUser $mcollectiveActivemqPassword 'c:\openshift\mcollective' $binLocation $rubyInstallLocation
#TODO: do something about facts


# setup cartridges
Write-Host 'Copying cartridges ...'
Cleanup-Directory $cartridgeBasePath
Write-Verbose "Creating cartridges directory '${cartridgeBasePath}' ..."
New-Item -path $cartridgeBasePath -type directory -Force | Out-Null
$sourceItems = (Join-Path $currentDir '..\..\..\cartridges\*')
Copy-Item -Recurse -Force -Verbose:($PSBoundParameters['Verbose'] -eq $true) -Path $sourceItems $cartridgeBasePath


# setup oo-bin alias paths
Setup-OOAliases $binLocation


# setup env vars in c:\openshift\env
Setup-GlobalEnv

Remove-Service 'openshift.mcollectived' $sshdCygwinDir
Remove-Service 'openshift.sshd' $sshdCygwinDir

$mcollectivePath = 'c:\openshift\mcollective\'

$mcollectiveLib = (Join-Path $mcollectivePath 'lib').Replace("\", "/")
$mcollectiveBin = (Join-Path $mcollectivePath 'bin\mcollectived')
$mcollectiveConfig = (Join-Path $mcollectivePath 'etc\server.cfg')

Create-Service 'openshift.mcollectived' (Join-Path $rubyInstallLocation 'bin\ruby.exe') "-I'${mcollectiveLib};' -- '${mcollectiveBin}' --config '${mcollectiveConfig}'" "OpenShift Windows Node MCollective Service" $sshdCygwinDir

$runSSHDScript = (Join-Path $binLocation 'powershell\tools\sshd\run-sshd.ps1')
$cygwinInstallationPath = (Join-Path $sshdCygwinDir 'installation')

Create-Service 'openshift.sshd' (Get-Command powershell).Path "-File '${runSSHDScript}' -targetDirectory '${cygwinInstallationPath}'" "OpenShift Windows Node SSHD Service" $sshdCygwinDir "/var/run/sshd.pid"

Write-Host 'Starting services ...'
net start openshift.mcollectived
net start openshift.sshd