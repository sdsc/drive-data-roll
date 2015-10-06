#Detemine directory of executables

WORDSIZE=`uname -m`
if [ "${WORDSIZE}" == "x86_64" ] ; then
    LOGCMD="${stxappdir}/SeaDragon_LogsUtil_310_Private_64"
    SEACHEST="${stxappdir}/SeaChest"
else
    LOGCMD="${stxappdir}/SeaDragon_LogsUtil_310_Private_32"
    SEACHEST="${stxappdir}/SeaChest32"
fi
declare AWKBIN=$(which awk)

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
    echo "Date       Time            Event" >> $_logpath
    logmessage "$(readlink -fn $0) version $version"
}

logmessage()
{
    #echo `date +%Y-%m-%d_%H-%M` $@ >> $logfile
    echo "$(date --rfc-3339=seconds)  $@" >> $logfile
}

_sleep()
{
    for (( tics=0; tics < $1; tics++ )); do
        sleep 1
    done
}

trap_call="";
trap 'if [ -z ${trap_call} ]; then trap_call="1"; trap_mesg ; fi' 2 10 15
