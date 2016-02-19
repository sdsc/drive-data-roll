#!/bin/bash

version=1.1

# Version 1.1, February 2016 BEL
# Changed drive handle gathering to filter for only disk type drives
# Uses lsscsi vs SeaChest to enumerate drives on the system
# Enhanced demarcation between drive logs, added date time stamp and done message to log at completion

# Version 1.0, January 2016 BEL
# Based on stxsm2.sh version 0.2
# Runs smartctl -a on all drives. Logs output to file in $1

# 1st patrameter is the logfile path or folder, 2nd parameter is the base of the logfile name
archivedir=$1
if [ ! -d $archivedir ];then mkdir -p $archivedir;fi
TESTdt=`date +%Y-%m-%d_%H-%M`
archivename="${TESTdt}_$2"

#Determine directory of executable
declare stxappdir=$(dirname $0)
source ${stxappdir}/common.sh
declare LSSCSI_BIN=$(/usr/bin/which lsscsi)

#DRVS=`$SEACHEST -s | grep /dev | tr -s ' ' | cut -d" " -f2`
DRVS=`${LSSCSI_BIN} | $AWKBIN '/ disk / {print $NF}'`
LOGFILE="$archivedir/${archivename}_smartctl.log"
for DRV in $DRVS ; do
	echo "$(date --rfc-3339=seconds) #####----------------- smartctl -a $DRV -----------------#####" >> $LOGFILE
	smartctl -a $DRV >> $LOGFILE
done
echo "$(date --rfc-3339=seconds) ===== $(basename $0) Done =====" >> $LOGFILE
