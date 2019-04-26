$performanceScriptLocation = "C:\Users\leee.jeffries\Documents\GitHub\PowerScale\Performance Measurement.ps1" #Performance gathering script location
$performanceIndividual = "Individual.xml"                                                   #Individual machine performance XML
$performanceOverAll = "Overall.xml"                                                         #Overall machine performance XML
$performanceSampleInterval = "1"                                                            #Interval of time to wait between samples
$performanceSamples = "1"                                                                   #Number of performance samples to gather
$citrixController = "UKSCTXXAC01.prospects.local"                                           #Citrix controller name or IP
$machinePrefix = "UKSCTXPPT"                                                                #Machine name prefix to include
$businessStartTime =  "06:00"                                                               #Start time of the business
$businessCloseTime = "18:00"                                                                #End time of the business
$outOfHoursMachines = "0"                                                                   #How many machines should be powered on during the weekends
$inHoursMachines = "2"                                                                      #How many machines should be powered on during the day (InsideOfHours will take into account further machines)
$machineScaling = "Schedule"                                                                #Options are (Schedule, CPU, Memory, Index or Sessions)
$LogNumberOfDays = 7                                                                        #Days to rotate the logs after
$LogMaxSize = 100                                                                           #Max Log size
$logLocation = "C:\Users\leee.jeffries\Documents\GitHub\PowerScale\PowerScale_Log.log"      #Log file location
$smtpServer = "10.110.4.32"                                                                 #SMTP server address
$smtpToAddress = "leee.jeffries@prospects.co.uk"                                            #Email address to send to
$smtpFromAddress = "copier@prospects.co.uk"                                                 #Email address mails will come from
$smtpSubject = "PowerScale"                                                                 #Mail Subject (will be appended with Error if error
$testingOnly = $true                                                                        #Debugging value, will only write out to the log
$exclusionTag = "excluded"                                                                  #Tag in Studio to ensure a machine is discounted from calculations
$wmiServiceAccount = "jeffrl-p"                                                             #WMI Service Account Name
$wmiServicePassword = "NewPassword789!"                                                     #WMI Service Account Password - leave empty if not required (!!!!Remove once this script is run!!!!)
          
#Tag to assign in Studio to exclude a machine from scaling operations

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
    LogMaxSizeComment = "Max Log size"
    LogMaxSize = $LogMaxSize
    LogNumberOfDaysComment = "Days to rotate the logs after"
    LogNumberOfDays = $LogNumberOfDays 
    logLocationComment = "Log file location"
    logLocation = $logLocation
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