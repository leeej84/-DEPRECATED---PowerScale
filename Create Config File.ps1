$performanceScriptLocation = "C:\Users\leee.jeffries.ctxlab.000\OneDrive - Leee Jeffries\Source\PowerScale\Performance Measurement.ps1" #Performance gathering script location
$citrixController = "XDDC-01.ctxlab.local"                                                           #Citrix controller name or IP
$machinePrefix = "XDSH"                                                                #Machine name prefix to include
$businessStartTime =  $([DateTime]"06:00")                                                  #Start time of the business
$businessCloseTime = $([DateTime]"18:00")                                                   #End time of the business
$outOfHoursMachines = "0"                                                                      #How many machines should be powered on during the weekends
$inHoursMachines = "2"                                                                     #How many machines should be powered on during the day (InsideOfHours will take into account further machines)
$machineScaling = "Schedule"                                                                 #Options are (Schedule, CPU, Memory, Index or Sessions)
$logLocation = "C:\Users\leee.jeffries.ctxlab.000\OneDrive - Leee Jeffries\Source\PowerScale\PowerScale_Log.log"         #Log file location
$smtpServer = "192.168.2.200"                                                                #SMTP server address
$smtpToAddress = "leee.jeffries@leee.jeffries.com"                                            #Email address to send to
$smtpFromAddress = "leee.jeffries@leee.jeffries.com"                                                 #Email address mails will come from
$smtpSubject = "PowerScale"                                                                 #Mail Subject (will be appended with Error if error
$testingOnly = $true                                                                        #Debugging value, will only write out to the log

$configContent = [PSCustomObject]@{ 
    performanceScriptLocationComment = "Performance gathering script location"
    performanceScriptLocation = $performanceScriptLocation
    citrixControllerComment = "Citrix controller name or IP"
    citrixController = $citrixController  
    machinePrefixComment = "Machine name prefix to include"
    machinePrefix = "XDSH"
    businessStartTimeComment = "Start time of the business"
    businessStartTime =  $([DateTime]"06:00")
    businessCloseTimeComment = "End time of the business"
    businessCloseTime = $([DateTime]"18:00")
    outOfHoursMachinesComment = "How many machines should be powered on during the weekends"
    outOfHoursMachines = "0"
    inHoursMachinesComment = "How many machines should be powered on during the day (InsideOfHours will take into account further machines)"
    inHoursMachines = "2"
    machineScalingComment = "Options are (Schedule, CPU, Memory, Index or Sessions)"
    machineScaling = "Schedule"
    logLocationComment = "Log file location"
    logLocation = "C:\Users\leee.jeffries.ctxlab.000\OneDrive - Leee Jeffries\Source\PowerScale\PowerScale_Log.log"
    smtpServerComment = "SMTP server address"
    smtpServer = "192.168.2.200" 
    smtpToAddressComment = "Email address to send to"
    smtpToAddress = "leee.jeffries@leee.jeffries.com"
    smtpFromAddressComment = "Email address mails will come from"
    smtpFromAddress = "leee.jeffries@leee.jeffries.com"
    smtpSubjectComment = "Mail Subject (will be appended with Error if error"
    $smtpSubject = "PowerScale"
    testingOnlyComment = "Debugging value, will only write out to the log "
    testingOnly = $true
}

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$configContent | Export-Clixml -Path "$scriptPath\config.xml"