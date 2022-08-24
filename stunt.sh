#!/bin/bash
#Testing 
# /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/luke-hagar-sp/VA-Scripts/dev/stunt.sh)"
#Prod 
# /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/luke-hagar-sp/VA-Scripts/main/stunt.sh)"

VERSION="v0.8"
LOGFILE=/home/sailpoint/stuntlog.txt
DATE=$(date -u +"%b_%d_%y-%H:%M")
DIVIDER="================================================================================"

if [[ -e "/home/sailpoint/config.yaml" ]]; then
  orgname=$(awk '/org/' /home/sailpoint/config.yaml | sed 's/org: //' | sed 's/\r$//') &&
  podname=$(awk '/pod/' /home/sailpoint/config.yaml | sed 's/pod: //' | sed 's/\r$//')
else
  echo "*** Config file not found. Please run this only on a SailPoint VA."
  echo "*** Execution stopped; no log file created or changes made. ***"
  exit 1
fi


help () {
  # Display help
  echo "The stunt script collects information about the current state of your"
  echo "VA, and places that data into a stuntlog.txt file. Collecting this helps"
  echo "SailPoint Cloud Support Engineers troubleshoot your system."
  echo
  echo "Syntax: ./stunt.sh [-h] [-t|p|u]"
  echo "Options:"
  echo "h   Print this help info and exit"
  echo "t   Add tracepath test"
  echo "p   Add ping test"
  echo "u   Perform forced update (this will make system changes)"
}

# Get cmd line args
while getopts ":htpu" option; do
  case $option in
    h) #display help
      help
      exit;;
    t)
      do_tracepath=true;;
    p)
      do_ping=true;;
    u)
      do_update=true;;
    \?) 
      echo "Invalid argument on command line. Please review help with ./stunt.sh -h"
      exit;;
    esac
done

echo $DIVIDER
echo "STUNT -- Support Team UNified Test -- ${VERSION}"
echo $DIVIDER
echo "*** This script tests network connectivity, gathers log/system data,"
echo "*** performs recommended setup steps from the SailPoint VA documents which"
echo "*** when skipped will cause network connectivity problems, and creates a"
echo "*** log file at ${LOGFILE}."
echo "*** No warranty is expressed or implied for this tool by SailPoint."
echo 

# Global vars for functions
is_canal_enabled=false
commandOutput=()
# Functions

# args:
# $1 == stdout description
# $2 == description for logfile if different
intro () {
  echo $DIVIDER >> $LOGFILE
  echo "$1"
  if [[ -e $2 ]]; then
    echo "$2" >> $LOGFILE
  else
    echo "$1" >> $LOGFILE
  fi
  echo $DIVIDER >> $LOGFILE
}

outro () {
  echo >> $LOGFILE
  echo
}

lookFor() {
  echo "********************************************************************************" >> $LOGFILE
  echo "*** Look for $1" >> $LOGFILE
  echo "********************************************************************************" >> $LOGFILE
}

# args:
# $1 == output of the command you are testing, use `command` format
# $2 == pattern that means success
# $3 == Description of the test
# $4 == original look for message, to preserve the log file structure
checkResponse() {
  echo $1
  echo $2
  echo $3
  echo $4
  result=$(grep -e "$2" "$1")
  echo $result
  if [ -n "$result" ]; then
    commandOutput+=("$3 Test Succeeded")
  else
    commandOutput+=("$3 Test Failed")
  fi
  lookFor "$4"
  echo "$1" >> $LOGFILE
}

if test -f "$LOGFILE"; then
  echo "*** Found an old log file. Renaming and creating new file." &&
  cp $LOGFILE $LOGFILE.$DATE.old &&
  rm $LOGFILE
fi

touch $LOGFILE
# Start the tests by placing a header in the logfile
echo $DIVIDER
echo "$(date -u) - STARTING TESTS for $orgname on $podname"
echo $DIVIDER
echo "$(date -u) - START TESTS for $orgname on $podname on stunt.sh $VERSION " >> $LOGFILE
outro

# detect Canal in config.yaml
if [[ $(cat /home/sailpoint/config.yaml) == *"tunnelTraffic: true"* ]]; then
  is_canal_enabled=true
  echo "Found that Secure Tunnel (canal) service is enabled; additional tests will be run"
  intro "NOTE: CANAL CONFIG DETECTED"
fi

# Execute tests

intro "Getting config.yaml" "~/config.yaml"
cat config.yaml | sed "s/keyPassphrase:.*/keyPassphrase: <redacted>/g" >> $LOGFILE
outro

intro "Getting OS version" "OS version with uname"
checkResponse `uname -a` "NAME=Flatcar Container Linux by Kinvolk" "Valdiating OS is Flatcar" "this section to contain 'Flatcar' and not 'CoreOS'."
outro

intro "Getting OpenJDK version from ccg" "grep -i openjdk ~/log/worker.log"
lookFor "this version of java to be 11.0.14 or higher and not 1.8.x: openjdk version '11.0.14' 2022-01-18"
grep -a openjdk /home/sailpoint/log/worker.log | tail -1 >> $LOGFILE
outro

if test -f /etc/profile.env; then
  intro "Getting profile.env" "cat /etc/profile.env"
  lookFor "existence of the file. May need to remove it if proxying is an issue."
  cat /etc/profile.env 1>> $LOGFILE 2>> $LOGFILE
  outro
fi

if test -f /etc/systemd/system.conf.d/10-default-env.conf; then
  intro "Getting 10-default-env.conf" "cat /etc/systemd/system.conf.d/10-default-env.conf"
  lookFor "existence of the file. May need to remove it if proxying is an issue."
  cat /etc/systemd/system.conf.d/10-default-env.conf 1>> $LOGFILE 2>> $LOGFILE
  outro
fi

intro "Getting docker.env" "cat /home/sailpoint/docker.env"
lookFor "proxy references in docker.env. Remove references to proxy if they're in this file and proxying is an issue."
cat /home/sailpoint/docker.env >> $LOGFILE
outro

if test -f /etc/systemd/network/static.network; then
  intro "Getting the static.network file" "cat /etc/systemd/network/static.network"
  lookFor "existence of the file. If so, individual DNS entries should be on separate lines beginning with 'DNS'."
  cat /etc/systemd/network/static.network >> $LOGFILE
  outro
fi

intro "Getting the resolv.conf file" "cat /etc/resolv.conf"
lookFor "DNS entries to match those in static.network, if it exists."
cat /etc/resolv.conf >> $LOGFILE
outro

if test -f /home/sailpoint/proxy.yaml; then
  intro "Getting the proxy config" "cat /home/sailpoint/proxy.yaml"
  cat /home/sailpoint/proxy.yaml >> $LOGFILE
  outro
fi

intro "Getting /etc/os-release info" "cat /etc/os-release"
lookFor "'NAME=Flatcar Container Linux by Kinvolk'. Check that version is >= 3227.*.*. If lower, run ./stunt.sh -u and reboot after."
cat /etc/os-release >> $LOGFILE
outro

intro "Getting CPU information" "lscpu"
lookFor "the number of CPU(s) to be >= 2 CPUs. This is from AWS m4.large specs."
lscpu >> $LOGFILE
outro

intro "Getting total RAM" "free"
lookFor "the RAM to be >= 7.3Gi (approx 8GB). This is from AWS m4.large specs."
free -h >> $LOGFILE
outro

intro "Network information for adapters" "ifconfig"
lookFor "an IP attached to the main adapter, (e.g., it isn't blank). Usually on ens160, or eth0"
ifconfig >> $LOGFILE
outro

intro "Getting networking check in charon.log" "charon.log networking check"
lookFor "all services to say \"PASS\" after their name"
grep -a "Networking check" /home/sailpoint/log/charon.log | tail -1 >> $LOGFILE
outro

intro "This step disables esx_dhcp_bump" "Disable esx_dhcp_bump"
lookFor "any output stating this was removed/disabled. If there is, be sure to do a sudo reboot."
sudo systemctl disable esx_dhcp_bump 1>> $LOGFILE 2>> $LOGFILE
outro

intro "External connectivity: Connection test for SQS (https://sqs.us-east-1.amazonaws.com)"
lookFor "a result of 404"
curl -i -vv https://sqs.us-east-1.amazonaws.com 2> /dev/null >> $LOGFILE
outro

intro "External connectivity: Connection test for $orgname.identitynow.com"
lookFor "a result of 302"
curl -i "https://$orgname.identitynow.com" 2> /dev/null >> $LOGFILE
outro

intro "External connectivity: Connection test for $orgname.api.identitynow.com"
lookFor "a result of 404"
curl -i "https://$orgname.api.identitynow.com" 2> /dev/null >> $LOGFILE
outro

intro "External connectivity: Connection test for $podname.accessiq.sailpoint.com"
lookFor "a result of 302"
curl -i "https://$podname.accessiq.sailpoint.com" 2> /dev/null >> $LOGFILE
outro

intro "External connectivity: Connection test for DynamoDB (https://dynamodb.us-east-1.amazonaws.com)"
lookFor "a result of 200"
curl -i https://dynamodb.us-east-1.amazonaws.com 2> /dev/null >> $LOGFILE
outro

if [ "$do_ping" = true ]; then
  intro "Pinging IdentityNow tenant" "ping -c 5 -W 2 $orgname.identitynow.com"
  ping -c 5 -W 2 $orgname.identitynow.com >> $LOGFILE
  outro
fi

if [ "$do_tracepath" = true ]; then
  intro "Collecting tracepath to SQS... this might take a minute" "tracepath sqs.us-east-1.amazonaws.com"
  tracepath sqs.us-east-1.amazonaws.com >> $LOGFILE
  outro
fi

intro "Getting route command output" "route output"
route >> $LOGFILE
outro

intro "Getting ccg.log - errors only" "ccg.log - 30 error lines"
lookFor "datestamps. Some logs might be very old and no longer pertinent."
lookFor "any error that says keystore.jks is missing or cannot be found; usually the keyPassphrase in config.yaml does not match the initial setting"
cat ./log/ccg.log | grep stacktrace | tail -n30 >> $LOGFILE
outro

intro "Getting docker images" "docker images"
lookFor "the CCG image: it should be less than 3 weeks old."
sudo docker images >> $LOGFILE
outro

intro "Getting docker processes" "docker processes"
lookFor "the following four (4) processes to be running: ccg, va_agent, charon, and va"
sudo docker ps >> $LOGFILE
outro

intro "Getting partition table info" "lsblk"
lookFor "total disk space under \"SIZE\". Should be ~128GB or more."
lookFor "one sda<#> to be TYPE 'part' and RO '0'. This means the PARTition is writable."
lsblk -o NAME,SIZE,FSSIZE,FSAVAIL,FSUSE%,MOUNTPOINT,TYPE,RO >> $LOGFILE
outro

intro "Getting disk usage stats" "disk usage - df -h"
df -h >> $LOGFILE
outro

intro "Getting jobs list" "ls -l /opt/sailpoint/share/jobs/"
lookFor "this to be (almost) empty. If lots of jobs are > 1 week old, run: sudo rm -rf /opt/sailpoint/share/jobs/* && sudo reboot"
ls -l /opt/sailpoint/share/jobs/ >> $LOGFILE
outro

intro "Getting last 50 lines of kernel journal logs" "kernel journal logs"
sudo journalctl -n50 -k >> $LOGFILE
outro

intro "Getting last 50 lines of network journal logs" "network journal logs"
sudo journalctl -n50 -u systemd-networkd >> $LOGFILE
outro

intro "Getting last 50 lines of ccg journal logs" "ccg journal logs"
sudo journalctl -n50 -u ccg >> $LOGFILE
outro

intro "Getting last 50 lines of va_agent journal logs" "va_agent journal logs"
sudo journalctl -n50 -u va_agent  >> $LOGFILE
outro

if [ "$is_canal_enabled" = true ]; then
  intro "The following tests are only run if Secure Tunnel config has been enabled"

  intro "Testing Secure Tunnel initialization handshake"
  lookFor "Output below should not be blank, and should begin with '^@^Z@'"
  echo -e "\x00\x0e\x38\xa3\xcf\xa4\x6b\x74\xf3\x12\x8a\x00\x00\x00\x00\x00" | ncat va-gateway-useast1.identitynow.com 443 | cat -v >> $LOGFILE
  outro

  intro "Getting last 50 lines of canal service journal logs" "canal service journal logs"
  sudo journalctl -n50 -u canal  >> $LOGFILE 
  outro
fi

if [ "$do_update" = true ]; then
  intro "Performing forced update - this process resets the machine-id and the update service. *REBOOTS ARE REQUIRED WHEN SUCCESSFUL*" "Forced update logs"
  sudo rm -f /etc/machine-id  1>> $LOGFILE 2>> $LOGFILE
  sudo systemd-machine-id-setup  1>> $LOGFILE 2>> $LOGFILE
  sudo systemctl restart update-engine  1>> $LOGFILE 2>> $LOGFILE
  sudo update_engine_client -update 1>> $LOGFILE 2>> $LOGFILE
  outro
fi

# close and datestamp
echo "$(date -u) - END TESTS for $orgname on $podname " >> $LOGFILE
echo >&2 "*** Tests completed on $(date -u) ***

echo ${commandOutput[@]}.

$DIVIDER
PLEASE RETRIEVE ${LOGFILE} AND UPLOAD TO YOUR CASE
$DIVIDER"