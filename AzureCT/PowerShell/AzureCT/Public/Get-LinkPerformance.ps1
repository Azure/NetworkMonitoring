function Get-LinkPerformance {
    # 1. Evaluate and Set input parameters
    # 2. Initialize
    # 3. Clear old run files
    # 4. Validate iPerf3 connectivity (two ping)Error Stop
    # 5. Validate PSPing connectivity (two ping)Error Stop
    # 6. Main Test Loop
    #    6.1 Start iPerf job if required
    #    6.2 Start PSPing job
    #    6.3 Wait for jobs to finish
    # 7. Parse each job file for data
    #    7.1 iPerf3 log file line loop
    #    7.2 PSPing log file line loop
    #    7.3 Get Percentile values
    #    7.4 Add results to object array
    # 8. Output results

    <#
    .SYNOPSIS
        Run a series of iPerf load tests and PSPing TCP pings concurrently between a local source and a remote host
        running iPerf3 in server mode. Seven tests of increasing load are performed and results are output at the
        conclusion of the test.

    .DESCRIPTION
        Run a series of iPerf load tests and PSPing TCP pings concurrently between a local source and a remote host
        running iPerf3 in server mode. Seven tests of increasing load are performed and results are output at the
        conclusion of the test.

        The remote server must be running iPerf3 in server mode; e.g iPerf3 -s

        On the local server from which this function is run, vaious parameters can be used to affect the testing.
        The output is a combination of both the load test and the latency test while the perf test is running.
        Each row of output represtents the summation of a given test, the follow test conditions are run:
         - No load, a PSPing TCP test without iPerf3 running, a pure latency test
         - 1 Session, a PSPIing TCP test with iPerf3 running a single thread of load
         - 6 Sessions, a PSPing TCP test with iPerf3 running a six thread load test
         - 16 Sessions, a PSPing TCP test with iPerf3 running a 16 thread load test
         - 16 Sessions with 1Mb window, a PSPing TCP test with iPerf3 running a 16 thread load test with a 1Mb window
         - 32 Sessions, a PSPing TCP test with iPerf3 running a 32 thread load test

         For each test iPerf is started and allowed to run for 10 seconds to establish the load and allow it to level.
         PSPing is then started to record latency during the load test.

         Results from each test are stored in a text file in the AzureCT Tools directory (C:\ACTTools)

         Output for each test is displayed in a table formatted object with the following columns:
          - Name: The name of the test for these values, eg No load, 1 session, etc
          - Bandwidth: The average bandwidth achieved by iPerf for the given test
          - Loss: percentage of packets lost during the PSPing test
          - P50 Latency: the 50th percentile of latency seen during the test

          If the detailed output option (-DetailedOutput) is used, the following columns are also output:
          - P90 Latency: the 90th percentile of latency seen during the test
          - P95 Latency: the 95th percentile of latency seen during the test
          - Avg Latency: the average TCP ping latency seen during the test
          - Min Latency: the minumum TCP ping latency seen during the test
          - Max Latency: the maximum TCP ping latency seen during the test

    .PARAMETER RemoteHost
        This parameter is required and is the Remote Host IP Address. This host must be running iPerf3 in server mode and
        be listening on either port 22 (SSH) for Linux hosts or 3389 (RDP) for Windows hosts.

    .PARAMETER RemoteHostOS
        This optional parameter signifies the operating system of the REMOTE host. Valid values are "Windows" or "Linux".
        It is assumed that if the remote host is Linux it is listening on port 22. If Windows PSPing will use the RDP port
        3389.

    .PARAMETER TestSeconds
        This optional parameter signifies the duration of the PSPing test in seconds. It is an integer value (whole number).
        The range of valid values is 10 - 3600 seconds (10 seconds - 1 hour). The default value is 60 seconds (1 minute).

    .PARAMETER DetailedOutput
        This optional parameter affects the output of the data results. Normal output consists of the Test Name, Bandwidth,
        Packet Loss, and the 50th percentile value for latency. With this parameter enabled addition data fields (Count of
        packets sent for each test, the Minimum, Maximum, Average, 90th, and 95th percentile latency values) are also sent
        as output.

    .EXAMPLE
        Get-LinkPerformance -RemoteHost 10.0.0.1

        This command returns network performance stats from a windows server at 10.0.0.1 for 6 one minute tests (default
        host type (Windows) and test duration (60 seconds))

    .EXAMPLE
        Get-LinkPerformance -RemoteHost 10.0.0.1 -HostType Linux -TestSeconds 3600

        This command returns network performance stats from a Linux server at 10.0.0.1 for 6 one-hour tests (3600 seconds)

    .EXAMPLE
        (Get-AzureVM -ServiceName 'myServiceName' -Name 'myVMName').IpAddress | Get-LinkPerformance

        This command pulls the VNet IP address from a VM in Azure and pipes it to the Get-AzureNetworkAvailability cmdlet

    .LINK
        https://github.com/Azure/NetworkMonitoring

    .NOTES
        This script will run against a remote server that must be running iPerf3 in server mode with firewall ports
        open to allow iPerf and the approprate PSPing port (22 or 3389). If the remote server is a windows machine
        an easy way to ensure proper configuration is to install the LinkPerformance tool on that remote machine and
        then run iPerf3 in server mode (iperf3 -s)
        More information can be found at https://github.com/Azure/NetworkMonitoring

    #>
    
    # 1. Evaluate and Set input parameters
    [cmdletBinding()]
    Param(
       [Parameter(ValueFromPipeline=$true,
                  Mandatory=$true,
                  HelpMessage='Enter IP Address of Remote Host')]
       [ipaddress]$RemoteHost,
       [ValidateSet(“Windows”,”Linux”)]
       [string]$RemoteHostOS="Windows",
       [ValidateRange(10,3600)] 
       [int]$TestSeconds=60,
       [switch]$DetailedOutput=$false
    )

    # 2. Initialize
    $ToolPath = "C:\ACTTools\"
    $WebSource = "https://github.com/Azure/NetworkMonitoring"
    $FileArray = "P00", "P01", "P06", "P16", "P17", "P32"
    $PingDuration = $TestSeconds
    $LoadDuration = $TestSeconds + 10
    If ($RemoteHostOS -eq "Windows") {$PingPort="3389"} Else {$PingPort="22"}
    [String]$HostPort = [string]$RemoteHost + ":" + [String]$PingPort

    # 3. Clear old run files
    Remove-Job -Name ACT.LinkPerf -Force -ErrorAction SilentlyContinue
    If (Test-Path $ToolPath"TestPing.log"){Remove-Item $ToolPath"TestPing.log"}
    If (Test-Path $ToolPath"TestPerf.log"){Remove-Item $ToolPath"TestPerf.log"}
    If (Test-Path $ToolPath"P*ping.log"){Remove-Item $ToolPath"P*ping.log"}
    If (Test-Path $ToolPath"P*perf.log"){Remove-Item $ToolPath"P*perf.log"}
    
    # 4. Validate iPerf3 connectivity (two ping)Error Stop
    $FileName = $ToolPath + "\TestPerf.log"
    $iPerfJob = Start-Job -ScriptBlock {C:\ACTTools\iperf3.exe -c $args[0] -t 2 -i 0 -P 1 --logfile $args[1]} -Name 'ACT.LinkPerf' -ArgumentList "$RemoteHost", "$FileName"
    Wait-Job -Name "ACT.LinkPerf" | Out-Null
    # Line Loop
    $TPut = "Error"
    Try {
        $Lines = Get-Content $FileName -ErrorAction Stop
        ForEach ($Line in $Lines) {
            If (($Line -like "*receiver*")) {$TPut = $Line.Substring(38,17).Trim()} # End If
        } # End For
    } # End Try
    Catch {}
    If ($TPut -eq "Error") {
        Write-Host
        Write-Warning "Unable to start iPerf session.

        Things to check:
         - Ensure iPerf is running in server mode (iperf3 -s) on the remote host at $RemoteHost
         - Ensure remote iPerf server is listening on the default port 5201
         - Check host and network firewalls to ensure this port is open on both hosts and any network devices between them
         - Ensure iPerf files are installed in C:\ACTTools, if not rerun Install-LinkPerformance
         - Ensure remote iPerf version is compatible with local version

        See $WebSource for more information."
        Return } # End If
   
    # 5. Validate PSPing connectivity (two ping)Error Stop
    $FileName = $ToolPath+"\TestPing.log"
    $iPerfJob = Start-Job -ScriptBlock {C:\ACTTools\psping.exe -n 2 -4 $args[0] -nobanner > $args[1]} -Name 'ACT.LinkPerf' -ArgumentList "$HostPort", "$FileName"
    Wait-Job -Name "ACT.LinkPerf" | Out-Null
    # Line Loop
    $Loss = "Error"
    Try {
        $Lines = Get-Content $FileName -ErrorAction Stop
        ForEach ($Line in $Lines) {
            If ($Line -like "*Sent*") {
                $Loss = $Line.Substring($Line.IndexOf("(",0)+1,$Line.IndexOf(")",0)-$Line.IndexOf("(",0)-1)
            } # End If
        } # End For
    } # End Try
    Catch {}
    If ($Loss -eq "100% loss" -or $Loss -eq "Error") {
        Write-Host
        Write-Warning "Unable to TCP ping remote machine.

        Things to check:
         - Ensure $HostPort is listening and reachable from this machine
         - Ensure remote OS attribute setting is correct, it's currently set to ""$RemoteHostOS""
         - Check host and network firewalls to ensure this port is open
         - Ensure PSPing.exe is installed in C:\ACTTools, if not rerun Install-LinkPerformance

        See $WebSource for more information."
        Return
        } # End If


    # 6. Main Test Loop
    ForEach ($FilePrefix in $FileArray) {
        switch($FilePrefix) {
            "P00" {$Threads = 00; $TestName = "Stage 1 of 6: No Load Ping Test..."}
            "P01" {$Threads = 01; $TestName = "Stage 2 of 6: Single Thread Test..."}
            "P06" {$Threads = 06; $TestName = "Stage 3 of 6: 6 Thread Test..."}
            "P16" {$Threads = 16; $TestName = "Stage 4 of 6: 16 Thread Test..."}
            "P17" {$Threads = 16; $TestName = "Stage 5 of 6: 16 Thread Test with 1Mb window..."}
            "P32" {$Threads = 32; $TestName = "Stage 6 of 6: 32 Thread Test..."}
            default {Write-Error "Invalid FilePrefix, execution stopping!"; Return}
        } # End Switch

        # Decalare Test Starting
        Write-Host (Get-Date)' - ' -NoNewline
        Write-Host $TestName -ForegroundColor Cyan

        # 6.1 Start iPerf job if required
        $FileName = $ToolPath + "\" + $FilePrefix + "perf.log"
        Switch($FilePrefix) {
            "P00" {}
            "P17" {
                $iPerfJob = Start-Job -ScriptBlock {C:\ACTTools\iperf3.exe -c $args[0] -t $args[1] -i 0 -P $args[2]  -w1M --logfile $args[3]} -Name 'ACT.LinkPerf' -ArgumentList "$RemoteHost", "$LoadDuration", "$Threads", "$FileName"
                Sleep -Seconds 5}
            default {
                $iPerfJob = Start-Job -ScriptBlock {C:\ACTTools\iperf3.exe -c $args[0] -t $args[1] -i 0 -P $args[2] --logfile $args[3]} -Name 'ACT.LinkPerf' -ArgumentList "$RemoteHost", "$LoadDuration", "$Threads", "$FileName"
                Sleep -Seconds 5}
        } # End Switch
    
        # 6.2 Start PSPing job
        $FileName = $ToolPath + "\" + $FilePrefix + "ping.log"
        [string]$StringDuration = $PingDuration.ToString() + "s"
        $iPerfJob = Start-Job -ScriptBlock {C:\ACTTools\psping.exe -n $args[0] -4 $args[1] -nobanner > $args[2]} -Name 'ACT.LinkPerf' -ArgumentList "$StringDuration", "$HostPort", "$FileName"

        # 6.3 Wait for jobs to finish
        If ($FilePrefix -eq "P00") {$time = $PingDuration + 2}
        Else {$time = $LoadDuration + 1} # End If
        foreach($i in (1..$time)) {
            $percentage = $i / $time
            $remaining = New-TimeSpan -Seconds ($time - $i)
            $message = "{0:p0} complete, remaining time {1}" -f $percentage, $remaining
            Write-Progress -Activity $message -PercentComplete ($percentage * 100) -CurrentOperation $TestName
            Start-Sleep 1
            } # End Foreach
        While ((Get-Job -Name 'ACT.LinkPerf' -ErrorAction SilentlyContinue | Where State -eq 'Running').Count -gt 0) {
            Write-Verbose "Waiting for job threads to finish..."
            Sleep 2
            } # End While
        } # End For
 
    Write-Host "Testing Complete!" -ForegroundColor Cyan

    # 7. Parse each job file for data
    $TestResults=@()
    # File Loop
    ForEach ($FilePrefix in $FileArray) {
        switch($FilePrefix) {
            "P00" {$TestName = "No Load"}
            "P01" {$TestName = "1 Session"}
            "P06" {$TestName = "6 Sessions"}
            "P16" {$TestName = "16 Sessions"}
            "P17" {$TestName = "16 Sessions with 1Mb window"}
            "P32" {$TestName = "32 Sessions"}
            default {}
        } # End Switch

        # 7.1 iPerf3 log file line loop
        $FileName = $ToolPath + "\" + $FilePrefix + "perf.log"
        $TPut = "Error"
        If ($FilePrefix -eq "P00") {
             $TPut = "N/A"}
        Else {
            Try {
                $Lines = Get-Content $FileName -ErrorAction Stop
                ForEach ($Line in $Lines) {
                    If ($FilePrefix -eq "P01") {If (($Line -like "*receiver*")) {$TPut = $Line.Substring(38,17).Trim()} #End If
                    }
                    Else {
                        If (($Line -like "*SUM*" -and $Line -like "*receiver*")) {$TPut = $Line.Substring(37,17).Trim()} #End If
                    } # End Else
                } # End For
            } # End Try
            Catch {Write-Warning "Error reading or processing file: $FileName"}
        } # End If


        # 7.2 PSPing log file line loop
        $FileName = $ToolPath + "\" + $FilePrefix + "ping.log"
        $PingArray = New-Object System.Collections.Generic.List[System.Object]
        $PingLoss = "Error"
        $PingSent = "Error"
        $PingP50 = "Error"
        $PingP90 = "Error"
        $PingP95 = "Error"
        $PingMin = "Error"
        $PingMax = "Error"
        $PingAvg = "Error"
        Try {
            $Lines = Get-Content $FileName -ErrorAction Stop
            ForEach ($Line in $Lines) {
                If ($Line.Contains("Connecting")) {
                    $Step1 = (($Line -split ':')[4])
                    $Step2 = $Step1.Trim()
                    [Decimal]$Step3 = $Step2.TrimEnd("ms")
                    $PingArray.Add($Step3)
                } # EndIf
                If ($Line -like "*Sent*") {
                    $PingSent = $Line.Substring($Line.IndexOf("=", $Line.IndexOf("Sent",0))+2, $Line.IndexOf(",", $Line.IndexOf("Sent",0))-$Line.IndexOf("=", $Line.IndexOf("Sent",0))-2)
                    $PingLoss = $Line.Substring($Line.IndexOf("(",0)+1,$Line.IndexOf(")",0)-$Line.IndexOf("(",0)-1)
                } # End If
                If ($Line -like "*Minimum*") {
                    $PingMin = $Line.Substring($Line.IndexOf("=", $Line.IndexOf("Minimum",0))+2, $Line.IndexOf(",", $Line.IndexOf("Minimum",0))-$Line.IndexOf("=", $Line.IndexOf("Minimum",0))-2)
                    $PingMax = $Line.Substring($Line.IndexOf("=", $Line.IndexOf("Maximum",0))+2, $Line.IndexOf(",", $Line.IndexOf("Maximum",0))-$Line.IndexOf("=", $Line.IndexOf("Maximum",0))-2)
                    $PingAvg = $Line.Substring($Line.IndexOf("=", $Line.IndexOf("Average",0))+2)
                } # End If
            } # End For
        } # End Try
        Catch {Write-Warning "Error reading or processing file: $FileName"}

        # 7.3 Get Percentile values
        # Remove the warm up ping and sort the arrary
        $PingArray.RemoveAt(0)
        $SortedArrary = $PingArray | Sort-Object
        # http://www.dummies.com/education/math/statistics/how-to-calculate-percentiles-in-statistics/
        # Pick 50th Percentile
        If ($SortedArrary.count%.5) {$PingP50 = $SortedArrary[[math]::Ceiling($SortedArrary.count*.5)-1]}
        Else {$PingP50 = ($SortedArrary[$SortedArrary.Count*.5] + $SortedArrary[$SortedArrary.count*.5-1])/2}
        # Pick 90th Percentile
        If ($SortedArrary.count%.9) {$PingP90 = $SortedArrary[[math]::Ceiling($SortedArrary.count*.9)-1]}
        Else {$PingP90 = ($SortedArrary[$SortedArrary.Count*.9] + $SortedArrary[$SortedArrary.count*.9-1])/2}
        # Pick 95th Percentile
        If ($SortedArrary.count%.95) {$PingP95 = $SortedArrary[[math]::Ceiling($SortedArrary.count*.95)-1]}
        Else {$PingP95 = ($SortedArrary[$SortedArrary.Count*.95] + $SortedArrary[$SortedArrary.count*.95-1])/2}

        # 7.4 Add results to object array
        $Test = New-Object -TypeName PSObject
        $Test | Add-Member -Name 'Name' -MemberType NoteProperty -Value $TestName
        $Test | Add-Member -Name 'Bandwidth' -MemberType NoteProperty -Value $TPut
        $Test | Add-Member -Name 'Count' -MemberType NoteProperty -Value $PingSent
        $Test | Add-Member -Name 'Loss' -MemberType NoteProperty -Value $PingLoss
        $Test | Add-Member -Name 'P50' -MemberType NoteProperty -Value $PingP50'ms'
        $Test | Add-Member -Name 'P90' -MemberType NoteProperty -Value $PingP90'ms'
        $Test | Add-Member -Name 'P95' -MemberType NoteProperty -Value $PingP95'ms'
        $Test | Add-Member -Name 'Avg' -MemberType NoteProperty -Value $PingAvg
        $Test | Add-Member -Name 'Min' -MemberType NoteProperty -Value $PingMin
        $Test | Add-Member -Name 'Max' -MemberType NoteProperty -Value $PingMax
        
        $TestResults += $Test
    } # End Foreach

    # 8. Output results
    If ($DetailedOutput) {Write-Output $TestResults}
    Else {Write-Output $TestResults | Select Name, Bandwidth, Loss, P50}

} # End Function
