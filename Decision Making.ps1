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
[String]$citrixController = "UKSCTXXAC01" #Citrix controller name or IP
$machinePrefix = "UKSCTXVDA" #Machine name prefix to include
$businessStartTime =  $([DateTime]"06:00") #Start time of the business
$businessCloseTime = $([DateTime]"18:00") #End time of the business
$weekendMachines = "2" #How many machines should be powered on during the weekends
$weekdayMachines = "20" #How many machines should be powered on during the day (scaling will take into account further machines)
$machineScaing = "Schedule" #Options are (Schedule, CPU, Memory, Index or Sessions)
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
        [Parameter(Mandatory=$true, 
                   ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()] 
        [Alias("LogContent")] 
        [string]$Message, 
 
        [Parameter(Mandatory=$false)] 
        [Alias('LogPath')] 
        [string]$Path='C:\Logs\PowerShellLog.log', 
         
        [Parameter(Mandatory=$false)] 
        [ValidateSet("Error","Warn","Info")] 
        [string]$Level="Info", 
         
        [Parameter(Mandatory=$false)] 
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
        [Parameter(Mandatory=$true, 
                   ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()] 
        [string]$Message, 
 
        [Parameter(Mandatory=$false)] 
        [string]$attachment='', 
         
        [Parameter(Mandatory=$false)] 
        [ValidateSet("Error","Warn","Info")] 
        [string]$Level="Info", 
         
        [Parameter(Mandatory=$false)] 
        [string]$smtpServer="",
         
        [Parameter(Mandatory=$false)] 
        [string]$fromAddress="",
         
        [Parameter(Mandatory=$false)] 
        [string]$toAddress="",

        [Parameter(Mandatory=$false)] 
        [string]$subject="",
         
        [Parameter(Mandatory=$false)] 
        [switch]$NoClobber 
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
    $weekdays = "Monday","Tuesday","Wednesday","Thursday","Friday"
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
        [Parameter(Mandatory=$true)]    
        [ValidateNotNullOrEmpty()] 
        [string]$citrixController, 
 
        [Parameter(Mandatory=$true)]   
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
        [Parameter(Mandatory=$true)]    
        [ValidateNotNullOrEmpty()] 
        [string]$citrixController, 
 
        [Parameter(Mandatory=$true)]   
        [ValidateNotNullOrEmpty()]      
        [string]$machinePrefix  
    )
    
    Return Get-BrokerSession -AdminAddress $citrixController -MaxRecordCount 10000 | Where {((($_.MachineName).Replace("\","\\")) -match $machinePrefix)}
}


#########################YOU ARE HERE COMPARING VARIABLES###################################
$machineVar = brokerMachineStates -citrixController $citrixController -machinePrefix $machinePrefix
$userVar = brokerUserSessions -citrixController $citrixController -machinePrefix $machinePrefix
$machineActiveSessions = $userVar | Where {$_.SessionState -eq "Active"} | Select MachineName, UserFullName | sort MachineName | Group MachineName
$machineNonActiveSessions = $userVar | Where {$_.SessionState -ne "Active"} | Select MachineName, UserFullName | sort MachineName | Group MachineName
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




