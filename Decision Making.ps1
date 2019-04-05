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

#Pull in all configuration information
$configInfo = configurationImport

#Set all variables for the script
$performanceScriptLocation = $configInfo.performanceScriptLocation 
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
$logLocation = $configInfo.logLocation 
$smtpServer = $configInfo.smtpServer
$smtpToAddress = $configInfo.smtpToAddress
$smtpFromAddress = $configInfo.smtpFromAddress
$smtpSubject = $configInfo.smtpSubject
$testingOnly = $configInfo.testingOnly
$exclusionTag = $configInfo.exclusionTag

#Get current date in correct format
$dateNow = $(Get-Date -Format dd/MM/yy).ToString()

#Setup a time object for comparison
$timesObj = [PSCustomObject]@{
    startTime = [datetime]::ParseExact($("$($dateNow) $($businessStartTime)"), "dd/MM/yy HH:mm", $null)
    endTime = [datetime]::ParseExact($("$($dateNow) $($businessCloseTime)"), "dd/MM/yy HH:mm", $null)
    timeNow = $(Get-Date)
    #Set a specific time for testing
    #timeNow = $([datetime]::ParseExact("03/04/19 11:00", "dd/MM/yy HH:mm", $null))
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
        [string]$Path='C:\Logs\PowerShellLog.log', 
         
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
        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path. 
        If (!(Test-Path $Path)) { 
            Write-Verbose "Creating $Path." 
            $NewLogFile = New-Item $Path -Force -ItemType File 
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
    $null -ne ($weekdays | ? { $($date.DayOfWeek) -match $_ })  # returns $true
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
        #Check the supplied machines levels against what is required
        #Return an object with the action required (Startup, Shutdown, Nothing and the amount of machines necessary to do it to)
        If ($currentMachines -gt $targetMachines) {
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
        } elseif ($currentMachines -eq $targetMachines) {
            $action = [PSCustomObject]@{        
                Task = "Scaling"
                Number = 0
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
    
    Return Get-BrokerMachine -AdminAddress $citrixController | Where {($_.DNSName -match $machinePrefix)}
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
        Return Get-BrokerSession -AdminAddress $citrixController -MaxRecordCount 10000 | Where {((($_.MachineName).Replace("\","\\")) -match $machinePrefix)}
    } else {
        Return Get-BrokerSession -AdminAddress $citrixController -MaxRecordCount 10000 | Where {$_.MachineName -eq $machineName}
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
    If ($delay) {
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

        [Parameter(Mandatory=$true, HelpMessage = "Message interval two")]    
        [ValidateNotNullOrEmpty()] 
        [int]$secondMessageInterval,

        [Parameter(Mandatory=$true, HelpMessage = "List of sessions to message")]    
        [ValidateNotNullOrEmpty()] 
        [object]$sessions
    )
    
    #Sending the initial message for users to logoff
    WriteLog -Path $logLocation -Message "Sending message to users to log off - $($firstMessageInterval) minute warning" -Level Info
    If (!$testingOnly) {Send-BrokerSessionMessage -AdminAddress $citrixController -InputObject $sessions -MessageStyle "Information" -Title "ICT Server Scheduled Shutdown" -Text "Please save your work and log-off. This machine will be shutdown in $($firstMessageInterval) mins"}
    #Wait for the interval time
    If (!$testingOnly) {start-sleep -seconds ($firstMessageInterval*60)}

    #Sending the initial message for users to logoff
    WriteLog -Path $logLocation -Message "Sending message to users to log off - $($secondMessageInterval) minute warning" -Level Info
    If (!$testingOnly) {Send-BrokerSessionMessage -InputObject $sessions -MessageStyle "Critical" -Title "ICT Server Scheduled Shutdown " -Text "Please save your work and log-off. This machine will be shutdown in $($secondMessageInterval) min"}
    #Wait for the interval time
    If (!$testingOnly) {start-sleep -seconds ($secondMessageInterval*60)}

    WriteLog -Path $logLocation -Message "Logging off all active user sessions after sending messages at $($firstMessageInterval) minutes and then $($secondMessageInterval) minutes" -Level Info
    If (!$testingOnly) { $sessions | Stop-BrokerSession }
}


#########################Reset All Variables and Get All Metrics###################################
#Reset variables (to avoid different data from multiple script runs)
$allMachines = ""
$allUserSessions = ""

#Run the performance monitoring script to create XML files
try {
    #& $performanceScriptLocation -ctxController $citrixController -machinePrefix $machinePrefix -interval $performanceInterval -samples $performanceSamples -exportLocation "$scriptPath\Individual.xml" -overallExportLocation "$scriptPath\Overall.xml"
} catch {
    WriteLog -Path $logLocation -Message "There was an error gathering performance metrics from the VDA machines, Please ensure you have the Powershell SDK installed and the user account you are using has rights to query the Citrix farm and WMI. " -Level Error
    Exit-PSSession
}
try {
    $allMachines = brokerMachineStates -citrixController $citrixController -machinePrefix $machinePrefix | Where-Object {$_.Tags -notcontains $exclusionTag}
    $allUserSessions = brokerUserSessions -citrixController $citrixController -machinePrefix $machinePrefix | Where-Object {$_.Tags -notcontains $exclusionTag}
} catch {
    WriteLog -Path $logLocation -Message "There was an error gathering information from the Citrix Controller - Please ensure you have the Powershell SDK installed and the user account you are using has rights to query the Citrix farm." -Level Error
    Exit-PSSession
}
try {
    $individualPerformance = Import-cliXml -Path "$ScriptPath\Individual.xml"
    $overallPerformance = Import-cliXml -Path "$ScriptPath\Overall.xml"
} catch {
    WriteLog -Path $logLocation -Message "There was an error generating and then importing the performance data, please ensure the performance script can run standalone using parameters." -Level Error
    Exit-PSSession
}

#Filter down the main objects into sub variables for scripting ease
$disconnectedSessions = $allUserSessions | Select * | Where-Object {$_.SessionState -eq "Disconnected"}
$activeSessions = $allUserSessions | Select * | Where-Object {$_.SessionState -eq "Active"}
$machinesOnAndMaintenance = $allMachines | Select * | Where {($_.RegistrationState -eq "Registered") -and ($_.PowerState -eq "On") -and ($_.InMaintenanceMode -eq $true)}
$machinesOnAndNotMaintenance = $allMachines | Select * | Where {($_.RegistrationState -eq "Registered") -and ($_.PowerState -eq "On") -and ($_.InMaintenanceMode -eq $false)}
$machinesPoweredOff = $allMachines | Select * | Where {($_.PowerState -eq "Off")}
#########################Reset All Variables and Get All Metrics###################################

#Main Logic 
#Log for script start
WriteLog -Path $logLocation -Message "#######PowerScale script starting - Test mode value is $testingOnly#######" -Level Info

#Is it a weekday?
If ($(IsWeekDay -date $($timesObj.timeNow))) {
    #If it is a weekday, then check if we are within working hours or not
    If ($(TimeCheck($timeObj)) -eq "OutOfHours") {
        #Outside working hours, perform analysis on powered on machines vs target machines
        WriteLog -Path $logLocation -Message "It is currently outside working hours - performing machine analysis" -Level Info
        $action = levelCheck -targetMachines $outOfHoursMachines -currentMachines $machinesOnAndNotMaintenance.RegistrationState.Count
        
        If ($action.Task -eq "Scaling") {
            WriteLog -Path $logLocation -Message "The current running machines matches the target machines, we are outside of working hours so there is nothing to do" -Level Info
                   
        } ElseIf ($action.Task -eq "Shutdown") {
        #Some machines to shutdown based on numbers returned
        #Check if we have any disconnected sessions and log them off
        If ($(($disconnectedSessions | Measure-Object).Count) -gt 0) {
            sessionLogOff -citrixController $citrixController -sessions $disconnectedSessions
        }
        #Check if we have any active sessions and log send a message before logging off
        If ($(($activeSessions | Measure-Object).Count) -gt 0) {
            sendMessage -citrixController $citrixController -firstMessageInterval 1 -secondMessageInterval 1 -sessions $activeSessions
        } 
        #For everymachine powered on up to the correct number, switch the poweroff
        $machinesToPowerOff = $machinesOnAndNotMaintenance | Select -First $($action.number)
        foreach ($machine in $machinesToPowerOff) {
            brokerAction -citrixController $citrixController -machineName $($machine.MachineName) -machineAction TurnOff
        } 
        }
    }    ElseIf ($(TimeCheck($timeObj)) -eq "InsideOfHours") {
        #Inside working hours, decide on what to do with current machines
        $action = levelCheck -targetMachines $InHoursMachines -currentMachines $machinesOnAndNotMaintenance.RegistrationState.Count
        WriteLog -Path $logLocation -Message "It is currently inside working hours - performing machine analysis" -Level Info
        If ($action.Task -eq "Scaling") {
            WriteLog -Path $logLocation -Message "It is currently inside working hours - performing machine analysis" -Level Info
            WriteLog -Path $logLocation -Message "The current running machines matches the target machines number, performing scaling analysis" -Level Info 
            #Perform Performance Scaling analysis -  run the performance scaling script to generate XML exports
            #& $performanceScriptLocation -ctxController $citrixController -interval $performanceInterval -samples $performanceSamples -exportLocation $performanceIndividualLoc -overallExportLocation $performanceOverallLoc
            
            If ($(Test-Path -Path "$scriptPath\$performanceIndividual") -and $(Test-Path -Path $performanceOverall)) {
                #If the performance xml files exist
                $individualPerformance = Import-Clixml -Path "$scriptPath\$performanceIndividual"
                $overallPerformance = Import-Clixml -Path "$scriptPath\$performanceOverall"
                
            } Else {
                WriteLog -Path $logLocation -Message "There has been an error gathering performance metrics for scaling calculations - the xml export files do not exist in the given location" -Level Error
                SendEmail -smtpServer $smtpServer -toAddress $smtpToAddress -fromAddress $smtpFromAddress -subject $smtpSubject -Message "There has been an error gathering performance metrics for scaling calculations - the xml export files do not exist in the given location" -attachment $logLocation -Level Error 
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
                    foreach ($machine in $($machinesOnAndMaintenance | Select -First $($action.number))) {
                        #Take machines out of maintenance mode
                        WriteLog -Path $logLocation -Message "Taking $($machine.DNSName) out of maintenance mode" -Level Info 
                        If (!$testingOnly) {maintenance -citrixController $citrixController -machine $machine -maintenanceMode Off}
                        maintenance -citrixController $citrixController -machine $machine -maintenanceMode Off
                    }
                } else {
                    #The number of machines in maintenance mode will not service the request, we need to power on machines too
                    WriteLog -Path $logLocation -Message "The number of machines in maintenance mode is $($machinesOnAndMaintenance.RegistrationState.Count) and the number of machine(s) needed is $($action.number)" -Level Info
                    WriteLog -Path $logLocation -Message "There are not sufficient machines in maintenance mode to service the request, we will power some on too" -Level Info
                    foreach ($machine in $($machinesOnAndMaintenance)) {
                        #Take machines out of maintenance mode
                        WriteLog -Path $logLocation -Message "Taking $($machine.DNSName) out of maintenance mode" -Level Info 
                        If (!$testingOnly) {maintenance -citrixController $citrixController -machine $machine -maintenanceMode Off}
                        maintenance -citrixController $citrixController -machine $machine -maintenanceMode Off
                    }
                    #Power on the machines we need by subtracting the machines already in maintenance mode from what is needed
                    foreach ($machine in $machinesPoweredOff | Select -First $($($action.Number)-$($machinesOnAndMaintenance.RegistrationState.Count))) {
                        #Power machines on
                        WriteLog -Path $logLocation -Message "Turning On $($machine.DNSName)" -Level Info 
                        If (!$testingOnly) {brokerAction -citrixController $citrixController -machineName $machine.MachineName -machineAction TurnOn}
                        brokerAction -citrixController $citrixController -machineName $machine.MachineName -machineAction TurnOn
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
                    maintenance -citrixController $citrixController -machine $machine -maintenanceMode Off
                }

                foreach ($machine in $machinesPoweredOff) {
                    #Power machines on
                    WriteLog -Path $logLocation -Message "Turning On $($machine.DNSName)" -Level Info 
                    If (!$testingOnly) {brokerAction -citrixController $citrixController -machineName $machine.MachineName -machineAction TurnOn}
                    brokerAction -citrixController $citrixController -machineName $machine.MachineName -machineAction TurnOn
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
        WriteLog -Path $logLocation -Message "The current running machines matches the target machines, we are outside of working hours so there is nothing to do" -Level Info
    
    } ElseIf ($action.Task -eq "Shutdown") {
        #Some machines to shutdown based on numbers returned
        #Check if we have any disconnected sessions and log them off
        If ($(($disconnectedSessions | Measure-Object).Count) -gt 0) {
            sessionLogOff -citrixController $citrixController -sessions $disconnectedSessions
        }
        #Check if we have any active sessions and log send a message before logging off
        If ($(($activeSessions | Measure-Object).Count) -gt 0) {
            sendMessage -citrixController $citrixController -firstMessageInterval 1 -secondMessageInterval 1 -sessions $activeSessions
        } 
        #For everymachine powered on up to the correct number, switch the poweroff
        $machinesToPowerOff = $machinesOnAndNotMaintenance | Select -First $($action.number)
        foreach ($machine in $machinesToPowerOff) {
            brokerAction -citrixController $citrixController -machineName $($machine.MachineName) -machineAction TurnOff
        } 
    }
}
#Log for script finish
WriteLog -Path $logLocation -Message "#######PowerScale script finishing#######" -Level Info -NoClobber
WriteLog -Path $logLocation -Message "-" -Level Info -NoClobber




