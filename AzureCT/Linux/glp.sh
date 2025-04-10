#!/bin/bash

# Get-LinkPerformance for Linux, version 1.0

#  1. Define Functions
#  2. Evaluate and Set input parameters
#  3. Initialize Variables
#  4. Clear old run files
#  5. Validate Ping connectivity (two ping)
#  6. Validate iPerf3 connectivity (two ping)
#  7. Start Ping Job
#  8. iPerf Test Loop
#  9. Parse each job file for data
#  9.1 iPerf file loop
#  9.2.1 iPerf line loop
# 10. Output results

# 1. Define Functions
function getIndex {
  # $1 = Array count being analyzed
  # $2 = The percentile being sought
  
  if [ $(( $1 * $2 % 100 )) -eq 0 ]
  then
    # Whole number
	k=$(( $1 * $2 / 100 ))
  else
    # Fraction
	k=$(( $1 * $2 / 100 + 1 ))
  fi
  
  if [ $k -eq 0 ]
  then
    k=1
  elif [ $k -gt $1 ]
  then
    k=$1
  fi
  
  echo $k
}

function valid_ip()
{
    # From https://www.linuxjournal.com/content/validating-ip-address-bash-script
	local  ip=$1
  local  stat=1

  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; 
    then
      OIFS=$IFS
      IFS='.'
      ip=($ip)
      IFS=$OIFS
      [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
       && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
      stat=$?
  fi
  return $stat
}

# 2. Evaluate and Set input parameters
printf "\n"
gotError="Nope"
msgError=""
if valid_ip $1
  then
  RemoteHost=$1
else
  msgError+="Invalid or missing remote host IP address.\n\n"
  gotError="Yep"
fi

if [[ $2 =~ ^[0-9]+$ ]]
  then
    if (( $2 > 3 && $2 < 86401 ))
      then
      TestSeconds=$2
    else
      msgError+="Invalid or missing TestSeconds.\n"
      msgError+="Value must be between 10 and 86,400 (24 hours).\n\n"
      gotError="Yep"
    fi
else
  msgError+="Invalid or missing TestSeconds.\n"
  msgError+="Value must be an integer between 10 and 86,400 (24 hours).\n\n"
  gotError="Yep"
fi

if [[ "$gotError" == "Yep" ]]
  then
  printf "glp: missing operand\n"
  printf "usage:"
  tput bold
  printf " glp <Remote IPv4> <TestSeconds>\n\n"
  tput sgr0
  printf "$msgError"
  exit
fi

# 3. Initialize Variables
WebSource="https://github.com/Azure/NetworkMonitoring"
strPingTest="PingTest.log"
strPerfTest="PerfTest.log"
strTestFile[1]="Ping.log"
strTestFile[2]="P01perf.log"
strTestFile[3]="P06perf.log"
strTestFile[4]="P16perf.log"
# strTestFile[5]="P17perf.log"
strTestFile[5]="P32perf.log"
logDir="data"
OutputArray=()
PingArray=()
PingLoss="Error"
PingSent="Error"
PingP50="Error"
PingP90="Error"
PingP95="Error"
PingMin="Error"
PingMax="Error"
PingAvg="Error"
TestName=()
TestName[1]="Stage 1 of 5: Latency Test..."
TestName[2]="Stage 2 of 5: Single Thread Test..."
TestName[3]="Stage 3 of 5: 6 Thread Test..."
TestName[4]="Stage 4 of 5: 16 Thread Test..."
# TestName[5]="Stage 5 of 6: 16 Thread Test with 1Mb window..."
TestName[5]="Stage 5 of 5: 32 Thread Test..."
Threads=()
Threads[1]=0
Threads[2]=1
Threads[3]=6
Threads[4]=16
# Threads[5]=16
Threads[5]=32
TPut=()

# 4. Clear old run files
if [ -d "$logDir" ]
  then
  rm -f ./$logDir/*
else
  mkdir $logDir
fi

# 5. Validate Ping connectivity (two ping)
ping $RemoteHost -c 2 -W 4 > ./$logDir/$strPingTest
while IFS= read -r line
do
  if [[ $line == *100??packet?loss* ]]
    then
    tput bold
    printf "Unable to ping remote machine.\n\n"
	  tput sgr0
	  printf "Things to check:\n"
    printf " - Ensure the remote server is listening and reachable from this machine\n"
    printf " - Check host and network firewalls to ensure ICMPv4 is allowed\n\n"
	  printf "See $WebSource for more information.\n\n"
	  exit
  fi
done < $logDir/$strPingTest

# 6. Validate iPerf3 connectivity (two ping)
iperf3 -c $RemoteHost -t 2 -i 0 -P 1 -b 1k --logfile ./$logDir/$strPerfTest
while IFS= read -r line
do
  if [[ $line == *error?-?unable?to?connect* ]]
    then
    tput bold
    printf "Unable to start iPerf session.\n\n"
	  tput sgr0
	  printf "Things to check:\n"
    printf " - Ensure iPerf is running in server mode (iperf3 -s) on the remote host at $RemoteHost\n"
	  printf " - Ensure remote iPerf server is listening on the default port 5201\n"
	  printf " - Check host and network firewalls to ensure this port is open on both hosts and any network devices between them\n"
	  printf " - Ensure iPerf files are installed\n"
	  printf " - Ensure remote iPerf version is compatible with local version\n\n"
	  printf "See $WebSource for more information.\n\n"
	  exit
  fi
done < $logDir/$strPerfTest

# 7. Start Ping Job
printf "$(date '+%m/%d/%Y %H:%M:%S') - "
tput setaf 6
printf "${TestName[1]}\n"
tput sgr0
ping $RemoteHost -c $TestSeconds > ./$logDir/${strTestFile[1]}

# 8. iPerf Test Loop
for i in {2..5}
do
  printf "$(date '+%m/%d/%Y %H:%M:%S') - "
  tput setaf 6
  printf "${TestName[$i]}\n"
  tput sgr0
  iperf3 -c $RemoteHost -t $TestSeconds -i 0 -P ${Threads[$i]} --logfile ./$logDir/${strTestFile[$i]}
  # Window size is currently unsupported in Linux iPerf3
  #  if [ $i -eq 5 ]
  #  then
  #	iperf3 -c $RemoteHost -t $TestSeconds -i 0 -P ${Threads[$i]} -w1M --logfile ./$logDir/${strTestFile[$i]}
  #  else
  #  iperf3 -c $RemoteHost -t $TestSeconds -i 0 -P ${Threads[$i]} --logfile ./$logDir/${strTestFile[$i]}
  #  fi
done

# 9. Parse each job file for data
# 9.1 Ping file loop
while IFS= read -r line
do
  # Starting ping line loop
  if [[ $line == *ttl=* ]]
    then
    IFS='=' read -r -a array <<< "$line"
    PingArray+=(`echo "${array[3]}" | cut -d' ' -f 1`)
  elif [[ $line == *received* ]]
    then
	  PingSent=`echo $line | cut -d' ' -f 1`
	  PingLoss=`echo $line | cut -d',' -f 3 | cut -d' ' -f 2`
  elif [[ $line == *min?avg?max* ]]
    then
	  PingMin=`echo $line | cut -d'/' -f 4 | cut -d' ' -f 3`
	  PingMax=`echo $line | cut -d'/' -f 6`
	  PingAvg=`echo $line | cut -d'/' -f 5`
  fi
done < $logDir/${strTestFile[1]}

# 9.2 Get percentile vaules
# http://www.dummies.com/education/math/statistics/how-to-calculate-percentiles-in-statistics/
IFS=$'\n' sortedPing=($(sort -n <<<"${PingArray[*]}"))
PingArrayCount=${#sortedPing[@]}
PingP50=${sortedPing[`getIndex $PingArrayCount 50` - 1]}
PingP90=${sortedPing[`getIndex $PingArrayCount 90` - 1]}
PingP95=${sortedPing[`getIndex $PingArrayCount 95` - 1]}

# 9.3 iPerf file loop
for i in {2..5}
do
  # 9.3.1 iPerf line loop
  WholeLine=""
  while IFS= read -r line
  do
    if [ $i -eq 2 ]
      then
	    if [[ $line == *receiver* ]]
	      then
	      WholeLine=$line
	    fi
    else
	    if [[ $line == *SUM* && $line == *receiver* ]]
	      then
	      WholeLine=$line
	    fi
    fi
  done < $logDir/${strTestFile[$i]}
  PaddedLine=`echo "$WholeLine" | cut -c38-55`
  ValuePart=`echo "$PaddedLine" | cut -d' ' -f 2`
  ScalePart=`echo "$PaddedLine" | cut -d' ' -f 3`
  if [[ "$ScalePart" == "Gbits/sec" ]]
    then
    ScaleConv="Gbps"
  elif [[ "$ScalePart" == "Mbits/sec" ]]
    then
    ScaleConv="Mbps"
  else
    ScaleConv="$ScalePart"
  fi
  TPut[$i]="$ValuePart $ScaleConv"
done
tput setaf 6
printf 'Test complete!\n'
tput sgr0
printf "\n"

# 10. Output results
format1="%-30s %4s  %-17s  %-17s\n"
format2="%-19s %9s\n"

temp1="$PingMin/$PingAvg/$PingMax"
temp2="$PingP50/$PingP90/$PingP95"

#format 1  "|           %30s             | |4s|  |     17s       |  |       17s      |"
#format 2  "|           %19s  | |   %9s |"
#printf    "         1         2         3         4         5         6         7         8\n"
#printf    "12345678901234567890123456789012345678901234567890123456789012345678901234567890\n"
printf "\n"
printf "Test                Bandwidth  Loss  min/avg/max        P50/P90/P95\n"
printf -- "----                ---------  ----  -----------        -----------\n"
printf "$format1" "Latency" "$PingLoss" "$temp1" "$temp2"
printf "$format2" "1 Session" "${TPut[2]}"
printf "$format2" "6 Sessions" "${TPut[3]}"
printf "$format2" "16 Sessions" "${TPut[4]}"
# printf "$format2" "16 with 1Mb window" "${TPut[5]}"
printf "$format2" "32 Sessions" "${TPut[5]}"
printf "\n"