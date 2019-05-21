$performanceIndividual = "Individual.xml"                                                   #Individual machine performance XML
$performanceOverAll = "Overall.xml"                                                         #Overall machine performance XML
$performanceSampleInterval = "1"                                                            #Interval of time to wait between samples
$performanceSamples = "1"                                                                   #Number of performance samples to gather
$citrixController = "XDDC-01.ctxlab.local"                                                  #Citrix controller name or IP
$machinePrefix = "XDSHNP"                                                                   #Machine name prefix to include
$businessStartTime =  "06:00"                                                               #Start time of the business
$businessCloseTime = "18:00"                                                                #End time of the business
$outOfHoursMachines = "0"                                                                   #How many machines should be powered on during the weekends
$inHoursMachines = "2"                                                                      #How many machines should be powered on during the day (InsideOfHours will take into account further machines)
$machineScaling = "CPU"                                                                     #Options are (Schedule, CPU, Memory, Index or Sessions)
$farmCPUThreshhold = "90"                                                                   #Farm CPU threshhold average ex: 90 = 90% CPU across the farm on average
$farmMemoryThreshhold = "90"                                                                #Farm memory threshhold average ex: 90 = 90% memory used across the farm on average
$farmIndexThreshhold = "5000"                                                               #Farm Load Index threshhold average ex: 5000 = Load index of 5000 on average across the farm
$farmSessionThreshhold = "20"                                                               #Farm Session threshhold average ex: 20 = An average of 20 users on each server
$LogNumberOfDays = 7                                                                        #Days to rotate the logs after
$logLocation = "C:\Users\leee.jeffries.ctxlab.000\OneDrive - Leee Jeffries\Source\PowerScale\PowerScale_Log.log"      #Log file location
$forceUserLogoff = $true                                                                    #Force user sessions to be logged off out of hours or allow user sessions to drain
$userLogoffFirstInterval = "1"                                                              #Initial logoff message interval if forcing user logoff in minutes
$userLogoffFirstMessage = "This server will be shutdown outside of working hours, please save your work and logoff"   #Initial logoff message 
$userLogoffSecondInterval = "1"                                                             #Second logoff message interval if forcing user logoff in minutes
$userLogoffSecondMessage = "This server will be shutdown shortly, please save your work and logoff as soon as possible"  #Second logoff message 
$smtpServer = "192.168.2.200"                                                               #SMTP server address
$smtpToAddress = "leee.jeffries@leeejeffries.com"                                           #Email address to send to
$smtpFromAddress = "leee.jeffries@leeejeffries.com"                                         #Email address mails will come from
$smtpSubject = "PowerScale"                                                                 #Mail Subject (will be appended with Error if error
$testingOnly = $true                                                                        #Debugging value, will only write out to the log
$exclusionTag = "excluded"                                                                  #Tag in Studio to ensure a machine is discounted from calculations
$wmiServiceAccount = "ctxlab.local\administrator"                                           #WMI Service Account Name - must include UPN or domain\username
$wmiServicePassword = ""                                                                    #WMI Service Account Password - leave empty if not required (!!!!Remove once this script is run!!!!)
        
$configContent = [PSCustomObject]@{ 
    performanceScriptLocationComment = "Performance gathering script location"
    performanceScriptLocation = $performanceScriptLocation
    performanceIndividual = $performanceIndividual = "Individual.xml"                                                   
    performanceIndividualComment = "Individual machine performance XML"
    performanceOverall = $performanceOverAll 
    performanceOverallComment = "Overall machine performance XML"
    performanceSampleInterval = $performanceSampleInterval 
    performanceSampleIntervalComment = "Interval of time to wait between samples"
    performanceSamples = $performanceSamples = "1"
    performanceSamplesComment = "Number of performance samples to gather"
    citrixControllerComment = "Citrix controller name or IP"
    citrixController = $citrixController  
    machinePrefixComment = "Machine name prefix to include"
    machinePrefix = $machinePrefix
    businessStartTimeComment = "Start time of the business"
    businessStartTime =  $businessStartTime
    businessCloseTimeComment = "End time of the business"
    businessCloseTime = $businessCloseTime
    outOfHoursMachinesComment = "How many machines should be powered on during the weekends"
    outOfHoursMachines = $outOfHoursMachines
    inHoursMachinesComment = "How many machines should be powered on during the day (InsideOfHours will take into account further machines)"
    inHoursMachines = $inHoursMachines
    machineScalingComment = "Options are (CPU, Memory, Index or Sessions)"
    machineScaling = $machineScaling
    farmCPUThreshhold = $farmCPUThreshhold
    farmCPUThreshholdComment = "Farm CPU threshhold average ex: 90 = 90% CPU across the farm on average"
    farmMemoryThreshhold = $farmMemoryThreshhold
    farmMemoryThreshholdComment = "Farm memory threshhold average ex: 90 = 90% memory used across the farm on average"
    farmIndexThreshhold = $farmIndexThreshhold
    farmIndexThreshholdComment = "Farm Load Index threshhold average ex: 5000 = Load index of 5000 on average across the farm"
    farmSessionThreshhold = $farmSessionThreshhold
    farmSessionThreshholdComment = "Farm Session threshhold average ex: 20 = An average of 20 users on each server"
    LogNumberOfDaysComment = "Days to rotate the logs after"
    LogNumberOfDays = $LogNumberOfDays 
    logLocationComment = "Log file location"
    logLocation = $logLocation
    forceUserLogoffComment = "Force user sessions to be logged off out of hours or allow user sessions to drain"
    forceUserLogoff = $forceUserLogoff
    userLogoffFirstIntervalComment = "Initial logoff message interval if forcing user logoff in minutes"
    userLogoffFirstInterval = $userLogoffFirstInterval                                                                         
    userLogoffFirstMessageComment = "Initial logoff message to user"
    userLogoffFirstMessage = $userLogoffFirstMessage
    userLogoffSecondIntervalComment = "Second logoff message interval if forcing user logoff in minutes"
    userLogoffSecondInterval = $userLogoffSecondInterval                                                                         
    userLogoffSecondMessageComment = "Second logoff message to user"
    userLogoffSecondMessage = $userLogoffSecondMessage 
    smtpServerComment = "SMTP server address"
    smtpServer = $smtpServer
    smtpToAddressComment = "Email address to send to"
    smtpToAddress = $smtpToAddress
    smtpFromAddressComment = "Email address mails will come from"
    smtpFromAddress = $smtpFromAddress
    smtpSubjectComment = "Mail Subject (will be appended with Error if error"
    smtpSubject = $smtpSubject
    exclusionTag = $exclusionTag
    exclusionTagComment = "Tag to assign in Studio to exclude a machine from scaling operations"
    wmiServiceAccount = $wmiServiceAccount
    wmiServiceAccountComment = "WMI Service Account Name"
    testingOnlyComment = "Debugging value, will only write out to the log "
    testingOnly = $testingOnly
}

#Encrypt WMI user credentials if wmiPassword is populated
If ($wmiServicePassword) {
    # Define variables
    $Directory = split-path -parent $MyInvocation.MyCommand.Definition
    $KeyFile = Join-Path $Directory  "AES_KEY_FILE.key"
    $PasswordFile = Join-Path $Directory "AES_PASSWORD_FILE.pass"

    $Password = $wmiServicePassword

    #Remove previous password files if they exist
    if ($(Test-Path $KeyFile) -eq $true) {
        Remove-Item -Path $KeyFile -Force
    }

    if ($(Test-Path $PasswordFile) -eq $true) {
        Remove-Item -Path $PasswordFile -Force
    }

    # Create the AES key file
    try {
    $Key = New-Object Byte[] 32
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($Key)
    $Key | out-file $KeyFile
            $KeyFileCreated = $True
        Write-Host "The key file $KeyFile was created successfully"
    } catch {
        write-Host "An error occurred trying to create the key file $KeyFile (error: $($Error[0])"
    }

    Start-Sleep 2

    # Add the plaintext password to the password file (and encrypt it based on the AES key file)
    If ( $KeyFileCreated -eq $True ) {
        try {
        $Key = Get-Content $KeyFile
            $encPassword = ConvertTo-SecureString $Password -AsPlainText -Force
            $encPassword | ConvertFrom-SecureString -key $Key | Out-File $PasswordFile
            Write-Host "The key file $PasswordFile was created successfully"
        } catch {
            write-Host "An error occurred trying to create the password file $PasswordFile (error: $($Error[0])"
        }
    } 
}

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition -Verbose
$configContent | Export-Clixml -Path "$scriptPath\config.xml" -Verbose