#Determine directory of executables

WORDSIZE=`uname -m`
if [ "${WORDSIZE}" == "x86_64" ] ; then
    LOGCMD="${stxappdir}/SeaDragon_LogsUtil_310_Private_64"
    SEACHEST="${stxappdir}/SeaChest"
else
    LOGCMD="${stxappdir}/SeaDragon_LogsUtil_310_Private_32"
    SEACHEST="${stxappdir}/SeaChest32"
fi
declare AWKBIN=$(/usr/bin/which awk)

logcreate()
{
    _logpath=$1
    _folder=$(dirname $_logpath)

    /bin/mkdir -p $_folder
    if [[ 0 -ne $? ]]; then
        echo "Could not create $_folder"
        exit 1
    else
        /bin/touch $_logpath
        if [[ 0 -ne $? ]]; then
            echo "Could not create $_logpath"
            exit 1
        fi
    fi
}

logstart()
{
    _logpath=$1
    #echo "Date       Time            Event" >> $_logpath
    printf "%-10s %-14s %-16s %-16s %-16s %s\n" Date Time Application Job Node Event >> $_logpath
    logmessage "$(readlink -fn $0) version $version"
}

logmessage()
{
    #echo `date +%Y-%m-%d_%H-%M` $@ >> $logfile
    #echo "$(date --rfc-3339=seconds)  $@" >> $logfile
    if [ X$appname == "X" ];then appname="-";fi
    if [ X$jobid == "X" ];then jobid="-";fi
    printf "%10s %14s %-16s %-16s %-16s " $(date --rfc-3339=seconds)  $appname $jobid $(hostname -s) >> $logfile
    echo $@ >> $logfile
}

_sleep()
{
    for (( tics=0; tics < $1; tics++ )); do
        sleep 1
    done
}

trap_call="";
trap 'echo "$(basename $0) caught SIGINT";  if [ -z ${trap_call} ]; then trap_call="1"; trap_mesg ; fi' SIGINT
trap 'echo "$(basename $0) caught SIGTERM"; if [ -z ${trap_call} ]; then trap_call="1"; trap_mesg ; fi' SIGTERM
trap 'echo "$(basename $0) caught SIGUSR1"; if [ -z ${trap_call} ]; then trap_call="1"; trap_mesg ; fi' SIGUSR1
