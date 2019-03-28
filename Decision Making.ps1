################################################################################################## 
#Main Logic script
#Copyright:         Free to use, please leave this header intact 
#Author:            Leee Jeffries
#Company:           https://www.leeejeffries.com
#Script help:       https://www.leeejeffries.com, please supply any errors or issues you encounter
#Purpose:           Perform logical operations to shutdown or start VDAs based on performance metrics gathered
#Enterprise users:  This script is recommended for users currently utilising smart scale to power up and down VDA's,
# Smart Scale is due to be deprecated in May

################################## Manual Variable Configuration ##################################
$performanceScriptLocation = "C:\Users\leee.jeffries\Documents\GitHub\PowerScale\Performance Measurement.ps1" #Performance gathering script location
$citrixController = "UKSCTXXAC01"                                                           #Citrix controller name or IP
$machinePrefix = "UKSCTXVDA"                                                                #Machine name prefix to include
$businessStartTime =  $([DateTime]"06:00")                                                  #Start time of the business
$businessCloseTime = $([DateTime]"18:00")                                                   #End time of the business
$outOfHoursMachines = "2"                                                                      #How many machines should be powered on during the weekends
$inHoursMachines = "20"                                                                     #How many machines should be powered on during the day (InsideOfHours will take into account further machines)
$machineScaling = "Schedule"                                                                 #Options are (Schedule, CPU, Memory, Index or Sessions)
$logLocation = "C:\Users\leee.jeffries\Documents\GitHub\PowerScale\InsideOfHours_Log.log"         #Log file location
$smtpServer = "10.110.4.124"                                                                #SMTP server address
$smtpToAddress = "leee.jeffries@prospects.co.uk"                                            #Email address to send to
$smtpFromAddress = "copier@prospects.co.uk"                                                 #Email address mails will come from
$smtpSubject = "PowerScale"                                                                 #Mail Subject (will be appended with Error if error
$testingOnly = $true                                                                        #Debugging value, will only write out to the log
################################## Manual Variable Configuration ##################################
################################### Test Variable Configuration ###################################

################################### Test Variable Configuration ###################################

#Setup a time object for comparison
$timesObj = [PSCustomObject]@{
    startTime = $businessStartTime
    endTime = $businessCloseTime
    timeNow = $(Get-Date)
    #timeNow = $([datetime]::ParseExact("29/02/19 05:59", "dd/MM/yy HH:mm", $null))
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
    #Weekdays
    $weekdays = "Monday","Tuesday","Wednesday","Thursday","Friday"
    #See if the current day of the week sits inside of any other weekdays, returns true or false
    $null -ne ($weekdays | ? { $(Get-Date -Format "dddd") -match $_ })  # returns $true
}

#Function to check if inside of business hours or outside to business hours
Function TimeCheck($timeObj) {
    If (($timesObj.timeNow -lt $timesObj.startTime) -or ($timesObj.timeNow -gt $timesObj.endTime)) {
        Return "OutOfHours" #OutOfHours as we are outside of working hours
    } ElseIf (($timesObj.timeNow -ge $timesObj.startTime) -and ($timesObj.timeNow -le $timesObj.endTime)) {
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

#Function to check active sessions on a machine
Function checkActive () {
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, HelpMessage = "Specifies which Citrix Controller to use, you must have admin rights on the site")]    
        [ValidateNotNullOrEmpty()] 
        [string]$citrixController, 
 
        [Parameter(Mandatory=$true, HelpMessage = "Specifies which VDA to check for active sessions on")]   
        [ValidateNotNullOrEmpty()]     
        [string]$machine
    )
    #Check the VDA to see if it has active sessions
    If ($(Get-BrokerSession -AdminAddress $citrixController -MachineName $machine | Where-Object {$_.SessionState -eq "Active"}).Count -gt 0) {
        #Return true if there are active sessions
        Return $true
    } Else {
        #Return false if there are no active sessions
        Return $false
    }
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
    If ($delay -gt 0) {
        If (!$testingOnly) {New-BrokerDelayedHostingPowerAction -AdminAddress $citrixcontroller -MachineName $machineName -Action $machineAction -Delay $(New-TimeSpan -Minutes $delay) }
    } else {
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
        [string]$sessions
    )
    #Do some logging off of disconnected sessions
    WriteLog -Path $logLocation -Message "Logging off all disconnected sessions in one hit" -Level Info
    get-brokersession -filter {sessionstate -eq "Disconnected"} | stop-brokersession

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

        [Parameter(Mandatory=$true, HelpMessage = "List of active sessions to message")]    
        [ValidateNotNullOrEmpty()] 
        [object]$sessions
    )
    
    Write-Verbose -Message "Sending message to users to log off - 5 minute warning" -Verbose
    # Write-host (date -Format hh:mm:ss)   -   "Sending message to users to log off - 5 minute warning" -ForegroundColor Yellow -Verbose

    Send-BrokerSessionMessage -AdminAddress $citrixController -InputObject $sessions -MessageStyle Information -Title "ICT Server Scheduled Shutdown " -Text "Please save your work and log-off. This machine will be shutdown in 5mins"
    start-sleep -minutes $firstMessageInterval

    #Write-host (date -Format hh:mm:ss)   -   "Sending message to users to log off - 1 minute warning" -ForegroundColor Yellow -Verbose
    Write-Verbose -Message "Sending message to users to log off - 1 minute warning" -Verbose
    
    Send-BrokerSessionMessage -InputObject $sessions -MessageStyle Critical -Title "ICT Server Scheduled Shutdown " -Text "Please save your work and log-off. This machine will be shutdown in 1 min"
    #sleep for 1 minute until the sessions get logged

    start-sleep -minutes $secondMessageInterval

    WriteLog -Path $logLocation -Message "Logging off all active user sessions in after sending messages at $($firstMessageInterval/60) and $($secondMessageInterval/60)" -Level Info
    $sessions | Stop-BrokerSession
}
#########################YOU ARE HERE COMPARING VARIABLES###################################
$allMachines = ""
$allUserSessions = ""
$allMachines = brokerMachineStates -citrixController $citrixController -machinePrefix $machinePrefix
$allUserSessions = brokerUserSessions -citrixController $citrixController -machinePrefix $machinePrefix
$machinesOnAndRegistered = $allMachines | Select * | Where {($_.RegistrationState -eq "Registered") -and ($_.PowerState -eq "On")}
$machinesOnAndMaintenance = $allMachines | Select * | Where {($_.RegistrationState -eq "Registered") -and ($_.PowerState -eq "On") -and ($_.InMaintenanceMode -eq $true)}
$machinesOnAndNotMaintenance = $allMachines | Select * | Where {($_.RegistrationState -eq "Registered") -and ($_.PowerState -eq "On") -and ($_.InMaintenanceMode -eq $false)}
$machinesPoweredOff = $allMachines | Select * | Where {($_.PowerState -eq "Off")}
$machineActiveSessions = $allUserSessions | Where {$_.SessionState -eq "Active"} | Select MachineName, UserFullName | sort MachineName | Group MachineName
$machineNonActiveSessions = $allUserSessions | Where {$_.SessionState -ne "Active"} | Select MachineName, UserFullName | sort MachineName | Group MachineName
If (!$testingOnly) {maintenance -citrixController $citrixController -machine $(Get-BrokerMachine -DNSName "UKSCTXPPT01.prospects.local") -maintenanceMode On}
#########################YOU ARE HERE COMPARING VARIABLES###################################

#Main Logic 
#Log for script start
WriteLog -Path $logLocation -Message "PowerScale script starting - Test mode value is $testingOnly" -Level Info

#Is it a weekday?
If ($(IsWeekDay)) {
    #If it is a weekday, then check if we are within working hours or not
    If ($(TimeCheck($timeObj)) -eq "OutOfHours") {
        #Outside working hours, perform analysis on powered on machines vs target machines
        WriteLog -Path $logLocation -Message "It is currently outside working hours - performing machine analysis" -Level Info
        $action = levelCheck -targetMachines $outOfHoursMachines -currentMachines $machinesOnAndMaintenance.RegistrationState.Count
        
        If ($action.Task -eq "Scaling") {
            WriteLog -Path $logLocation -Message "The current running machines matches the target machines, we are outside of working hours so there is nothing to do" -Level Info
        
        } ElseIf ($action.Task -eq "Startup") {
            #Some machines to startup based on numbers returned
            WriteLog -Path $logLocation -Message "Machines to startup $($action.Number)" -Level Info
            #Check for machines in maintenance mode that is powered on and is registered
            #Take x amount of machines out of maintenance mode
        
        } ElseIf ($action.Task -eq "Shutdown") {
            #Some machines to shutdown based on numbers returned
            $actionsToPerform = $action.Number
            WriteLog -Path $logLocation -Message "Machines to shutdown $($actionsToPerform)" -Level Info
            #Check for machines in maintenance mode that is powered on and is registered
            
            #Shutdown these machines
        }
    } ElseIf ($(TimeCheck($timeObj)) -eq "InsideOfHours") {
        #Inside working hours, decide on what to do with current machines
        $action = levelCheck -targetMachines $InHoursMachines -currentMachines $machinesOnAndNotMaintenance.RegistrationState.Count
        WriteLog -Path $logLocation -Message "It is currently inside working hours - performing machine analysis" -Level Info
        If ($action.Task -eq "Scaling") {
            WriteLog -Path $logLocation -Message "It is currently inside working hours - performing machine analysis" -Level Info
            WriteLog -Path $logLocation -Message "The current running machines matches the target machines number, performing scaling analysis" -Level Info 
            #Perform Performance Scaling analysis -  run the performance scaling script to generate XML exports
            #& $performanceScriptLocation -ctxController $citrixController -interval $performanceInterval -samples $performanceSamples -exportLocation $performanceIndividualLoc -overallExportLocation $performanceOverallLoc
            
            If ($(Test-Path -Path $performanceIndividualLoc) -and $(Test-Path -Path $performanceOverallLoc)) {
                #If the performance xml files exist
                $individualPerformance = Import-Clixml -Path $performanceIndividualLoc
                $overallPerformance = Import-Clixml -Path $performanceOverallLoc
                
            } Else {
                WriteLog -Path $logLocation -Message "There has been an error gathering performance metrics for scaling calculations - the xml export files do not exist in the given location" -Level Error
                SendEmail -smtpServer $smtpServer -toAddress $smtpToAddress -fromAddress $smtpFromAddress -subject $smtpSubject -Message "There has been an error gathering performance metrics for scaling calculations - the xml export files do not exist in the given location" -attachment $logLocation -Level Error 
            }
        
        } ElseIf ($action.Task -eq "Startup") {
            #Some machines to startup based on numbers returned
            WriteLog -Path $logLocation -Message "It is currently inside working hours, machines are required to be started - performing machine analysis" -Level Info
            WriteLog -Path $logLocation -Message "There are $($machinesOnAndNotMaintenance.RegistrationState.Count) machine(s) currently switched on and registered, $($inHoursMachines - $machinesOnAndMaintenance.RegistrationState.Count) machines are needed" -Level Info
            #If the amount of machines that are in maintenance mode are greater or equal to the number of machines needed to be started
            ##Need to work out the maths here
            If ($machinesOnAndMaintenance.RegistrationState.count -le $($inHoursMachines - $machinesOnAndNotMaintenance.RegistrationState.Count)) {
                $maintenanceCount = $($inHoursMachines - $machinesOnAndNotMaintenance.RegistrationState.Count)
                #Select the machines in maintenance mode to be switched on
                $numberOfMachines = ($machinesOnAndMaintenance | Select -First $($inHoursMachines - $machinesOnAndNotMaintenance.RegistrationState.Count))
                #For every machine selected turn off maintenance mode
                ForEach ($machine in $numberOfMachines) {
                    WriteLog -Path $logLocation -Message "Taking $($machine.DNSName) out of maintenance mode" -Level Info
                    If (!$testingOnly) {maintenance -citrixController $citrixController -machine $machine -maintenanceMode "On"}                    
                }
            } Else {
                #We need to power-up some machines that are currently switched off  
                #Calculate the number of machines needing to be powered on - minus the machines that have just been powered on
                $numberOfMachines = ($machinesPoweredOff | Select -First $($inHoursMachines - $machinesOnAndRegistered.RegistrationState.Count)-$maintenanceCount) 
                #For every machine selected perfom a startup          
                ForEach ($machine in $numberOfMachines) {
                    WriteLog -Path $logLocation -Message "Placing $($machine.DNSName) in maintenance mode" -Level Info
                    If (!$testingOnly) {maintenance -citrixController $citrixController -machine $machine -maintenanceMode "On"}
                    WriteLog -Path $logLocation -Message "Powering on $($machine.DNSName)" -Level Info
                    If (!$testingOnly) {brokerAction -citrixController $citrixController -machineName $machine.DNSName -machineAction "TurnOn"}
                }
            }                   

        } ElseIf ($action.Task -eq "Shutdown") {
            #Some machines to shutdown based on numbers returned
            WriteLog -Path $logLocation -Message "It is currently inside working hours, machines are required to be shutdown - performing machine analysis" -Level Info
            WriteLog -Path $logLocation -Message "There are $($machinesOnAndRegistered.RegistrationState.Count) machine(s) currently switched on and registered" -Level Info
            #For each machine found to be turned on, check user session are not active and place the machines in maintenance mode and issue a shutdown with a delay of 5 minutes
            $numberOfMachines = ($machinesOnAndRegistered | Select -First $($inHoursMachines - $machinesOnAndRegistered.RegistrationState.Count))
            ForEach ($machine in $numberOfMachines) {
            #Check for any active sessions and perform actions if no active sessions are found
                If (!$(checkActive -citrixController $citrixController -machine $machine.MachineName)) {
                    WriteLog -Path $logLocation -Message "$($machine.MachineName) has no active sessions, performing a shutdown" -Level Info
                    WriteLog -Path $logLocation -Message "Placing $($machine.DNSName) in maintenance mode" -Level Info
                    If (!$testingOnly) {maintenance -citrixController $citrixController -machine $machine -maintenanceMode "On"}
                    WriteLog -Path $logLocation -Message "Logging users off of $($machine.DNSName)" -Level Info
                    If (!$testingOnly) {sessionLogOff -citrixController $citrixController -sessions}
                    WriteLog -Path $logLocation -Message "Powering off $($machine.DNSName) in $shutdownDelay minutes" -Level Info
                    If (!$testingOnly) {brokerAction -citrixController $citrixController -machineName $machine.DNSName -machineAction "Shutdown" -delay $shutdownDelay}
                }  Else {
                    WriteLog -Path $logLocation -Message "There are active sessions on $($machine.DNSName), leaving this machine alone" -Level Info
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
    $action = levelCheck -targetMachines $outOfHoursMachines -currentMachines $(brokerMachineStates -citrixController $citrixController -machinePrefix $machinePrefix).Count
    
    If ($action.Task -eq "Scaling") {
        WriteLog -Path $logLocation -Message "The current running machines matches the target machines, we are outside of working hours so there is nothing to do" -Level Info
    
    } ElseIf ($action.Task -eq "Startup") {
        #Some machines to startup based on numbers returned
    
    } ElseIf ($action.Task -eq "Shutdown") {
        #Some machines to shutdown based on numbers returned
    }
}
#Log for script finish
WriteLog -Path $logLocation -Message "PowerScale script finishing" -Level Info -NoClobber




