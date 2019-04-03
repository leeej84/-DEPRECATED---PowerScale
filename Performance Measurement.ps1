######## 
#Performance Gathering of Citrix VDAs
#Copyright:         Free to use, please leave this header intact 
#Author:            Leee Jeffries
#Company:           https://www.leeejeffries.com
#Script help:       https://www.leeejeffries.com, please supply any errors or issues you encounter
#Purpose:           This script gathers information about VDAs to be able to make shutdown or startup decisions
#Enterprise users:  This script is recommended for users currently utilising smart scale to power up and down VDA's,
# Smart Scale is due to be deprecated in May
#Example:           Performance Measurement.ps1 -ctxController CTXXDDC1 -interval 15 -samples 10 -exportLocation C:\temp\perf.xml -overallExportLocation C:\temp\overall.xml
# Will connect to CTXXDDC1 (Make sure you have rights) and gather performance metrics 10 times with an interval of 15 seconds exporting the data to C:\Temp 

param(
    [Parameter(
        MANDATORY=$true    
    )]
    [String]$ctxController, 

    [String]$machinePrefix, 

    [int]$interval = 5,

    [int]$samples = 12,

    [Parameter(
        MANDATORY=$true    
    )]
    [String]$exportLocation,

    [Parameter(
        MANDATORY=$true    
    )]
    [String]$overallExportLocation
)

#Load Citrix Modules
try {
    asnp Citrix*
} catch {
    "There has been an error loading powershell snap-ins"
}

#Get a list of live Citrix Servers from the Broker that are currently powered on
$computers = Get-BrokerMachine -AdminAddress $ctxController | Where {($_.DNSName -match $machinePrefix) -And ($_.RegistrationState -eq "Registered") -And ($_.PowerState -eq "On")} | Select-Object -ExpandProperty DNSName

#Zero out results so we dont see last set of results on the first run of performance information gathering
$results = ""

#Loop through each machine obtained from the broker and gathers its information for scaling puroposes
ForEach ($computer in $computers) {    
    Start-Job -Name $computer -ScriptBlock {
        param (
        $computer,
        $ctxController,
        $interval,
        $samples
        )

        #Load the Citrix snap-ins
        asnp Citrix*    
        
        #Create a custom object to store the results
        $results = [PSCustomObject]@{
        Machine = $computer
        CPU = [int](Get-Counter '\Processor(_Total)\% Processor Time' -ComputerName $computer -SampleInterval $interval -MaxSamples $samples | select -expand CounterSamples | Measure-Object -average cookedvalue | Select-Object -ExpandProperty Average)
        Memory = [int](Get-Counter -Counter '\Memory\Available MBytes' -ComputerName $computer -SampleInterval $interval -MaxSamples $samples | select -expand CounterSamples | Measure-Object -average cookedvalue | Select-Object -ExpandProperty Average)
        LoadIndex = (Get-BrokerMachine -AdminAddress $ctxController | Where {$_.DNSName -eq $computer}) | Select -expand LoadIndex
        Sessions = (Get-BrokerMachine -AdminAddress $ctxController | Where {$_.DNSName -eq $computer}) | Select -expand SessionCount
        } 
        
        #Write out the results for this computer only if the CPU and Memory calculations worked
        if ($results.CPU -eq 0 -or $results.memory -eq 0) {
            $results
        } else {
            $results
        }
    
    } -ArgumentList $computer, $ctxController, $interval, $samples
}

#Loop through all running jobs every 5 seconds to see if complete, if they are; receive the jobs and store the metrics
$Metrics = Do {
    $runningJobs = Get-Job | Where {$_.State -ne "Completed"}
    $completedJobs = Get-Job |  Where {$_.State -eq "Completed"}
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
"$($overallAverage.overallCPU.Average) - Overall CPU Average"
"$($overallAverage.overallMemory.Average) - Overall Memory Average"
"$($overallAverage.overallIndex.Average) - Overall Session Index Average"
"$($overallAverage.overallSession.Average) - Overall Session Count Average"
