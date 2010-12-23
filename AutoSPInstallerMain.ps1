param 
(
    [string]$InputFile = $(throw '- Need parameter input file (e.g. "c:\SP2010\AutoSPInstaller\AutoSPInstallerInput.xml")')
)

##$xmlinput = [xml] (get-content $InputFile)
# Globally update all instances of "localhost" in the input file to actual local server name
[xml]$xmlinput = (Get-Content $InputFile) -replace ("localhost", $env:COMPUTERNAME)

# ===================================================================================
#
# AutoSPInstaller - See # MAIN for what to run
#
# ===================================================================================

#Region Setup Paths

$0 = $myInvocation.MyCommand.Definition
$dp0 = [System.IO.Path]::GetDirectoryName($0)
$bits = Get-Item $dp0 | Split-Path -Parent

$PSConfig = "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\14\BIN\psconfig.exe"

#EndRegion

#Region External Functions
. "$dp0\AutoSPInstallerFunctions.ps1"
. "$dp0\AutoSPInstallerFunctionsCustom.ps1"
#EndRegion

#Region Prepare For Install
Function PrepForInstall
{
	StartTracing
    CheckConfig
	CheckOS
    CheckSQLAccess
}
#EndRegion

#Region Install SharePoint binaries
Function Run-Install
{
    write-host " Install based on $InputFile for"  $xmlinput.Configuration.getAttribute("Environment")  "Version " $xmlinput.Configuration.getAttribute("Version") -ForegroundColor White 

    DisableLoopbackCheck $xmlinput
    DisableServices $xmlinput
    InstallPrerequisites $xmlinput
    InstallSharePoint $xmlinput
    InstallLanguagePacks $xmlinput
}
#EndRegion

#Region Setup Farm
Function Setup-Farm
{
    [System.Management.Automation.PsCredential]$farmCredential  = GetFarmCredentials ($xmlinput) 
    [security.securestring]$SecPhrase = GetFarmPassphrase ($xmlinput)
    ConfigureFarmAdmin ($xmlinput)
    Load-SharePoint-Powershell
    CreateOrJoinFarm ($xmlinput) ([security.securestring]$SecPhrase) ([System.Management.Automation.PsCredential]$farmCredential)
    CreateCentralAdmin ($xmlinput)
	CheckFarmTopology ($xmlinput)
	ConfigureFarm ($xmlinput)
    AddManagedAccounts ($xmlinput)   
    CreateWebApplications ($xmlinput)
}
#EndRegion

#Region Setup Services
Function Setup-Services
{
    InstallSandboxSolutionService ($xmlinput)
    CreateMetadataServiceApp ($xmlinput)
	StartSearchQueryAndSiteSettingsService
	CreateUserProfileServiceApplication ($xmlinput)
	CreateStateServiceApp ($xmlinput)
	CreateWSSUsageApp ($xmlinput)
	CreateWebAnalyticsApp ($xmlinput)
	CreateSecureStoreServiceApp ($xmlinput)
}
#EndRegion

#Region MAIN - Check for input file and start the install

PrepForInstall
Run-Install
Setup-Farm
Setup-Services

#EndRegion

#Region Finalize Install (perform any cleanup operations)
# Run last
Function Finalize-Install 
{
    #RemoveFarmAccount from admins
	If ($CreateCentralAdmin -eq "1")
	{
		## Run Farm configuration Wizard for whatever's left to configure...
		Write-Host -ForegroundColor White "- Launching Configuration Wizard..."
		Start-Process "http://$($env:COMPUTERNAME):$CentralAdminPort/_admin/adminconfigintro.aspx?scenarioid=adminconfig&welcomestringid=farmconfigurationwizard_welcome" -WindowStyle Normal
	}

	## Remove Farm Account from local Administrators group to avoid big scary warnings in Central Admin
	If (!($RunningAsFarmAcct))
	{
		$FarmAcct = $xmlinput.Configuration.Farm.Account.Username
		Write-Host -ForegroundColor White "- Removing $FarmAcct from local Administrators..."
		$FarmAcctDomain,$FarmAcctUser = $FarmAcct -Split "\\"
		try
		{
			([ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group").Remove("WinNT://$FarmAcctDomain/$FarmAcctUser")
			If (-not $?) {throw}
		}
		catch {Write-Host -ForegroundColor White " - $FarmAcct already removed from Administrators."}
	}

	#Write-Progress -Activity "Installing SharePoint (Unattended)" -Status "Done." -Completed
	Write-Host -ForegroundColor White "- Finished!`a"
	$EndDate = Get-Date
	Write-Host -ForegroundColor White "-----------------------------------"
	Write-Host -ForegroundColor White "| Automated SP2010 install script |"
	Write-Host -ForegroundColor White "| Started on: $StartDate |"
	Write-Host -ForegroundColor White "| Completed:  $EndDate |"
	Write-Host -ForegroundColor White "-----------------------------------"
	Stop-Transcript
	Pause
	Invoke-Item $LogFile
}
Finalize-Install 
#EndRegion

# ===================================================================================
# LOAD ASSEMBLIES
# ===================================================================================
#[void][System.Reflection.Assembly]::Load("Microsoft.SharePoint, Version=14.0.0.0, Culture=neutral, PublicKeyToken=71e9bce111e9429c") 
