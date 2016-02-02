#!/bin/bash

version=1.0

# Based on stxsm2.sh version 0.2

# Version 1.0, January 2016 BEL
# Runs smartctl -a on all drives. Logs output to file in $1

# 1st patrameter is the logfile path or folder, 2nd parameter is the base of the logfile name
archivedir=$1
if [ ! -d $archivedir ];then mkdir -p $archivedir;fi
TESTdt=`date +%Y-%m-%d_%H-%M`
archivename="${TESTdt}_$2"

#Determine directory of executable
declare stxappdir=$(dirname $0)
source ${stxappdir}/common.sh

DRVS=`$SEACHEST -s | grep /dev | tr -s ' ' | cut -d" " -f2`
LOGFILE="$archivedir/${archivename}_smartctl.log"
for DRV in $DRVS ; do
	echo "# smartctl -a $DRV -----------------" >> $LOGFILE
	/usr/sbin/smartctl -a $DRV >> $LOGFILE
done

