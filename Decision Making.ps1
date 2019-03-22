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
[String]$citrixController = "UKSCTXXAC01"                                   #Citrix controller name or IP
$machinePrefix = "UKSCTXVDA"                                                #Machine name prefix to include
$businessStartTime =  $([DateTime]"06:00")                                  #Start time of the business
$businessCloseTime = $([DateTime]"18:00")                                   #End time of the business
$weekendMachines = "2"                                          #How many machines should be powered on during the weekends
$weekdayMachines = "20"                                         #How many machines should be powered on during the day (scaling will take into account further machines)
$machineScaing = "Schedule"                                     #Options are (Schedule, CPU, Memory, Index or Sessions)
$logLocation = "C:\Users\leee.jeffries\Documents\GitHub\PowerScale\Scaling_Log.log" #Log file location
$smtpServer = "10.110.4.124" #SMTP server address
$smtpToAddress = "leee.jeffries@prospects.co.uk" #Email address to send to
$smtpFromAddress = "copier@prospects.co.uk" # Email address mails will come from
$smtpSubject = "PowerScale" #Mail Subject (will be appended with Error if error
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
        } else {
            # Send email message without attachment
            Send-MailMessage -SmtpServer $smtpServer -From $fromAddress -To $toAddress -Subject $("$subject - $Level") -Body "$FormattedDate $LevelText $Message"
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

#Function to check if inside of business hours or outside to activate scaling
Function TimeCheck($timeObj) {
    If (($timesObj.timeNow -lt $timesObj.startTime) -or ($timesObj.timeNow -gt $timesObj.endTime)) {
        Return "Activate" #Activate as we are outside of working hours
    } ElseIf (($timesObj.timeNow -ge $timesObj.startTime) -and ($timesObj.timeNow -le $timesObj.endTime)) {
        Return "Halt" #Dont activate as we are inside working hours
    } Else {
        Return "Error" #Dont do anything if the time calculation is not conclusive
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
 
        [Parameter(Mandatory=$true, HelpMessage = "Specifies a prefix to search for for the VDA machine names")]   
        [ValidateNotNullOrEmpty()]      
        [string]$machinePrefix  
    )
    
    Return Get-BrokerSession -AdminAddress $citrixController -MaxRecordCount 10000 | Where {((($_.MachineName).Replace("\","\\")) -match $machinePrefix)}
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
        New-BrokerDelayedHostingPowerAction -AdminAddress $citrixcontroller -MachineName $machineName -Action $machineAction -Delay $(New-TimeSpan -Minutes $delay)
    } else {
        New-BrokerHostingPowerAction -AdminAddress $citrixcontroller -MachineName $machineName -Action $machineAction
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
            Set-BrokerMachineMaintenanceMode -AdminAddress $citrixController -InputObject $machine -MaintenanceMode $true
        } catch {
            WriteLog -Path $logLocation -Message "there was an error placing $($machine.DNSName) into maintenance mode" -Level Error
        }
    } elseif ($maintenanceMode -eq "Off") {
        try {
            Set-BrokerMachineMaintenanceMode -AdminAddress $citrixController -InputObject $machine -MaintenanceMode $false
        } catch {
            WriteLog -Path $logLocation -Message "there was an error taking $($machine.DNSName) out of maintenance mode" -Level Error
        }
    }
}
#########################YOU ARE HERE COMPARING VARIABLES###################################
$machineVar = brokerMachineStates -citrixController $citrixController -machinePrefix $machinePrefix
$userVar = brokerUserSessions -citrixController $citrixController -machinePrefix $machinePrefix
$machineActiveSessions = $userVar | Where {$_.SessionState -eq "Active"} | Select MachineName, UserFullName | sort MachineName | Group MachineName
$machineNonActiveSessions = $userVar | Where {$_.SessionState -ne "Active"} | Select MachineName, UserFullName | sort MachineName | Group MachineName
maintenance -citrixController $citrixController -machine $(Get-BrokerMachine -DNSName "UKSCTXPPT01.prospects.local") -maintenanceMode Off
#########################YOU ARE HERE COMPARING VARIABLES###################################

#Main Logic 
#Log for script start
WriteLog -Path $logLocation -Message "Scaling script starting" -Level Info

#Is it a weekday?
If ($(IsWeekDay)) {
    If ($(TimeCheck($timeObj)) -eq "Activate") {
        #Stuff to do when activated                
        WriteLog -Path $logLocation -Message "Scaling within window of time - activating" -Level Info
    } ElseIf ($(TimeCheck($timeObj)) -eq "Halt") {
        #Stuff to do when halted
        "DO NOT Acvtivate"
        WriteLog -Path $logLocation -Message "Scaling inside business hours - not activating" -Level Info
    } ElseIf ($(TimeCheck($timeObj)) -eq "Error") {
        #Stuff to do when Error
        "ERROR"
        WriteLog -Path $logLocation -Message "There has been an error, please review the log" -Level Error
    }
} Else { #Its the weekend
    
}

#Log for script finish
WriteLog -Path $logLocation -Message "Scaling script finishing" -Level Info -NoClobber
#SendEmail -smtpServer $smtpServer -toAddress $smtpToAddress -fromAddress $smtpFromAddress -subject $smtpSubject -Message "This is a test message" -attachment $logLocation -Level Error




