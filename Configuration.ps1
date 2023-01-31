#==========================================#
# LogRhythm SmartResponse Plugin           #
# SmartResponse Configure File             #
# aviral.gahlot@logrhythm.com              #
# Case Mgt V5.0  --  Jan, 2020             #
#										   #
# Edited by DosPuntoCero to work with the  #
# Email Generator SRP. v0.1                #
# V0  --  January, 2021				       #
#==========================================#

[CmdletBinding()] 
Param( 
[Parameter(Mandatory=$True)]
[ValidateNotNullOrEmpty()]
[string]$SMTPserver, 
[Parameter(Mandatory=$True)]
[ValidateNotNullOrEmpty()]
[string]$EmailRecipients,
[Parameter(Mandatory=$True)]
[ValidateNotNullOrEmpty()]
[string]$EmailSender,
[Parameter(Mandatory=$true)]
[ValidateNotNullOrEmpty()]
[string]$IP,
[Parameter(Mandatory=$false)]
[string]$Port,
[Parameter(Mandatory=$true)]
[string]$ApiKey,
[Parameter(Mandatory=$false)]
[string]$IncludeCaseSRPOut="N",
[Parameter(Mandatory=$false)]
[string]$UserName,
[Parameter(Mandatory=$false)]
[string]$Password
)



# Trap for an exception during the Script
trap [Exception]
{
    if ($PSItem.ToString() -eq "ExecutionFailure")
	{
		exit 1
	}
	else
	{
		write-error $("Trapped: $_")
		write-host "Aborting Operation."
		exit
	}
}


# Function to Check and Create SmartResponse Directory

function Create-SRPDirectory
{
	if (!(Test-Path -Path $global:ConfigurationDirectoryPath))
	{
		New-Item -ItemType "directory" -Path $global:ConfigurationDirectoryPath -Force | Out-null
	}
}


# Function to Check and Create SmartResponse Config File

function Check-ConfigFile
{
	if (!(Test-Path -Path $global:ConfigurationFilePath))
	{
		New-Item -ItemType "file" -Path $global:ConfigurationFilePath -Force | Out-null
	}
}


# Function to Disable SSL Certificate Error and Enable Tls12

function Disable-SSLError
{
	# Disabling SSL certificate error
    add-type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy


    # Forcing to use TLS1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

# Function to Validate API URL and API Key

function Validate-API{
	$ValidateURL = $ApiUrl + "lr-case-api/cases"
	$Header = @{
			"Authorization" = ("Bearer " + $ApiKey);
			"Content-Type" = "application/json"
			}
	try{
		$ValidateData = Invoke-RestMethod -Uri $ValidateURL -Method Get -Headers $Header	
}
	catch{
		$message = $_.Exception.Message
		if ($message -eq "The remote server returned an error: (400) Bad Request."){
			write-host "API call Unsuccessful."
			write-error "Error: Unable to communicate to lr-case-API. Please check the service instance is up and healthy."
			throw "ExecutionFailure"
		}
		elseif ($message -eq "The underlying connection was closed: The connection was closed unexpectedly."){
			write-host "Invalid API Key."
			write-error "Error: Invalid or Incorrect API key provided."
			throw "ExecutionFailure"
		}
		elseif ($message -eq "Unable to connect to the remote server"){
			write-host "Invalid API URL."
			write-error "Error: Could not resolve API URL. Invalid or Incorrect API URL."
			throw "ExecutionFailure"
		}
        elseif($message -eq "The remote server returned an error: (401) Unauthorized."){
            write-host "Invalid API Key."
			write-error "Error: Invalid or Incorrect API key provided."
			throw "ExecutionFailure"
        }
		else{
			write-host $message
			write-error "API Call Unsuccessful."
			throw "ExecutionFailure"
		}
	}
}

# Function to encrypt the values

function Create-Hashtable
{
	$global:HashTable = [PSCustomObject]@{ "ApiUrl" = $SecureApiUrl
                                       	"ApiKey" = $SecureApiKey
                                        "EmailRecipients" = $SecureEmailRecipients
										"EmailSender" = $SecureEmailSender
										"SMTPServer" = $SecureSMTPserver
										"IncludeCaseSRPOut" = $SecureIncludeCaseSRPOut
										"UserName" = $SecureUserName
										"Password" = $SecurePassword
						}
}


# Function to Create Hashtable for the parameters

function Create-ConfigFile
{
	$global:HashTable | Export-Clixml -Path $global:ConfigurationFilePath
	Write-host "Validations Passed."
	write-host "Configuration Parameters saved for Email SRP"
	
}

if($IP -eq "localhost"){
    if($Port -eq $null -or $Port -eq ""){
        $ApiUrl = "http://"+"$IP/"
    }else{
        $ApiUrl = "http://"+"$IP"+":$Port/"
    }
}else{
    if($Port -eq $null -or $Port -eq ""){
        $ApiUrl = "https://"+"$IP/"
    }else{
        $ApiUrl = "https://"+"$IP"+":$Port/"
    }
}

if ($UserName.Length -lt 2){
	$UserName="No UserName Provided"
}
if ($Password.Length -lt 2){
	$Password="No Password Provided"
}

$ApiUrl = $ApiUrl.Trim()
$ApiKey = $ApiKey.Trim()
$EmailRecipients = $EmailRecipients.Trim()
$EmailSender = $EmailSender.Trim()
$SMTPserver = $SMTPserver.Trim()
$IncludeCaseSRPOut = $IncludeCaseSRPOut.Trim()
$UserName = $UserName.Trim()
$Password = $Password.Trim()

$EmailRecipients.Split(',') | %{
	if (-not ($_ -match '\w+@\w+\.\w+')){
		Write-Host "$_ Is Not A Valid Email Address`n"
		$EmailRecipients
		Throw "Paramater Validation error"
		Exit 1
	}
}

$global:ConfigurationDirectoryPath = "C:\Program Files\LogRhythm\SmartResponse Plugins"
$global:ConfigurationFilePath = "C:\Program Files\LogRhythm\SmartResponse Plugins\EmailConfigFile.xml"

Create-SRPDirectory
Check-ConfigFile
Disable-SSLError
Validate-API

$SecureApiUrl = $ApiUrl | ConvertTo-SecureString -AsPlainText -Force
$SecureApiKey = $ApiKey | ConvertTo-SecureString -AsPlainText -Force
$SecureEmailRecipients = $EmailRecipients | ConvertTo-SecureString -AsPlainText -Force
$SecureEmailSender = $EmailSender | ConvertTo-SecureString -AsPlainText -Force
$SecureSMTPserver = $SMTPserver | ConvertTo-SecureString -AsPlainText -Force
$SecureIncludeCaseSRPOut = $IncludeCaseSRPOut | ConvertTo-SecureString -AsPlainText -Force
$SecureUserName = $UserName | ConvertTo-SecureString -AsPlainText -Force
$SecurePassword = $Password | ConvertTo-SecureString -AsPlainText -Force

Create-Hashtable
Create-ConfigFile
