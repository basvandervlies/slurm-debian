#!/bin/sh
#
# chkconfig: 345 90 10
# description: SLURM is a simple resource management system which \
#              manages exclusive access o a set of compute \
#              resources and distributes work to those resources.
#
# processname: /usr/sbin/slurmd
# pidfile: /var/run/slurm-llnl/slurmd.pid
#
# config: /etc/default/slurmd
#
### BEGIN INIT INFO
# Provides:          slurmd
# Required-Start:    $remote_fs $syslog $network munge
# Required-Stop:     $remote_fs $syslog $network munge
# Should-Start:      $named
# Should-Stop:       $named
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: slurm daemon management
# Description:       Start slurm to provide resource management
### END INIT INFO

BINDIR=/usr/bin
CONFDIR=/etc/slurm-llnl
LIBDIR=/usr/lib
SBINDIR=/usr/sbin

# Source slurm specific configuration
if [ -f /etc/default/slurmd ] ; then
    . /etc/default/slurmd
else
    SLURMD_OPTIONS=""
fi

# Checking for slurm.conf presence
if [ ! -f $CONFDIR/slurm.conf ] ; then
    if [ -n "$(echo $1 | grep start)" ] ; then
      echo Not starting slurmd
    fi
      echo slurm.conf was not found in $CONFDIR
      echo Please follow the instructions in \
            /usr/share/doc/slurmd/README.Debian
    exit 0
fi


DAEMONLIST="slurmd"
test -f $SBINDIR/slurmd || exit 0

#Checking for lsb init function
if [ -f /lib/lsb/init-functions ] ; then
  . /lib/lsb/init-functions
else
  echo Can\'t find lsb init functions
  exit 1
fi

# setup library paths for slurm and munge support
export LD_LIBRARY_PATH=$LIBDIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

#Function to check for cert and key presence
checkcertkey()
{
  MISSING=""
  keyfile=""
  certfile=""

  if [ "$1" = "slurmd" ] ; then
    keyfile=$(grep JobCredentialPublicCertificate $CONFDIR/slurm.conf \
                  | grep -v "^ *#")
    keyfile=${keyfile##*=}
    keyfile=${keyfile%#*}
    [ -e $keyfile ] || MISSING="$keyfile"
  fi

  if [ "${MISSING}" != "" ] ; then
    echo Not starting slurmd
    echo $MISSING not found
    echo Please follow the instructions in \
      /usr/share/doc/slurmd/README.cryptotype-openssl
    exit 0
  fi
}

get_daemon_description()
{
    case $1 in
      slurmd)
        echo slurm compute node daemon
	;;
      slurmctld)
	echo slurm central management daemon
	;;
      *)
	echo slurm daemon
	;;
    esac
}

start() {
  CRYPTOTYPE=$(grep CryptoType $CONFDIR/slurm.conf | grep -v "^ *#")
  CRYPTOTYPE=${CRYPTOTYPE##*=}
  CRYPTOTYPE=${CRYPTOTYPE%#*}
  if [ "$CRYPTOTYPE" = "crypto/openssl" ] ; then
    checkcertkey $1
  fi

  # Create run-time variable data
  mkdir -p /var/run/slurm-llnl
  chown slurm:slurm /var/run/slurm-llnl

  # Checking if SlurmdSpoolDir is under run
  if [ "$1" = "slurmd" ] ; then
    SDIRLOCATION=$(grep SlurmdSpoolDir /etc/slurm-llnl/slurm.conf \
                       | grep -v "^ *#")
    SDIRLOCATION=${SDIRLOCATION##*=}
    SDIRLOCATION=${SDIRLOCATION%#*}
    if [ "${SDIRLOCATION}" = "/var/run/slurm-llnl/slurmd" ] ; then
      if ! [ -e /var/run/slurm-llnl/slurmd ] ; then
        ln -s /var/lib/slurm-llnl/slurmd /var/run/slurm-llnl/slurmd
      fi
    fi
  fi

  desc="$(get_daemon_description $1)"
  log_daemon_msg "Starting $desc" "$1"
  unset HOME MAIL USER USERNAME
  #FIXME $STARTPROC $SBINDIR/$1 $2
  STARTERRORMSG="$(start-stop-daemon --start --oknodo \
                   --exec "$SBINDIR/$1" -- $2 2>&1)"
  STATUS=$?
  log_end_msg $STATUS
  if [ "$STARTERRORMSG" != "" ] ; then
    echo $STARTERRORMSG
  fi
  touch /var/lock/slurm
}

stop() {
    desc="$(get_daemon_description $1)"
    log_daemon_msg "Stopping $desc" "$1"
    STOPERRORMSG="$(start-stop-daemon --oknodo --stop -s TERM \
                    --exec "$SBINDIR/$1" 2>&1)"
    STATUS=$?
    log_end_msg $STATUS
    if [ "$STOPERRORMSG" != "" ] ; then
      echo $STOPERRORMSG
    fi
    rm -f /var/lock/slurm
}

getpidfile() {
    dpidfile=`grep -i ${1}pid $CONFDIR/slurm.conf | grep -v '^ *#'`
    if [ $? = 0 ]; then
        dpidfile=${dpidfile##*=}
        dpidfile=${dpidfile%#*}
    else
        dpidfile=/var/run/${1}.pid
    fi

    echo $dpidfile
}

#
# status() with slight modifications to take into account
# instantiations of job manager slurmd's, which should not be
# counted as "running"
#
slurmstatus() {
    base=${1##*/}

    pidfile=$(getpidfile $base)

    pid=`pidof -o $$ -o $$PPID -o %PPID -x $1 || \
         pidof -o $$ -o $$PPID -o %PPID -x ${base}`

    if [ -f $pidfile ]; then
        read rpid < $pidfile
        if [ "$rpid" != "" -a "$pid" != "" ]; then
            for i in $pid ; do
                if [ "$i" = "$rpid" ]; then
                    echo "${base} (pid $pid) is running..."
                    return 0
                fi
            done
        elif [ "$rpid" != "" -a "$pid" = "" ]; then
#           Due to change in user id, pid file may persist
#           after slurmctld terminates
            if [ "$base" != "slurmctld" ] ; then
               echo "${base} dead but pid file exists"
            fi
            return 1
        fi

    fi

    if [ "$base" = "slurmctld" -a "$pid" != "" ] ; then
        echo "${base} (pid $pid) is running..."
        return 0
    fi

    echo "${base} is stopped"

    return 3
}

#
# stop slurm daemons,
# wait for termination to complete (up to 10 seconds) before returning
#
slurmstop() {
    for prog in $DAEMONLIST ; do
       stop $prog
       for i in 1 2 3 4
       do
          sleep $i
          slurmstatus $prog
          if [ $? != 0 ]; then
             break
          fi
       done
    done
}

#
# The pathname substitution in daemon command assumes prefix and
# exec_prefix are same.  This is the default, unless the user requests
# otherwise.
#
# Any node can be a slurm controller and/or server.
#
case "$1" in
    start)
	start slurmd "$SLURMD_OPTIONS"
        ;;
    startclean)
        SLURMD_OPTIONS="-c $SLURMD_OPTIONS"
        start slurmd "$SLURMD_OPTIONS"
        ;;
    stop)
	slurmstop
        ;;
    status)
	for prog in $DAEMONLIST ; do
	   slurmstatus $prog
	done
        ;;
    restart)
        $0 stop
        $0 start
        ;;
    force-reload)
        $0 stop
        $0 start
	;;
    condrestart)
        if [ -f /var/lock/subsys/slurm ]; then
            for prog in $DAEMONLIST ; do
                 stop $prog
                 start $prog
            done
        fi
        ;;
    reconfig)
	for prog in $DAEMONLIST ; do
	    PIDFILE=$(getpidfile $prog)
	    start-stop-daemon --stop --signal HUP --pidfile \
	      "$PIDFILE" --quiet $prog
	done
	;;
    test)
	for prog in $DAEMONLIST ; do
	    echo "$prog runs here"
	done
	;;
    *)
        echo "Usage: $0 {start|startclean|stop|status|restart|reconfig|condrestart|test}"
        exit 1
        ;;
esac
