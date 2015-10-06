#!/bin/bash

version=1.1
# blktrscript.sh orchestrates taking blktrace/parse samples

# Version 1.1, July/August 2015 BEL
# Based on tracescript.sh done for sysbench testing
# Added usage info
# Changed file naming

# Version 1.0, March 2015.
# Runs blktrace after 2 minutes (firstwaitsecs) then at the end of every period thereafter

# Detemine directory of executable and source common functions
declare stxappdir=$(dirname $0)
source ${stxappdir}/common.sh

# Set parameters
declare    device=$1 #device to trace
declare -i runsecs=${2:-14400} #run time in seconds, entire period over which the script runs
declare -i tracedwell=${3:-60} #duration of a single trace in seconds
declare -i sampleperiodsecs=${4:-3600} #duration of a period within which trace sample is taken
declare -i firstwaitsecs=${5:-120} #delay in seconds to first trace sample
declare -i padsecs=${6:-30} #seconds from end of trace to end of sample period
declare    tracedir=${7:-tracedir} #folder name for the traces, also helps organize traces
declare    trname=$8 #file name uiniquiefier to include test case info and help identify trace

if [ $firstwaitsecs -lt 0 ]; then
    firstwaitsecs=0
    initialtrace="FALSE"
else
    initialtrace="TRUE"
fi
runperiods=$((runsecs/sampleperiodsecs))
period=0
TESTdt=`date +%Y-%m-%d_%H-%M`
logfile=$tracedir"/"$TESTdt"trace.log"
partfile=$tracedir/$TESTdt"_partitions"

usage()
{
    echo -e "\n******************************************"
    echo "$0 version $version"
    echo
    echo "Captures multiple blktrace|blkparse output files"
    echo "Only the blkparse output is saved, not blktrace files"
    echo "The default blkparse output format is used"
    echo "The /proc/partitions file is captured"
    echo "Takes care of mounting the debug FS if not yet mounted"
    echo "Logs actions to a log file"
    echo
    echo "Usage: $0 device [run_time [trace_dwell [sample_period [initial_wait [end_pad [folder [name]]]]]]]"
    echo
    echo "All times in seconds"
    echo "Only the device parameter is required.  However -"
    echo " parameters are positional and must be included when any parameter further right is included"
    echo 'device is the device name to trace as in /dev/sdx, can include multiple in quotes "/dev/sdy /dev/sdz"'
    echo "run_time is the overall time to run the script, defaults to 14400 seconds (4 hours)"
    echo "trace_dwell is the duration of each trace, defaults to 60 seconds"
    echo "sample_period is period within which a trace will be taken, defaults to 3600 seconds (1 hour)"
    echo "initial_wait is delay prior to taking the first trace in the first period, defaults to 120 seconds"
    echo " If initial_wait is negative the initial first period trace will be skipped"
    echo "end_pad is the time from the end of a trace to the end of a sample period, defaults to 30 seconds"
    echo "folder is the name of the folder to hold the traces and log, defaults to tracedir"
    echo "name is text to include in the trace file names to help identify the trace, defaults to blank"
    echo
    echo "Assuming a long enough run_time, two traces are taken in the first period. One after initial_wait"
    echo " and one that completes end_pad prior to the end of the first period."
    echo "Each subsequent period, if any, includes one trace that completes end_pad prior to the period end"
    echo "Each trace file name begins with a date-time stamp and includes the supplied name, if any,"
    echo " number of periods and the period number"
    echo "An output log file is captured with a name that begins with a date-time stamp and ends in trace.log"
    echo
    echo "Example: $0 /dev/sdx 36000 1800 7200 60 30 DBtraces jobx"
    echo "This traces device /dev/sdx over the course of 10 hours with half hour traces taken every two hours"
    echo "The first two hour period has the first trace taken 1 minute after starting the script"
    echo "All five periods have a trace taken that completes a half minute prior to the end of the period"
    echo "Trace file names are placed in the folder named DBtraces and include the string jobx in the file name"
    echo -e "******************************************\n"
    exit
}

#Setup termination procedure
makeitstop()
{
    #Check if blktrace is running, if so kill it
    #Apparently the trap isn't called until after blktrace completes
    declare -i maxattempts=10 attempts=0
    for (( attempts=0; attempts < maxattempts; attempts++ )); do
        #ps -ef output format - UID        PID  PPID  C STIME TTY          TIME CMD
        pid=`ps -ef | gawk '{if ($8 == "blktrace") print $2}'`
        if [ "X$pid" != "X" ]; then kill -SIGUSR1 $pid; else break; fi
        sleep 1
    done
    if [ $attempts -ge $maxattempts ]; then
        logadd "Unable to stop $command in $maxattempts seconds"
    else
        logadd "Stopped $command in $attempts seconds"
    fi
    #Check if blkparse or btconvert is running, if so wait until they complete then exit
    for command in blkparse btconvert.sh; do
        declare -i maxattempts=1000 attempts=0 #large value for max
        for (( attempts=0; attempts < maxattempts; attempts++ )); do
            #ps -ef output format - UID        PID  PPID  C STIME TTY          TIME CMD
            pid=`ps -ef | gawk '{if ($8 == "'$command'") print $2}'`
            if [ "X$pid" == "X" ]; then break; fi
            sleep 1
        done
        if [ $attempts -ge $maxattempts ]; then
            logadd "$command hasn't stopped in $maxattempts seconds"
        else
            logadd "$command completed in $attempts seconds"
        fi
    done
    exit 0 #exit w/o starting any further periods
}

#Set trap for termination signal
trap "makeitstop" SIGUSR1

logmessage()
{
    echo `date +%Y-%m-%d_%H-%M` $@ >> $logfile
}

gettrace()
{
    tracedt=`date +%Y-%m-%d_%H-%M`
    outfile=$tracedir"/"$tracedt$trname"_period"$((period++))"of${runperiods}_blkp"
    logmessage "Logging to $outfile"
    blktrace -d $device -w $tracedwell -o - | blkparse -i - -o $outfile
    #convert to .csv by device
    declare -a _drives=($device)
    for dev in ${_drives[@]}; do
        ./btconvert.sh $outfile $partfile - DC $dev
    done
}

if [ $# -lt 1 ]; then usage; fi #Display usage if no parameters are given

#Make folder for storing traces and log if not already existing
if [ ! -d $tracedir ]; then mkdir -p $tracedir; fi

#Prepend _ to trname if not null
if [ "x$trname" != "x" ]; then trname="_"$trname; fi

#Start log
logmessage "$@, version $version"

#Log parameters
logmessage "dwell $tracedwell, 1stwait $firstwaitsecs, period $sampleperiodsecs, pad $padsecs, periods $runperiods"

#Capture the partitions file
logmessage "Copying /proc/partitions to $partfile"
cp /proc/partitions $partfile

#Mount debug fs needed by blktrace if not already mounted
mount | grep debug || mount -t debugfs debugfs /sys/kernel/debug

#Take first trace after firstwaitsecs
if [ $initialtrace == "TRUE" -a $runsecs -gt $((firstwaitsecs+tracedwell)) ]; then
    sleep $firstwaitsecs
    gettrace
fi

if [ $runsecs -gt $((period-tracedwell)) ]; then
    #Each successive trace ends padsecs seconds prior to the end of the period
    sleep $((sampleperiodsecs-firstwaitsecs-tracedwell*2-padsecs))

    #Take trace at the end of each successive period
    while [ $runperiods -ge $period ]; do
        gettrace
        if [ $runperiods -ge $period ]; then sleep $((sampleperiodsecs-tracedwell)); fi
    done
fi
logmessage "Done"
