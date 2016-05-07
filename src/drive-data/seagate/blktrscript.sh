#!/bin/bash

version=2.0
# blktrscript.sh orchestrates taking blktrace/parse samples

# Version 2.0, May 2016 BEL
# Added error checking/logging
# Fixed issue with blkparse -o clipping the filename to 126 characters by using redirect > vs -o

# Version 1.5, January 2016 BEL
# Updated parameter parsing so it can handle a single parameter in quotes ie "/dev/sdc"

# Version 1.4, January 2016 BEL
# Added gzip command to compress the blktrace file

# Version 1.3, November 2015 BEL
# Added section to recombine what was intended to be passed as a multi word parameter
#  When multiple words are passed within quotes on the command line they become a single parameter
#  When this same string is passed from a calling script each word becomes a separate parameter
#  The added code recombines the quoted string as a single parameter
#  For example "a b c" d e when passed on the command line becomes $1=a b c, $2=d, $3=e
#  When passed from another script these become $1="a, $2=b, $3=c", $4=d, $5=e
#  The additional code fixes this so that the parameters are always received as intended
# Added drive detail to log message in btconvert loop
# Corrected periodwaitsecs logic when there is no initial trace
# Set period to 1 when initialtrace is false
# Enhanced periodwaitsecs log messages
# Cleaned up usage text and added _ after date to file names
# Corrected partitions and log file names to spec

# Version 1.2, October 2015 TKC
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

# Determine directory of executable and source common functions
declare stxappdir=$(dirname $0)
source ${stxappdir}/common.sh

declare BLKTRACE_BIN=$(/usr/bin/which blktrace)
declare BLKPARSE_BIN=$(/usr/bin/which blkparse)
declare GZIP_BIN=$(/usr/bin/which gzip)

#echo "\$1=$1"
#echo "\$2=$2"
#echo "\$3=$3"
#echo "\$4=$4"
#echo "\$5=$5"
#echo "\$6=$6"
#echo "\$7=$7"
#echo "\$8=$8"

declare -a _commandsave=($@)
declare -a _params=($@)
declare param
declare -i shiftcnt=1

# Determine if quoted parameter fixing may be required
if [ $# -eq ${#_params[@]} ];then

  # Get next parameter honoring quotes to recombine as necessary
  getp()
  {

  #echo ${#_params[@]} ${_params[@]}
  if [ ${#_params[@]} -eq 0 ];then param=;shiftcnt=0;return;else shiftcnt=1;fi
  local -i ndx=0 match=0
  param=${_params[0]};if [ ${param:0:1} == \" ];then match=1;_params[0]=${_params[0]:1};param=;fi
  #echo $param $match

  while [ $match -gt 0 -a $ndx -lt ${#_params[@]} ];do
   par=${_params[$((ndx++))]};if [ ${par:${#par}-1:1} == \" ];then match=0;par=${par:0:${#par}-1};fi
   param+=" $par" #;echo $ndx $param
   shiftcnt=$ndx
  done

  }

  # Set parameters
  _params=($@);getp
  declare    device=$param  #device to trace
  shift $shiftcnt;unset _params;_params=($@);getp
  declare -i runsecs=${param:-14400} #run time in seconds, entire period over which the script runs
  shift $shiftcnt;unset _params;_params=($@);getp
  declare -i tracedwell=${param:-60} #duration of a single trace in seconds
  shift $shiftcnt;unset _params;_params=($@);getp
  declare -i sampleperiodsecs=${param:-3600} #duration of a period within which trace sample is taken
  shift $shiftcnt;unset _params;_params=($@);getp
  declare -i firstwaitsecs=${param:-120} #delay in seconds to first trace sample
  shift $shiftcnt;unset _params;_params=($@);getp
  declare -i padsecs=${param:-30} #seconds from end of trace to end of sample period
  shift $shiftcnt;unset _params;_params=($@);getp
  declare    tracedir=${param:-tracedir} #folder name for the traces, also helps organize traces
  shift $shiftcnt;unset _params;_params=($@);getp
  declare    trname=$param #file name uiniquiefier to include test case info and help identify trace

else # No parameter adjustment needed

  # Set parameters
  declare    device=$1  #device to trace
  declare -i runsecs=${2:-14400} #run time in seconds, entire period over which the script runs
  declare -i tracedwell=${3:-60} #duration of a single trace in seconds
  declare -i sampleperiodsecs=${4:-3600} #duration of a period within which trace sample is taken
  declare -i firstwaitsecs=${5:-120} #delay in seconds to first trace sample
  declare -i padsecs=${6:-30} #seconds from end of trace to end of sample period
  declare    tracedir=${7:-tracedir} #folder name for the traces, also helps organize traces
  declare    trname=$8 #file name uiniquiefier to include test case info and help identify trace

fi

debug2() {
echo "device=          $device"
echo "runsecs=         $runsecs"
echo "tracedwell=      $tracedwell"
echo "sampleperiodsecs=$sampleperiodsecs"
echo "firstwaitsecs=   $firstwaitsecs"
echo "padsecs=         $padsecs"
echo "tracedir=        $tracedir"
echo "tracename=       $trname"
}
#debug2

#Prepend _ to trname if not null
if [ "x$trname" != "x" ]; then trname="_"$trname; fi

#Setup parameters depending on period 0 being required
if [ $firstwaitsecs -lt 0 ]; then
    firstwaitsecs=0
    period=1
    initialtrace="FALSE"
else
    period=0
    initialtrace="TRUE"
fi
runperiods=$((runsecs/sampleperiodsecs))

#Setup file names
TESTdt=`date +%Y-%m-%d_%H-%M`
logfile=$tracedir/$TESTdt${trname}_trace.log
partfile=$tracedir/$TESTdt${trname}_partitions
tmpfile=$tracedir/$TESTdt${trname}_trace.tmp

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

    device        - the device name to trace as in /dev/sdx, can include
                    multiple in quotes, for example... "/dev/sdy /dev/sdz"

    run_time      - the overall time to run the script, defaults to 14400
                    seconds (4 hours)

    trace_dwell   - the duration of each trace, defaults to 60 seconds

    sample_period - the period within which a trace will be taken, defaults
                    to 3600 seconds (1 hour)

    initial_wait  - the delay prior to taking the first trace in the first
                    period, defaults to 120 seconds. If initial_wait is
                    negative the initial first period trace will be skipped

    end_pad       - the time from the end of a trace to the end of a sample
                    period, defaults to 30 seconds

    folder        - the name of the folder to hold the samples and log

    name          - text to include in the trace file names to help identify
                    the trace, defaults to ''

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
    ${BLKTRACE_BIN} -d $device -w $tracedwell -o - | ${BLKPARSE_BIN} -i - > $outfile 2> $tmpfile
    if [ $? -ne 0 ];then logmessage "blktrace/parse failed";cat $tmpfile >> $logfile;exit $?;fi
    #convert to .csv by device
    declare -a _drives=($device)
    for drive in ${_drives[@]}; do
        logmessage "Converting $outfile to csv for $drive"
        # btconvert.sh requires device stripped of '/dev/' prefix...
         dev=$(basename $drive)
        ${stxappdir}/btconvert.sh $outfile $partfile - DC $dev 2> $tmpfile
        if [ $? -ne 0 ];then logmessage "btconvert error";cat $tmpfile >> $logfile;exit $?;fi
    done
    ${GZIP_BIN} $outfile 2> $tmpfile
    if [ $? -ne 0 ];then logmessage "gzip error";cat $tmpfile >> $logfile;exit $?;fi
}

if [ ${#_commandsave[@]} -lt 1 ]; then usage; fi #Display usage if no parameters are given

#Make folder for storing traces and log if not already existing
if [ ! -d $tracedir ]; then mkdir -p $tracedir; fi

#Create/Start log
logcreate $logfile
logstart $logfile
logmessage "Command Line: $(readlink -fn $0) ${_commandsave[@]}"

#Log parameters
logmessage "dwell $tracedwell, 1stwait $firstwaitsecs, period $sampleperiodsecs, pad $padsecs, periods $runperiods"

#Verify blktrace and blkparse are available/executable
if [[ ! -x ${BLKTRACE_BIN} ]] || [[ ! -x ${BLKPARSE_BIN} ]]; then
    logmessage "$(basename $0) cannot run without blktrace and blkparse"
    exit 1
fi

#Capture the partitions file
logmessage "Copying /proc/partitions to $partfile"
cp /proc/partitions $partfile

#Mount debug fs needed by blktrace if not already mounted
mount -t debugfs | grep -q "/sys/kernel/debug" || mount -t debugfs debugfs /sys/kernel/debug >/dev/null 2> $tmpfile
if [ 0 -ne $? ]; then
    logmessage "$(basename $0) requires debugfs for blktrace"
    cat $tmpfile >> $logfile
    exit 1
fi

#Take first trace after firstwaitsecs
if [ $initialtrace == "TRUE" -a $runsecs -ge $((firstwaitsecs+tracedwell)) ]; then
    logmessage "Sleeping for $firstwaitsecs before first trace"
    _sleep $firstwaitsecs
    gettrace
fi

declare -i periodwaitsecs=-1
if [ $initialtrace == "TRUE" -a $runsecs -ge $((firstwaitsecs+tracedwell*2+padsecs)) ]; then
    periodwaitsecs=$((sampleperiodsecs-firstwaitsecs-tracedwell*2-padsecs))
elif [ $initialtrace == "FALSE" -a $runsecs -ge $((tracedwell-padsecs)) ]; then
    periodwaitsecs=$((sampleperiodsecs-tracedwell-padsecs))
fi
if [ $periodwaitsecs -ge 0 ]; then
    #Each successive trace ends padsecs seconds prior to the end of the period
    logmessage "Sleeping for $periodwaitsecs before period $period trace"
    _sleep $periodwaitsecs

    while [ $runperiods -ge $period ]; do
        gettrace
        if [ $runperiods -ge $period ]; then
            periodwaitsecs=$((sampleperiodsecs-tracedwell))
            logmessage "Sleeping for $periodwaitsecs before period $period trace"
            _sleep $periodwaitsecs
        fi
    done
fi

rm -f $tmpfile
logmessage "Done"

exit 0
