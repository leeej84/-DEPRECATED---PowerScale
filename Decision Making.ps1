################################################################################################## 
#Main Logic script
#Copyright:         Free to use, please leave this header intact 
#Author:            Leee Jeffries
#Company:           https://www.leeejeffries.com
#Script help:       https://www.leeejeffries.com, please supply any errors or issues you encounter
#Purpose:           Perform logical operations to shutdown or start VDAs based on performance metrics gathered
#Enterprise users:  This script is recommended for users currently utilising smart scale to power up and down VDA's,
# Smart Scale is due to be deprecated in May 2019

#Get current script folder
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$scriptPath

#Function to pull in configuration information from the config file
Function configurationImport () {
    If (Test-Path ("$scriptPath\config.xml")) {
        Return Import-Clixml -Path "$scriptPath\config.xml"
    } else {
        Return "Error"
    }
}

function WMIDetailsImport () {
    # Define variables
    $Directory = $scriptPath
    $KeyFile = Join-Path $Directory  "AES_KEY_FILE.key"
    $PasswordFile = Join-Path $Directory "AES_PASSWORD_FILE.pass"

    # Read the secure password from a password file and decrypt it to a normal readable string
    $SecurePassword = ( (Get-Content $PasswordFile) | ConvertTo-SecureString -Key (Get-Content $KeyFile) )        # Convert the standard encrypted password stored in the password file to a secure string using the AES key file
    $Credentials = New-Object System.Management.Automation.PSCredential ($wmiServiceAccount, $SecurePassword)
    Return $Credentials
}

#Pull in all configuration information
$configInfo = configurationImport

#Set all variables for the script
$performanceIndividual = $configInfo.performanceIndividual
$performanceOverall = $configInfo.performanceOverall
$performanceInterval = $configInfo.performanceSampleInterval
$performanceSamples = $configInfo.performanceSamples
$citrixController = $configInfo.citrixController                                                          
$machinePrefix = $configInfo.machinePrefix 
$businessStartTime =  $configInfo.businessStartTime 
$businessCloseTime = $configInfo.businessCloseTime 
$outOfHoursMachines = $configInfo.outOfHoursMachines
$inHoursMachines = $configInfo.inHoursMachines
$machineScaling = $configInfo.machineScaling 
$farmCPUThreshhold = $configInfo.farmCPUThreshhold
$farmMemoryThreshhold = $configInfo.farmMemoryThreshhold
$farmIndexThreshhold = $configInfo.farmIndexThreshhold
$farmSessionThreshhold = $configInfo.farmSessionThreshhold
$LogNumberOfDays = $configInfo.LogNumberOfDays
$logLocation = $configInfo.logLocation 
$forceUserLogoff = $config.forceUserLogoff    
$userLogoffFirstInterval = $config.userLogoffFirstInterval
$userLogoffFirstMessage = $config.userLogoffFirstMessage
$userLogoffSecondInterval = $config.userLogoffSecondInterval
$userLogoffSecondMessage = $config.userLogoffSecondMessage
$smtpServer = $configInfo.smtpServer
$smtpToAddress = $configInfo.smtpToAddress
$smtpFromAddress = $configInfo.smtpFromAddress
$smtpSubject = $configInfo.smtpSubject
$testingOnly = $configInfo.testingOnly
$exclusionTag = $configInfo.exclusionTag
$wmiServiceAccount = $configInfo.wmiServiceAccount

#Get current date in correct format
$dateNow = $(Get-Date -Format dd/MM/yy).ToString()

#Setup a time object for comparison
$timesObj = [PSCustomObject]@{
    startTime = [datetime]::ParseExact($("$($dateNow) $($businessStartTime)"), "dd/MM/yy HH:mm", $null)
    endTime = [datetime]::ParseExact($("$($dateNow) $($businessCloseTime)"), "dd/MM/yy HH:mm", $null)
    timeNow = $(Get-Date)
    #Set a specific time for testing
    #timeNow = $([datetime]::ParseExact("13/05/19 09:00", "dd/MM/yy HH:mm", $null))
}

#Load Citrix Snap-ins
Add-PSSnapin Citrix*

#Function to create a log file
Function WriteLog() {

    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, HelpMessage = "The error message text to be placed into the log.")] 
        [ValidateNotNullOrEmpty()] 
        [Alias("LogContent")] 
        [string]$Message, 
 
        [Parameter(Mandatory=$true, HelpMessage = "The location of the logfile to be written to.")] 
        [Alias('LogPath')] 
        #SC: I will append the .log later on Process along with the date
        [string]$Path, 
         
        [Parameter(Mandatory=$false, HelpMessage = "The error level of the event.")] 
        [ValidateSet("Error","Warn","Info")] 
        [string]$Level="Info", 
         
        [Parameter(Mandatory=$false, HelpMessage = "Specify to not overwrite the previous log file.")]         
        [switch]$NoClobber 
    ) 
 
    Begin 
    { 
        # Set VerbosePreference to Continue so that verbose messages are displayed. 
        $VerbosePreference = 'Continue' 
    } 
    Process 
    { 
        # append the date to the $path variable. It will also append .log at the end.
        $DateForLogFileName = Get-Date -Format "yyyy-MM-dd"
        $Path = $Path + "_" + $DateForLogFileName+".log"

        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path. 
        If (!(Test-Path $Path)) { 
            Write-Verbose "Creating $Path." 
            New-Item $Path -Force -ItemType File 
            } 
 
        else { 
            # Nothing to see here yet. 
            } 
 
        # Format Date for our Log File 
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss" 
        
         # Write message to error, warning, or verbose pipeline and specify $LevelText 
        switch ($Level) { 
            'Error' { 
                Write-Error $Message 
                $LevelText = 'ERROR:' 
                } 
            'Warn' { 
                Write-Warning $Message 
                $LevelText = 'WARNING:' 
                } 
            'Info' { 
                Write-Verbose $Message 
                $LevelText = 'INFO:' 
                } 
            } 
         
        # Write log entry to $Path 
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append 
    } 
    End 
    { 
    } 
}

Function CircularLogging() {

    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, HelpMessage = "The number of days to keep logs of.")] 
        [ValidateNotNullOrEmpty()] 
        [Alias("LogNumberOfDays")] 
        [int]$NumberOfDays, 

        [Parameter(Mandatory=$true, HelpMessage = "The location of the logfile to be written to.")] 
        [Alias('LogsPath')] 
        [string]$LogLocation
    ) 
 
    Begin 
    { 
        # Set VerbosePreference to Continue so that verbose messages are displayed. 
        $VerbosePreference = 'Continue' 
    } 
    Process 
    {   
        $Path = Split-Path -Path $LogLocation
        WriteLog -Path $LogLocation -Message "Start Circular Log Management" -Level Info
        #Get all log files in the log folder with .log extension, select the oldest ones past the specified retention number and remove them
        $files = Get-ChildItem ("$Path\*.log") | Sort-Object CreationTime
        #Check how many log files we have
        If ($files.count -gt 5) {
            #Calculate files to remove
            $filesToRemove = Get-ChildItem ("$Path\$LogTypeToProcess*.log") | Sort-Object CreationTime | Select-Object -First $($files.count - 5)
            $filesToRemove
            foreach ($file in $filesToRemove) {
                $file | Remove-Item               
                WriteLog -Path $LogLocation -Message "Log file removed $file" -Level Info
            }            
            WriteLog -Path $LogLocation -Message "Completed Circular Log Management" -Level Info
        }
    } 
        End 
    { 
    } 
}


#Function to send an email message in same format as the log
Function SendEmail() {

    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, HelpMessage = "The message to be placed into the email.")] 
        [ValidateNotNullOrEmpty()] 
        [string]$Message, 
 
        [Parameter(Mandatory=$false, HelpMessage = "The attachment to be sent with the email.")] 
        [string]$attachment='', 
         
        [Parameter(Mandatory=$false, HelpMessage = "The warning level of the event.")] 
        [ValidateSet("Error","Warn","Info")] 
        [string]$Level="Info", 
         
        [Parameter(Mandatory=$false, HelpMessage = "The SMTP server that will deliver the email.")] 
        [string]$smtpServer="",
         
        [Parameter(Mandatory=$false, HelpMessage = "The email address to send emails from.")] 
        [string]$fromAddress="",
         
        [Parameter(Mandatory=$false, HelpMessage = "The email address to send emails to.")] 
        [string]$toAddress="",

        [Parameter(Mandatory=$false, HelpMessage = "The subject line of the email")] 
        [string]$subject=""
    )
 
    Begin 
    { 
        # Set VerbosePreference to Continue so that verbose messages are displayed. 
        $VerbosePreference = 'Continue' 
    } 
    Process 
    {               
 
        # Format Date for our Log File 
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
 
        # Write message to error, warning, or verbose pipeline and specify $LevelText 
        switch ($Level) { 
            'Error' { 
                Write-Error $Message 
                $LevelText = 'ERROR:' 
                } 
            'Warn' { 
                Write-Warning $Message 
                $LevelText = 'WARNING:' 
                } 
            'Info' { 
                Write-Verbose $Message 
                $LevelText = 'INFO:' 
                } 
            } 
        # Check if the attachment exists
        if (Test-Path $attachment) { 
            "Attachment file $attachment exists"
            # Send email message with attachment
            Send-MailMessage -SmtpServer $smtpServer -From $fromAddress -To $toAddress -Subject $("$subject - $Level") -Body "$FormattedDate $LevelText $Message" -Attachments $attachment
            WriteLog -Path $logLocation -Message "Sending out an email with an attachment." -Level Info 
        } else {
            # Send email message without attachment
            Send-MailMessage -SmtpServer $smtpServer -From $fromAddress -To $toAddress -Subject $("$subject - $Level") -Body "$FormattedDate $LevelText $Message"
            WriteLog -Path $logLocation -Message "Sending out an email without an attachment, attachment did not exist." -Level warning 
        }        
    } 
    End 
    { 
    } 
}

#Function to check if its a weekday
Function IsWeekDay() {
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, HelpMessage = "The date that needs to be compared to weekdays")] 
        [ValidateNotNullOrEmpty()] 
        [datetime]$date        
    )
    
    #Weekdays
    $weekdays = "Monday","Tuesday","Wednesday","Thursday","Friday"
    #See if the current day of the week sits inside of any other weekdays, returns true or false
    $null -ne ($weekdays | Where-Object { $($date.DayOfWeek) -match $_ })  # returns $true
}

#Function to check if inside of business hours or outside to business hours
Function TimeCheck($timeObj) {
    If (($timesObj.timeNow.Hour -lt $timesObj.startTime.Hour) -or ($timesObj.timeNow.Hour -gt $timesObj.endTime.Hour)) {
        Return "OutOfHours" #OutOfHours as we are outside of working hours
    } ElseIf (($timesObj.timeNow.Hour -ge $timesObj.startTime.Hour) -and ($timesObj.timeNow.Hour -le $timesObj.endTime.Hour)) {
        Return "InsideOfHours" #Dont OutOfHours as we are inside working hours
    } Else {
        Return "Error" #Dont do anything if the time calculation is not conclusive
    }
}

#Function to check the level of machines based on current time and day
Function levelCheck() {
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, HelpMessage = "Number of machines currently live.")]    
        [ValidateNotNullOrEmpty()] 
        [int]$currentMachines, 
 
        [Parameter(Mandatory=$true, HelpMessage = "Number of machines to scale up or down to.")]   
        [ValidateNotNullOrEmpty()]      
        [int]$targetMachines
    )
        
        $scalingFactor = 0
        #Perform some calculation for performance scaling
        If ($machineScaling -eq "CPU") {
            If ($($overallPerformance.overallCPU.average) -gt $farmCPUThreshhold) {
                $scalingFactor = 1 
                WriteLog -Path $logLocation -Message "CPU Threshhold of $farmCPUThreshhold is lower than current farm average of $($overallPerformance.overallCPU.average), we need to spin up an additional machine" -Level Info -Verbose   
            }            
        } elseif ($machineScaling -eq "Memory") {
            If ($($overallPerformance.overallMemory.Average) -gt $farmMemoryThreshhold) {
                $scalingFactor = 1    
                WriteLog -Path $logLocation -Message "Memory Threshhold of $farmMemoryThreshhold is lower than current farm average of $($overallPerformance.overallMemory.Average), we need to spin up an additional machine" -Level Info -Verbose   
            }
        } elseif ($machineScaling -eq "Index") {
            If ($($overallPerformance.overallIndex.Average) -gt $farmIndexThreshhold) {
                $scalingFactor = 1    
                WriteLog -Path $logLocation -Message "Index Threshhold of $farmIndexThreshhold is lower than current farm average of $($overallPerformance.overallIndex.Average), we need to spin up an additional machine" -Level Info -Verbose   
            }
        } elseif ($machineScaling -eq "Sessions") {
                If ($($overallPerformance.overallSession.Average) -gt $farmSessionThreshhold) {
                    $scalingFactor = 1 
                    WriteLog -Path $logLocation -Message "Session Threshhold of $farmSessionThreshhold is lower than current farm average of $($overallPerformance.overallSession.Average), we need to spin up an additional machine" -Level Info -Verbose      
                }
        } else {
            WriteLog -Path $logLocation -Message "There is an error in the config for the machine scaling variable as no case was recognised for sclaing - current variable = $machineScaling" -Level Error -Verbose
        }
    
        #Check the supplied machines levels against what is required
        #Return an object with the action required (Startup, Shutdown, Nothing and the amount of machines necessary to do it to)
        If (($currentMachines -gt $targetMachines) -and ($scalingFactor -eq 0)) {
            $action = [PSCustomObject]@{        
                Task = "Shutdown"
                Number = $($currentMachines - $targetMachines)
            }
            WriteLog -Path $logLocation -Message "The current number of powered on machines is $currentMachines and the target is $targetMachines - resulting action is to $($action.Task) $($action.Number) machines" -Level Info -Verbose
        } elseif ($currentMachines -lt $targetMachines) {
            $action = [PSCustomObject]@{        
                Task = "Startup"
                Number = $($targetMachines - $currentMachines)
            }
            WriteLog -Path $logLocation -Message "The current number of powered on machines is $currentMachines and the target is $targetMachines - resulting action is to $($action.Task) $($action.Number) machines" -Level Info -Verbose
        } elseif (($currentMachines -ge $targetMachines)) {
            $action = [PSCustomObject]@{        
                Task = "Scaling"
                Number = 0 + $scalingFactor
            }
            WriteLog -Path $logLocation -Message "The current number of powered on machines is $currentMachines and the target is $targetMachines - resulting action is to perform Scaling calculations" -Level Info -Verbose
            
        }        
        Return $action
}

#Function to get a list of all machines and current states from Broker
Function brokerMachineStates() {

    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, HelpMessage = "Specifies which Citrix Controller to use, you must have admin rights on the site")]    
        [ValidateNotNullOrEmpty()] 
        [string]$citrixController, 
 
        [Parameter(Mandatory=$true, HelpMessage = "Specifies a prefix to search for for the VDA machine names")]   
        [ValidateNotNullOrEmpty()]     
        [string]$machinePrefix
    )
    
    Return Get-BrokerMachine -AdminAddress $citrixController | Where-Object {($_.DNSName -match $machinePrefix)}
}

#Function to get a list of all sessions and current state from Broker
Function brokerUserSessions() {
    
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, HelpMessage = "Specifies which Citrix Controller to use, you must have admin rights on the site")]    
        [ValidateNotNullOrEmpty()] 
        [string]$citrixController, 
 
        [Parameter(Mandatory=$false, HelpMessage = "Specifies a prefix to search for for the VDA machine names")]        
        [string]$machinePrefix,
        
        [Parameter(Mandatory=$false, HelpMessage = "Specifies machine name to get sessions from")]      
        [string]$machineName
    )
    
    If (!$machineName) {
        Return Get-BrokerSession -AdminAddress $citrixController -MaxRecordCount 10000 | Where-Object {((($_.MachineName).Replace("\","\\")) -match $machinePrefix)}
    } else {
        Return Get-BrokerSession -AdminAddress $citrixController -MaxRecordCount 10000 | Where-Object {$_.MachineName -eq $machineName}
    }
}

#Function to Shutdown or TurnOn a machine - TurnOn, TurnOff, Shutdown, Reset, Restart, Suspend, Resume with or without delay
Function brokerAction() {
    
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, HelpMessage = "Specifies which Citrix Controller to use, you must have admin rights on the site")]    
        [ValidateNotNullOrEmpty()] 
        [string]$citrixController, 
 
        [Parameter(Mandatory=$true, HelpMessage = "The name of the specific VDA that you are powering down or up")]   
        [ValidateNotNullOrEmpty()]      
        [string]$machineName,  

        [Parameter(Mandatory=$true, HelpMessage = "Which machine action you are perfmoring - TurnOn, TurnOff, Shutdown, Reset, Restart, Suspend, Resume")]   
        [ValidateSet("TurnOn", "TurnOff", "Shutdown", "Reset", "Restart", "Suspend", "Resume")]      
        [string]$machineAction, 

        [Parameter(Mandatory=$false, HelpMessage = "[Optional] The delay in minutes of how long the controller should wait before executing the command (missing this parameter makes the execution immediate)")]   
        [int]$delay        
    )
    #Check if a delay has been sent or not and execute the relevant command based on this
    If (-not $null -eq $delay) {
        WriteLog -Path $logLocation -Message "Machine action for $machineName - $machineAction in $delay minutes" -Level Info
        If (!$testingOnly) {New-BrokerDelayedHostingPowerAction -AdminAddress $citrixcontroller -MachineName $machineName -Action $machineAction -Delay $(New-TimeSpan -Minutes $delay) }
    } else {
        WriteLog -Path $logLocation -Message "Machine action for $machineName - $machineAction immediately" -Level Info
        If (!$testingOnly) {New-BrokerHostingPowerAction -AdminAddress $citrixcontroller -MachineName $machineName -Action $machineAction}
    }
}

Function maintenance() {
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, HelpMessage = "Specifies which Citrix Controller to use, you must have admin rights on the site")]    
        [ValidateNotNullOrEmpty()] 
        [string]$citrixController, 
 
        [Parameter(Mandatory=$true, HelpMessage = "The machine object that will be placed into maintenance mode")]   
        [ValidateNotNullOrEmpty()]      
        [object]$machine,  

        [Parameter(Mandatory=$true, HelpMessage = "Specify whether maintenance mode should be On or Off")]   
        [ValidateSet("On", "Off")]      
        [string]$maintenanceMode     
    )
    #This set a machine or machines in maintenance mode
    If ($maintenanceMode -eq "On") {
        try {
            If (!$testingOnly) {Set-BrokerMachineMaintenanceMode -AdminAddress $citrixController -InputObject $machine -MaintenanceMode $true}
        } catch {
            WriteLog -Path $logLocation -Message "There was an error placing $($machine.DNSName) into maintenance mode" -Level Error
            SendEmail -smtpServer $smtpServer -toAddress $smtpToAddress -fromAddress $smtpFromAddress -subject $smtpSubject -Message "There was an error placing $($machine.DNSName) into maintenance mode" -attachment $logLocation -Level Error
        }
    } elseif ($maintenanceMode -eq "Off") {
        try {
            If (!$testingOnly) {Set-BrokerMachineMaintenanceMode -AdminAddress $citrixController -InputObject $machine -MaintenanceMode $false}
        } catch {
            WriteLog -Path $logLocation -Message "There was an error taking $($machine.DNSName) out of maintenance mode" -Level Error
            SendEmail -smtpServer $smtpServer -toAddress $smtpToAddress -fromAddress $smtpFromAddress -subject $smtpSubject -Message "There was an error taking $($machine.DNSName) out of maintenance mode" -attachment $logLocation -Level Error
        }
    }
}

#Function to receive a list of sessions in an object and logoff all the disconnected sessions
Function sessionLogOff() {
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, HelpMessage = "Specifies which Citrix Controller to use, you must have admin rights on the site")]    
        [ValidateNotNullOrEmpty()] 
        [string]$citrixController,

        [Parameter(Mandatory=$true, HelpMessage = "List of disconnected sessions to be logged off")]    
        [ValidateNotNullOrEmpty()] 
        [object]$sessions
    )
    #Do some logging off of disconnected sessions
    WriteLog -Path $logLocation -Message "Logging off all disconnected sessions in one hit" -Level Info
    foreach ($session in $sessions) {
        WriteLog -Path $logLocation -Message "Logging off $($session.UserName)" -Level Info
        If (!$testingOnly) {Stop-BrokerSession -InputObject $session}
    }
}

#Function that sends a message to active users that are running on machines and then log them off
Function sendMessage () {
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, HelpMessage = "Specifies which Citrix Controller to use, you must have admin rights on the site")]    
        [ValidateNotNullOrEmpty()] 
        [string]$citrixController,

        [Parameter(Mandatory=$true, HelpMessage = "Message interval one")]    
        [ValidateNotNullOrEmpty()] 
        [int]$firstMessageInterval,

        [Parameter(Mandatory=$true, HelpMessage = "Message one")]    
        [ValidateNotNullOrEmpty()] 
        [string]$firstMessage,

        [Parameter(Mandatory=$true, HelpMessage = "Message interval two")]    
        [ValidateNotNullOrEmpty()] 
        [int]$secondMessageInterval,

        [Parameter(Mandatory=$true, HelpMessage = "Message one")]    
        [ValidateNotNullOrEmpty()] 
        [string]$secondMessage,

        [Parameter(Mandatory=$true, HelpMessage = "List of sessions to message")]    
        [ValidateNotNullOrEmpty()] 
        [object]$sessions
    )
    
    #Sending the initial message for users to logoff
    WriteLog -Path $logLocation -Message "Sending message to users to log off - $($firstMessageInterval) minute warning" -Level Info
    If (!$testingOnly) {Send-BrokerSessionMessage -AdminAddress $citrixController -InputObject $sessions -MessageStyle "Information" -Title "Server Scheduled Shutdown" -Text "$firstMessage $(" - A reminder will be sent in $firstMessageInterval") mins"}
    #Wait for the interval time
    If (!$testingOnly) {start-sleep -seconds ($firstMessageInterval*60)}

    #Sending the initial message for users to logoff
    WriteLog -Path $logLocation -Message "Sending message to users to log off - $($secondMessageInterval) minute warning" -Level Info
    If (!$testingOnly) {Send-BrokerSessionMessage -InputObject $sessions -MessageStyle "Critical" -Title "Server Scheduled Shutdown " -Text "$secondMessage $(" - Shutdown will occur in $secondMessageInterval") mins"}
    #Wait for the interval time
    If (!$testingOnly) {start-sleep -seconds ($secondMessageInterval*60)}

    WriteLog -Path $logLocation -Message "Logging off all active user sessions after sending messages at $($firstMessageInterval) minutes and then $($secondMessageInterval) minutes" -Level Info
    If (!$testingOnly) { $sessions | Stop-BrokerSession }
}

Function performanceAnalysis () {
    [CmdletBinding()] 

    param(
    [Parameter(Mandatory=$true, HelpMessage = "Specifies which Citrix Controller to use, you must have admin rights on the site")]    
    [ValidateNotNullOrEmpty()] 
    [string]$citrixController, 

    [Parameter(Mandatory=$true, HelpMessage = "Specifies a prefix to search for for the VDA machine names")]   
    [ValidateNotNullOrEmpty()]     
    [string]$machinePrefix,

    [Parameter(Mandatory=$true, HelpMessage = "Interval between performance samples")]   
    [ValidateNotNullOrEmpty()]     
    [int]$performanceInterval,

    [Parameter(Mandatory=$true, HelpMessage = "Number of performance samples to gather")]   
    [ValidateNotNullOrEmpty()]     
    [int]$performanceSamples,

    [Parameter(Mandatory=$true, HelpMessage = "Export location for individual machine performance details")]   
    [ValidateNotNullOrEmpty()]     
    [string]$exportLocation,

    [Parameter(Mandatory=$true, HelpMessage = "Export location for overall average machine performance details")]   
    [ValidateNotNullOrEmpty()]     
    [string]$overallExportLocation
)

#Check variables for any known issue
If (-not ([String]::IsNullOrEmpty($wmiServiceAccount))) {
    #WMI account provided check for upn or domain\username
    if ((($wmiServiceAccount) -match "\\") -or (($wmiServiceAccount) -match "@")) {
        "WMI Account seems to be valid"
        WriteLog -Path $logLocation -Message "The wmi account provided is in the correct format, continuing" -Level Info -Verbose
    } else {
        "WMI Account invalid"
        WriteLog -Path $logLocation -Message "The wmi account provided is not valid for use as it is in an incorrect format, script execution will now stop" -Level Error -Verbose
        Exit
    }
}

#Get a list of live Citrix Servers from the Broker that are currently powered on
$computers = Get-BrokerMachine -AdminAddress $citrixController | Where-Object {($_.DNSName -match $machinePrefix) -And ($_.RegistrationState -eq "Registered") -And ($_.PowerState -eq "On")} | Select-Object -ExpandProperty DNSName

#Zero out results so we dont see last set of results on the first run of performance information gathering
$results = ""

#Loop through each machine obtained from the broker and gathers its information for scaling puroposes
ForEach ($computer in $computers) {
    #Check if we have a wmi account to use, if we do check access for each machine, otherwise run in current user context    
    If  (-not ([String]::IsNullOrEmpty($wmiServiceAccount))) {  
        #Only gather performance metrics for machines that we have WMI access to 
        WriteLog -Path $logLocation -Message "Starting performance measurement job for $computer using specified credentials" -Level Info -Verbose
        If  ($(Get-WmiObject -query "SELECT * FROM Win32_OperatingSystem" -ComputerName $computer -Credential $(WMIDetailsImport))) {
            Start-Job -Name $computer -Credential $(WMIDetailsImport) -ScriptBlock {
                param (
                $computer,
                $ctxController,
                $interval,
                $samples
                )

                #Load the Citrix snap-ins
                Add-PSSnapin Citrix*    
                
                #Create a custom object to store the results
                $results = [PSCustomObject]@{
                Machine = $computer
                CPU = [int](Get-Counter '\Processor(_Total)\% Processor Time' -ComputerName $computer -SampleInterval $interval -MaxSamples $samples | Select-Object -expand CounterSamples | Measure-Object -average cookedvalue | Select-Object -ExpandProperty Average)
                Memory = [int](Get-Counter -Counter '\Memory\% Committed Bytes In Use' -ComputerName $computer -SampleInterval $interval -MaxSamples $samples | Select-Object -expand CounterSamples | Measure-Object -average cookedvalue | Select-Object -ExpandProperty Average)
                LoadIndex = (Get-BrokerMachine -AdminAddress $ctxController | Where-Object {$_.DNSName -eq $computer}) | Select-Object -expand LoadIndex
                Sessions = (Get-BrokerMachine -AdminAddress $ctxController | Where-Object {$_.DNSName -eq $computer}) | Select-Object -expand SessionCount
                } 
                
                #Write out the results for this computer only if the CPU and Memory calculations worked
                if ($results.CPU -eq 0 -or $results.memory -eq 0) {
                    $results
                } else {
                    $results
                }
            
            } -ArgumentList $computer, $citrixController, $performanceInterval, $performanceSamples
        }
    } elseif ($(Get-WmiObject -query "SELECT * FROM Win32_OperatingSystem" -ComputerName $computer)) { 
        WriteLog -Path $logLocation -Message "Starting performance measurement job for $computer using script run credentials" -Level Info -Verbose
        Start-Job -Name $computer -ScriptBlock {
        param (
        $computer,
        $ctxController,
        $interval,
        $samples
        )

        #Load the Citrix snap-ins
        Add-PSSnapin Citrix*    
        
        #Create a custom object to store the results
        $results = [PSCustomObject]@{
        Machine = $computer
        CPU = [int](Get-Counter '\Processor(_Total)\% Processor Time' -ComputerName $computer -SampleInterval $interval -MaxSamples $samples | Select-Object -expand CounterSamples | Measure-Object -average cookedvalue | Select-Object -ExpandProperty Average)
        Memory = [int](Get-Counter -Counter '\Memory\% Committed Bytes In Use' -ComputerName $computer -SampleInterval $interval -MaxSamples $samples | Select-Object -expand CounterSamples | Measure-Object -average cookedvalue | Select-Object -ExpandProperty Average)
        LoadIndex = (Get-BrokerMachine -AdminAddress $ctxController | Where-Object {$_.DNSName -eq $computer}) | Select-Object -expand LoadIndex
        Sessions = (Get-BrokerMachine -AdminAddress $ctxController | Where-Object {$_.DNSName -eq $computer}) | Select-Object -expand SessionCount
        } 
        
        #Write out the results for this computer only if the CPU and Memory calculations worked
        if ($results.CPU -eq 0 -or $results.memory -eq 0) {
            $results
        } else {
            $results
        }
    
        } -ArgumentList $computer, $citrixController, $performanceInterval, $performanceSamples
    } else {
        WriteLog -Path $logLocation -Message "There has been an error connecting to any machines to gather performance metrics" -Level Error -Verbose
    }
}
    
#Loop through all running jobs every 5 seconds to see if complete, if they are; receive the jobs and store the metrics
$Metrics = Do {
    $runningJobs = Get-Job | Where-Object {$_.State -ne "Completed"}
    $completedJobs = Get-Job |  Where-Object {$_.State -eq "Completed"}
    ForEach ($job in $completedJobs) {
        Receive-Job $job | Select-Object * -ExcludeProperty RunspaceId 
        Remove-Job $job
    }

    Start-Sleep -Seconds 5
} Until ($runningJobs.Count -eq 0)

#Export metrics as XML to be read into another scripts as an object
$Metrics | Export-Clixml -Path $exportLocation
$Metrics

#Custom object for overall averages
$overallAverage = [PSCustomObject]@{
    overallCPU = $Metrics | Measure-Object -Property CPU -Average -Minimum -Maximum
    overallMemory = $Metrics | Measure-Object -Property Memory -Average -Minimum -Maximum -Sum  
    overallIndex = $Metrics | Measure-Object -Property LoadIndex -Average -Minimum -Maximum
    overallSession = $Metrics | Measure-Object -Property Sessions -Average -Minimum -Maximum
}

$overallAverage | Export-Clixml -Path $overallExportLocation
WriteLog -Path $logLocation -Message "$($overallAverage.overallCPU.Average) - Overall CPU Average" -Level Info
WriteLog -Path $logLocation -Message "$($overallAverage.overallMemory.Average) - Overall Memory Average" -Level Info
WriteLog -Path $logLocation -Message "$($overallAverage.overallIndex.Average) - Overall Session Index Average" -Level Info
WriteLog -Path $logLocation -Message "$($overallAverage.overallSession.Average) - Overall Session Count Average" -Level Info

}

#Log for script start
WriteLog -Path $logLocation -Message "-" -Level Info -NoClobber
WriteLog -Path $logLocation -Message "#######PowerScale script starting - Test mode value is $testingOnly#######" -Level Info

#########################Reset All Variables and Get All Metrics###################################
#Reset variables (to avoid different data from multiple script runs)
$allMachines = ""
$allUserSessions = ""

#Run the performance monitoring script to create XML files
try {
    performanceAnalysis -citrixController $citrixController -machinePrefix $machinePrefix -performanceSamples $performanceSamples -performanceInterval $performanceInterval -exportLocation $performanceIndividual -overallExportLocation $performanceOverall
} catch {
    WriteLog -Path $logLocation -Message "There was an error gathering performance metrics from the VDA machines, Please ensure you have the Powershell SDK installed and the user account you are using has rights to query the Citrix farm and WMI. " -Level Error
    #Log out the latest error - does not mean performance measurement was unsuccessful on all machines
    WriteLog -Path $logLocation -Message "$Error[$($Error.Count)]" -Level Error
    Exit
}
try {
    $allMachines = brokerMachineStates -citrixController $citrixController -machinePrefix $machinePrefix | Where-Object {$_.Tags -notcontains $exclusionTag}
    $allUserSessions = brokerUserSessions -citrixController $citrixController -machinePrefix $machinePrefix | Where-Object {$_.Tags -notcontains $exclusionTag}
} catch {
    WriteLog -Path $logLocation -Message "There was an error gathering information from the Citrix Controller - Please ensure you have the Powershell SDK installed and the user account you are using has rights to query the Citrix farm." -Level Error
    Exit
}
try {
    $individualPerformance = Import-cliXml -Path "$ScriptPath\Individual.xml"
    $overallPerformance = Import-cliXml -Path "$ScriptPath\Overall.xml"
} catch {
    WriteLog -Path $logLocation -Message "There was an error generating and then importing the performance data, please ensure the performance script can run standalone using parameters." -Level Error
    Exit
}

#Filter down the main objects into sub variables for scripting ease
$disconnectedSessions = $allUserSessions | Select-Object * | Where-Object {$_.SessionState -eq "Disconnected"}
$activeSessions = $allUserSessions | Select-Object * | Where-Object {$_.SessionState -eq "Active"}
$machinesOnAndMaintenance = $allMachines | Select-Object * | Where-Object {($_.RegistrationState -eq "Registered") -and ($_.PowerState -eq "On") -and ($_.InMaintenanceMode -eq $true)}
$machinesOnAndNotMaintenance = $allMachines | Select-Object * | Where-Object {($_.RegistrationState -eq "Registered") -and ($_.PowerState -eq "On") -and ($_.InMaintenanceMode -eq $false)}
$machinesPoweredOff = $allMachines | Select-Object * | Where-Object {($_.PowerState -eq "Off")}
$machinesScaled = $allMachines | Select-Object * | Where-Object {$_.Tags -contains "Scaled-On"}

#Create the broker tag for scaling if it doesn't exist
If (-not (Get-BrokerTag -Name "Scaled-On" -AdminAddress $citrixController )) {
    New-BrokerTag "Scaled-On"
}
#########################Reset All Variables and Get All Metrics###################################

#Main Logic
#Kick off Circular logging maintenance
CircularLogging -NumberOfDays $LogNumberOfDays -LogLocation $logLocation

#Is it a weekday?
If ($(IsWeekDay -date $($timesObj.timeNow))) {
    #If it is a weekday, then check if we are within working hours or not
    If ($(TimeCheck($timeObj)) -eq "OutOfHours") {
        #Outside working hours, perform analysis on powered on machines vs target machines
        WriteLog -Path $logLocation -Message "It is currently outside working hours - performing machine analysis" -Level Info
        $action = levelCheck -targetMachines $outOfHoursMachines -currentMachines $machinesOnAndNotMaintenance.RegistrationState.Count        
        If ($action.Task -eq "Scaling") {
            WriteLog -Path $logLocation -Message "The current running machines matches the target machines, we are outside of working hours we will only scale up new machines based on performance" -Level Info
            if (($($machinesPoweredOff.MachineName.Count) -gt 0) -or ($null -ne $($machinesPoweredOff.MachineName.Count))) {
                WriteLog -Path $logLocation -Message "Scaling has have been activated, the current scaling metric is $machineScaling and there are $($machinesPoweredOff.machineName.count) machines currently powered off and available." -Level Info
                #Select a machine to be powered on
                $machineToPowerOn = $machinesPoweredOff | Select-Object -First 1
                If ($null -eq $machineToPowerOn) {
                    WriteLog -Path $logLocation -Message "There are no machines available to power on" -Level Info
                } else {
                    WriteLog -Path $logLocation -Message "Machine selected to be powered on is $($machineToPowerOn.DNSName)" -Level Info
                    #Perform logic on scaling
                    if (($overallPerformance.overallCPU.Average -gt $farmCPUThreshhold) -and ($machineScaling -eq "CPU")) {
                        WriteLog -Path $logLocation -Message "Issuing a power command to $($machineToPowerOn.DNSName) to power up, the CPU threshhold has been triggered." -Level Info
                        If (!$testingOnly) { brokerAction -citrixController $citrixController -machineName $machineToPowerOn.DNSName -machineAction TurnOn }
                        If (!$testingOnly) { Add-BrokerTag -Name "Scaled-On" -Machine $machineToPowerOn.MachineName -AdminAddress $citrixController }
                    }
                    if (($overallPerformance.overallMemory.Average -gt $farmMemoryThreshhold) -and ($machineScaling -eq "Memory")) {
                        WriteLog -Path $logLocation -Message "Issuing a power command to $($machineToPowerOn.DNSName) to power up, the Memory threshhold has been triggered." -Level Info
                        If (!$testingOnly) { brokerAction -citrixController $citrixController -machineName $machineToPowerOn.DNSName -machineAction TurnOn }
                        If (!$testingOnly) { Add-BrokerTag -Name "Scaled-On" -Machine $machineToPowerOn.MachineName -AdminAddress $citrixController }
                    }
                    if (($overallPerformance.overallIndex.Average -gt $farmIndexThreshhold) -and ($machineScaling -eq "Index")) {
                        WriteLog -Path $logLocation -Message "Issuing a power command to $($machineToPowerOn.DNSName) to power up, the Index threshhold has been triggered." -Level Info
                        If (!$testingOnly) { brokerAction -citrixController $citrixController -machineName $machineToPowerOn.DNSName -machineAction TurnOn }
                        If (!$testingOnly) { Add-BrokerTag -Name "Scaled-On" -Machine $machineToPowerOn.MachineName -AdminAddress $citrixController }
                    }
                    if (($overallPerformance.overallSession.Average -gt $farmSessionThreshhold) -and ($machineScaling -eq "Session")) {
                        WriteLog -Path $logLocation -Message "Issuing a power command to $($machineToPowerOn.DNSName) to power up, the Session threshhold has been triggered." -Level Info
                        If (!$testingOnly) { brokerAction -citrixController $citrixController -machineName $machineToPowerOn.DNSName -machineAction TurnOn }
                        If (!$testingOnly) { Add-BrokerTag -Name "Scaled-On" -Machine $machineToPowerOn.MachineName -AdminAddress $citrixController }
                    }                    
                    WriteLog -Path $logLocation -Message "PowerScale did not find any machines that are powered off to be turned on, please add more machines into your catalog(s)" -Level Warn
                }
            }       
        } ElseIf ($action.Task -eq "Shutdown") {
            #Some machines to shutdown based on numbers returned
            #Check if we have any disconnected sessions and log them off
            If ($(($disconnectedSessions | Measure-Object).Count) -gt 0) {
                WriteLog -Path $logLocation -Message "Logging off all disconnected sessions" -Level Info
                sessionLogOff -citrixController $citrixController -sessions $disconnectedSessions
            }
            #Check if we have any active sessions and log send a message before logging off if we are forcing user logoffs
            If ($forceUserLogoff) {
                WriteLog -Path $logLocation -Message "User logoff mode is set to force, logging all users off of machines that are required to be shutdown" -Level Info
                sendMessage -citrixController $citrixController -firstMessageInterval $userLogoffFirstInterval -firstMessage $userLogoffFirstMessage -secondMessageInterval $userLogoffSecondInterval -secondMessage $userLogoffSecondMessage -sessions $activeSessions
                $machinesToPowerOff = $machinesOnAndNotMaintenance | Select-Object -First $($action.number)
                #For everymachine powered on up to the correct number, switch the poweroff
                foreach ($machine in $machinesToPowerOff) {
                    If (!$testingOnly) { brokerAction -citrixController $citrixController -machineName $($machine.MachineName) -machineAction TurnOff }
                }
            }
            #If we are not forcing users to logoff then we can loop through machines checking for non-active sessions
            If (!$forceUserLogoff) {
                WriteLog -Path $logLocation -Message "User logoff mode is not set to force, waiting for sessions to gracefully disconnect before powering machines down" -Level Info
                $machinesToPowerOff = $machinesOnAndNotMaintenance | Select-Object -First $($action.number)                
                foreach ($machine in $machinesToPowerOff) {
                    #Check for active sessions on each machine before shutting down
                    $sessions = $(brokerUserSessions -citrixController $citrixController -machineName $($machine.MachineName) | Where-Object {$_.SessionState -eq "Active"} | Select-Object *)
                    If ($null -eq $sessions) {
                        WriteLog -Path $logLocation -Message "No active session found on $($machine.DNSName), performing shutdown" -Level Info
                        #Shutdown the machines as there are no active sessions (this will include disconnected sessions)
                        If (!$testingOnly) { brokerAction -citrixController $citrixController -machineName $($machine.MachineName) -machineAction TurnOff }
                    }
                }
            }       
        }
    } ElseIf ($(TimeCheck($timeObj)) -eq "InsideOfHours") {
        #Inside working hours, decide on what to do with current machines, let level check know that scaling should be considered       
        $action = levelCheck -targetMachines $InHoursMachines -currentMachines $machinesOnAndNotMaintenance.RegistrationState.Count
        WriteLog -Path $logLocation -Message "It is currently inside working hours - performing machine analysis" -Level Info
        If ($action.Task -eq "Scaling") {            
            WriteLog -Path $logLocation -Message "The current running machines matches the target machines number, performing scaling analysis" -Level Info 
            if (($($machinesPoweredOff.MachineName.Count) -gt 0) -or ($null -ne $($machinesPoweredOff.MachineName.Count))) {
                WriteLog -Path $logLocation -Message "Scaling has have been activated, the current scaling metric is $machineScaling and there are $($machinesPoweredOff.machineName.count) machines currently powered off and available." -Level Info
                #Select a machine to be powered on
                $machineToPowerOn = $machinesPoweredOff | Select-Object -First 1
                If ($null -eq $machineToPowerOn) {
                    WriteLog -Path $logLocation -Message "There are no machines available to power on" -Level Info
                } else {
                    WriteLog -Path $logLocation -Message "Machine selected to be powered on is $($machineToPowerOn.DNSName)" -Level Info

                    #Perform logic on scaling
                    if (($overallPerformance.overallCPU.Average -gt $farmCPUThreshhold) -and ($machineScaling -eq "CPU")) {
                        WriteLog -Path $logLocation -Message "Issuing a power command to $($machineToPowerOn.DNSName) to power up, the CPU threshhold has been triggered." -Level Info
                        If (!$testingOnly) { brokerAction -citrixController $citrixController -machineName $machineToPowerOn.DNSName -machineAction TurnOn }
                        If (!$testingOnly) { Add-BrokerTag -Name "Scaled-On" -Machine $machineToPowerOn.MachineName -AdminAddress $citrixController }
                    }
                    if (($overallPerformance.overallMemory.Average -gt $farmMemoryThreshhold) -and ($machineScaling -eq "Memory")) {
                        WriteLog -Path $logLocation -Message "Issuing a power command to $($machineToPowerOn.DNSName) to power up, the Memory threshhold has been triggered." -Level Info
                        If (!$testingOnly) { brokerAction -citrixController $citrixController -machineName $machineToPowerOn.DNSName -machineAction TurnOn }
                        If (!$testingOnly) { Add-BrokerTag -Name "Scaled-On" -Machine $machineToPowerOn.MachineName -AdminAddress $citrixController }
                    }
                    if (($overallPerformance.overallIndex.Average -gt $farmIndexThreshhold) -and ($machineScaling -eq "Index")) {
                        WriteLog -Path $logLocation -Message "Issuing a power command to $($machineToPowerOn.DNSName) to power up, the Index threshhold has been triggered." -Level Info
                        If (!$testingOnly) { brokerAction -citrixController $citrixController -machineName $machineToPowerOn.DNSName -machineAction TurnOn }
                        If (!$testingOnly) { Add-BrokerTag -Name "Scaled-On" -Machine $machineToPowerOn.MachineName -AdminAddress $citrixController }
                    }
                    if (($overallPerformance.overallSession.Average -gt $farmSessionThreshhold) -and ($machineScaling -eq "Session")) {
                        WriteLog -Path $logLocation -Message "Issuing a power command to $($machineToPowerOn.DNSName) to power up, the Session threshhold has been triggered." -Level Info
                        If (!$testingOnly) { brokerAction -citrixController $citrixController -machineName $machineToPowerOn.DNSName -machineAction TurnOn }
                        If (!$testingOnly) { Add-BrokerTag -Name "Scaled-On" -Machine $machineToPowerOn.MachineName -AdminAddress $citrixController }
                    }                    
                    WriteLog -Path $logLocation -Message "PowerScale did not find any machines that are powered off to be turned on, please add more machines into your catalog(s)" -Level Warn
                }
            }                              
        } ElseIf ($action.Task -eq "Startup") {
            #Some machines to startup based on numbers returned
            WriteLog -Path $logLocation -Message "It is currently inside working hours, machines are required to be started" -Level Info
            WriteLog -Path $logLocation -Message "There are $($machinesOnAndNotMaintenance.RegistrationState.Count) machine(s) currently switched on and registered, There are $($machinesOnAndMaintenance.RegistrationState.Count) machine(s) in maintenance mode and there are $($machinesPoweredOff.MachineName.Count) machine(s) powered off" -Level Info
            WriteLog -Path $logLocation -Message "In total there are $($($machinesOnAndMaintenance.RegistrationState.Count) + $($machinesPoweredOff.MachineName.Count)) machine(s) able to be placed into service." -Level Info
            
            #If the amount of machines that are in maintenance mode are greater or equal to the number of machines needed to be started
            #Check if the number of machines available will service the requirement for machines needed
            If($action.number -le $($($machinesOnAndMaintenance.RegistrationState.Count) + $($machinesPoweredOff.MachineName.Count))) {
                WriteLog -Path $logLocation -Message "The number of machines available is $($($machinesOnAndMaintenance.RegistrationState.Count) + $($machinesPoweredOff.MachineName.Count)) and the number required is $($action.number)" -Level Info
                if ($action.number -le $($machinesOnAndMaintenance.RegistrationState.Count)) {
                    #The number of machines in maintenance mode will service the request
                    WriteLog -Path $logLocation -Message "The number of machines in maintenance mode is $($machinesOnAndMaintenance.RegistrationState.Count) and the number of machine(s) needed is $($action.number)" -Level Info
                    WriteLog -Path $logLocation -Message "There are sufficient machines in maintenance mode to service the request" -Level Info
                    foreach ($machine in $($machinesOnAndMaintenance | Select-Object -First $($action.number))) {
                        #Take machines out of maintenance mode
                        WriteLog -Path $logLocation -Message "Taking $($machine.DNSName) out of maintenance mode" -Level Info 
                        If (!$testingOnly) {maintenance -citrixController $citrixController -machine $machine -maintenanceMode Off}                        
                    }
                } else {
                    #The number of machines in maintenance mode will not service the request, we need to power on machines too
                    WriteLog -Path $logLocation -Message "The number of machines in maintenance mode is $($machinesOnAndMaintenance.RegistrationState.Count) and the number of machine(s) needed is $($action.number)" -Level Info
                    WriteLog -Path $logLocation -Message "There are not sufficient machines in maintenance mode to service the request, we will power some on too" -Level Info
                    foreach ($machine in $($machinesOnAndMaintenance)) {
                        #Take machines out of maintenance mode
                        WriteLog -Path $logLocation -Message "Taking $($machine.DNSName) out of maintenance mode" -Level Info 
                        If (!$testingOnly) {maintenance -citrixController $citrixController -machine $machine -maintenanceMode Off}                    
                    }
                    #Power on the machines we need by subtracting the machines already in maintenance mode from what is needed
                    foreach ($machine in $($machinesPoweredOff | Select-Object -First $($($action.Number)-$($machinesOnAndMaintenance.RegistrationState.Count)))) {
                        #Power machines on
                        WriteLog -Path $logLocation -Message "Turning On $($machine.DNSName)" -Level Info 
                        If (!$testingOnly) {brokerAction -citrixController $citrixController -machineName $machine.MachineName -machineAction TurnOn}
                    }
                }

            } else {
                WriteLog -Path $logLocation -Message "The number of machines available is $($($machinesOnAndMaintenance.RegistrationState.Count) + $($machinesPoweredOff.MachineName.Count)) and the number required is $($action.number)" -Level Info
                WriteLog -Path $logLocation -Message "There are not enough machines available to service the request, working on the machines we can" -Level Warn

                #Take machines out of maintenance mode that are powered on and registered
                foreach ($machine in $machinesOnAndMaintenance) {
                    #Take machines out of maintenance mode
                    WriteLog -Path $logLocation -Message "Taking $($machine.DNSName) out of maintenance mode" -Level Info 
                    If (!$testingOnly) {maintenance -citrixController $citrixController -machine $machine -maintenanceMode Off}                    
                }

                foreach ($machine in $machinesPoweredOff) {
                    #Power machines on
                    WriteLog -Path $logLocation -Message "Turning On $($machine.DNSName)" -Level Info 
                    If (!$testingOnly) {brokerAction -citrixController $citrixController -machineName $machine.MachineName -machineAction TurnOn}                    
                }
            }
        } ElseIf ($action.Task -eq "Shutdown") {
            #We need to powerdown during production hours         
            #We are not forcing users to logoff so we can loop through machines checking for 0 sessions
            WriteLog -Path $logLocation -Message "We are in production hours, waiting for sessions to gracefully disconnect before powering machines down" -Level Info
            foreach ($machine in $machinesOnAndNotMaintenance) {
                #Check for any sessions on each machine before shutting down
                $sessions = $(brokerUserSessions -citrixController $citrixController -machineName $($machine.MachineName) | Select-Object *)
                If ($null -eq $sessions) {
                    WriteLog -Path $logLocation -Message "No active session found on $($machine.DNSName), performing shutdown" -Level Info
                    #Shutdown the machines as there are no sessions active or disconnected
                    If (!$testingOnly) { brokerAction -citrixController $citrixController -machineName $($machine.MachineName) -machineAction TurnOff }
                    If (!$null -eq $(Get-BrokerTag -Name "Scaled-On" -MachineUid $machine.Uid -AdminAddress $citrixController)) {
                        If (!$testingOnly) { Remove-BrokerTag -Name "Scaled-On" -Machine $machine.MachineName -AdminAddress $citrixController }
                    }
                }
            }              
        }
    } ElseIf ($(TimeCheck($timeObj)) -eq "Error") {
        #There has been an error just comparing the date
        WriteLog -Path $logLocation -Message "There has been an error calculating the date or time, review the logs" -Level Error
        SendEmail -smtpServer $smtpServer -toAddress $smtpToAddress -fromAddress $smtpFromAddress -subject $smtpSubject -Message "There has been an error calculating the date or time, please review the attached logs" -attachment $logLocation -Level Error
    }
} Else { #Its the weekend
    WriteLog -Path $logLocation -Message "It is currently a weekend - performing machine analysis" -Level Info
    $action = levelCheck -targetMachines $outOfHoursMachines -currentMachines $machinesOnAndNotMaintenance.count
    
    If ($action.Task -eq "Scaling") {
        WriteLog -Path $logLocation -Message "The current running machines matches the target machines number, performing scaling analysis" -Level Info 
        if (($($machinesPoweredOff.MachineName.Count) -gt 0) -or ($null -ne $($machinesPoweredOff.MachineName.Count))) {
            WriteLog -Path $logLocation -Message "Scaling has have been activated, the current scaling metric is $machineScaling and there are $($machinesPoweredOff.machineName.count) machines currently powered off and available." -Level Info
            #Select a machine to be powered on
            $machineToPowerOn = $machinesPoweredOff | Select-Object -First 1
            If ($null -eq $machineToPowerOn) {
                WriteLog -Path $logLocation -Message "There are no machines available to power on" -Level Info
            } else {
                WriteLog -Path $logLocation -Message "Machine selected to be powered on is $($machineToPowerOn.DNSName)" -Level Info

                #Perform logic on scaling
                if (($overallPerformance.overallCPU.Average -gt $farmCPUThreshhold) -and ($machineScaling -eq "CPU")) {
                    WriteLog -Path $logLocation -Message "Issuing a power command to $($machineToPowerOn.DNSName) to power up, the CPU threshhold has been triggered." -Level Info
                    If (!$testingOnly) { brokerAction -citrixController $citrixController -machineName $machineToPowerOn.DNSName -machineAction TurnOn }
                    If (!$testingOnly) { Add-BrokerTag -Name "Scaled-On" -Machine $machineToPowerOn.MachineName -AdminAddress $citrixController }
                }
                if (($overallPerformance.overallMemory.Average -gt $farmMemoryThreshhold) -and ($machineScaling -eq "Memory")) {
                    WriteLog -Path $logLocation -Message "Issuing a power command to $($machineToPowerOn.DNSName) to power up, the Memory threshhold has been triggered." -Level Info
                    If (!$testingOnly) { brokerAction -citrixController $citrixController -machineName $machineToPowerOn.DNSName -machineAction TurnOn }
                    If (!$testingOnly) { Add-BrokerTag -Name "Scaled-On" -Machine $machineToPowerOn.MachineName -AdminAddress $citrixController }
                }
                if (($overallPerformance.overallIndex.Average -gt $farmIndexThreshhold) -and ($machineScaling -eq "Index")) {
                    WriteLog -Path $logLocation -Message "Issuing a power command to $($machineToPowerOn.DNSName) to power up, the Index threshhold has been triggered." -Level Info
                    If (!$testingOnly) { brokerAction -citrixController $citrixController -machineName $machineToPowerOn.DNSName -machineAction TurnOn }
                    If (!$testingOnly) { Add-BrokerTag -Name "Scaled-On" -Machine $machineToPowerOn.MachineName -AdminAddress $citrixController }
                }
                if (($overallPerformance.overallSession.Average -gt $farmSessionThreshhold) -and ($machineScaling -eq "Session")) {
                    WriteLog -Path $logLocation -Message "Issuing a power command to $($machineToPowerOn.DNSName) to power up, the Session threshhold has been triggered." -Level Info
                    If (!$testingOnly) { brokerAction -citrixController $citrixController -machineName $machineToPowerOn.DNSName -machineAction TurnOn }
                    If (!$testingOnly) { Add-BrokerTag -Name "Scaled-On" -Machine $machineToPowerOn.MachineName -AdminAddress $citrixController }
                }                    
                WriteLog -Path $logLocation -Message "PowerScale did not find any machines that are powered off to be turned on, please add more machines into your catalog(s)" -Level Warn
            }
        }    
    } ElseIf ($action.Task -eq "Shutdown") {
        #Some machines to shutdown based on numbers returned
        #Check if we have any disconnected sessions and log them off
        If ($(($disconnectedSessions | Measure-Object).Count) -gt 0) {
            WriteLog -Path $logLocation -Message "Logging off all disconnected sessions" -Level Info
            sessionLogOff -citrixController $citrixController -sessions $disconnectedSessions
        }
        #Check if we have any active sessions and log send a message before logging off if we are forcing user logoffs
        If ($forceUserLogoff) {
            WriteLog -Path $logLocation -Message "User logoff mode is set to force, logging all users off of machines that are required to be shutdown" -Level Info
            sendMessage -citrixController $citrixController -firstMessageInterval $userLogoffFirstInterval -firstMessage $userLogoffFirstMessage -secondMessageInterval $userLogoffSecondInterval -secondMessage $userLogoffSecondMessage -sessions $activeSessions
            $machinesToPowerOff = $machinesOnAndNotMaintenance | Select-Object -First $($action.number)
            #For everymachine powered on up to the correct number, switch the poweroff
            foreach ($machine in $machinesToPowerOff) {
                If (!$testingOnly) { brokerAction -citrixController $citrixController -machineName $($machine.MachineName) -machineAction TurnOff }
            }
        }
        #If we are not forcing users to logoff then we can loop through machines checking for non-active sessions
        If (!$forceUserLogoff) {
            WriteLog -Path $logLocation -Message "User logoff mode is not set to force, waiting for sessions to gracefully disconnect before powering machines down" -Level Info
            $machinesToPowerOff = $machinesOnAndNotMaintenance | Select-Object -First $($action.number)                
            foreach ($machine in $machinesToPowerOff) {
                #Check for active sessions on each machine before shutting down
                $sessions = $(brokerUserSessions -citrixController $citrixController -machineName $($machine.MachineName) | Where-Object {$_.SessionState -eq "Active"} | Select-Object *)
                If ($null -eq $sessions) {
                    WriteLog -Path $logLocation -Message "No active session found on $($machine.DNSName), performing shutdown" -Level Info
                    #Shutdown the machines as there are no active sessions (this will include disconnected sessions)
                    If (!$testingOnly) { brokerAction -citrixController $citrixController -machineName $($machine.MachineName) -machineAction TurnOff }
                }
            }
        } 
    }
}
#Log for script finish
WriteLog -Path $logLocation -Message "#######PowerScale script finishing#######" -Level Info -NoClobber
WriteLog -Path $logLocation -Message "-" -Level Info -NoClobber




