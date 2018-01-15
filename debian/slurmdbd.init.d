#!/bin/sh
#
# chkconfig: 345 90 10
# description: SLURMDBD is a database server interface for \
#              SLURM (Simple Linux Utility for Resource Management).
#
# processname: /usr/sbin/slurmdbd
# pidfile: /var/run/slurm-llnl/slurmdbd.pid
#
# config: /etc/default/slurmdbd
#
### BEGIN INIT INFO
# Provides:          slurmdbd
# Required-Start:    $remote_fs $syslog $network munge
# Required-Stop:     $remote_fs $syslog $network munge
# Should-Start:      $named mysql
# Should-Stop:       $named mysql
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: SLURM database daemon
# Description:       Start slurm to provide database server for SLURM
### END INIT INFO

SBINDIR=/usr/sbin
LIBDIR=/usr/lib
CONFFILE="/etc/slurm-llnl/slurmdbd.conf"
DESCRIPTION="slurm-wlm database server interface"
NAME="slurmdbd"

# Source slurm specific configuration
if [ -f /etc/default/slurmdbd ] ; then
    . /etc/default/slurmdbd
else
    SLURMDBD_OPTIONS=""
fi

#Checking for configuration file
if [ ! -f $CONFFILE ] ; then
  if [ -n "$(echo $1 | grep start)" ] ; then 
    echo Not starting slurmdbd
  fi 
  echo $CONFFILE not found
  exit 0
fi

#Checking for lsb init function
if [ -f /lib/lsb/init-functions ] ; then
  . /lib/lsb/init-functions
else
  echo Can\'t find lsb init functions 
  exit 1
fi

getpidfile() {
    dpidfile=`grep PidFile $CONFFILE | grep -v '^ *#'`
    if [ $? = 0 ]; then
        dpidfile=${dpidfile##*=}
        dpidfile=${dpidfile%#*}
    else
        dpidfile=/var/run/slurm-llnl/slurmdbd.pid
    fi

    echo $dpidfile
}

# setup library paths for slurm and munge support
export LD_LIBRARY_PATH=$LIBDIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

start() {

    # Create run-time variable data
    mkdir -p /var/run/slurm-llnl
    chown slurm:slurm /var/run/slurm-llnl

    unset HOME MAIL USER USERNAME 
    log_daemon_msg "Starting $DESCRIPTION"
    STARTERRORMSG="$(start-stop-daemon --start --oknodo \
    			--exec "$SBINDIR/$NAME" -- $SLURMDBD_OPTIONS 2>&1)"
    STATUS=$?
    if [ "$STARTERRORMSG" != "" ] ; then 
      STARTERRORMSG=$(echo $STARTERRORMSG | sed "s/.$//")
      log_progress_msg $STARTERRORMSG
    else
      log_progress_msg $NAME
    fi
    touch /var/lock/$NAME
    log_end_msg $STATUS
}

stop() { 
    log_daemon_msg "Stopping $DESCRIPTION"
    STOPERRORMSG="$(start-stop-daemon --oknodo --stop -s TERM \
    			--exec "$SBINDIR/$NAME" 2>&1)"
    STATUS=$?
    if [ "$STOPERRORMSG" != "" ] ; then 
      STOPERRORMSG=$(echo $STOPERRORMSG | sed "s/.$//")
      log_progress_msg $STOPERRORMSG
    else
      log_progress_msg "$NAME"
    fi
    log_end_msg $STATUS
    rm -f /var/lock/$NAME
}

slurmstatus() {
    base=${1##*/}

    pidfile=$(getpidfile)

    pid=`pidof -o $$ -o $$PPID -o %PPID -x slurmdbd`

    if [ -f $pidfile ]; then
        read rpid < $pidfile
        if [ "$rpid" != "" -a "$pid" != "" ]; then
            for i in $pid ; do
                if [ "$i" = "$rpid" ]; then 
                    echo "slurmdbd (pid $pid) is running..."
                    return 0
                fi     
            done
        elif [ "$rpid" != "" -a "$pid" = "" ]; then
            echo "slurmdbd is stopped"
            return 1
        fi 

    fi
     
    echo "slurmdbd is stopped"
    
    return 3
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
	start
        ;;
    stop)
	stop
        ;;
    status)
	slurmstatus
        ;;
    restart)
	stop
	sleep 1
	start
        ;;
    force-reload)
        $0 stop
        $0 start
	;;
    condrestart)
        if [ -f /var/lock/subsys/slurm ]; then
                 stop
                 start
        fi
        ;;
    reconfig)
	PIDFILE=$(getpidfile)
	start-stop-daemon --stop --signal HUP --pidfile \
	    	"$PIDFILE" --quiet slurmdbd
	;;
    *)
        echo "Usage: $0 {start|stop|status|restart|condrestart|reconfig}"
        exit 1
        ;;
esac
