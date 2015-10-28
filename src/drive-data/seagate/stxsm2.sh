#!/bin/bash

version=0.1
# Version 0.1, October 2014 TKC
# Refactoring, common code to ./common.sh which must be sourced early
# Changes for readability

#Updated July 2015 BEL for use at SDSC
#Added command-line parameter to output file name

filenameprefix=$1

#Detemine directory of executable
declare stxappdir=$(dirname $0)
source ${stxappdir}/common.sh

DRVS=`$SEACHEST -s |grep "ST[0-9]00FM"   |tr -s ' '|cut -d" " -f2`
for DRV in $DRVS ; do
	#$LOGCMD --sm2 --triggerUDS --uds -d $DRV
	$LOGCMD --sm2  -d $DRV
	echo ""
done
#Changed file-name structure below BEL
#THISHOST=`hostname`
#LOGZIPFILE="AllLogs.${THISHOST}.tar.gz"
LOGZIPFILE=$1"_SM2.tar.gz"

#Added rm and removed mv and echo commands BEL
#tar -cvzf $LOGZIPFILE *.UDS  *.SM2
#tar -cvzf $LOGZIPFILE  *.SM2
tar -czf $LOGZIPFILE  *.SM2 && rm -f *.sm2
#mv *.UDS /tmp
#mv *.SM2 /tmp
#echo ""
#echo "Send file $LOGZIPFILE to Seagate"
