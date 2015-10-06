#!/bin/bash

version=1.1
# periodically collects multiple statistics samples
# based on blktrscript.sh

# Version 1.1, October 2014 TKC
# Refactoring, common code to ./common.sh which must be sourced early
# Here document for usage
# Fix stats binary logging to variable that evaluates to 'null'
# _sleep() function to allow interruption of long waits
# Changes for readability

# Version 1.0, August 2015 BEL
# Collects IO counts from /sys/block/$(basename $DEV)/stat
# Collect iostat from selected drives
# collect mpstat

# Detemine directory of executable
declare stxappdir=$(dirname $0)
source ${stxappdir}/common.sh

declare IOSTAT_BIN=$(which iostat)
declare MPSTAT_BIN=$(which mpstat)
declare VMSTAT_BIN=$(which vmstat)

if [[ ! -x ${IOSTAT_BIN} ]] || [[ ! -x ${MPSTAT_BIN} ]] || [[ ! -x ${VMSTAT_BIN} ]]; then
    echo "$(basename $0) cannot run without iostat, mpstat and vmstat"
    exit 1
fi

# Set parameters
declare    device=$1 #device to sample
declare -i runsecs=${2:-14400} #run time in seconds, entire period over which the script runs
declare -i sampledwell=${3:-60} #duration of a single sample in seconds
declare -i sampleperiodsecs=${4:-3600} #duration of a period within which sample sample is taken
declare -i firstwaitsecs=${5:-120} #delay in seconds to first sample sample
declare -i padsecs=${6:-30} #seconds from end of sample to end of sample period
declare    sampledir=${7:-sampledir} #folder name for the samples, also helps organize samples
declare    flname=$8 #file name uiniquiefier to include test case info and help identify sample

if [ $firstwaitsecs -lt 0 ]; then
    firstwaitsecs=0
    initialsample="FALSE"
else
    initialsample="TRUE"
fi
runperiods=$((runsecs/sampleperiodsecs))
period=0
TESTdt=`date +%Y-%m-%d_%H-%M`
logfile=$sampledir"/"$TESTdt"sample.log"
outfile=$sampledir"/"$TESTdt$flname

usage()
{
cat << EOT

==-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=-=-=-=-=-=-
$0 version $version

Captures multiple statistics files and logs actions to a log file

Usage: $0 device [run_time [sample_dwell [sample_period [initial_wait [end_pad [folder [name]]]]]]]

Only the device parameter is required. However parameters are positional and
must be included when any parameter further right is included.

Input parameters...

    device        - the device name to sample as in /dev/sdx, can include
                    multiple in quotes, for example... "/dev/sdy /dev/sdz"

    run_time      - the overall time to run the script, defaults to 14400
                    seconds (4 hours)

    sample_dwell  - the duration of each sample, defaults to 60 seconds

    sample_period - the period within which a sample will be taken, defaults
                    to 3600 seconds (1 hour)

    initial_wait  - the delay prior to taking the first sample in the first
                    period, defaults to 120 seconds. If initial_wait is -ve
                    the initial first period sample will be skipped

    end_pad       - the time from the end of a sample to the end of a sample
                    period, defaults to 30 seconds

    folder        - the name of the folder to hold the samples and log

    name          - text to include in the sample file names to help identify
                    the sample, defaults to ''

Assuming a long enough run_time, two samples are taken in the first period. One
after initial_wait and one that completes end_pad prior to the end of the first
period.

Each subsequent period, if any, includes one sample that completes end_pad prior
to the period end.

Each sample file name begins with a date-time stamp and includes the supplied
name, if any, number of periods and the period number.

An output log file is captured with a name that begins with a date-time stamp
and ends in sample.log

Example:

    $0 /dev/sdx 36000 1800 7200 60 30 DBsamples jobx

This samples device /dev/sdx over the course of 10 hours with half hour samplesi
taken every two hours.

The first two hour period has the first sample taken 1 minute after starting
the script.

All five periods have a sample taken that completes a half minute prior to thei
end of the period sample file names are placed in the folder named DBsamples i
and include the string jobx in the file name.

==-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=-=-=-=-=-=-
EOT

    exit
}

#Setup termination procedure
trap_mesg()
{
    #Don't start any new periods
    exit 0
}

getstats()
{
    ${IOSTAT_BIN} -mtxy $device >> ${outfile}_iostat.txt
    ${MPSTAT_BIN} -P ALL >> ${outfile}_mpstat.txt
    ${VMSTAT_BIN} -t >> ${outfile}_vmstat.txt
}

if [ $# -lt 1 ]; then usage; fi #Display usage if no parameters are given

#Make folder for storing samples and log if not already existing
if [ ! -d $sampledir ]; then mkdir -p $sampledir; fi

#Prepend _ to flname if not null
if [ "x$flname" != "x" ]; then flname="_"$flname; fi

#Crate/Start log
logcreate $logfile
logstart $logfile
logmessage "Command Line: $(readlink -fn $0) $@"

#Log parameters & folder
logmessage "dwell $sampledwell, 1stwait $firstwaitsecs, period $sampleperiodsecs, pad $padsecs, periods $runperiods"
logmessage "Logging to $outfile"

#Take first sample after firstwaitsecs
if [ $initialsample == "TRUE" -a $runsecs -gt $((firstwaitsecs+sampledwell)) ]; then
    logmessage "Sleeping for $firstwaitsecs before first sample."
    _sleep $firstwaitsecs
    getstats
fi

if [ $runsecs -gt $((period-sampledwell)) ]; then
    #Each successive sample ends padsecs seconds prior to the end of the period
    periodwaitsecs=$((sampleperiodsecs-firstwaitsecs-sampledwell*2-padsecs))
    logmessage "Sleeping for $periodwaitsecs before next sample."
    _sleep $periodwaitsecs

    #Take sample at the end of each successive period
    while [ $runperiods -ge $period ]; do
        getstats
        if [ $runperiods -ge $period ]; then
            _sleep $((sampleperiodsecs-sampledwell))
        fi
    done
fi
logmessage "Done"

exit 0

# Notes:
# /sys/block//stat
# The stat file consists of a single line of text containing 11 decimal
# values separated by whitespace.  The fields are summarized in the
# following table, and described in more detail below.
#
# Name            units         description
# ----            -----         -----------
# read I/Os       requests      number of read I/Os processed
# read merges     requests      number of read I/Os merged with in-queue I/O
# read sectors    sectors       number of sectors read
# read ticks      milliseconds  total wait time for read requests
# write I/Os      requests      number of write I/Os processed
# write merges    requests      number of write I/Os merged with in-queue I/O
# write sectors   sectors       number of sectors written
# write ticks     milliseconds  total wait time for write requests
# in_flight       requests      number of I/Os currently in flight
# io_ticks        milliseconds  total time this block device has been active
# time_in_queue   milliseconds  total wait time for all requests
#
# read I/Os, write I/Os
# =====================
#
# These values increment when an I/O request completes.
#
# read merges, write merges
# =========================
#
# These values increment when an I/O request is merged with an
# already-queued I/O request.
#
# read sectors, write sectors
# ===========================
#
# These values count the number of sectors read from or written to this
# block device.  The "sectors" in question are the standard UNIX 512-byte
# sectors, not any device- or filesystem-specific block size.  The
# counters are incremented when the I/O completes.
#
# read ticks, write ticks
# =======================
#
# These values count the number of milliseconds that I/O requests have
# waited on this block device.  If there are multiple I/O requests waiting,
# these values will increase at a rate greater than 1000/second; for
# example, if 60 read requests wait for an average of 30 ms, the read_ticks
# field will increase by 60*30 = 1800.
#
# in_flight
# =========
#
# This value counts the number of I/O requests that have been issued to
# the device driver but have not yet completed.  It does not include I/O
# requests that are in the queue but not yet issued to the device driver.
#
# io_ticks
# ========
#
# This value counts the number of milliseconds during which the device has
# had I/O requests queued.
#
# time_in_queue
# =============
#
# This value counts the number of milliseconds that I/O requests have waited
# on this block device.  If there are multiple I/O requests waiting, this
# value will increase as the product of the number of milliseconds times the
# number of requests waiting (see "read ticks" above for an example).
