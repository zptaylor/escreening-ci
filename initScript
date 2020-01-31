#!/usr/bin/env bash
# chkconfig: 345 55 25
# description: Set up NAT ports, Mongo connection, and start up Tomcat for VIC

# REQUIRES: /app/vic/scripts/ directory to contain: env, startMongo.sh, and startupTomcat.sh

# INSTALL INSTRUCTIONS
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

# Source function library.
. /etc/init.d/functions

. $(dirname $(readlink -f $0))/env

start() {
    echo "Starting Application"
    echo "Setting NAT forwards"
	initIptables

    #echo "Starting Mongo"
    #daemon $SCRIPTPATH/startMongo.sh
    #in Prod a "health check" needs to be performed at this point

    echo "Starting Tomcat"
    daemon --user=tomcat $SCRIPTPATH/startupTomcat.sh
}

stop() {
    # code to stop app comes here
    # example: killproc program_name
    daemon --user=tomcat $SCRIPTPATH/shutdownTomcat.sh
}

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

exit 0