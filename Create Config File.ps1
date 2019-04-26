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
$smtpServer = "10.110.4.32"                                                               #SMTP server address
$smtpToAddress = "leee.jeffries@prospects.co.uk"                                          #Email address to send to
$smtpFromAddress = "copier@prospects.co.ukr"                                        #Email address mails will come from
$smtpSubject = "PowerScale"                                                                 #Mail Subject (will be appended with Error if error
$testingOnly = $true                                                                        #Debugging value, will only write out to the log
$exclusionTag = "excluded"   

          
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

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition -Verbose
$configContent | Export-Clixml -Path "$scriptPath\config.xml" -Verbose