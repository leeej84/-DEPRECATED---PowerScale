##################################################################################################
#Main Logic script
#Copyright:         Free to use, please leave this header intact
#Author:            Leee Jeffries
#Company:           https://www.leeejeffries.com
#Script help:       https://www.leeejeffries.com, please supply any errors or issues you encounter
#Purpose:           Perform logical operations to shutdown or start VDAs based on performance metrics gathered
#Enterprise users:  This script is recommended for users currently utilising smart scale to power up and down VDA's,
# Smart Scale is due to be deprecated in May 2019

#Input command for testing purposes, to supply a time
[CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$false, HelpMessage = "Specify a testing time for data generation")]
        [ValidateNotNullOrEmpty()]
        [Alias("Time")]
        $inputTime
    )

#Get current script folder
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$scriptPath
$dashPath = "$scriptPath\Dashboard"
$jsonPath = "$dashPath\JSON"


#Function to pull in configuration information from the config file
Function configurationImport () {
    If (Test-Path ("$scriptPath\config.xml")) {
        Return Import-Clixml -Path "$scriptPath\config.xml"
    } else {
        Return "Error gathering configuration information from xml file"
    }
}

function AuthDetailsImport () {
    # Define variables
    $Directory = $scriptPath
    $KeyFile = Join-Path $Directory  "AES_KEY_FILE.key"
    $PasswordFile = Join-Path $Directory "AES_PASSWORD_FILE.pass"

    # Read the secure password from a password file and decrypt it to a normal readable string
    $SecurePassword = ( (Get-Content $PasswordFile) | ConvertTo-SecureString -Key (Get-Content $KeyFile) )        # Convert the standard encrypted password stored in the password file to a secure string using the AES key file
    $Credentials = New-Object System.Management.Automation.PSCredential ($authServiceAccount, $SecurePassword)
    Return $Credentials
}

#Pull in all configuration information
$configInfo = configurationImport

#Set all variables for the script
$performanceThreadsMax = $configInfo.performanceThreadsMax
$performanceIndividual = $configInfo.performanceIndividual
$performanceOverall = $configInfo.performanceOverall
$performanceScaling = $configInfo.performanceScaling
$citrixController = $configInfo.citrixController
$machineDetection = $configInfo.machineDetection
$machinePrefix = $configInfo.machinePrefix
$machineDeliveryGroups = $configInfo.machineDeliveryGroups
$machineCatalogs = $configInfo.machineCatalogs
$machineTags = $configInfo.machineTags
$businessStartTime =  $configInfo.businessStartTime
$businessCloseTime = $configInfo.businessCloseTime
$outOfHoursMachines = $configInfo.outOfHoursMachines
$inHoursMachines = $configInfo.inHoursMachines
$machineScaling = $configInfo.machineScaling
$farmCPUThreshhold = $configInfo.farmCPUThreshhold
$farmMemoryThreshhold = $configInfo.farmMemoryThreshhold
$farmIndexThreshhold = $configInfo.farmIndexThreshhold
$farmSessionThreshhold = $configInfo.farmSessionThreshhold
$dashboardBackupTime = $configInfo.dashboardBackupTime
$dashboardRetention = $configInfo.dashboardRetention
$scriptRunInterval = New-TimeSpan -Minutes $configInfo.scriptRunInterval
$LogNumberOfDays = $configInfo.LogNumberOfDays
$logLocation = $configInfo.logLocation
$forceUserLogoff = $configInfo.forceUserLogoff
$userLogoffFirstInterval = $configInfo.userLogoffFirstInterval
$userLogoffFirstMessage = $configInfo.userLogoffFirstMessage
$userLogoffSecondInterval = $configInfo.userLogoffSecondInterval
$userLogoffSecondMessage = $configInfo.userLogoffSecondMessage
$smtpServer = $configInfo.smtpServer
$smtpToAddress = $configInfo.smtpToAddress
$smtpFromAddress = $configInfo.smtpFromAddress
$smtpSubject = $configInfo.smtpSubject
$testingOnly = $configInfo.testingOnly
$exclusionTag = $configInfo.exclusionTag
$authServiceAccount = $configInfo.authServiceAccount
#Add a script run interval variable, must be filled in for comparison of dashboard backup
#Add a dashboard backup variable, the time the dashboard files should be backed up

#Set value for JSON files missing to false as its used in comparison
$jsonMissing = $false

#Set array of file names for JSON files
$jsonFileTable = "times.json","machinesOn.json","machinesScaled.json","machinesMaintenance.json","machinesExcluded.json","farmCPU.json","farmMemory.json","farmIndex.json","farmSession.json"

#Get current date in correct format
$dateNow = $(Get-Date -Format dd/MM/yy).ToString()

#Setup a time object for comparison taking into account the input time for testing
if ($inputTime) {
    $inputDate = $([datetime]::ParseExact("$inputTime", "dd/MM/yyyy HH:mm", $null)).ToShortDateString()

    $timesObj = [PSCustomObject]@{
        startTime = [datetime]::ParseExact($("$($inputDate) $($businessStartTime)"), "dd/MM/yyyy HH:mm", $null)
        endTime = [datetime]::ParseExact($("$($inputDate) $($businessCloseTime)"), "dd/MM/yyyy HH:mm", $null)
        backupTime = [datetime]::ParseExact($("$($inputDate) $($dashboardBackupTime)"), "dd/MM/yyyy HH:mm", $null)
        timeNow = $([datetime]::ParseExact("$inputTime", "dd/MM/yyyy HH:mm", $null))
    }
} else {
    $timesObj = [PSCustomObject]@{
        startTime = [datetime]::ParseExact($("$($dateNow) $($businessStartTime)"), "dd/MM/yy HH:mm", $null)
        endTime = [datetime]::ParseExact($("$($dateNow) $($businessCloseTime)"), "dd/MM/yy HH:mm", $null)
        backupTime = [datetime]::ParseExact($("$($dateNow) $($dashboardBackupTime)"), "dd/MM/yy HH:mm", $null)
        timeNow = $(Get-Date)
    }
}

#Load Citrix Snap-ins
Add-PSSnapin Citrix*

#Function to parse log file and pull out any errors to be populated into the Dashboard
Function GatherErrors() {
    #Log folder
    $currentLog = Get-ChildItem -Path "$(Split-Path -Path $logLocation)\*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        #Check for the existence of the latest logfile
    if(test-path $currentLog) {
        $logcontent = Get-Content $currentLog
        $allErrors = $logcontent | Where-Object {$_.ToString() -match '^.*ERROR.*$'}
    }
    if ($allErrors) {
        return $allErrors
    } else {
        return "No Errors Recorded"
    }
}

#Function to generate Dashboards
Function GenerateDashboard() {
    #Check if the json folder exists
    if (test-path $jsonPath) {
    $jsonData = [System.Collections.ArrayList]::new()
    foreach ($jsonFile in $jsonFileTable) {
        #Test if we can get to each json file and it already exists
        if (Test-Path "$jsonPath\$jsonFile") {
                $readData = [PSCustomObject]@{$jsonFile=[PSCustomObject]@{json = $(Get-Content "$jsonPath\$jsonFile" | ConvertFrom-Json -Verbose)}}
                $jsonData.Add($readData)
            } else {
                #Logout which files were missing
                WriteLog -Message "JSON folder exists but JSON file $jsonFile is missing" -Level Warn
                $jsonMissing = $true
            }
        }

        if (!$jsonMissing) {
            #Add a value into the array
            $jsonData.'times.json'.json.labels += $(@($timesObj.timeNow.ToShortTimeString() + "-" + $timesObj.timeNow.ToShortDateString()))
            $jsonData.'machinesOn.json'.json.data += $machinesOnAndNotMaintenance.DNSName.count
            $jsonData.'machinesScaled.json'.json.data += $machinesScaled.DNSName.count
            $jsonData.'machinesMaintenance.json'.json.data += $machinesMaintenance.DNSName.count
            $jsonData.'machinesExcluded.json'.json.data += $machinesExcluded.DNSName.count
            $jsonData.'farmCPU.json'.json.data += $overallPerformance.overallCPU.Average
            $jsonData.'farmMemory.json'.json.data += $overallPerformance.overallMemory.Average
            $jsonData.'farmIndex.json'.json.data += $overallPerformance.overallIndex.Average
            $jsonData.'farmSession.json'.json.data += $overallPerformance.overallSession.Average
        } else {
            #Remove JSON files and log out what is happening
            Remove-Item -Path $jsonPath -Force
            WriteLog -Message "JSON folder deleted, dashboard metrics will reset" -Level Warn
        }
    } else {
        #Create JSON Object Array
        $jsonData = [System.Collections.ArrayList]::new()

        #Create the subfolder
        New-Item -ItemType Directory -Path "$scriptPath\Dashboard" -Name JSON
        New-Item -ItemType Directory -Path $scriptPath -Name Dashboard

        #Create the JSON file
        foreach ($jsonFile in $jsonFileTable) {
            New-Item -ItemType File -Path $jsonPath -Name $jsonFile
        }

        $readData = [PSCustomObject]@{'times.json'=[PSCustomObject]@{json=[PSCustomObject]@{labels = @($timesObj.timeNow.ToShortTimeString() + "-" + $timesObj.timeNow.ToShortDateString())}}}
        $jsonData.Add($readData)
        $readData = [PSCustomObject]@{'machinesOn.json'=[PSCustomObject]@{json=[PSCustomObject]@{data = @($machinesOnAndNotMaintenance.DNSName.count)}}}
        $jsonData.Add($readData)
        $readData = [PSCustomObject]@{'machinesScaled.json'=[PSCustomObject]@{json=[PSCustomObject]@{data = @($machinesScaled.DNSName.count)}}}
        $jsonData.Add($readData)
        $readData = [PSCustomObject]@{'machinesMaintenance.json'=[PSCustomObject]@{json=[PSCustomObject]@{data = @($machinesMaintenance.DNSName.count)}}}
        $jsonData.Add($readData)
        $readData = [PSCustomObject]@{'machinesExcluded.json'=[PSCustomObject]@{json=[PSCustomObject]@{data = @($machinesExcluded.DNSName.count)}}}
        $jsonData.Add($readData)
        $readData = [PSCustomObject]@{'farmCPU.json'=[PSCustomObject]@{json=[PSCustomObject]@{data = @($overallPerformance.overallCPU.Average)}}}
        $jsonData.Add($readData)
        $readData = [PSCustomObject]@{'farmMemory.json'=[PSCustomObject]@{json=[PSCustomObject]@{data = @($overallPerformance.overallMemory.Average)}}}
        $jsonData.Add($readData)
        $readData = [PSCustomObject]@{'farmIndex.json'=[PSCustomObject]@{json=[PSCustomObject]@{data = @($overallPerformance.overallIndex.Average)}}}
        $jsonData.Add($readData)
        $readData = [PSCustomObject]@{'farmSession.json'=[PSCustomObject]@{json=[PSCustomObject]@{data = @($overallPerformance.overallSession.Average)}}}
        $jsonData.Add($readData)
    }

    foreach ($jsonFile in $jsonFileTable) {
        $jsonData.$jsonFile.json | ConvertTo-Json | Set-Content "$jsonPath\$jsonFile"
    }

     #Replacements in javascript for graph data
    $jsScript = Get-Content "$scriptPath\Template\script_template.js"
    $jsScript = $jsScript.Replace("<TIMESJSON>",$($jsonData.'times.json'.json | ConvertTo-Json).Replace("}",""))
    $jsScript = $jsScript.Replace("<MACHINESONDATA>",$($jsonData.'machinesOn.json'.json | ConvertTo-Json).Replace("{","").Replace("}",""))
    $jsScript = $jsScript.Replace("<MACHINESSCALEDATA>",$($jsonData.'machinesScaled.json'.json | ConvertTo-Json).Replace("{","").Replace("}",""))
    $jsScript = $jsScript.Replace("<MACHINESMAINTDATA>",$($jsonData.'machinesMaintenance.json'.json | ConvertTo-Json).Replace("{","").Replace("}",""))
    $jsScript = $jsScript.Replace("<MACHINESEXCLDATA>",$($jsonData.'machinesExcluded.json'.json | ConvertTo-Json).Replace("{","").Replace("}",""))
    $jsScript = $jsScript.Replace("<CPUDATA>",$($jsonData.'farmCPU.json'.json | ConvertTo-Json).Replace("{","").Replace("}",""))
    $jsScript = $jsScript.Replace("<MEMORYDATA>",$($jsonData.'farmMemory.json'.json | ConvertTo-Json).Replace("{","").Replace("}",""))
    $jsScript = $jsScript.Replace("<INDEXDATA>",$($jsonData.'farmIndex.json'.json | ConvertTo-Json).Replace("{","").Replace("}",""))
    $jsScript = $jsScript.Replace("<SESSIONDATA>",$($jsonData.'farmSession.json'.json | ConvertTo-Json).Replace("{","").Replace("}",""))
    $jsScript | Set-Content "$scriptPath\Dashboard\script.js"

    #Replacements in HTML for configuration data
    $HTML = Get-Content "$scriptPath\Template\dashboard_template.html"
    $HTML = $HTML.Replace('&lt;Controller&gt;',$citrixController)
    if ($machineDetection -eq "prefix") {
        $HTML = $HTML.Replace('&lt;DetectionValue&gt;',"Machine Prefix")
        $HTML = $HTML.Replace('&lt;DetectionEntries&gt;',$machinePrefix)
    }
    if ($machineDetection -eq "dg") {
        $HTML = $HTML.Replace('&lt;DetectionValue&gt;',"Delivery Group")
        $HTML = $HTML.Replace('&lt;DetectionEntries&gt;',$machineDeliveryGroups)
    }
    if ($machineDetection -eq "mc") {
        $HTML = $HTML.Replace('&lt;DetectionValue&gt;',"Machine Catalog")
        $HTML = $HTML.Replace('&lt;DetectionEntries&gt;',$machineCatalogs)
    }
    if($machineDetection -eq "tag") {
        $HTML = $HTML.Replace('&lt;DetectionValue&gt;',"Machine Tags")
        $HTML = $HTML.Replace('&lt;DetectionEntries&gt;',$machineTags)
    }
    $HTML = $HTML.Replace('&lt;Controller&gt;',$citrixController)
    $HTML = $HTML.Replace('&lt;TestValue&gt;',$(if ($testingOnly) {"Test Mode"}else{"Live Mode"}))
    $HTML = $HTML.Replace('&lt;PefixValue&gt;',$machinePrefix)
    $HTML = $HTML.Replace('&lt;StartTime&gt;',$businessStartTime)
    $HTML = $HTML.Replace('&lt;EndTime&gt;',$businessCloseTime)
    $HTML = $HTML.Replace('&lt;InHoursMachines&gt;',$inHoursMachines)
    $HTML = $HTML.Replace('&lt;OutHoursMachines&gt;',$outOfHoursMachines)
    $HTML = $HTML.Replace('&lt;ScalingMode&gt;',$machineScaling)
    $HTML = $HTML.Replace('&lt;MonitoringThreads&gt;',$performanceThreadsMax)
    $HTML = $HTML.Replace('&lt;DashboardRenew&gt;',$dashboardBackupTime)
    $HTML = $HTML.Replace('&lt;DashboardRetention&gt;',$dashboardRetention)
    $HTML = $HTML.Replace('&lt;LogRetention&gt;',$LogNumberOfDays)
    $HTML = $HTML.Replace('&lt;CPUValue&gt;',$overallPerformance.overallCPU.average)
    $HTML = $HTML.Replace('&lt;MemoryValue&gt;',$overallPerformance.overallMemory.average)
    $HTML = $HTML.Replace('&lt;LoadValue&gt;',$overallPerformance.overallIndex.average)
    $HTML = $HTML.Replace('&lt;SessionValue&gt;',$overallPerformance.overallSession.average)
    $HTML = $HTML.Replace('&lt;CPUThresh&gt;',$farmCPUThreshhold)
    $HTML = $HTML.Replace('&lt;MEMThresh&gt;',$farmMemoryThreshhold)
    $HTML = $HTML.Replace('&lt;INDThresh&gt;',$farmIndexThreshhold)
    $HTML = $HTML.Replace('&lt;SESSThresh&gt;',$farmSessionThreshhold)
    $HTML = $HTML.Replace('&lt;ErrorBar&gt;',$(GatherErrors))

    $HTML | Set-Content "$scriptPath\Dashboard\Dashboard.html"

    if (-Not (Test-Path "$scriptPath\Dashboard\chart.min.js")) {
        Copy-Item -Path "$scriptPath\Template\chart.min.js" -Destination "$scriptPath\Dashboard\chart.min.js"
    }
}

#Function to Update Dashboard File Navigation Links
Function UpdateDashboardNavigation {
    #Get a list of all html files in the Dashboard folder
    $htmlFiles = Get-ChildItem -Path ("$scriptPath\Dashboard\Dashboard-*.html") | Sort-Object Name

    #Create first link in HTML Nav links
    $htmlNav="<A HREF=Dashboard.html>Current</A>&nbsp;&nbsp;"

    #Loop to generate html text
    foreach ($htmlFile in $htmlFiles) {
            $htmlNav = $htmlNav + "<A HREF=`"$($htmlFile.Name)`">$($($($htmlFile.Name).Replace('Dashboard-','')).replace('.html',''))</A>&nbsp;&nbsp;"
        }

    foreach ($htmlFile in $htmlFiles) {
        $(Get-Content -Path $htmlFile.FullName) -replace '(?<=<nav>).*?(?=</nav)', $htmlNav | Set-Content -Path $htmlFile.FullName
    }

    $(Get-Content -Path "$dashPath\Dashboard.html") -replace '(?<=<nav>).*?(?=</nav)', $htmlNav | Set-Content -Path "$dashPath\Dashboard.html"
}

#Function to control Dashboard retention
Function CircularDashboard() {

    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true, HelpMessage = "How many historical dashboards to store")]
        [ValidateNotNullOrEmpty()]
        [Alias("DashRetention")]
        [int]$retention

    )

    Begin
    {
        # Set VerbosePreference to Continue so that verbose messages are displayed.
        $VerbosePreference = 'Continue'
        WriteLog -Message "Start Circular Dashboard Management" -Level Info
    }
    Process
    {
        #Find all HTML files
        $htmlFiles = Get-ChildItem ("$scriptPath\Dashboard\*.html") | Sort-Object CreationTime
        #Find all javascript files
        $jscriptFiles = Get-ChildItem ("$scriptPath\Dashboard\*.js") -Exclude "*chart.min.js*" | Sort-Object CreationTime
        #Find all currently backed up Dashboard files
        $htmlFilesCopied = Get-ChildItem ("$scriptPath\Dashboard\Dashboard-*.html") | Sort-Object CreationTime

        #Write to log, files found
        WriteLog -Message "$($htmlFilesCopied.count) html files found" -Level Info
        WriteLog -Message "$($jscriptFiles.count) js files found" -Level Info
        WriteLog -Message "Number of dashboards to retain $retention" -Level Info

        #Trigger retention to create the backup of the dashboard
        If ($htmlFilesCopied.count -lt $retention) {
            #Log out that a new dashboard in being generated
            WriteLog -Message "New Dashboard being generated as we are not over the retention amount of $retention" -Level Info

            #Remove older JSON files
            Get-ChildItem -Path "$jsonPath\*.json" | Remove-Item

            #Grab html file contents and make replacements before renaming
            (Get-Content -Path "$scriptPath\Dashboard\Dashboard.html").Replace("script.js","script-$($timesObj.timeNow.ToShortDateString().Replace("/","-")).js") | Set-Content -Path "$scriptPath\Dashboard\Dashboard.html"

            #Create a backup of the current dashboard
            Rename-Item -Path "$scriptPath\Dashboard\Dashboard.html" -NewName "Dashboard-$($timesObj.timeNow.ToShortDateString().Replace("/","-")).html"
            Rename-Item -Path "$scriptPath\Dashboard\script.js" -NewName "script-$($timesObj.timeNow.ToShortDateString().Replace("/","-")).js"
        }

        #There are already enough dashboards, remove some of the old ones
        If ($htmlFilesCopied.count -ge $retention) {
            #Log out that the retention period is being triggered
            WriteLog -Message "Existing Dashboard being recycled as we are over the retention amount of $retention with $($htmlFilesCopied.count)" -Level Info

            #Remove older JSON files
            Get-ChildItem -Path "$jsonPath\*.json" | Remove-Item

            #Check how many log files we have
            If ($htmlFiles.count -ge $retention) {
                #Calculate files to remove
                $filesToRemove = $htmlFiles | Sort-Object CreationTime | Select-Object -First $($htmlFiles.count - $retention)
                WriteLog -Message "There are $($htmlFiles.count) dashboard backups and we want $retention, deleting $($htmlFiles.count - $retention)" -Level Info
                foreach ($file in $filesToRemove) {
                    $file | Remove-Item
                    WriteLog -Message "Older dashboard files removed $file" -Level Info
                }
            }
            If ($jscriptFiles.count -ge $retention) {
                #Calculate files to remove
                $filesToRemove = ($jscriptFiles) | Sort-Object CreationTime | Select-Object -First $($jscriptFiles.count - $retention)
                WriteLog -Message "There are $($jscriptFiles.count) dashboard backups and we want $retention, deleting $($jscriptFiles.count - $retention)" -Level Info
                foreach ($file in $filesToRemove) {
                    $file | Remove-Item
                    WriteLog -Message "Older javascript files removed $file" -Level Info
                }
            }

            #Now create a new Dashboard as we've recycled the old one
            WriteLog -Message "Dashboard being generated as we have just recycled the last one" -Level Info

            #Remove older JSON files
            Get-ChildItem -Path "$jsonPath\*.json" | Remove-Item

            #Grab html file contents and make replacements before renaming
            (Get-Content -Path "$scriptPath\Dashboard\Dashboard.html").Replace("script.js","script-$($timesObj.timeNow.ToShortDateString().Replace("/","-")).js") | Set-Content -Path "$scriptPath\Dashboard\Dashboard.html"

            #Create a backup of the current dashboard
            Rename-Item -Path "$scriptPath\Dashboard\Dashboard.html" -NewName "Dashboard-$($timesObj.timeNow.ToShortDateString().Replace("/","-")).html"
            Rename-Item -Path "$scriptPath\Dashboard\script.js" -NewName "script-$($timesObj.timeNow.ToShortDateString().Replace("/","-")).js"

            WriteLog -Message "Completed Circular Dashboard Management" -Level Info
        }
    }
    End
    {
    }
}

#Function to create a log file
Function WriteLog() {

    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true, HelpMessage = "The error message text to be placed into the log.")]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,

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
        $logLocation = $logLocation + "_" + $DateForLogFileName+".log"

        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path.
        If (!(Test-Path $logLocation)) {
            Write-Verbose "Creating $logLocation."
            New-Item $logLocation -Force -ItemType File
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
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $logLocation -Append
    }
    End
    {
    }
}

Function CircularLogging() {

    Begin
    {
        # Set VerbosePreference to Continue so that verbose messages are displayed.
        $VerbosePreference = 'Continue'
    }
    Process
    {
        $Path = Split-Path -Path $logLocation
        WriteLog -Message "Start Circular Log Management" -Level Info
        #Get all log files in the log folder with .log extension, select the oldest ones past the specified retention number and remove them
        $files = Get-ChildItem ("$Path\*.log") | Sort-Object CreationTime
        #Check how many log files we have
        If ($files.count -gt $LogNumberOfDays) {
            #Calculate files to remove
            $filesToRemove = Get-ChildItem ("$Path\$LogTypeToProcess*.log") | Sort-Object CreationTime | Select-Object -First $($files.count - $LogNumberOfDays)
            $filesToRemove
            foreach ($file in $filesToRemove) {
                $file | Remove-Item
                WriteLog -Message "Log file removed $file" -Level Info
            }
            WriteLog -Message "Completed Circular Log Management" -Level Info
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
            WriteLog -Message "Sending out an email with an attachment." -Level Info
        } else {
            # Send email message without attachment
            Send-MailMessage -SmtpServer $smtpServer -From $fromAddress -To $toAddress -Subject $("$subject - $Level") -Body "$FormattedDate $LevelText $Message"
            WriteLog -Message "Sending out an email without an attachment, attachment did not exist." -Level Warn
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
    If (($timesObj.timeNow.Hour -lt $timesObj.startTime.Hour) -or (($timesobj.timeNow.hour -eq $timesObj.startTime.hour) -and ($timesobj.timeNow.Minute -lt $timesObj.startTime.Minute))) {
        Return "OutOfHours" #OutOfHours Too Early
    }
    if (($timesObj.timeNow.hour -gt $timesObj.endTime.hour) -or (($timesObj.timeNow.Hour -eq $timesObj.endTime.hour) -and ($timesObj.timeNow.Minute -gt $timesObj.endTime.Minute))) {
        Return "OutofHours" #Out of Hours - Too Late
    }
    Return "InsideOfHours" #Dont OutOfHours as we are inside working hours
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
                WriteLog -Message "CPU Threshhold of $farmCPUThreshhold is lower than current farm average of $($overallPerformance.overallCPU.average), we need to spin up an additional machine" -Level Info -Verbose
            }
        } elseif ($machineScaling -eq "Memory") {
            If ($($overallPerformance.overallMemory.Average) -gt $farmMemoryThreshhold) {
                $scalingFactor = 1
                WriteLog -Message "Memory Threshhold of $farmMemoryThreshhold is lower than current farm average of $($overallPerformance.overallMemory.Average), we need to spin up an additional machine" -Level Info -Verbose
            }
        } elseif ($machineScaling -eq "Index") {
            If ($($overallPerformance.overallIndex.Average) -gt $farmIndexThreshhold) {
                $scalingFactor = 1
                WriteLog -Message "Index Threshhold of $farmIndexThreshhold is lower than current farm average of $($overallPerformance.overallIndex.Average), we need to spin up an additional machine" -Level Info -Verbose
            }
        } elseif ($machineScaling -eq "Session") {
                If ($($overallPerformance.overallSession.Average) -gt $farmSessionThreshhold) {
                    $scalingFactor = 1
                    WriteLog -Message "Session Threshhold of $farmSessionThreshhold is lower than current farm average of $($overallPerformance.overallSession.Average), we need to spin up an additional machine" -Level Info -Verbose
                }
        } else {
            WriteLog -Message "There is an error in the config for the machine scaling variable as no case was recognised for sclaing - current variable = $machineScaling" -Level Error -Verbose
        }

        #Check the supplied machines levels against what is required
        #Return an object with the action required (Startup, Shutdown, Nothing and the amount of machines necessary to do it to)
        If (($currentMachines -gt $targetMachines) -and ($scalingFactor -eq 0)) {
            $action = [PSCustomObject]@{
                Task = "Shutdown"
                Number = $($currentMachines - $targetMachines)
            }
            WriteLog -Message "The current number of powered on machines is $currentMachines and the target is $targetMachines - resulting action is to $($action.Task) $($action.Number) machines" -Level Info -Verbose
        } elseif ($currentMachines -lt $targetMachines) {
            $action = [PSCustomObject]@{
                Task = "Startup"
                Number = $($targetMachines - $currentMachines)
            }
            WriteLog -Message "The current number of powered on machines is $currentMachines and the target is $targetMachines - resulting action is to $($action.Task) $($action.Number) machines" -Level Info -Verbose
        } elseif (($currentMachines -ge $targetMachines)) {
            $action = [PSCustomObject]@{
                Task = "Scaling"
                Number = 0 + $scalingFactor
            }
            WriteLog -Message "The current number of powered on machines is $currentMachines and the target is $targetMachines - resulting action is to perform Scaling calculations" -Level Info -Verbose

        }
        Return $action
}

#Function to get a list of all machines and current states from Broker
Function brokerMachineStates() {
    Return Get-BrokerMachine -AdminAddress $citrixController -MaxRecordCount 9999
}

#Function to get a list of all sessions and current state from Broker
Function brokerUserSessions() {

    [CmdletBinding()]
    Param
    (
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
        WriteLog -Message "Machine action for $machineName - $machineAction in $delay minutes" -Level Info
        If (!$testingOnly) {New-BrokerDelayedHostingPowerAction -AdminAddress $citrixcontroller -MachineName $machineName -Action $machineAction -Delay $(New-TimeSpan -Minutes $delay) }

    } else {
        WriteLog -Message "Machine action for $machineName - $machineAction immediately" -Level Info
        If (!$testingOnly) {New-BrokerHostingPowerAction -AdminAddress $citrixcontroller -MachineName $machineName -Action $machineAction}
    }

    #Remove the scaling tag if one exists
    if (Get-BrokerTag -MachineUid $(Get-BrokerMachine -MachineName $machineName).uid) {
        WriteLog -Message "Remove Scaling tag from $machineName" -Level Info
        Remove-BrokerTag "Scaled-On" -Machine $machineName
    }
}

Function maintenance() {
    [CmdletBinding()]
    Param
    (
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
            WriteLog -Message "There was an error placing $($machine.DNSName) into maintenance mode" -Level Error
            SendEmail -smtpServer $smtpServer -toAddress $smtpToAddress -fromAddress $smtpFromAddress -subject $smtpSubject -Message "There was an error placing $($machine.DNSName) into maintenance mode" -attachment $logLocation -Level Error
        }
    } elseif ($maintenanceMode -eq "Off") {
        try {
            If (!$testingOnly) {Set-BrokerMachineMaintenanceMode -AdminAddress $citrixController -InputObject $machine -MaintenanceMode $false}
        } catch {
            WriteLog -Message "There was an error taking $($machine.DNSName) out of maintenance mode" -Level Error
            SendEmail -smtpServer $smtpServer -toAddress $smtpToAddress -fromAddress $smtpFromAddress -subject $smtpSubject -Message "There was an error taking $($machine.DNSName) out of maintenance mode" -attachment $logLocation -Level Error
        }
    }
}

#Function to receive a list of sessions in an object and logoff all the disconnected sessions
Function sessionLogOff() {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true, HelpMessage = "List of disconnected sessions to be logged off")]
        [ValidateNotNullOrEmpty()]
        [object]$sessions
    )
    #Do some logging off of disconnected sessions
    WriteLog -Message "Logging off all disconnected sessions in one hit" -Level Info
    foreach ($session in $sessions) {
        WriteLog -Message "Logging off $($session.UserName)" -Level Info
        If (!$testingOnly) {Stop-BrokerSession -InputObject $session}
    }
}

#Function that sends a message to active users that are running on machines and then log them off
Function sendMessage () {
    [CmdletBinding()]
    Param
    (
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
    WriteLog -Message "Sending message to users to log off - $($firstMessageInterval) minute warning on" -Level Info
    If (!$testingOnly) {Send-BrokerSessionMessage -AdminAddress $citrixController -InputObject $sessions -MessageStyle "Information" -Title "Server Scheduled Shutdown" -Text "$firstMessage $(" - A reminder will be sent in $firstMessageInterval") mins"}
    #Wait for the interval time
    If (!$testingOnly) {start-sleep -seconds ($firstMessageInterval*60)}

    #Sending the initial message for users to logoff
    WriteLog -Message "Sending message to users to log off - $($secondMessageInterval) minute warning" -Level Info
    If (!$testingOnly) {Send-BrokerSessionMessage -InputObject $sessions -MessageStyle "Critical" -Title "Server Scheduled Shutdown " -Text "$secondMessage $(" - Shutdown will occur in $secondMessageInterval") mins"}
    #Wait for the interval time
    If (!$testingOnly) {start-sleep -seconds ($secondMessageInterval*60)}

    WriteLog -Message "Logging off all active user sessions after sending messages at $($firstMessageInterval) minutes and then $($secondMessageInterval) minutes" -Level Info
    If (!$testingOnly) { $sessions | Stop-BrokerSession }
}

Function performanceAnalysis () {
    [CmdletBinding()]

    param(
    [Parameter(Mandatory=$true, HelpMessage = "Machines to enumerate")]
    [ValidateNotNullOrEmpty()]
    [array]$machines,

    [Parameter(Mandatory=$true, HelpMessage = "Export location for individual machine performance details")]
    [ValidateNotNullOrEmpty()]
    [string]$exportLocation,

    [Parameter(Mandatory=$true, HelpMessage = "Export location for overall average machine performance details")]
    [ValidateNotNullOrEmpty()]
    [string]$overallExportLocation
)

#Check variables for any known issue
If (-not ([String]::IsNullOrEmpty($authServiceAccount))) {
    #authentication account provided check for upn or domain\username
    if ((($authServiceAccount) -match "\\") -or (($authServiceAccount) -match "@")) {
        WriteLog -Message "The authentication account provided is in the correct format, continuing" -Level Info -Verbose
    } else {
        "authentication Account invalid"
        WriteLog -Message "The authentication account provided is not valid for use as it is in an incorrect format, script execution will now stop" -Level Error -Verbose
        Exit
    }
}

#region Runspace Pool
[runspacefactory]::CreateRunspacePool()
$SessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$RunspacePool = [runspacefactory]::CreateRunspacePool(
    1, #Min Runspaces
    $performanceThreadsMax #Max Runspaces
)

$PowerShell = [powershell]::Create()
#Uses the RunspacePool vs. Runspace Property

#Cannot have both Runspace and RunspacePool property used; last one applied wins
$PowerShell.RunspacePool = $RunspacePool
$RunspacePool.Open()
#endregion

#Create an array to store runspace and script instances for later retrieval
$jobs = New-Object System.Collections.ArrayList

#Grab credentialy for performance measurement
$myCreds = If (-not ([String]::IsNullOrEmpty($authServiceAccount))) { AuthDetailsImport }

#Loop through each machine obtained from the broker and gathers its information for scaling puroposes
ForEach ($computer in $machines) {
    #Create parameter object for the runspace scriptblocks
    $Parameters = @{
        computer = $computer
        creds = $myCreds
        controller = $citrixController
    }

    #Check if we have a service account to use, if we do check access for each machine, otherwise run in current user context
    If  (-not ([String]::IsNullOrEmpty($authServiceAccount))) {
        #Only gather performance metrics for machines that we have access to
        WriteLog -Message "Starting performance measurement job for $computer using specified credentials" -Level Info -Verbose

        #Check connection using CIM for performance measurements and run the performance measurement
        if ($cimSession = New-CimSession -Credential $myCreds -ComputerName $computer) {
            WriteLog -Message "CIM Connection test for $computer successful" -Level Info -Verbose

            #Remove the session as it needs to be recreated in the RunSpace script
            Remove-CimSession -CimSession $cimSession

            #Create a runspace for each job running
            $PowerShell = [powershell]::Create()
            $PowerShell.RunspacePool = $RunspacePool

            #Get the Thread ID of the script
            $ThreadID = [appdomain]::GetCurrentThreadId()
            Write-Verbose “ThreadID: Beginning $ThreadID” -Verbose

            #Create the script that will run
            [void]$PowerShell.AddScript({
                Param (
                    $computer,
                    $creds,
                    $controller
                )

                #Load the Citrix snap-ins
                Add-PSSnapin Citrix*

                $ThreadID = [appdomain]::GetCurrentThreadId()
                Write-Verbose “ThreadID: Beginning $ThreadID” -Verbose
                $cimSession = New-CimSession -ComputerName $computer -Credential $creds

                [pscustomobject]@{
                    Computer = $computer
                    CPU = (Get-CimInstance -CimSession $cimSession -ClassName CIM_Processor | Select-Object LoadPercentage | Select-Object -ExpandProperty LoadPercentage)
                    Memory = (Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object @{ Name = 'Memory';  Expression = {[int](($($_.TotalVisibleMemorySize - $_.FreePhysicalMemory) / $_.TotalVisibleMemorySize)  * 100)}} | Select-Object -ExpandProperty Memory)
                    LoadIndex = (Get-BrokerMachine -AdminAddress $controller | Where-Object {$_.DNSName -eq $computer}) | Select-Object -expand LoadIndex
                    Sessions = (Get-BrokerMachine -AdminAddress $controller | Where-Object {$_.DNSName -eq $computer}) | Select-Object -expand SessionCount
                    Thread = $ThreadID
                    ProcessID = $PID
                }
                Write-Verbose "ThreadID: Ending $ThreadID" -Verbose

            })

            #Add the parameter block to the script
            [void]$PowerShell.AddParameters($Parameters)

            #Kick off the runspace script
            $Handle = $PowerShell.BeginInvoke()

            #create an object to store the runspace instance and script instance (PowerShell is runspace and Handle is the script)
            $temp = "" | Select-Object PowerShell,Handle

            #Set the PowerShell instance in the object just created
            $temp.PowerShell = $PowerShell

            #Set the script instance in the object just created
            $temp.handle = $Handle

            #Add the object with instances to the array
            [void]$jobs.Add($Temp)

            #Write out what the status is of the jobs
            "Available Runspaces in RunspacePool: {0}" -f $RunspacePool.GetAvailableRunspaces()
            "Remaining Jobs: {0}" -f @($jobs | Where-Object {$_.handle.iscompleted -ne 'Completed'}).Count
        } else {
            WriteLog -Message "Error during CIM connection test for $computer not successful" -Level Warn -Verbose
        }
    } elseif (([String]::IsNullOrEmpty($authServiceAccount))) {
        if ($cimSession = New-CimSession -ComputerName $computer) {
            WriteLog -Message "CIM Connection test for $computer successful using script run credentials" -Level Info -Verbose
            WriteLog -Message "Starting performance measurement job for $computer using script run credentials" -Level Info -Verbose

            #Remove the session as it needs to be recreated in the RunSpace script
            Remove-CimSession -CimSession $cimSession

            #Create a runspace for each job running
            $PowerShell = [powershell]::Create()
            $PowerShell.RunspacePool = $RunspacePool

            #Get the Thread ID of the script
            $ThreadID = [appdomain]::GetCurrentThreadId()
            Write-Verbose “ThreadID: Beginning $ThreadID” -Verbose

            #Create the script that will run
            [void]$PowerShell.AddScript({
                Param (
                    $computer,
                    $creds,
                    $controller
                )

                #Load the Citrix snap-ins
                Add-PSSnapin Citrix*

                $ThreadID = [appdomain]::GetCurrentThreadId()
                Write-Verbose “ThreadID: Beginning $ThreadID” -Verbose
                $cimSession = New-CimSession -ComputerName $computer

                [pscustomobject]@{
                    Computer = $computer
                    CPU = Get-CimInstance -CimSession $cimSession -ClassName CIM_Processor | Select-Object LoadPercentage | Select-Object -ExpandProperty LoadPercentage
                    Memory = (Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object @{ Name = 'Memory';  Expression = {[int](($($_.TotalVisibleMemorySize - $_.FreePhysicalMemory) / $_.TotalVisibleMemorySize)  * 100)}} | Select-Object -ExpandProperty Memory)
                    LoadIndex = (Get-BrokerMachine -AdminAddress $controller | Where-Object {$_.DNSName -eq $computer}) | Select-Object -expand LoadIndex
                    Sessions = (Get-BrokerMachine -AdminAddress $controller | Where-Object {$_.DNSName -eq $computer}) | Select-Object -expand SessionCount
                    Thread = $ThreadID
                    ProcessID = $PID
                }
                Write-Verbose "ThreadID: Ending $ThreadID" -Verbose
            })

            #Add the parameter block to the script
            [void]$PowerShell.AddParameters($Parameters)

            #Kick off the runspace script
            $Handle = $PowerShell.BeginInvoke()

            #create an object to store the runspace instance and script instance (PowerShell is runspace and Handle is the script)
            $temp = "" | Select-Object PowerShell,Handle

            #Set the PowerShell instance in the object just created
            $temp.PowerShell = $PowerShell

            #Set the script instance in the object just created
            $temp.handle = $Handle

            #Add the object with instances to the array
            [void]$jobs.Add($Temp)

            #Write out what the status is of the jobs
            "Available Runspaces in RunspacePool: {0}" -f $RunspacePool.GetAvailableRunspaces()
            "Remaining Jobs: {0}" -f @($jobs | Where-Object {$_.handle.iscompleted -ne 'Completed'}).Count

        } else {
            WriteLog -Message "Error during CIM connection test using script run credentials for $computer not successful" -Level Warn -Verbose
        }
    }
}
    #Verify completed - Echo out a final status after all jobs have executed
    “Available Runspaces in RunspacePool: {0}” -f $RunspacePool.GetAvailableRunspaces()
    “Remaining Jobs: {0}” -f @($jobs | Where-Object {$_.handle.iscompleted -ne ‘Completed’}).Count

    #Check if we have jobs to process
    if ($jobs) {

    #Wait for all jobs to complete with a 5 second wait inbetween checks
        Do {
            Start-Sleep -Seconds 5
        } until ($($jobs.Handle | Where-Object {$_.IsCompleted -eq $False}).count -eq 0)

        $Metrics = $jobs | ForEach-Object {
            #Cleanup the job in the runspace
            $_.PowerShell.EndInvoke($_.Handle)
            #Cleanup the run space itself
            $_.PowerShell.Dispose()
        }

        #Clear out array
        $jobs.clear()

        #Clear out all existing runspaces except the default
        foreach ($runspace in $(Get-Runspace | Where-Object {$_.State -eq "Closed"})) {
            $runspace.Dispose()
        }
    }

#Export metrics as XML to be read into another scripts as an object
$Metrics | Export-Clixml -Path $exportLocation
$Metrics | Select-Object *

#Custom object for overall averages
$overallAverage = [PSCustomObject]@{
    overallCPU = $Metrics | Measure-Object -Property CPU -Average -Minimum -Maximum
    overallMemory = $Metrics | Measure-Object -Property Memory -Average -Minimum -Maximum -Sum
    overallIndex = $Metrics | Measure-Object -Property LoadIndex -Average -Minimum -Maximum
    overallSession = $Metrics | Measure-Object -Property Sessions -Average -Minimum -Maximum
}

$overallAverage | Export-Clixml -Path $overallExportLocation
WriteLog -Message "$($overallAverage.overallCPU.Average) - Overall CPU Average" -Level Info
WriteLog -Message "$($overallAverage.overallMemory.Average) - Overall Memory Average" -Level Info
WriteLog -Message "$($overallAverage.overallIndex.Average) - Overall Session Index Average" -Level Info
WriteLog -Message "$($overallAverage.overallSession.Average) - Overall Session Count Average" -Level Info

Return $overallAverage
}

#Force user logoffs out of hours for the specified number of machines
Function forceLogoffShutdown () {
    [CmdletBinding()]

    param(
    [Parameter(Mandatory=$true, HelpMessage = "Number of machines to power off")]
    [ValidateNotNullOrEmpty()]
    [int]$numberMachines

    )

    WriteLog -Message "User logoff mode is set to force, logging all users off of machines that are required to be shutdown" -Level Info
    $machinesToPowerOff = $machinesOnAndNotMaintenance | Sort-Object -Property SessionCount | Select-Object -First $($numberMachines)
    #For everymachine powered on up to the correct number, switch the poweroff
    foreach ($machine in $machinesToPowerOff) {
        #Set the machine in maintenance mode
        WriteLog -Message "Setting $($machine.DNSName) maintenance mode On"
        If (!$testingOnly) { maintenance -machine $machine -maintenanceMode On }
        #Generate a list of sessions per machine
        $logoffSessions = $allUserSessions | Where-Object {$_.MachineName -eq $machine.MachineName}
        WriteLog -Message "Found $($logOffSessions.UserName.Count) user sessions on $($machine.DNSName)"
        #Start a job for each machine so we are not waiting
        If ($($logOffSessions.UserName.Count) -gt 0) {
            #Send a message to all users on the specific server
            WriteLog -Message "Messaging all users on $($machine.MachineName) to logoff"
            If (!$testingOnly) {
                Start-Job -Name $computer -ScriptBlock {
                    param (
                    $userLogoffFirstInterval,
                    $userLogoffFirstMessage,
                    $userLogoffSecondInterval,
                    $userLogoffSecondMessage,
                    $logoffSessions,
                    $logLocation,
                    $citrixController,
                    $machine
                    )

                    #Load the Citrix snap-ins
                    Add-PSSnapin Citrix*

                    #Having to add the WriteLog Function into this
                    Function WriteLog() {

                        [CmdletBinding()]
                        Param
                        (
                            [Parameter(Mandatory=$true, HelpMessage = "The error message text to be placed into the log.")]
                            [ValidateNotNullOrEmpty()]
                            [Alias("LogContent")]
                            [string]$Message,

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
                            $logLocation = $logLocation + "_" + $DateForLogFileName+".log"

                            # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path.
                            If (!(Test-Path $logLocation)) {
                                Write-Verbose "Creating $logLocation."
                                New-Item $logLocation -Force -ItemType File
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
                            "$FormattedDate $LevelText $Message" | Out-File -FilePath $logLocation -Append
                        }
                        End
                        {
                        }
                    }

                    #Having to add the sendMessage Function into this
                    Function sendMessage () {
                        [CmdletBinding()]
                        Param
                        (
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
                        WriteLog -Message "Sending message to users to log off - $($firstMessageInterval) minute warning" -Level Info
                        If (!$testingOnly) {Send-BrokerSessionMessage -AdminAddress $citrixController -InputObject $sessions -MessageStyle "Information" -Title "Server Scheduled Shutdown" -Text "$firstMessage $(" - A reminder will be sent in $firstMessageInterval") mins"}
                        #Wait for the interval time
                        If (!$testingOnly) {start-sleep -seconds ($firstMessageInterval*60)}

                        #Sending the initial message for users to logoff
                        WriteLog -Message "Sending message to users to log off - $($secondMessageInterval) minute warning" -Level Info
                        If (!$testingOnly) {Send-BrokerSessionMessage -InputObject $sessions -MessageStyle "Critical" -Title "Server Scheduled Shutdown " -Text "$secondMessage $(" - Shutdown will occur in $secondMessageInterval") mins"}
                        #Wait for the interval time
                        If (!$testingOnly) {start-sleep -seconds ($secondMessageInterval*60)}

                        WriteLog -Message "Logging off all active user sessions after sending messages at $($firstMessageInterval) minutes and then $($secondMessageInterval) minutes" -Level Info
                        If (!$testingOnly) { $sessions | Stop-BrokerSession }
                    }

                    #Having to add the brokerAction Function into this
                    Function brokerAction() {

                        [CmdletBinding()]
                        Param
                        (
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
                            WriteLog -Message "Machine action for $machineName - $machineAction in $delay minutes" -Level Info
                            If (!$testingOnly) {New-BrokerDelayedHostingPowerAction -AdminAddress $citrixcontroller -MachineName $machineName -Action $machineAction -Delay $(New-TimeSpan -Minutes $delay) }
                        } else {
                            WriteLog -Message "Machine action for $machineName - $machineAction immediately" -Level Info
                            If (!$testingOnly) {New-BrokerHostingPowerAction -AdminAddress $citrixcontroller -MachineName $machineName -Action $machineAction}
                        }
                    }

                    #Send messages to users
                    sendMessage -firstMessageInterval $userLogoffFirstInterval -firstMessage $userLogoffFirstMessage -secondMessageInterval $userLogoffSecondInterval -secondMessage $userLogoffSecondMessage -sessions $logoffSessions

                    #Powerdown the VDA now all users have been messaged
                    brokerAction -machineName $($machine.MachineName) -machineAction Shutdown
                } -ArgumentList $userLogoffFirstInterval, $userLogoffFirstMessage, $userLogoffSecondInterval, $userLogoffSecondMessage, $logoffSessions, $logLocation, $citrixController, $machine
            }
        } else {
            #Session count must be zero so shutdown the machine immediately
            WriteLog -Message "No sessions found on $($machine.DNSName), shutting down"
            brokerAction -machineName $($machine.MachineName) -machineAction Shutdown
        }
    }

#Loop until all running jobs are finished and all users have been messaged
Do {
    $runningJobs = Get-Job | Where-Object {$_.State -ne "Completed"}
    $completedJobs = Get-Job |  Where-Object {$_.State -eq "Completed"}
    ForEach ($job in $completedJobs) {
        Receive-Job $job | Select-Object * -ExcludeProperty RunspaceId
        Remove-Job $job                }

    Start-Sleep -Seconds 10
} Until ($runningJobs.Count -eq 0)

#Take all machines shutdown out of maintenance mode
foreach ($machine in $machinesToPowerOff) {
        #Take machines out of maintenance mode
        WriteLog -Message "Setting $($machine.DNSName) maintenance mode Off"
        If (!$testingOnly) { maintenance -machine $machine -maintenanceMode Off }
    }
}

#Wait for user sessions for disconnect using idle disconnect timers and log them off
Function LogoffShutdown () {
    [CmdletBinding()]

    param(
    [Parameter(Mandatory=$true, HelpMessage = "Number of machines to power off")]
    [ValidateNotNullOrEmpty()]
    [int]$numberMachines

    )

    WriteLog -Message "User logoff mode is not set to force, waiting for sessions to gracefully disconnect before powering machines down" -Level Info
    $machinesToPowerOff = $machinesOnAndNotMaintenance | Sort-Object -Property SessionCount | Select-Object -First $($numberMachines) 

    foreach ($machine in $machinesToPowerOff) {
        #Check for active sessions on each machine before shutting down
        $sessions = $(brokerUserSessions -machineName $($machine.MachineName) | Where-Object {$_.SessionState -eq "Active"} | Select-Object *)
        If ($null -eq $sessions) {
            WriteLog -Message "No active session found on $($machine.DNSName), performing shutdown" -Level Info
            #Shutdown the machines as there are no active sessions (this will include disconnected sessions)
            If (!$testingOnly) { brokerAction -machineName $($machine.MachineName) -machineAction Shutdown }
        } else {
            WriteLog -Message "Active session(s) found on $($machine.DNSName), this machine cannot be gracefully shutdown yet" -Level Info
            maintenance -machine $machine.MachineName -maintenanceMode On
            foreach ($session in $sessions) {
                WriteLog -Message "Sessions active on $($machine.DNSName), $($session.BrokeringUsername) - session length and state $($(New-TimeSpan -Start $($session.EstablishmentTime)).Minutes) Minutes - State $($session.SessionState) " -Level Info
            }
        }
    }
}

Function Startup () {
    [CmdletBinding()]

    param(
    [Parameter(Mandatory=$true, HelpMessage = "Number of machines to power on")]
    [ValidateNotNullOrEmpty()]
    [int]$numberMachines

    )

    #Some machines to startup based on numbers returned
    WriteLog -Message "It is currently inside working hours, machines are required to be started" -Level Info
    WriteLog -Message "There are $($machinesOnAndNotMaintenance.RegistrationState.Count) machine(s) currently switched on and registered, There are $($machinesOnAndMaintenance.RegistrationState.Count) machine(s) in maintenance mode and there are $($machinesPoweredOff.MachineName.Count) machine(s) powered off" -Level Info
    WriteLog -Message "In total there are $($($machinesOnAndMaintenance.RegistrationState.Count) + $($machinesPoweredOff.MachineName.Count)) machine(s) able to be placed into service." -Level Info

    #If the amount of machines that are in maintenance mode are greater or equal to the number of machines needed to be started
    #Check if the number of machines available will service the requirement for machines needed
    If($numberMachines -le $($($machinesOnAndMaintenance.RegistrationState.Count) + $($machinesPoweredOff.MachineName.Count))) {
        WriteLog -Message "The number of machines available is $($($machinesOnAndMaintenance.RegistrationState.Count) + $($machinesPoweredOff.MachineName.Count)) and the number required is $numberMachines" -Level Info
        if ($numberMachines -le $($machinesOnAndMaintenance.RegistrationState.Count)) {
            #The number of machines in maintenance mode will service the request
            WriteLog -Message "The number of machines in maintenance mode is $($machinesOnAndMaintenance.RegistrationState.Count) and the number of machine(s) needed is $($numberMachines)" -Level Info
            WriteLog -Message "There are sufficient machines in maintenance mode to service the request" -Level Info
            foreach ($machine in $($machinesOnAndMaintenance | Get-Random -Count $($numberMachines))) {
                #Take machines out of maintenance mode
                WriteLog -Message "Taking $($machine.DNSName) out of maintenance mode" -Level Info
                If (!$testingOnly) {maintenance -machine $machine -maintenanceMode Off}
            }
        } else {
            #The number of machines in maintenance mode will not service the request, we need to power on machines too
            WriteLog -Message "The number of machines in maintenance mode is $($machinesOnAndMaintenance.RegistrationState.Count) and the number of machine(s) needed is $($numberMachines)" -Level Info
            WriteLog -Message "There are not sufficient machines in maintenance mode to service the request, we will power some on too" -Level Info
            foreach ($machine in $($machinesOnAndMaintenance)) {
                #Take machines out of maintenance mode
                WriteLog -Message "Taking $($machine.DNSName) out of maintenance mode" -Level Info
                If (!$testingOnly) {maintenance -machine $machine -maintenanceMode Off}
            }
            #Power on the machines we need by subtracting the machines already in maintenance mode from what is needed
            foreach ($machine in $($machinesPoweredOff | Select-Object -First ($numberMachines-$($machinesOnAndMaintenance.RegistrationState.Count)))) {
                #Power machines on
                WriteLog -Message "Turning On $($machine.DNSName)" -Level Info
                If (!$testingOnly) {brokerAction -machineName $machine.MachineName -machineAction TurnOn}
            }
        }
    } else {
        WriteLog -Message "The number of machines available is $($($machinesOnAndMaintenance.RegistrationState.Count) + $($machinesPoweredOff.MachineName.Count)) and the number required is $($numberMachines)" -Level Info
        WriteLog -Message "There are not enough machines available to service the request, working on the machines we can" -Level Warn

        #Take machines out of maintenance mode that are powered on and registered
        foreach ($machine in $machinesOnAndMaintenance) {
            #Take machines out of maintenance mode
            WriteLog -Message "Taking $($machine.DNSName) out of maintenance mode" -Level Info
            If (!$testingOnly) {maintenance -machine $machine -maintenanceMode Off}
        }

        foreach ($machine in $machinesPoweredOff) {
            #Power machines on
            WriteLog -Message "Turning On $($machine.DNSName)" -Level Info
            If (!$testingOnly) {brokerAction -machineName $machine.MachineName -machineAction TurnOn}
        }
    }
}

Function Scaling () {
    WriteLog -Message "The current running machines matches the target machines number, performing scaling analysis" -Level Info
    if (($($machinesPoweredOff.MachineName.Count) -gt 0) -or ($null -ne $($machinesPoweredOff.MachineName.Count))) {
        WriteLog -Message "Scaling has been selected, the current scaling metric is $machineScaling and there are $($machinesPoweredOff.machineName.count) machines currently powered off and available." -Level Info
        #Select a machine to be powered on
        $machineToPowerOn = $machinesPoweredOff | Get-Random -Count 1
        If ($null -eq $machineToPowerOn) {
            WriteLog -Message "There are no machines available to power on" -Level Info
            WriteLog -Message "PowerScale did not find any machines that are powered off to be turned on, please add more machines into your catalog(s)" -Level Warn
        } else {
            WriteLog -Message "Machine selected to be powered on is $($machineToPowerOn.DNSName)" -Level Info

            #Perform logic on scaling
            if (($overallPerformance.overallCPU.Average -gt $farmCPUThreshhold) -and ($machineScaling -eq "CPU")) {
                WriteLog -Message "Issuing a power command to $($machineToPowerOn.DNSName) to power up, the CPU threshhold has been triggered." -Level Info
                If (!$testingOnly) { brokerAction -machineName $machineToPowerOn.DNSName -machineAction TurnOn }
                If (!$testingOnly) { Add-BrokerTag -Name "Scaled-On" -Machine $machineToPowerOn.MachineName -AdminAddress $citrixController }
            }
            if (($overallPerformance.overallMemory.Average -gt $farmMemoryThreshhold) -and ($machineScaling -eq "Memory")) {
                WriteLog -Message "Issuing a power command to $($machineToPowerOn.DNSName) to power up, the Memory threshhold has been triggered." -Level Info
                If (!$testingOnly) { brokerAction -machineName $machineToPowerOn.DNSName -machineAction TurnOn }
                If (!$testingOnly) { Add-BrokerTag -Name "Scaled-On" -Machine $machineToPowerOn.MachineName -AdminAddress $citrixController }
            }
            if (($overallPerformance.overallIndex.Average -gt $farmIndexThreshhold) -and ($machineScaling -eq "Index")) {
                WriteLog -Message "Issuing a power command to $($machineToPowerOn.DNSName) to power up, the Index threshhold has been triggered." -Level Info
                If (!$testingOnly) { brokerAction -machineName $machineToPowerOn.DNSName -machineAction TurnOn }
                If (!$testingOnly) { Add-BrokerTag -Name "Scaled-On" -Machine $machineToPowerOn.MachineName -AdminAddress $citrixController }
            }
            if (($overallPerformance.overallSession.Average -gt $farmSessionThreshhold) -and ($machineScaling -eq "Session")) {
                WriteLog -Message "Issuing a power command to $($machineToPowerOn.DNSName) to power up, the Session threshhold has been triggered." -Level Info
                If (!$testingOnly) { brokerAction -machineName $machineToPowerOn.DNSName -machineAction TurnOn }
                If (!$testingOnly) { Add-BrokerTag -Name "Scaled-On" -Machine $machineToPowerOn.MachineName -AdminAddress $citrixController }
            }
        }
    }
}

Function LogOffDisconnected () {
    If ($(($disconnectedSessions | Measure-Object).Count) -gt 0) {
        WriteLog -Message "Logging off all disconnected sessions" -Level Info
        sessionLogOff -sessions $disconnectedSessions
    }
}
#Log for script start
WriteLog -Message "-" -Level Info -NoClobber
WriteLog -Message "#######PowerScale script starting - Test mode value is $testingOnly#######" -Level Info

#########################Reset All Variables and Get All Metrics###################################
$allMachines = ""
$allUserSessions = ""
$machinesExcluded = ""

#Grab all machine details and user session details from the Citrix Farm
try {
        #Get all machines
        if ($machineDetection -eq "prefix") {
            $allMachines = foreach ($prefix in $machinePrefix) {
                WriteLog -Message "Getting a list of machine from $citrixController based on prefix - $prefix" -Level Info
                brokerMachineStates | Where-Object {($_.DNSName -match $prefix) -and ($_.Tags -notcontains $exclusionTag)}
            }
        }
        if ($machineDetection -eq "dg") {
            $allMachines = foreach ($dg in $machineDeliveryGroups) {
                WriteLog -Message "Getting a list of machine from $citrixController based on delivery group - $dg" -Level Info
                brokerMachineStates | Where-Object {($_.DesktopGroupName -contains $dg) -and ($_.Tags -notcontains $exclusionTag)}
            }
        }
        if ($machineDetection -eq "mc") {
            $allMachines = foreach ($c in $machineCatalogs) {
                WriteLog -Message "Getting a list of machine from $citrixController based on machine catalog - $c" -Level Info
                brokerMachineStates | Where-Object {($_.CatalogName -eq $c) -and ($_.Tags -notcontains $exclusionTag)}
            }
        }
        if($machineDetection -eq "tag") {
            $allMachines = foreach ($tag in $machineTags) {
                WriteLog -Message "Getting a list of machine from $citrixController based on tags - $tag" -Level Info
                brokerMachineStates | Where-Object {($_.Tags -contains $tag) -and ($_.Tags -notcontains $exclusionTag)}
            }
        }

        #Get all user sessions
        if ($machineDetection -eq "prefix") {
            $allUserSessions = foreach ($prefix in $machinePrefix) {
                brokerUserSessions  | Where-Object {($_.DNSName -match $prefix) -and ($_.Tags -notcontains $exclusionTag)}
            }
        }
        if ($machineDetection -eq "dg") {
            $allUserSessions = foreach ($dg in $machineDeliveryGroups) {
                brokerUserSessions | Where-Object {($_.DesktopGroupName -eq $dg) -and ($_.Tags -notcontains $exclusionTag)}
            }
        }
        if ($machineDetection -eq "mc") {
            $allUserSessions = foreach ($c in $machineCatalogs) {
                brokerUserSessions | Where-Object {($_.CatalogName -eq $c) -and ($_.Tags -notcontains $exclusionTag)}
            }
        }
        if($machineDetection -eq "tag") {
            $allUserSessions = foreach ($tag in $machineTags) {
                brokerUserSessions | Where-Object {($_.Tags -contains $tag) -and ($_.Tags -notcontains $exclusionTag)}
            }
        }

        #Get excluded machines
        if ($machineDetection -eq "prefix") {
            $machinesExcluded = foreach ($prefix in $machinePrefix) {
                brokerMachineStates  | Where-Object {($_.DNSName -match $prefix) -and ($_.Tags -contains $exclusionTag)}
            }
        }
        if ($machineDetection -eq "dg") {
            $machinesExcluded = foreach ($dg in $machineDeliveryGroups) {
                brokerMachineStates | Where-Object {($_.Tags -match $tag) -and ($_.Tags -contains $exclusionTag)}
            }
        }
        if ($machineDetection -eq "mc") {
            $machinesExcluded = foreach ($c in $machineCatalogs) {
                brokerMachineStates | Where-Object {($_.CatalogName -eq $c) -and ($_.Tags -contains $exclusionTag)}
            }
        }
        if($machineDetection -eq "tag") {
            $machinesExcluded = foreach ($tag in $machineTags) {
                brokerMachineStates | Where-Object {($_.Tags -eq $tag) -and ($_.Tags -contains $exclusionTag)}
            }
        }

        #Filter down the main objects into sub variables for scripting ease
        $disconnectedSessions = $allUserSessions | Select-Object * | Where-Object {$_.SessionState -eq "Disconnected"}
        $activeSessions = $allUserSessions | Select-Object * | Where-Object {$_.SessionState -eq "Active"}
        $machinesOnAndMaintenance = $allMachines | Select-Object * | Where-Object {($_.RegistrationState -eq "Registered") -and ($_.PowerState -eq "On") -and ($_.InMaintenanceMode -eq $true)}
        $machinesOnAndNotMaintenance = $allMachines | Where-Object {($_.RegistrationState -eq "Registered") -and ($_.PowerState -eq "On") -and ($_.InMaintenanceMode -eq $false)}
        $machinesPoweredOff = $allMachines | Select-Object * | Where-Object {($_.PowerState -eq "Off")}
        $machinesScaled = $allMachines | Select-Object * | Where-Object {$_.Tags -contains "Scaled-On"}

} catch {
    WriteLog -Message "There was an error gathering information from the Citrix Controller - Please ensure you have the Powershell SDK installed and the user account you are using has rights to query the Citrix farm." -Level Error
    Exit
}
if ($performanceScaling) {
    #Run the performance monitoring script to create XML files
    WriteLog -Message "Performance scaling is enabled - attempting performance metrics capture" -Level Info
    try {
        $overallPerformance = performanceAnalysis -machines $($machinesOnAndNotMaintenance.DNSName) -exportLocation $performanceIndividual -overallExportLocation $performanceOverall
    } catch {
        WriteLog -Message "There was an error gathering performance metrics from the VDA machines, Please ensure you have the Powershell SDK installed and the user account you are using has rights to query the Citrix farm and CMI. " -Level Error
        #Log out the latest error - does not mean performance measurement was unsuccessful on all machines
        Exit
    }
}

#Create the broker tag for scaling if it doesn't exist
If (-not (Get-BrokerTag -Name "Scaled-On" -AdminAddress $citrixController)) {
    New-BrokerTag "Scaled-On"

}
#########################Reset All Variables and Get All Metrics###################################

#Main Logic
#Kick off Circular logging maintenance
CircularLogging

#Is it a weekday?
If ($(IsWeekDay -date $($timesObj.timeNow))) {
    #If it is a weekday, then check if we are within working hours or not
    If ($(TimeCheck($timeObj)) -eq "OutOfHours") {
        #Outside working hours, perform analysis on powered on machines vs target machines
        WriteLog -Message "It is currently outside working hours - performing machine analysis" -Level Info
        $action = levelCheck -targetMachines $outOfHoursMachines -currentMachines $machinesOnAndNotMaintenance.RegistrationState.Count
        If ($action.Task -eq "Scaling" -and $performanceScaling) {
            #Perform scaling calculations
            Scaling
        } ElseIf ($action.Task -eq "Shutdown") {
            #Logoff all disconnected sessions
            LogOffDisconnected
            #Shutdown machines sending a message to users to logoff
            If ($forceUserLogoff) {
                forceLogoffShutdown -numberMachines $action.number
            }
            #Shutdown all machines that currently have no sessions running
            If (!$forceUserLogoff) {
                LogoffShutdown -numberMachines $action.number
            }
        } ElseIf ($action.Task -eq "Startup") {
            #Startup machines if we dont have enough or one has been excluded
            Startup -numberMachines $action.Number
        }
        if ($($action.Number) -eq 0) {
        #Remove the scaling tag if one exists
            foreach ($machine in $machinesScaled) {
                if (Get-BrokerTag -MachineUid $(Get-BrokerMachine -MachineName $($machine).MachineName).uid) {
                    WriteLog -Message "We're out of hours with the correct number of machines - removing scaling tag from $($machine.MachineName)" -Level Info
                    Remove-BrokerTag "Scaled-On" -Machine $machine
                }
            }
        }
    } ElseIf ($(TimeCheck($timeObj)) -eq "InsideOfHours") {
        #Inside working hours, decide on what to do with current machines, let level check know that scaling should be considered
        $action = levelCheck -targetMachines $InHoursMachines -currentMachines $machinesOnAndNotMaintenance.RegistrationState.Count
        WriteLog -Message "It is currently inside working hours - performing machine analysis" -Level Info
        If ($action.Task -eq "Scaling" -and $performanceScaling) {
            #Perform scaling calculations
            Scaling
        } ElseIf ($action.Task -eq "Startup") {
            #Startup machines if we dont have enough or one has been excluded
            Startup -numberMachines $action.Number
        } ElseIf ($action.Task -eq "Shutdown") {
            #Shutdown all machines that currently have no sessions running
            LogoffShutdown -numberMachines $action.number
        }
    } ElseIf ($(TimeCheck($timeObj)) -eq "Error") {
        #There has been an error just comparing the date
        WriteLog -Message "There has been an error calculating the date or time, review the logs" -Level Error
        SendEmail -smtpServer $smtpServer -toAddress $smtpToAddress -fromAddress $smtpFromAddress -subject $smtpSubject -Message "There has been an error calculating the date or time, please review the attached logs" -attachment $logLocation -Level Error
    }
} Else { #Its the weekend
    $action = levelCheck -targetMachines $outOfHoursMachines -currentMachines $machinesOnAndNotMaintenance.MachineName.Count
    WriteLog -Message "It is currently a weekend - performing machine analysis" -Level Info
    If ($action.Task -eq "Scaling" -and $performanceScaling) {
        #Perform scaling calculations
        Scaling
    } ElseIf ($action.Task -eq "Shutdown") {
        #Logoff all disconnected sessions
        LogOffDisconnected
        #Shutdown machines sending a message to users to logoff
        If ($forceUserLogoff) {
            forceLogoffShutdown -numberMachines $action.number
        }
        #Shutdown all machines that currently have no sessions running
        If (!$forceUserLogoff) {
            LogoffShutdown -numberMachines $action.number
        }
    } ElseIf ($action.Task -eq "Startup") {
        #Startup machines if we dont have enough or one has been excluded
        Startup -numberMachines $action.Number
    }
}

#Generate the Dashboard Files
GenerateDashboard

If ((($($timesObj.timeNow) -ge $($timesObj.backupTime)) -and ($($timesObj.timeNow) -le $($($timesObj.backupTime) + $scriptRunInterval)))) {
    Write-Output "Circular Dashboard Maintenance Triggered"
    Write-Output "Dashboard Backup Time:$($timesObj.backupTime) - Time Now: $($timesObj.timeNow) - Dashboard Backup Window: $($timesObj.backupTime + $scriptRunInterval)"
    WriteLog -Message "Circular Dashboard Maintenance Triggered" -Level Info -NoClobber
    CircularDashboard -retention $dashboardRetention
}

#Update Dashboard navigation links
UpdateDashboardNavigation

#Log for script finish
WriteLog -Message "#######PowerScale script finishing#######" -Level Info -NoClobber
WriteLog -Message "-" -Level Info -NoClobber




