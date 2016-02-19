#!/bin/bash

version=0.3

# Version 0.3, February 2016 BEL
# Added a log file and redirected the command output to the log

# Version 0.2, November 2015 BEL
# Corrected archive file path construction and added conditional mkdir
# Corrected case of SM2 on rm command

# Version 0.1, October 2014 TKC
# Refactoring, common code to ./common.sh which must be sourced early
# Changes for readability

#Updated July 2015 BEL for use at SDSC
#Added command-line parameter to output file name

archivedir=$1
if [ ! -d $archivedir ];then mkdir -p $archivedir;fi
TESTdt=`date +%Y-%m-%d_%H-%M`
archivename="${TESTdt}_$2"
LOGFILE="$archivedir/${archivename}_stxsm2.log"

#Determine directory of executable
declare stxappdir=$(dirname $0)
source ${stxappdir}/common.sh

DRVS=`$SEACHEST -s |grep "ST[0-9]00FM"   |tr -s ' '|cut -d" " -f2`
for DRV in $DRVS ; do
	#$LOGCMD --sm2 --triggerUDS --uds -d $DRV
	echo "$(date --rfc-3339=seconds) #####----------------- $(basename $0) -sm2 -d $DRV -----------------#####" >> $LOGFILE
	$LOGCMD --sm2  -d $DRV  >> $LOGFILE
	echo ""
done
#Changed file-name structure below BEL
#THISHOST=`hostname`
#LOGZIPFILE="AllLogs.${THISHOST}.tar.gz"
LOGZIPFILE="$archivedir/${archivename}_SM2.tar.gz"

#Added rm and removed mv and echo commands BEL
#tar -cvzf $LOGZIPFILE *.UDS  *.SM2
#tar -cvzf $LOGZIPFILE  *.SM2
tar -czf $LOGZIPFILE  *.SM2 && rm -f *.SM2
#mv *.UDS /tmp
#mv *.SM2 /tmp
#echo ""
#echo "Send file $LOGZIPFILE to Seagate"
echo "$(date --rfc-3339=seconds) ===== $(basename $0) Done =====" >> $LOGFILE
