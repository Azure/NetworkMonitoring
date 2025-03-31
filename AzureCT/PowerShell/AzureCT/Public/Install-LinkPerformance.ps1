function Install-LinkPerformance{
    # 1. Warning check
    # 2. Initialize
    # 3. Create C:\ACTTools dir
    # 4. Check for iPerf files
    #    4.1 If either are needed, download, extract
    # 5. Check for PSPing
    #    5.1 If needed, download
    # 6. Check other files
    # 7. Pull from GitHub if needed
    # 8. Kill PSPing popup
    # 9. Open Firewall rules

    <#
    .SYNOPSIS
        Downloads critial files required to run the Get-LinkPerformance command in the Azure Connectivity Toolkit.

    .DESCRIPTION
        To enable the Get-LinkPerformance command to run succesfully, certain third party applications are
        needed as well as local host configurations. The Install-LinkPerformance command will download and
        configure these requirements.

        This command only needs to be run once for a given host. However if required files are deleted or
        the host is configured so that Get-LinkPerformance can't run successfully you will be prompted to
        run Install-LinkPerformance again to get the host enabled for successfull testing.

        When called, this cmdlet will perform the following step:
        1. Create a C:\ACTTools directory
        2. Download iPerf3 files to the directory
        3. Download PSPing to the directory
        4. Download two files from GitHub (a firewalls rule script, and a readme file)
        5. Accept the EULA for PSPing
        6. Open the local host firewall for ICMP and Port 5201 traffic

    .PARAMETER Force
        This optional parameter will bypass the "Are you sure" prompt and enable a silent or scripted installation.

    .EXAMPLE
        Install-LinkPerformance

        This command will prompt the user to ensure they accept the changes performed by this installation. If conditions
        are accepted, the installation continues, if not accepted, the installation ends with no changes make to the host.

    .EXAMPLE
        Install-LinkPerformance -Force

        This command will bypass the user prompt and begin the installation and configuration changes.

    .LINK
        https://github.com/Azure/NetworkMonitoring

    #>


    Param([switch]$Force=$false)

    # 1. Warning check
    If (-not $Force) {
        Write-Host
        Write-Host "                               " -BackgroundColor Black
        Write-Host "  ***************************  " -ForegroundColor Red -BackgroundColor Black
        Write-Host "  ***                     ***  " -ForegroundColor Red -BackgroundColor Black
        Write-Host "  ***" -ForegroundColor Red -BackgroundColor Black -NoNewline
        Write-Host "    !!!Warning!!!    " -ForegroundColor Yellow -BackgroundColor Black -NoNewline
        Write-host "***  "  -ForegroundColor Red -BackgroundColor Black
        Write-Host "  ***                     ***  " -ForegroundColor Red -BackgroundColor Black
        Write-Host "  ***************************  " -ForegroundColor Red -BackgroundColor Black
        Write-Host "                               " -BackgroundColor Black
        Write-Host 
        Write-Host "  This script will install 3rd party products: iPerf3 and PSPing" -ForegroundColor Cyan
        Write-Host "  As well as open firewall port 5201 and allow ICMPv4" -ForegroundColor Cyan
        Write-Host
        $foo = Read-Host -Prompt "Are you sure you wish to continue? [y]"
        If ($foo -ne "y" -and $foo -ne "") {Return}
    
        } # End If


    # 2. Initialize
    $ToolPath = "C:\ACTTools\"
    $GitHubURL = "https://raw.githubusercontent.com/tracsman/NetworkMonitoring/LinkPerf/AzureCT/PowerShell/AzureCT/Public/"
    $PSPingURL = "https://live.sysinternals.com/psping.exe"
    $iPerf3URL = "https://files.budman.pw/iperf3.13_64.zip"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # 3. Create C:\ACTTools dir
    If (-Not (Test-Path $ToolPath)){New-Item -ItemType Directory -Force -Path $ToolPath | Out-Null}


    # 4. Check for iPerf files
    # Yes I know I should make the file pull (and other things) a callable function, but lazy is ok sometimes
    If (-Not (Test-Path $ToolPath"iperf3.exe") -or -Not (Test-Path $ToolPath"cygwin1.dll")){
        # 4.1 If either are needed, download, extract
        $File = $ToolPath + "iperf3.13_64.zip"
        Try {
            $webClient = new-object System.Net.WebClient
            $webClient.DownloadFile($iPerf3URL, $File)
            }
        Catch {
            Write-Host
            Write-Warning "Something bad happened with the iPerf download. Most likely either files are missing at the source or this host doesn't have internet access."
            Write-Host
            Write-Host "You can manually add the files and rerun this Install script."
            Write-Host "To manually install iPerf3:"
            Write-Host "  1. Download the zip file from $iPerf3URL"
            Write-Host "  2. Extract zipped files (iPerf3.exe and cygwin1.dll) to $ToolPath"
            Write-Host "  3. With those files in place, rerun this install."
            Write-Host
            Return
            } # End Try

        Try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($File, $ToolPath)
            move-item -path ($ToolPath + "iperf-3.1.3-win64\*.*") -destination $ToolPath -Force
            Remove-Item -Path ($ToolPath + "iperf-3.1.3-win64\") -Force
            Remove-Item -Path $File -Force
            }
        Catch {
            Write-Host
            Write-Warning "Something bad happened Unzipping and moving the iPerf files. Most likely .Net or other required subsystem files are not loaded."
            Write-Host
            Write-Host "You can manually add the files and rerun this Install script."
            Write-Host "To manually install iPerf3:"
            Write-Host "  1. Find $File"
            Write-Host "  2. Extract zipped files (iPerf3.exe and cygwin1.dll) to $ToolPath (not a subdirectory!)"
            Write-Host "  3. With those files in place, rerun this install."
            Write-Host
            Return
            } # End Try
        } # End If


    # 5. Check for PSPing
    If (-Not (Test-Path $ToolPath"psping.exe")){
        # 5.1 If needed, download
        $File = $ToolPath + "psping.exe"
        Try {
            $webClient = new-object System.Net.WebClient
            $webClient.DownloadFile($PSPingURL, $File)
            }
        Catch {
            Write-Host
            Write-Warning "Something bad happened with the PSPing download. Most likely either files are missing at the source or this host doesn't have internet access."
            Write-Host
            Write-Host "You can manually add the file and rerun this Install script."
            Write-Host "To manually install PSPing:"
            Write-Host "  1. Download the file from $PSPingURL"
            Write-Host "  2. Move the psping.exe file to the $ToolPath directory."
            Write-Host "  3. With psping.exe in place, rerun this install."
            Write-Host
            Return
            } # End Try
        } # End If

    # 6. Check other files
    $FileName = @()
    If (-Not (Test-Path ($ToolPath + "Set-iPerfFirewallRules.ps1"))){$FileName += 'Set-iPerfFirewallRules.ps1'}
    If (-Not (Test-Path ($ToolPath + "README.md"))){$FileName += 'README.md'}

    # 7. Pull from GitHub if needed
    If ($FileName.Count -gt 0) {
        Try {
            ForEach ($File in $FileName) {
                $webClient = new-object System.Net.WebClient
                $webClient.DownloadFile( $GitHubURL + $File, $ToolPath + $File )
                } #End ForEach
            }
        Catch {
            Write-Host
            Write-Warning "Something bad happened pulling files from GitHub. Most likely either files are missing at the source or this host doesn't have internet access."
            Write-Host
            Write-Host "You can manually add the four files and rerun this Install script."
            Write-Host "To manually install the files:"
            Write-Host "  1. Go to $GitHubURL"
            Write-Host "  2. Save the files 'Set-iPerfFirewallRules.ps1' and 'README.md' to the local $ToolPath directory."
            Write-Host "  3. With these files in place, rerun this install."
            Write-Host
            Return
            } # End Try
        } # End If

    # 8. Kill PSPing popup
    $cmd = $ToolPath + "psping.exe -accepteula | Out-Null"
    Invoke-Expression -Command $cmd

    # 9. Open Firewall rules
    If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
        {Start-Process powershell -Verb runAs -ArgumentList ($ToolPath + "Set-iPerfFirewallRules.ps1")}
    Else {Invoke-Expression -Command ($ToolPath + "Set-iPerfFirewallRules.ps1")}

} # End Function
