#!/bin/bash

version=0.7
# Orchestrates folder creation, file naming and calling of metrics collection scripts

# Version 0.7, January 2016 BEL
# Added call to smartscript.sh in scriptstostart and scriptsatend
# Removed extra / from the basefolder string
# Added check for no drives found and exit with status 2

# Version 0.66, November 2015 BEL
# Added basefolder to define the base location for collected files and moved log to this folder
# Corrected formation filebase and folder to match design spec
# Removed date-time-stamp from folder definition, this is a spec change
# Corrected name of drive logging script from stxm2.sh to stxsm2.sh
# Remove for loop from start script generation and fixed quoting around drives ie "/dev/sdx /dev/sdy . . ."
# Fixed convert from SCSI generic by referencing fields from the end of the string
# Simplified start script initiation
# Added folder and filebase to end command SM2

# Version 0.6, October 2015 TKC
# Refactoring, common code to ./common.sh which must be sourced early
# _scriptstostart array restructured
# _sleep() function to allow interruption of long waits
# Changes for readability

# Version 0.5, July/August 2015 BEL
# Accepts Application-name and JobID as parameters to be used in folder and file naming
# Accepts a run-time parameter
# Accept a function parameter of START or END
# The Start function kicks off time-based scripts in their own threads
# The End function terminates any running time-based scripts and starts job-end scripts
# Logs activity to log file

# Exit status 0 for good, 1 for parameter error, 2 for no drives found

set -e

if [ $# -ne 4 ]; then #note can't log this as log is not set up at this point
  echo "Please specify function[start|end] application-name job-id run-time (sec) on command line"
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
declare filebase="${appname}_${jobid}_$(hostname -s)"
declare basefolder="/scratch/drive-data"
declare folder="$basefolder/$appname/${appname}_$jobid/$filebase"
declare logfile="$basefolder/$(hostname -s).log"

#Detemine directory of executable
declare stxappdir=$(dirname $0)
source ${stxappdir}/common.sh

#Create/Start log
logcreate $logfile
logstart $logfile
logmessage "Command Line: $(readlink -fn $0) $@"
logmessage "Function $func, App $appname, Job $jobid, Runtime(sec) $runtime"

#Discover drives as /dev/sdx and place in _drives array
#Call SeaChest -s to get SCSI_generic names filtered by drive model
#Expects the following format
#SEAGATE   /dev/sg4  ST800FM0043             0056ed22               4.30
declare ITDRVS=`$SEACHEST -s |grep "INTEL SSDSC2BB160G4R"   |tr -s ' '|cut -d" " -f2`
declare SGDRVS=`$SEACHEST -s |grep "ST[0-9]00FM"   |tr -s ' '|cut -d" " -f2`
#declare SGDRVS=`$SEACHEST -s |grep "ST[3,8]00[F,M]M"   |tr -s ' '|cut -d" " -f2` #for debug
declare -a _drives=($ITDRVS $SGDRVS)
logmessage "${#_drives[@]} drives found"
if [ ${#_drives[@]} -eq 0 ];then logmessage "Exiting due to no drives found";exit 2;fi

#Convert SCSI generic list, /dev/sgx, to block device list, /dev/sdy
for ((ndx=0; ndx < ${#_drives[@]}; ndx++)); do
    drive=`echo ${_drives[$ndx]} | cut -d"/" -f3` #strip /dev/
    #Find sgx string in /sys/class/scsi_generic
    # lrwxrwxrwx. 1 root root 0 Jul 23 09:32 sg0 -> ../../devices/pci0000:00/0000:00:02.0/0000:02:00.0/host0/target0:2:0/0:2:0:0/scsi_generic/sg0
    #
    #Collect SCSI target string - targetH:B:T
    SCSIt=`ls -ls /sys/class/scsi_generic | $AWKBIN -F/ '{if (NF > 2) {if ($(NF) == "'$drive'") print $(NF-3)}}'`
    #Find target string in /sys/dev/block
    # lrwxrwxrwx. 1 root root 0 Jul 23 09:37 8:0 -> ../../devices/pci0000:00/0000:00:02.0/0000:02:00.0/host0/target0:2:0/0:2:0:0/block/sda
    #
    #Collect block device name - sdy, and replace sgx with /dev/sdy in _drives array
    _drives[$ndx]="/dev/"`ls -ls /sys/dev/block | $AWKBIN -F/ '{if (NF > 2) {if ($(NF-3) == "'$SCSIt'") print $(NF)}}'`
    logmessage "/dev/$drive = ${_drives[$ndx]}"
done

#Define scripts and their parameters
#Array for scripts to run at start. Can be added to. Run in their own thread.
declare -a _scriptstostart=(\
"${stxappdir}/smartscript.sh $folder $filebase" \
"${stxappdir}/blktrscript.sh \"${_drives[@]}\" $runsecs $tracedwell $sampleperiodsecs $firstwaitsecs $padsecs $folder $filebase" \
"${stxappdir}/statsscript.sh \"${_drives[@]}\" $runsecs $tracedwell $sampleperiodsecs $firstwaitsecs $padsecs $folder $filebase"\
)

#Array for scripts to run at end. Can be added to. Run sequentially in this thread.
declare -a _scriptsatend=(\
"${stxappdir}/smartscript.sh $folder $filebase" \
"${stxappdir}/stxsm2.sh $folder $filebase")

#Kick off sampling scripts in separate threads and return
if [ $func == "START" ]; then
    for ((ndx=0; ndx < ${#_scriptstostart[@]}; ndx++)); do
        script=${_scriptstostart[$ndx]}
        logmessage "Starting ${script}"
        $script &
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
            pid=`/bin/ps -ef | $AWKBIN '{if ($9 == "'$command'") print $2}'` #CMD will be /bin/bash, so command is $9
            if [ "X$pid" != "X" ]; then
                /bin/kill -SIGUSR1 $pid
            else break
            fi
            _sleep 1
        done
        if [ $attempts -ge $maxattempts ]; then
            logmessage "Unable to stop $command in $maxattempts seconds"
            logmessage "Attempting hard kill of children of $command ($pid)"
            /usr/bin/pkill -KILL -P $pid
        else
            logmessage "Stopped $command in $attempts seconds"
        fi
    done

    #Run end scripts
    for ((ndx=0; ndx < ${#_scriptsatend[@]}; ndx++)); do
        script=$(echo ${_scriptsatend[$ndx]} | /bin/sed "s/'//g")
        logmessage "Running $script"
        ${script}
        logmessage "Completed $script"
    done
    exit 0
fi

msg="Invalid function $func"
echo $msg
logmessage $msg
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
