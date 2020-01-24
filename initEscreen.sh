#!/usr/bin/env bash
# chkconfig: 345 55 25
# description: start eScreening

# REQUIRES: /app/*/scripts/ directory to contain: env, functions.sh

# INSTALL INSTRUCTIONS (Need to be updated)
# dzdo rm /app/vic/scripts/initVIC.sh ; dzdo nano /app/vic/scripts/initVIC.sh ; dzdo chmod a+rwx /app/vic/scripts/initVIC.sh
## paste this whole script in there and save
## to create the init link for server startup:
# dzdo ln -s /app/vic/scripts/initVIC.sh /etc/init.d/initVIC
# dzdo systemctl daemon-reload
# dzdo chkconfig initVIC on

##References
### https://www.thegeekdiary.com/how-to-enable-or-disable-service-on-boot-with-chkconfig/
### https://access.redhat.com/discussions/1455613
### https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/5/html/Installation_Guide/s1-boot-init-shutdown-run-boot.html
### https://arstechnica.com/civis/viewtopic.php?p=2147913
### https://www.linuxjournal.com/article/4445

echo Source function library.
. /etc/init.d/functions

echo Source custom env variables for app
. $(dirname $(readlink -f $0))/env

echo Source custom functions for app
. $(dirname $(readlink -f $0))/functions.sh

start() {
    echo "Starting Application"
    echo "Disabling SELinux!"
      setenforce 0
    echo "Setting NAT forwards"
	wipeIptables
	initIptables

    echo "Starting Tomcat"
#    daemon --user=tomcat $SCRIPTPATH/startupTomcat.sh
}

stop() {
    # code to stop app comes here
    # example: killproc program_name
 #   daemon --user=tomcat $SCRIPTPATH/shutdownTomcat.sh
    echo "Stopping not set up."
}

if [ -n "${1-}" ]
then
  case "$1" in
    start)
       start
       ;;
    stop)
       stop
       ;;
    restart)
       stop
       start
       ;;
    status)
       # code to check status of app comes here
       # example: status program_name
       #daemon --user=tomcat $SCRIPTPATH/showlog.sh
       ;;
    *)
       echo "Usage: $0 {start|stop|status|restart}"
  esac

elif [ "${1+defined}" = defined ]
then
    #'empty but defined'
	echo an argument must be passed
else
    echo 'argument must be passed'
fi

exit 0
