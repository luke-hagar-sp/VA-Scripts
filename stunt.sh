#!/bin/bash

VERSION="v0.7"
LOGFILE=/home/sailpoint/stuntlog.txt
DATE=$(date -u +"%b_%d_%y-%H:%M")
DIVIDER="==========================================================================="

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
  echo "Syntax: ./stunt.sh [-h] [-t|p]"
  echo "Options:"
  echo "h   Print this help info and exit"
  echo "t   Add tracepath test"
  echo "p   Add ping test"
}

# Get cmd line args
while getopts ":htp" option; do
  case $option in
    h) #display help
      help
      exit;;
    t)
      do_tracepath=true;;
    p)
      do_ping=true;;
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
echo 

# Global vars for functions
is_canal_enabled=false

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
  echo "***************************************************************************" >> $LOGFILE
  echo "*** Look for $1" >> $LOGFILE
  echo "***************************************************************************" >> $LOGFILE
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
lookFor "this section to contain 'Flatcar' and not 'CoreOS'."
uname -a >> $LOGFILE
outro

intro "Getting /etc/os-release info" "cat /etc/os-release"
lookFor "'NAME=\"Flatcar Container Linux by Kinvolk\"'. Check that version is semi-recent: https://www.flatcar.org/releases#stable-release"
cat /etc/os-release >> $LOGFILE
outro

intro "Getting CPU information" "lscpu"
lookFor "the number of CPU(s) to be >= 2 CPUs. This is from AWS m4.large specs."
lscpu >> $LOGFILE
outro

intro "Getting total RAM" "free"
lookFor "the RAM to be >= 8GB. This is from AWS m4.large specs."
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
sudo systemctl disable esx_dhcp_bump >> $LOGFILE
outro

intro "External connectivity: Connection test for SQS (https://sqs.us-east-1.amazonaws.com)"
lookFor "a result of 404"
curl -i https://sqs.us-east-1.amazonaws.com 2> /dev/null >> $LOGFILE
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

# close and datestamp
echo "$(date -u) - END TESTS for $orgname on $podname " >> $LOGFILE
echo >&2 "*** Tests completed on $(date -u) ***

$DIVIDER
PLEASE RETRIEVE ${LOGFILE} AND UPLOAD TO YOUR CASE
$DIVIDER"
