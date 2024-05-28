  #=============================================#
  # Alarm Email                               	#
  # SRP-AlarmEmail								#
  # DosPuntoCero 						        #
  # v0  --  Jan 2021 
  # v1  --  Added Log Source to email body 5/28/2024
  #=============================================#
<#

RUN THIS FROM A SYSTEM MONITOR HOST

#>
[CmdletBinding()]
Param(
	[string] [Parameter(Mandatory=$true)] $AlarmId,
	[string] [Parameter(Mandatory=$true)] $CaseNumber,
	[string] $OverRideRecipients
)

function Get-ConfigFileData
{
	try{
		if (!(Test-Path -Path $global:ConfigurationFilePath))
		{
			write-host "No Config File Found."
			write-error "Error: Config File Not Found. Please run 'Create Case Management Configuration File' action."
			throw "ExecutionFailure"
		}
		else
		{
			$ConfigFileContent = Import-Clixml -Path $global:ConfigurationFilePath
			$EncryptedApiUrl = $ConfigFileContent.ApiUrl
			$EncryptedApiKey = $ConfigFileContent.ApiKey
            $EncryptedEmailRecipients = $ConfigFileContent.EmailRecipients
			$EncryptedEmailSender = $ConfigFileContent.EmailSender
			$EncryptedSmtpServer = $ConfigFileContent.SmtpServer
			$EncryptedIncludeCaseSRPOut = $ConfigFileContent.IncludeCaseSRPOut
			$EncryptedUserName = $ConfigFileContent.UserName
			$EncryptedPassword = $ConfigFileContent.Password
            $global:PlainApiUrl = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($EncryptedApiUrl))))
			$global:PlainApiKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($EncryptedApiKey))))
			$global:PlainEmailRecipients = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($EncryptedEmailRecipients))))
			$global:PlainEmailSender = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($EncryptedEmailSender))))
			$global:PlainSmtpServer = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($EncryptedSmtpServer))))
			$global:PlainIncludeCaseSRPOut = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($EncryptedIncludeCaseSRPOut))))
			$global:PlainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($EncryptedUserName))))
			$global:PlainUser = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($EncryptedPassword))))
            
		}
	}
	catch{
		$message = $_.Exception.message
		if($message -eq "ExecutionFailure"){
			throw "ExecutionFailure"
		}
		else{
			write-host "Error: User does not have access to Config File."
			write-error $message
			throw "ExecutionFailure"
		}
	}
}

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

try{
	$global:ConfigurationFilePath = "C:\Program Files\LogRhythm\SmartResponse Plugins\EmailConfigFile.xml"
	
	Get-ConfigFileData
	Disable-SSLError
	$ApiUrl = $global:PlainApiUrl
	$ApiKey = $global:PlainApiKey
	$OutputPath = $global:PlainOutputPath
	$EmailRecipients = $global:PlainEmailRecipients
	$EmailSender = $global:PlainEmailSender
	$SmtpServer = $global:PlainSmtpServer
	$IncludeCaseSRPOut = $global:PlainIncludeCaseSRPOut
	$CredsUser = $global:PlainUser
	$CredsPass = $global:PlainPassword
	$IncludeCaseOutput = $false

	if ($IncludeCaseSRPOut[0] -match '(t|y){1}'){
		$IncludeCaseOutput = $true
	}
	
	if (($OverRideRecipients.Length -gt 1) -and ($OverRideRecipients -match '@')){
		$FirstTimeThrough = $true
		$OverRideRecipients.Split(',') | %{
			if ((-not ($_ -match '\w+@\w+\.\w+')) -or ($_ -match '@[^,]+@')){
				Write-Host "$_ Is Not A Valid Email Address`n"
				$OverRideRecipients
				Write-Host "`nUsing the default email address list"
				$EmailRecipients
			} else {
				if ($FirstTimeThrough){
					$FirstTimeThrough = $false
					$EmailRecipients = $OverRideRecipients
				} else {
					$EmailRecipients += $OverRideRecipients
				}
			}
		}
	}
	
	#Construct Case URL for the email
	$CaseURL = "https://"+$ENV:COMPUTERNAME+"."+$ENV:USERDNSDOMAIN+":8443/cases/"+$CaseNumber
	
	# Create the API URLs using the base Api Url
	$AlarmApiUri = [io.path]::combine($ApiUrl, "lr-alarm-api/alarms/$AlarmId")	
	$AlarmApiEventUri = "$AlarmApiUri/events"
	$DrillDownUri = [io.path]::combine($ApiUrl, "lr-drilldown-cache-api/drilldown/$AlarmId")
	$count = 0
	
	# Preparing and making API calls
	$Headers = @{
			"Authorization" = ("Bearer " + $ApiKey);
			"Content-type" = "application/json" 
		}
	Start-Sleep -Seconds 10
	$AlarmApiResponse = Invoke-RestMethod -Uri $AlarmApiUri -Headers $Headers -Method Get
	$AlarmApiEventResponse = Invoke-RestMethod -Uri $AlarmApiEventUri -Headers $Headers -Method Get
	While (! $DrillDownDetails){	
		Start-Sleep -Milliseconds 500
		$DrillDownDetails = (Invoke-RestMethod -Uri $DrillDownUri -Headers $Headers -Method Get).Data.DrillDownResults.RuleBlocks.DrillDownLogs #All relevant info is this deep#>
		$count
		$count ++
		if ($count -gt 6){
			"No Drill Down Details"
			break
		}
	}
	
	if ($DrillDownDetails){
		$DrillDownInfo = @{}
		If($DrillDownDetails.GetType().Name -eq 'Object[]'){
			$DrillDownDetails = $DrillDownDetails[0] #Sometimes this is an array, other times it is a string, this is to ensure we are working with a string
		}
		$DrillDownDetails.Split(',') | %{
			$key = $_ -replace '":.*','' -replace '^.*?"',''
			if(!($DrillDownInfo.Contains($key))){
				$DrillDownInfo.Add(($_ -replace '":.*','' -replace '^.*?"',''),($_ -replace '^.*:["]*','' -replace '"',''))
			}
			
		}
	}
	
	$EmailBody = "<style>
	table {
	  font-family: arial, sans-serif;
	  border-collapse: collapse;
	  width: 100%;
	}

	td, th {
	  border: 1px solid #dddddd;
	  text-align: left;
	  padding: 8px;
	}

	tr:nth-child(even) {
	  background-color: #dddddd;
	}
	</style>
	</head>
	<body><table><tr><td>Alarm Rule Name:`t</td><td>"+$AlarmApiResponse.alarmDetails.alarmRuleName+"</td></tr><tr><td>Risk Score:</td><td>"+$AlarmApiResponse.alarmDetails.rbpMax+"</td></tr><tr><td>Alarm Date:</td><td>"+$AlarmApiResponse.alarmDetails.alarmDate+'</td></tr><tr><td>Case Link:</td><td><a href="'+$CaseURL+'">'+$CaseURL+"</a></td></tr>"
	if ($AlarmApiEventResponse.alarmEventsDetails.classificationName){$EmailBody += "<tr><td>Classification:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.classificationName+"</td></tr>"}
	elseif ($DrillDownInfo.classificationName){$EmailBody += "<tr><td>Classification:</td><td>"+$DrillDownInfo.classificationName+"</td></tr>"}
	if ($AlarmApiEventResponse.alarmEventsDetails.command){$EmailBody += "<tr><td>Command:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.command+"</td></tr>"}
	elseif ($DrillDownInfo.command){$EmailBody += "<tr><td>Command:</td><td>"+$DrillDownInfo.command+"</td></tr>"}
	if ($AlarmApiEventResponse.alarmEventsDetails.count){$EmailBody += "<tr><td>Count:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.count+"</td></tr>"}
	elseif ($DrillDownInfo.count){$EmailBody += "<tr><td>Count:</td><td>"+$DrillDownInfo.count+"</td></tr>"}
	if ($AlarmApiEventResponse.alarmEventsDetails.directionName){$EmailBody += "<tr><td>Direction:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.directionName+"</td></tr>"}
	elseif ($DrillDownInfo.directionName){$EmailBody += "<tr><td>Direction:</td><td>"+$DrillDownInfo.directionName+"</td></tr>"}
	if ($AlarmApiEventResponse.alarmEventsDetails.objectName){$EmailBody += "<tr><td>Object:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.objectName+"</td></tr>"}
	elseif ($DrillDownInfo.objectName){$EmailBody += "<tr><td>Object:</td><td>"+$DrillDownInfo.objectName+"</td></tr>"}
	if ($AlarmApiEventResponse.alarmEventsDetails.policy){$EmailBody += "<tr><td>Policy:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.policy+"</td></tr>"}
	elseif ($DrillDownInfo.policy){$EmailBody += "<tr><td>Policy:</td><td>"+$DrillDownInfo.policy+"</td></tr>"}
	if ($AlarmApiEventResponse.alarmEventsDetails.process){$EmailBody += "<tr><td>Process:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.process+"</td></tr>"}
	elseif ($DrillDownInfo.process){$EmailBody += "<tr><td>Process:</td><td>"+$DrillDownInfo.process+"</td></tr>"}
	if ($AlarmApiEventResponse.alarmEventsDetails.result){$EmailBody += "<tr><td>Result:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.result+"</td></tr>"}
	elseif ($DrillDownInforesult){$EmailBody += "<tr><td>Result:</td><td>"+$DrillDownInfo.result+"</td></tr>"}
	if ($AlarmApiEventResponse.alarmEventsDetails.severity){$EmailBody += "<tr><td>Severity:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.severity+"</td></tr>"}
	elseif ($DrillDownInfo.severity){$EmailBody += "<tr><td>Severity:</td><td>"+$DrillDownInfo.severity+"</td></tr>"}
	if ($AlarmApiEventResponse.alarmEventsDetails.status){$EmailBody += "<tr><td>Status:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.status+"</td></tr>"}
	elseif ($DrillDownInfo.status){$EmailBody += "<tr><td>Status:</td><td>"+$DrillDownInfo.status+"</td></tr>"}
	if ($AlarmApiEventResponse.alarmEventsDetails.threatName){$EmailBody += "<tr><td>Threat Name:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.threatName+"</td></tr>"}
	elseif ($DrillDownInfo.threatName){$EmailBody += "<tr><td>Threat Name:</td><td>"+$DrillDownInfo.threatName+"</td></tr>"}
	if ($AlarmApiEventResponse.alarmEventsDetails.url){$EmailBody += "<tr><td>URL:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.url+"</td></tr>"}
	elseif ($DrillDownInfo.url){$EmailBody += "<tr><td>URL:</td><td>"+$DrillDownInfo.url+"</td></tr>"}
	if ($AlarmApiEventResponse.alarmEventsDetails.vendorInfo){$EmailBody += "<tr><td>Vendor Info:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.vendorInfo+"</td></tr>"}
	elseif ($DrillDownInfo.vendorInfo){$EmailBody += "<tr><td>Vendor Info:</td><td>"+$DrillDownInfo.vendorInfo+"</td></tr>"}
	if ($AlarmApiEventResponse.alarmEventsDetails.sender){$EmailBody += "<tr><td>Sender:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.sender+"</td></tr>"}
	elseif ($DrillDownInfo.sender){$EmailBody += "<tr><td>Sender:</td><td>"+$DrillDownInfo.sender+"</td></tr>"}
	if ($AlarmApiEventResponse.alarmEventsDetails.recipient){$EmailBody += "<tr><td>Recipient:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.recipient+"</td></tr>"}
	elseif ($DrillDownInfo.recipient){$EmailBody += "<tr><td>Recipient:</td><td>"+$DrillDownInfo.recipient+"</td></tr>"}
	if ($AlarmApiEventResponse.alarmEventsDetails.subject){$EmailBody += "<tr><td>Subject:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.subject+"</td></tr>"}
	elseif ($DrillDownInfo.subject){$EmailBody += "<tr><td>Subject:</td><td>"+$DrillDownInfo.subject+"</td></tr>"}
	$EmailBody += "<tr><td>Log Source:</td><td>"+$DrillDownInfo.logsource+"</td></tr>" #Added at my bosses request 5/28/24
	if (($AlarmApiEventResponse.alarmEventsDetails.impactedIP) -or ($AlarmApiEventResponse.alarmEventsDetails.impactedHostName) -or ($AlarmApiEventResponse.alarmEventsDetails.originIP) -or ($AlarmApiEventResponse.alarmEventsDetails.originHostName) -or ($AlarmApiEventResponse.alarmEventsDetails.login) -or ($AlarmApiEventResponse.alarmEventsDetails.account)){
		$EmailBody += "</table><table><tr><th></th><th>Origin</th><th>Impacted</th></tr>"
		if (($AlarmApiEventResponse.alarmEventsDetails.originHostName) -or ($AlarmApiEventResponse.alarmEventsDetails.impactedHostName)){
			$EmailBody += "<tr><td>Host:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.originHostName+"</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.impactedHostName+"</td></tr>"
		}
		if (($AlarmApiEventResponse.alarmEventsDetails.originIP) -or ($AlarmApiEventResponse.alarmEventsDetails.impactedIP)){
			$EmailBody += "<tr><td>IP:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.originIP+"</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.impactedIP+"</td></tr>"
		}
		if (($AlarmApiEventResponse.alarmEventsDetails.login) -or ($AlarmApiEventResponse.alarmEventsDetails.account)){
			$EmailBody += "<tr><td>User:</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.login+"</td><td>"+$AlarmApiEventResponse.alarmEventsDetails.account+"</td></tr>"
		}
	}
	elseif (($DrillDownInfo.impactedIP) -or ($DrillDownInfo.impactedHostName) -or ($DrillDownInfo.originIP) -or ($DrillDownInfo.originHostName) -or ($DrillDownInfo.login) -or ($DrillDownInfo.account)){
		$EmailBody += "</table><table><tr><th></th><th>Origin</th><th>Impacted</th></tr>"
		if (($DrillDownInfo.originHostName) -or ($DrillDownInfo.impactedHostName)){
			$EmailBody += "<tr><td>Host:</td><td>"+$DrillDownInfo.originHostName+"</td><td>"+$DrillDownInfo.impactedHostName+"</td></tr>"
		}
		if (($DrillDownInfo.originIP) -or ($DrillDownInfo.impactedIP)){
			$EmailBody += "<tr><td>IP:</td><td>"+$DrillDownInfo.originIP+"</td><td>"+$DrillDownInfo.impactedIP+"</td></tr>"
		}
		if (($DrillDownInfo.login) -or ($DrillDownInfo.account)){
			$EmailBody += "<tr><td>User:</td><td>"+$DrillDownInfo.login+"</td><td>"+$DrillDownInfo.account+"</td></tr>"
		}
	}
	$EmailBody += "</table>"
	
	if ($AlarmApiResponse.alarmDetails.smartResponseActions.standardOut){
		if ($IncludeCaseOutput){
			$EmailBody += "<br>"+$AlarmApiResponse.alarmDetails.smartResponseActions.standardOut
		}else{
			$EmailBody += "<br>"+($AlarmApiResponse.alarmDetails.smartResponseActions.standardOut -replace "\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\s\|\s\w+\s\|\sCaseSRP.*\n",'')
		}
	}
	$EmailSubject = $AlarmApiResponse.alarmDetails.alarmRuleName
	
	if ($CredsUser -ne "No UserName Provided"){
		[SecureString]$secureString = $CredsPass | ConvertTo-SecureString -AsPlainText -Force 
		[PSCredential]$credentialObejct = New-Object System.Management.Automation.PSCredential -ArgumentList $CredsUser, $secureString
		try {
			Send-MailMessage -Body $EmailBody -From $EmailSender -SmtpServer $SMTPserver -Subject $EmailSubject -To $EmailRecipients -BodyAsHtml -Credential $credentialObejct
		} catch {
			try{
				Send-MailMessage -Body $EmailBody -From $EmailSender -SmtpServer $SMTPserver -Subject $EmailSubject -To $EmailRecipients -BodyAsHtml -Credential $credentialObejct
			} catch {
				$APIError = $_
			}
		}
	} else {
		try {
			Send-MailMessage -Body $EmailBody -From $EmailSender -SmtpServer $SMTPserver -Subject $EmailSubject -To $EmailRecipients -BodyAsHtml
		} catch {
			try{
				Send-MailMessage -Body $EmailBody -From $EmailSender -SmtpServer $SMTPserver -Subject $EmailSubject -To $EmailRecipients -BodyAsHtml
			} catch {
				$APIError = $_
			}
		}
	}
} catch {
	Write-Error "Something went wrong"
	$APIError
	$Error
}
	