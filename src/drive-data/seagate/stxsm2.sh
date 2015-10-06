#!/bin/bash

#Updated July 2015 BEL for use at SDSC
#Added command-line parameter to output file name

filenameprefix=$1

WORDSIZE=`uname -m`

if [ "${WORDSIZE}" == "x86_64" ] ; then
	LOGCMD="./SeaDragon_LogsUtil_310_Private_64"
	SEACHEST="./SeaChest"
else
	LOGCMD="./SeaDragon_LogsUtil_310_Private_32"
	SEACHEST="./SeaChest32"
fi
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
