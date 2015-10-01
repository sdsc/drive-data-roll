#!/bin/bash

version=0.5
# Orchestrates folder creation, file naming and calling of metrics collection scripts

# Version 0.5, July/August 2015 BEL
# Accepts Application-name and JobID as parameters to be used in folder and file naming
# Accepts a run-time parameter
# Accept a function parameter of START or END
# The Start function kicks off time-based scripts in their own threads
# The End function terminates any running time-based scripts and starts job-end scripts
# Logs activity to log file

set -e

if [ $# -ne 4 ]; then #note can't log this as log is not set up at this point
  echo "Please specify function[start|end] application-name job-id run-time on command line"
  exit 1
fi

#Capture command-line parameters
declare -u func=$1
declare appname=$2
declare jobid=$3
declare runtime=$4 #Runtime in seconds

#Calculate time parameters for time based scripts
declare -i runsecs=$runtime #run time in seconds, entire period over which the script runs
declare -i tracedwell=$runsecs #duration of a single trace in seconds
if [ $tracedwell -gt 1800 ]; then tracedwell=1800; fi #1/2 hour max
declare -i sampleperiodsecs=$runsecs #duration of a period within which trace sample is taken
if [ $sampleperiodsecs -gt 3600 ]; then sampleperiodsecs=3600; fi #1 hour max
declare -i firstwaitsecs=-1 #delay in seconds to first trace sample, -1=no initial sample
declare -i padsecs=0 #seconds from end of trace to end of sample period

#Build folder name
declare TESTdt=`date +%Y-%m-%d_%H-%M`
declare filebase="$appname_jobid_$(hostname -s)"
declare folder="/scratch/drive-data/$jobid/$TESTdt_$filebase"
declare logpath="$folder/$filebase.log"

#Detemine directory of executable
declare stxappdir=$(dirname $0)

logcreate()
{
    /bin/mkdir -p $folder
    if [[ 0 -ne $? ]]; then
        echo "Could not create $folder"
        exit 1
    else
        /bin/touch $logpath
        if [[ 0 -ne $? ]]; then
            echo "Could not create $logpath"
        exit 1
    fi
fi
}

logstart()
{
    echo "Date-time stamp  Event version $version" >> $logpath
    logadd "Function $func, App $appname, Job $jobid, Runtime(sec) $runtime"
}

logadd() #Event text passed as parameter
{
    echo `date +%Y-%m-%d_%H-%M` $@ >> $logpath
}

logcreate
logstart

#Discover drives as /dev/sdx and place in _drives array
#Call SeaChest -s to get SCSI_generic names filtered by drive model
#Expects the following format
#SEAGATE   /dev/sg4  ST800FM0043             0056ed22               4.30      
declare SEACHEST=${stxappdir}/SeaChest
declare AWKBIN=$(which awk)
declare ITDRVS=`$SEACHEST -s |grep "INTEL SSDSC2BB160G4R"   |tr -s ' '|cut -d" " -f2`
declare SGDRVS=`$SEACHEST -s |grep "ST[0-9]00FM"   |tr -s ' '|cut -d" " -f2`
declare -a _drives=($ITDRVS $SGDRVS)
logadd "${#_drives[@]} drives found"

#Convert SCSI generic list, /dev/sgx, to block device list, /dev/sdy
for ((ndx=0; ndx < ${#_drives[@]}; ndx++)); do
  _drive=`echo ${_drives[$ndx]} | cut -d"/" -f3` #strip /dev/
  #Find sgx string in /sys/class/scsi_generic
  # lrwxrwxrwx. 1 root root 0 Jul 23 09:32 sg0 -> ../../devices/pci0000:00/0000:00:02.0/0000:02:00.0/host0/target0:2:0/0:2:0:0/scsi_generic/sg0
  #
  #Collect SCSI target string - targetH:B:T
  _SCSIt=`ls -ls /sys/class/scsi_generic | $AWKBIN -v pat=$_drive -F/ '$0 ~ pat {print $8}'`
  #Find target string in /sys/dev/block
  # lrwxrwxrwx. 1 root root 0 Jul 23 09:37 8:0 -> ../../devices/pci0000:00/0000:00:02.0/0000:02:00.0/host0/target0:2:0/0:2:0:0/block/sda
  #
  #Collect block device name - sdy, and replace sgx with /dev/sdy in _drives array
  _drives[$ndx]="/dev/"`ls -ls /sys/dev/block | $AWKBIN -v pat=$_SCSIt -F/ '$0 ~ pat {print $11}' | /bin/sort -u`
  logadd "/dev/$_drive = ${_drives[$ndx]}"
done

#Define scripts and their parameters
#Array for scripts to run at start. Can be added to. Run in their own thread.
declare -a _scriptstostart=()
for ((ndx=0; ndx < ${#_drives[@]}; ndx++)); do
  script="'${stxappdir}/blktrscript.sh ${_drives[$ndx]} $runsecs $tracedwell $sampleperiodsecs $firstwaitsecs $padsecs $folder $filebase'"
  _scriptstostart+=("$script")
  script="'${stxappdir}/statsscript.sh ${_drives[$ndx]} $runsecs $tracedwell $sampleperiodsecs $firstwaitsecs $padsecs $folder $filebase'"
  _scriptstostart+=("$script")
done

#Array for scripts to run at end. Can be added to. Run sequentially in this thread.
declare -a _scriptsatend=("${stxappdir}/stxm2.sh")

#Kick off sampling scripts in separate threads and return
if [ $func == "START" ]; then

    for ((ndx=0; ndx < ${#_scriptstostart[@]}; ndx++)); do
        script=$(echo ${_scriptstostart[$ndx]} | /bin/sed "s/'//g") 
        logadd "Starting ${script}"
        ${script} &
    done
    exit 0
fi

#Kill sampling scripts if still running and kick off ending scripts
if [ $func == "END" ]; then

    #Kill any running sampling scripts
    for ((ndx=0; ndx < ${#_scriptstostart[@]}; ndx++)); do
        unset _commandparams
        script=$(echo ${_scriptstostart[$ndx]} | /bin/sed "s/'//g")
        declare -a _commandparams=(${script}) #Break apart command and parameters into array so command is 1st element
        declare command=${_commandparams[0]}
        declare -i maxattempts=10 attempts=0
        for (( attempts=0; attempts < maxattempts; attempts++ )); do
            #ps -ef output format - UID        PID  PPID  C STIME TTY          TIME CMD
            pid=`ps -ef | gawk '{if ($9 == "'$command'") print $2}'` #CMD will be /bin/bash, so command is $9
            if [ "X$pid" != "X" ]; then kill -SIGUSR1 $pid; else break; fi
            sleep 1
        done
        if [ $attempts -ge $maxattempts ]; then
            logadd "Unable to stop $command in $maxattempts seconds"
        else
            logadd "Stopped $command in $attempts seconds"
        fi
    done

    #Run end scripts
    for ((ndx=0; ndx < ${#_scriptsatend[@]}; ndx++)); do
        script=$(echo ${_scriptstostart[$ndx]} | /bin/sed "s/'//g")
        logadd "Running   $script"
        ${script}
        logadd "Completed $script"
    done
    exit 0
fi

msg="Invalid function $func"
echo $msg
logadd $msg
exit 1 #First parameter invalid function

#Observations for ps -ef

#Test with a parameter starts a subprocess for parameter seconds
#[root@T620Eric SDSC]# ./test.sh 8
#1
#start count
#./test.sh
#root     27762  9264  0 10:24 pts/0    00:00:00 /bin/bash ./test.sh 8
#root     27765 27762  0 10:24 pts/0    00:00:00 grep ./test.sh
#0:27762
#27767:
#This is the child process that has been started, $? is 0
#0:root     27763 27762  0 10:24 pts/0    00:00:00 /bin/bash ./count.sh 5:
#Call the script again with no parameter, does not start a new subprocess
#[root@T620Eric SDSC]# ./test.sh 
#0
#./test.sh
#root     27777  9264  0 10:24 pts/0    00:00:00 /bin/bash ./test.sh
#root     27779 27777  0 10:24 pts/0    00:00:00 grep ./test.sh
#0:27777
#27780:
#This is the previously invoked subprocess now running on its own, $? is 0
#0:root     27763     1  0 10:24 pts/0    00:00:00 /bin/bash ./count.sh 5:
#[root@T620Eric SDSC]# 
#Time elapses and the subprocess terminates
#[root@T620Eric SDSC]# ./test.sh 
#0
#./test.sh
#root     27796  9264  0 10:27 pts/0    00:00:00 /bin/bash ./test.sh
#root     27798 27796  0 10:27 pts/0    00:00:00 grep ./test.sh
#0:27796
#27799:
#There is no process named count, $? is still 0
#0::

