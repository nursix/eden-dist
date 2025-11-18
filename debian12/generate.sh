#!/bin/bash

mkdir -p $BUILD$WEB2PY_HOME
mkdir -p $BUILD/usr/local/lib/sahana

# uWSGI =======================================================================
#
UWSGI_VERSION=2.0.28
UWSGI_URL=https://files.pythonhosted.org/packages/24/c2/d58480aadc9a1f420dd96fc43cf0dcd8cb5ededb95cab53743529c23b6cd/uwsgi-2.0.28.tar.gz

mkdir -p $BUILD/tmp
cd $BUILD/tmp
wget $UWSGI_URL

# edenvars.sh =================================================================
#
cat << EOF > "$BUILD/usr/local/lib/sahana/edenvars.sh"
INSTANCE=$INSTANCE
APPNAME=$APPNAME

WEB2PY_HOME=$WEB2PY_HOME
APPS_HOME=\$WEB2PY_HOME/applications
EDEN_HOME=\$APPS_HOME/\$APPNAME

DBNAME=$DBNAME
DBUSER=$DBUSER

UWSGI_VERSION=$UWSGI_VERSION

UWSGI_SOCKET=$UWSGI_SOCKET
UWSGI_WORKERS=$UWSGI_WORKERS
UWSGI_UID=$UWSGI_UID
UWSGI_GID=$UWSGI_GID
EOF

# uwsgi.ini ===================================================================
#
cat << EOF > "$BUILD$WEB2PY_HOME/uwsgi.ini"
[uwsgi]
uid = $UWSGI_UID
gid = $UWSGI_GID
chdir = $WEB2PY_HOME/
module = wsgihandler
mule = run_scheduler.py
workers = $UWSGI_WORKERS
cheap = true
idle = 1000
harakiri = 180
pidfile = /var/run/uwsgi-$INSTANCE.pid
daemonize = /var/log/uwsgi/$INSTANCE.log
socket = 127.0.0.1:$UWSGI_SOCKET
master = true
chmod-socket = 666
chown-socket = $UWSGI_UID:nginx
EOF

# run_scheduler.py ============================================================
#
cat << EOF > "$BUILD$WEB2PY_HOME/run_scheduler.py"
#!/usr/bin/python

import os
import sys

if '__file__' in globals():
    path = os.path.dirname(os.path.abspath(__file__))
    os.chdir(path)
else:
    path = os.getcwd()

sys.path = [path]+[p for p in sys.path if not p==path]

import gluon.widget
from gluon.shell import run

# Start Web2py Scheduler
if __name__ == '__main__':
    run('$APPNAME',True,True,None,False,"from gluon import current; current._scheduler.loop()")
EOF

# routes.py ===================================================================
#
cat << EOF > "$BUILD$WEB2PY_HOME/routes.py"
#!/usr/bin/python
default_application = '$APPNAME'
default_controller = 'default'
default_function = 'index'
routes_onerror = [
        ('$APPNAME/400', '!'),
        ('$APPNAME/401', '!'),
        ('$APPNAME/405', '!'),
        ('$APPNAME/409', '!'),
        ('$APPNAME/509', '!'),
        ('$APPNAME/*', '/$APPNAME/errors/index'),
        ('*/*', '/$APPNAME/errors/index'),
        ]
EOF

# uwsgi-eden ==================================================================
#
cat << EOF > "$BUILD/usr/local/lib/sahana/uwsgi-$INSTANCE"
#!/bin/sh
### BEGIN INIT INFO
# Provides:          uwsgi-$INSTANCE
# Required-Start:    \$local_fs \$remote_fs \$network
# Required-Stop:     \$local_fs \$remote_fs \$network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start/stop custom uWSGI server instance
### END INIT INFO

## Variables
PATH=/sbin:/usr/sbin:/bin:/usr/bin

NAME="$INSTANCE"
DESC="$INSTANCE uWSGI server"

SCRIPTNAME=/etc/init.d/uwsgi-\$NAME
DAEMON=/usr/local/bin/uwsgi

UWSGI_UID=$UWSGI_UID
UWSGI_GID=$UWSGI_GID

PIDFILE=/run/uwsgi-\$NAME.pid

DAEMON_ARGS=" \
  --daemonize /var/log/uwsgi/\${NAME}.log \
  --pidfile \$PIDFILE \
  --uid \$UWSGI_UID \
  --gid \$UWSGI_GID \
  --ini /home/\${NAME}/uwsgi.ini \
"

## Prep

# Exit if the package is not installed
[ -x \$DAEMON ] || exit 0

# Load the VERBOSE setting and other rcS variables
. /lib/init/vars.sh

# Define LSB log_* functions.
# Depend on lsb-base (>= 3.0-6) to ensure that this file is present.
. /lib/lsb/init-functions

## Functions

# Return:
#  0 if daemon has been started
#  1 if daemon was already running
#  2 if daemon could not be started
do_start()
{
  start-stop-daemon --start --quiet \
    --pidfile \$PIDFILE \
    --exec \$DAEMON \
    --test > /dev/null \
      || return 1

  start-stop-daemon --start --quiet \
    --pidfile \$PIDFILE \
    --exec \$DAEMON -- \$DAEMON_ARGS \
      || return 2

  local INTERVAL_START=\$(date +%s)
  local INTERVAL_END=\$(date +%s)
  local WAITING=2 # seconds

  # Wait until daemon getting to create pidfile.
  while [ ! -e "\$PIDFILE" ]; do
    INTERVAL_END=\$(date +%s)
    if [ \$(expr \$INTERVAL_END - \$INTERVAL_START) -gt \$WAITING ]; then
      return
    fi
    sleep 0.05
  done

  chown root:root \$PIDFILE
  chmod 644 \$PIDFILE

  return 0
}

# Return:
#  0 if daemon has been stopped
#  1 if daemon was already stopped
#  2 if daemon could not be stopped
#  other if a failure occurred
do_stop()
{
  start-stop-daemon --stop --quiet \
    --retry=QUIT/30/KILL/5 \
    --pidfile \$PIDFILE \
    --exec \$DAEMON

  RETVAL="\$?"
  [ "\$RETVAL" = 2 ] && return 2

  rm -rf \$RUNDIR

  return "\$RETVAL"
}

# Return:
#  0 if daemon has been reloaded
#  3 if daemon could not be reloaded
do_reload()
{
  start-stop-daemon --stop --quiet \
    --signal=HUP \
    --pidfile \$PIDFILE \
    --exec \$DAEMON

  RETVAL="\$?"

  # There is no such process, nothing to reload!
  [ "\$RETVAL" = 1 ] && RETVAL=3

  return "\$RETVAL"
}

# Return:
#  0 if daemon has been reloaded
#  3 if daemon could not be reloaded
do_force_reload()
{
  start-stop-daemon --stop --quiet \
    --signal=TERM \
    --pidfile \$PIDFILE \
    --exec \$DAEMON

  RETVAL="\$?"

  # There is no such process, nothing to reload!
  [ "\$RETVAL" = 1 ] && RETVAL=3

  return "\$RETVAL"
}

## Execute
case "\$1" in
    start)
        log_daemon_msg "Starting \$DESC" "\$NAME"
        do_start
        log_end_msg "\$?"
        ;;

    stop)
        log_daemon_msg "Stopping \$DESC" "\$NAME"
        do_stop
        log_end_msg "\$?"
        ;;

    status)
        status_of_proc -p "\$PIDFILE" "\$DAEMON" "\$NAME" && exit 0 || exit \$?
        ;;

    reload)
        log_daemon_msg "Reloading \$DESC" "\$NAME"
        do_reload
        log_end_msg "\$?"
        ;;

    force-reload)
        log_daemon_msg "Forced reloading \$DESC" "\$NAME"
        do_force_reload
        log_end_msg "\$RETVAL"
        ;;

    restart)
        log_daemon_msg "Restarting \$DESC" "\$NAME"
        do_stop
        case "\$?" in
            0)
                do_start
                log_end_msg "\$?"
                ;;
            *)
                # Failed to stop
                log_end_msg 1
                ;;
        esac
        ;;

    *)
        echo "Usage: \$SCRIPTNAME {start|stop|status|restart|reload|force-reload}" >&2
        exit 3
        ;;
esac

:
EOF

# END =========================================================================

