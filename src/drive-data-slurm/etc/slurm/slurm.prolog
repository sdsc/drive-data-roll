#!/bin/sh

# Emperically, the following SLURM ENV VARS are available on the 'MASTER'
# and 'SLAVE' nodes in the prolog...

# [root@comet-fe1 ~]# sdiff <(ssh comet-01-09 cat /tmp/PROLOG_SLURM.env) \
#    <(ssh comet-01-10 cat /tmp/PROLOG_SLURM.env)
# SLURM_NODELIST=comet-01-[09-12]	SLURM_NODELIST=comet-01-[09-12]
# SLURMD_NODENAME=comet-01-09	      |	SLURMD_NODENAME=comet-01-10
# SLURM_JOBID=98			SLURM_JOBID=98
# SLURM_STEP_ID=0			SLURM_STEP_ID=0
# SLURM_CONF=/etc/slurm/slurm.conf	SLURM_CONF=/etc/slurm/slurm.conf
# SLURM_JOB_ID=98			SLURM_JOB_ID=98
# SLURM_JOB_USER=tcooper		SLURM_JOB_USER=tcooper
# SLURM_UID=500				SLURM_UID=500
# SLURM_JOB_UID=500			SLURM_JOB_UID=500
# SLURM_CLUSTER_NAME=comet		SLURM_CLUSTER_NAME=comet
# SLURM_JOB_PARTITION=virt		SLURM_JOB_PARTITION=virt

# Any other parameters need to be obtained by querying slurmctld
# using slurm commands (ie. scontrol show job) and parsing
# the output.

LOGGER=/usr/bin/logger

SLURM_BIN=/usr/bin
SLURM_SCONTROL=${SLURM_BIN}/scontrol
SLURM_SINFO=${SLURM_BIN}/sinfo

this_host=$(/bin/hostname -s)
TRACKING_DIR=/var/spool/slurmd/job_tracking/${SLURM_JOB_USER}

retval=0

if [ x$SLURM_UID = "x" ] ; then
    exit $retval
fi
if [ x$SLURM_JOB_ID = "x" ] ; then
        exit $retval
fi

export COMPUTESET_JOB_STAGE='PROLOG'
export NOTIFY_SCRIPT=/home/dimm/code/nucleus-service/nucleus_service/computeset_job_notify.sh
function notify(){
    export COMPUTESET_JOB_STATE="$1"
    ${NOTIFY_SCRIPT}
}

function check_status(){
    # $1 = expected value
    # $2 = status
    # $3 = message if different
    # Offline node if any checks fail and exit

    if [[ $1 != $2 ]] ; then
        note=$3
        ${SLURM_SCONTROL} requeue ${SLURM_JOB_ID}
        ${SLURM_SCONTROL} update nodename=${this_host} state=DRAIN reason="${note}"
        ${LOGGER} -p local0.alert "Node offlined in $0 due to: ${note}"
	if [[ ${SLURM_JOB_PARTITION} == "virt" ]] ; then
    		${LOGGER} -p local0.warning -t nucleus-slurm -i "Node offlined in $0 due to: ${note}"
	fi
        retval=1
	exit $retval
    fi
}

${LOGGER} -p local0.alert "********  starting $0 for job $SLURM_JOB_ID"

if [[ ${SLURM_JOB_PARTITION} == "virt" ]] ; then
    ${LOGGER} -p local0.info -t nucleus-slurm -i "PROLOG: Starting virt setup for JobID:${SLURM_JOB_ID}"

    /usr/bin/test -x ${NOTIFY_SCRIPT}
    check_status 0 $? "PROLOG: celery notification script missing"

    #notify 'submitted'
    /bin/rm /tmp/computeset_job_notify.sh.out

    /usr/bin/test $(/sbin/lspci | /bin/grep Mellanox | /usr/bin/wc -l) -eq 2
    check_status 0 $? "PROLOG: Mellanox SR-IOV device missing"

    /sbin/service libvirtd status
    check_status 0 $? "PROLOG: libvirtd is not running"

    /sbin/service img-storage-vm status
    check_status 0 $? "PROLOG: img-storage-vm is not running"

    /bin/mount -t zfs | /bin/grep -q "scratch on /scratch type zfs"
    check_status 0 $? "PROLOG: ZFS filesystem NOT mounted at /scratch"

    fs=$(/bin/df -hP -t zfs --block-size=1G | /bin/awk '/scratch/ {print $4}')
    /usr/bin/test $fs -gt 100
    check_status 0 $? "PROLOG: /scratch filesystem is not empty ($fs GB free)"

    /usr/bin/test -d /mnt/images/public
    check_status 0 $? "PROLOG: virtual cluster ISO repository not found"

    /usr/bin/test -d /home/${SLURM_JOB_USER}
    check_status 0 $? "PROLOG: virtual cluster user homedir not mounted"

    /bin/sleep $(( $RANDOM % 15))

    ${LOGGER} -p local0.info -t nucleus-slurm -i "PROLOG: Finished virt setup for JobID:${SLURM_JOB_ID}"
fi

#
# Add tracking dir for this job
#
/bin/mkdir -p ${TRACKING_DIR}/${SLURM_JOB_ID}
check_status 0 $? "PROLOG: Cannot create ${TRACKING_DIR}/${SLURM_JOB_ID}"

#
# Store critical SLURM env vars in tracking file
#
/usr/bin/printenv | /bin/grep SLURM > ${TRACKING_DIR}/${SLURM_JOB_ID}/environment
/bin/grep SLURM_JOB_PARTITION ${TRACKING_DIR}/${SLURM_JOB_ID}/environment
/bin/chown ${SLURM_JOB_USER} ${TRACKING_DIR}/${SLURM_JOB_ID}/environment
check_status 0 $? "PROLOG: Missing content in ${TRACKING_DIR}/${SLURM_JOB_ID}/environment"

#
# Create local scratch directory
#
/bin/mkdir -p /scratch/${SLURM_JOB_USER}/${SLURM_JOB_ID}
check_status 0 $? "PROLOG: Cannot create local scratch"

#
# Set local scratch ownership and permissions
#
/bin/chmod o+rx /scratch/${SLURM_JOB_USER}
check_status 0 $? "PROLOG: Cannot chmod user local scratch dir"
/bin/chown -R ${SLURM_JOB_USER} /scratch/${SLURM_JOB_USER}/${SLURM_JOB_ID}
check_status 0 $? "PROLOG: Cannot chown user local scratch dir"

#
# Record current /scratch usage
#
block_usage=$(/bin/df -B 1024 /scratch | /bin/grep scratch)
inode_usage=$(/bin/df -i /scratch | /bin/grep scratch)
${LOGGER} -p local0.alert "sdsc_stats job start $SLURM_JOB_ID $SLURM_JOB_USER local scratch block usage ${block_usage}"
${LOGGER} -p local0.alert "sdsc_stats job start $SLURM_JOB_ID $SLURM_JOB_USER local scratch inode usage ${inode_usage}"

#
# Clean-up for non-shared nodes
#
if [[ ${SLURM_JOB_PARTITION} != "shared" ]] ; then

  # Drop caches on exclusive use jobs
  /bin/sync
  check_status 0 $? "PROLOG: Cannot sync filesystems in user_cleanup"
  /bin/echo 3 > /proc/sys/vm/drop_caches
  check_status 0 $? "PROLOG: Cannot drop_caches in user_cleanup"
fi

# Add user to access list
ACCESS_CONF=/etc/security/access.conf
ACCESS_CONF_LOCK_FILE=/var/lock/access.conf.lock
(
  /usr/bin/flock -x 200
  rval=$?
  if [ 0 -ne $rval ]
  then
    exit $rval
  else
    /bin/sed -i "s/\(EXCEPT.*\):/\1 ${SLURM_JOB_USER}:/" ${ACCESS_CONF}
    #sleep 5 # sleeping here holds the lock, other commands/scripts honoring
            # the lock WILL NOT attempt to access the file controlled by the lock
  check_status 0 $? "PROLOG: Cannot update access.conf"
  fi
) 200>${ACCESS_CONF_LOCK_FILE}

access_chk=1
access_status=1
while [ $access_chk -le 3 ]
do
  /bin/grep -q "${SLURM_JOB_USER}" ${ACCESS_CONF}
  if [ 0 -eq $? ]
  then
    access_status=0
    break
  else
    access_chk=$(( $access_chk + 1 ))
    /bin/sleep 2
  fi
done
check_status 0 $access_status "PROLOG: Cannot verify access.conf was updated"

# Start-up seagate monitoring...
/usr/bin/test -x /opt/seagate/stxdaemon
if [[ $? -eq 0 ]]; then
  #SLURM_TIMELIMIT=$(/usr/bin/sacct -nP --format=Timelimit -j ${SLURM_JOB_ID})
  SLURM_TIMELIMIT=$(/usr/bin/scontrol show job ${SLURM_JOB_ID} | /usr/bin/tr -s ' ' '\n' | /bin/awk -F= '/TimeLimit/ {print $2}')
  SLURM_WALLTIME_SECS=$(dhmsToSecs "$SLURM_TIMELIMIT")
  /opt/seagate/daemonize -c /opt/seagate -e /tmp/stxdaemon.log -o /tmp/stxdaemon.log \
    /opt/seagate/stxdaemon ${SLURM_JOB_USER} ${SLURM_JOB_ID} ${SLURM_WALLTIME_SECS}
fi

${LOGGER} -p local0.alert "******** finished $0 for job $SLURM_JOB_ID"

exit $retval
