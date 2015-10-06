#!/bin/bash

version=1.2
# blktrscript.sh orchestrates taking blktrace/parse samples

# Version 1.2, October 2014 TKC
# Refactoring, common code to ./common.sh which must be sourced early
# Here document for usage
# _sleep() function to allow interruption of long waits
# Changes for readability

# Version 1.1, July/August 2015 BEL
# Based on tracescript.sh done for sysbench testing
# Added usage info
# Changed file naming

# Version 1.0, March 2015.
# Runs blktrace after 2 minutes (firstwaitsecs) then at the end of every period thereafter

# Detemine directory of executable and source common functions
declare stxappdir=$(dirname $0)
source ${stxappdir}/common.sh

declare BLKTRACE_BIN=$(which blktrace)
declare BLKPARSE_BIN=$(which blkparse)

if [[ ! -x ${BLKTRACE_BIN} ]] || [[ ! -x ${BLKPARSE_BIN} ]]; then
    echo "$(basename $0) cannot run without blktrace and blkparse"
    exit 1
fi

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
cat << EOT

==-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=-=-=-=-=-=-
$0 version $version

Captures multiple blktrace|blkparse output files
Only the blkparse output is saved, not blktrace files
The default blkparse output format is used
The /proc/partitions file is captured
Takes care of mounting the debug FS if not yet mounted
Logs actions to a log file

Usage: $0 device [run_time [trace_dwell [sample_period [initial_wait [end_pad [folder [name]]]]]]]

Only the device parameter is required. However parameters are positional and
must be included when any parameter further right is included.

Input parameters...

    device        - the device name to sample as in /dev/sdx, can include
                    multiple in quotes, for example... '/dev/sdy /dev/sdz'

    run_time      - the overall time to run the script, defaults to 14400
                    seconds (4 hours)

    trace_dwell   - the duration of each trace, defaults to 60 seconds

    sample_period - the period within which a trace will be taken, defaults
                    to 3600 seconds (1 hour)

    initial_wait  - the delay prior to taking the first sample in the first
                    period, defaults to 120 seconds. If initial_wait is -ve
                    the initial first period sample will be skipped

    end_pad       - the time from the end of a sample to the end of a sample
                    period, defaults to 30 seconds

    folder        - the name of the folder to hold the samples and log

    name          - text to include in the sample file names to help identify
                    the sample, defaults to ''

Assuming a long enough run_time, two traces are taken in the first period. One
after initial_wait and one that completes end_pad prior to the end of the first
period.

Each subsequent period, if any, includes one trace that completes end_pad prior
to the period end.

Each trace file name begins with a date-time stamp and includes the supplied
name, if any, number of periods and the period number.

An output log file is captured with a name that begins with a date-time stamp
and ends in trace.log

Example:

    $0 /dev/sdx 36000 1800 7200 60 30 DBtraces jobx

This traces device /dev/sdx over the course of 10 hours with half hour traces
taken every two hours.

The first two hour period has the first trace taken 1 minute after starting the
script.

All five periods have a trace taken that completes a half minute prior to the
end of the period.

Trace file names are placed in the folder named DBtraces and include the string
jobx in the file name.

==-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=-=-=-=-=-=-
EOT

    exit
}

#Setup termination procedure
trap_mesg()
{
    #Check if blktrace is running, if so kill it
    declare -i maxattempts=10 attempts=0
    for (( attempts=0; attempts < maxattempts; attempts++ )); do
        declare -a pid=($(pgrep blktrace))
        if [ ${#pid[@]} -gt 0 ]; then
        for (( ndx=0; ndx<${#pid[@]}; ndx++ )); do
            kill -SIGTERM ${pid[$ndx]} || kill -SIGINT ${pid[$ndx]} || kill -SIGKILL ${pid[$ndx]}
        done
        else
        break
        fi
    _sleep 1
    done

    if [ $attempts -ge $maxattempts ]; then
        logmessage "Unable to stop blktrace in $maxattempts seconds"
    else
        logmessage "Stopped blktrace in $attempts seconds"
    fi

    #Check if blkparse or btconvert is running, if so wait until they complete then exit
    for command in blkparse btconvert.sh; do
        declare -i maxattempts=1000 attempts=0 #large value for max
        for (( attempts=0; attempts < maxattempts; attempts++ )); do
            declare -a pid=($(pgrep ${command}))
            if [ ${#pid[@]} -gt 0 ]; then
            for (( ndx=0; ndx<${#pid[@]}; ndx++ )); do
                if [ "X${pid[$ndx]}" != "X" ]; then
                    break
                fi
            done
            else
                break
            fi
            _sleep 1
        done

        if [ $attempts -ge $maxattempts ]; then
            logmessage "$command hasn't stopped in $maxattempts seconds"
        else
            logmessage "$command completed in $attempts seconds"
        fi
    done

    exit 0 #exit w/o starting any further periods
}

gettrace()
{
    tracedt=`date +%Y-%m-%d_%H-%M`
    outfile=$tracedir"/"$tracedt$trname"_period"$((period++))"of${runperiods}_blkp"
    logmessage "Logging to $outfile"
    ${BLKTRACE_BIN} -d $device -w $tracedwell -o - | ${BLKPARSE_BIN} -i - -o $outfile
    #convert to .csv by device
    declare -a _drives=($device)
    for drive in ${_drives[@]}; do
        logmessage "Converting $outfile to csv"
        # btconvert.sh requires device stripped of '/dev/' prefix...
        dev=$(echo $drive | ${AWKBIN} -F/ '{print $3}')
        ${stxappdir}/btconvert.sh $outfile $partfile - DC $dev
    done
}

if [ $# -lt 1 ]; then usage; fi #Display usage if no parameters are given

#Make folder for storing traces and log if not already existing
if [ ! -d $tracedir ]; then mkdir -p $tracedir; fi

#Prepend _ to trname if not null
if [ "x$trname" != "x" ]; then trname="_"$trname; fi

#Create/Start log
logcreate $logfile
logstart $logfile
logmessage "Command Line: $(readlink -fn $0) $@"

#Log parameters
logmessage "dwell $tracedwell, 1stwait $firstwaitsecs, period $sampleperiodsecs, pad $padsecs, periods $runperiods"

#Capture the partitions file
logmessage "Copying /proc/partitions to $partfile"
cp /proc/partitions $partfile

#Mount debug fs needed by blktrace if not already mounted
mount -t debugfs | grep -q "/sys/kernel/debug" || mount -t debugfs debugfs /sys/kernel/debug >/dev/null 2>&1
if [ 0 -ne $? ]; then
    echo "$(basename $0) requires debugfs for blktrace"
    exit 1
fi

#Take first trace after firstwaitsecs
if [ $initialtrace == "TRUE" -a $runsecs -gt $((firstwaitsecs+tracedwell)) ]; then
    logmessage "Sleeping for $firstwaitsecs before first sample."
    _sleep $firstwaitsecs
    gettrace
fi

if [ $runsecs -gt $((period-tracedwell)) ]; then
    #Each successive trace ends padsecs seconds prior to the end of the period
    periodwaitsecs=$((sampleperiodsecs-firstwaitsecs-tracedwell*2-padsecs))
    logmessage "Sleeping for $periodwaitsecs before next sample."
    _sleep $periodwaitsecs

    #Take trace at the end of each successive period
    while [ $runperiods -ge $period ]; do
        gettrace
        if [ $runperiods -ge $period ]; then
            _sleep $((sampleperiodsecs-tracedwell))
        fi
    done
fi
logmessage "Done"

exit 0
