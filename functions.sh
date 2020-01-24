#!/usr/bin/env bash
FAIL_ON_ERROR()
{
    if test "$BASH" = "" || "$BASH" -uc "a=();true \"\${a[@]}\"" 2>/dev/null; then
        # Bash 4.4, Zsh
        set -euo pipefail
    else
        # Bash 4.3 and older chokes on empty arrays with set -u.
        set -eo pipefail
    fi
    shopt -s nullglob globstar
    set -e
    set -o nounset
}
setJavaHome()
{
    if [ -d "$JAVA_HOME" ]; then
        echo Setting JAVA_HOME to "$JAVA_HOME"
        export JAVA_HOME="$JAVA_HOME"
    else
        echo Setting JAVA_HOME to "/usr"
        export JAVA_HOME=/usr
    fi
}
checkUserVariable()
{
    #https://stackoverflow.com/questions/3601515/how-to-check-if-a-variable-is-set-in-bash
    if [ -z ${USER+x} ];
    then echo "USER is unset - cannot check USER privileges"
        return 1;
    else echo "USER is set to '$USER'"
        return 0;
    fi
}

rerunAs()
{
    echo rerunAs "$@"
    sudoRun -u "$@" "$THISCMD" "$THISARGS"
}

runAsTomcatUser()
{
    checkUserVariable
    echo checking if user "$USER" matches "$TOMCAT_USER"
    local arg1=$@
    echo arg1=$arg1
    if [ "$USER" != "$TOMCAT_USER" ]; then
        echo "Found Tomcat User! $USER Running:" $SUDO_CMD -u "$TOMCAT_USER" $arg1
        sudoRun -u "$TOMCAT_USER" $arg1;
    else echo "NOT TOMCAT USER $USER";
    fi
}

setPermissions()
{
    echo Setting permissions on $APP_WAR  to "$TOMCAT_USER":"$TOMCAT_USER"
    sudoRun chown "$TOMCAT_USER":"$TOMCAT_USER" $APP_WAR || true
    echo Setting permissions on $APP_WAR  to 7777
    sudoRun chmod 7777 $APP_WAR || true
    echo Setting permissions on Properties Files
    sudoRun chown "$TOMCAT_USER":"$TOMCAT_USER" $APP_PROPERTIES_ORIGINAL || true
    sudoRun chown "$TOMCAT_USER":"$TOMCAT_USER" $APP_PROPERTIES || true
}
sudoRun()
{
#    if [ "$USER" != "root" ]; then
        echo sudoRunning $SUDO_CMD $@
        $SUDO_CMD $@;
#    else 
#      echo "$@"
#      $@;
#    fi
}
apacheRestart()
{
    if [ "$USER" != "$TOMCAT_USER" ]
    then
        rerunAs "$TOMCAT_USER"
        echo exiting
        exit 0;
    fi

    apacheShutdown
    apacheStart
    apacheShowlog
}
apacheStart()
{
    if [ "$USER" != "$TOMCAT_USER" ]
    then
        rerunAs "$TOMCAT_USER"
        echo exiting
        exit 0;
    fi
    
    echo "Starting Apache HTTPD with $APACHE_CTL start"
    $APACHE_CTL start
}

apacheShutdown()
{
    if [ "$USER" != "$TOMCAT_USER" ]
    then
        rerunAs "$TOMCAT_USER"
        echo exiting
        exit 0;
    fi
    
    echo "Stop Apache HTTPD with $APACHE_CTL start"
    $APACHE_CTL stop
    pkill -u $TOMCAT_USER httpd || true
}
tomcatDebug()
{
    if [ "$USER" != "$TOMCAT_USER" ]
    then
		setPermissions
        rerunAs "$TOMCAT_USER"
        echo exiting
        exit 0;
    fi
    tomcatShutdown || $TOMCAT_DIR/bin/shutdown.sh || true
    copyProperties
    copyWAR
    $TOMCAT_DIR/bin/catalina.sh jpda start
    tomcatShowlog
}
tomcatStartup()
{
    if [ "$USER" != "$TOMCAT_USER" ]
    then
        rerunAs "$TOMCAT_USER"
        echo exiting
        exit 0;
    fi
    echo Running as "$USER"
    
    echo Shutting down Tomcat
    $TOMCAT_DIR/bin/shutdown.sh || true
    
    echo Killing java instances under "$TOMCAT_USER"
    pkill -u $TOMCAT_USER java || true
    
    echo Starting Tomcat
    $TOMCAT_DIR/bin/startup.sh
    
}
tomcatShutdown()
{
    if [ "$USER" != "$TOMCAT_USER" ]
    then
        rerunAs "$TOMCAT_USER"
        echo exiting
        exit 0;
    fi
    echo Running as "$USER"
    
    $TOMCAT_DIR/bin/shutdown.sh || true
}
copyProperties()
{
    echo Copying properties file $APP_PROPERTIES_ORIGINAL to $APP_PROPERTIES
    cp -p $APP_PROPERTIES_ORIGINAL $APP_PROPERTIES
}
copyWAR()
{
    if [ -r "$APP_WAR" ]; then
        echo Copying WAR file $APP_WAR to $APP_WAR_TOMCAT    
        cp -p $APP_WAR $APP_WAR_TOMCAT
    else
        echo WAR file could not be found at $APP_WAR
	exit 1
    fi
}
deploy()
{
    if [ "$USER" != "$TOMCAT_USER" ]
    then
        setPermissions
#	sudoRun wipeIptables
#	sudoRun initIptables
        rerunAs "$TOMCAT_USER"
        echo exiting
        exit 0;
    fi
    echo Running as "$USER"
    tomcatShutdown || $TOMCAT_DIR/bin/shutdown.sh || true
    copyProperties
    copyWAR
    tomcatStartup
    apacheStart || true
#    tomcatShowlog
    
    exit 0
}
tomcatShowlog()
{
    if [ "$USER" != "$TOMCAT_USER" ]
    then
        rerunAs "$TOMCAT_USER"
        echo exiting
        exit 0;
    fi
    echo Running as "$USER"
    TAIL_OPTS=-5f
    local arg1=$THISARGS
    if [ -n "${arg1-}" ]
    then
        #       echo 'not empty'
        #	echo "Argument supplied: $arg1"
        TAIL_OPTS=$arg1
        
    elif [ "${arg1+defined}" = defined ]
    then
        echo 'empty but defined'
    else
        echo 'unset'
    fi
    
    tail $TAIL_OPTS $TOMCAT_DIR/logs/catalina.out
}
apacheShowlog()
{
    if [ "$USER" != "$TOMCAT_USER" ]
    then
        rerunAs "$TOMCAT_USER"
        echo exiting
        exit 0;
    fi
    echo Running as "$USER"
    TAIL_OPTS=-f
    local arg1=$THISARGS
    if [ -n "${arg1-}" ]
    then
        #       echo 'not empty'
        #       echo "Argument supplied: $arg1"
        TAIL_OPTS=$arg1

    #elif [ "${arg1+defined}" = defined ]
    #then
    #    echo 'empty but defined'
    #else
    #    echo 'unset'
    fi
    cd /
    find "$HTTPD_DIR"/logs/ -type f \( -name "*log" \) -exec tail "$TAIL_OPTS" {} +
}
pushToOtherServer()
{
    if [ "$USER" != "$TOMCAT_USER" ]
    then
        rerunAs "$TOMCAT_USER"
        echo exiting
        exit 0;
    fi
    scp $APP_WAR $TOMCAT_USER@$SSH_PUSH_DEST:/tmp/
}
runScriptOnOtherServer()
{
    ssh -t $TOMCAT_USER@$SSH_PUSH_DEST "bash /tmp/deploy.sh"
}
hotDeploy()
{
    if [ "$USER" != "$TOMCAT_USER" ]
    then
        setPermissions
        rerunAs "$TOMCAT_USER"
        echo exiting
        exit 0;
    fi
    copyProperties
    copyWAR
    tomcatShowlog
}
wipeIptables()
{
    if [ "$USER" != "root" ]
    then
        rerunAs "root"
        echo exiting
        exit 0;
    fi
    echo "Wiping IP Tables as " "$USER"
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -t nat -F
    iptables -t mangle -F
    iptables -F
    iptables -X
    echo "All wiped"
}
showIptables()
{
    if [ "$USER" != "root" ]
    then
        rerunAs "root"
        echo exiting
        exit 0;
    fi
    sudo  iptables -t nat -L -n
}
initIptables()
{
    if [ "$USER" != "root" ]
    then
        setPermissions
        rerunAs "root"
        echo exiting
        exit 0;
    fi
    
    echo checking if iptables already updated
    IP_OUTPUT="$(iptables -t nat -L -n)"
	
	echo ORIGINAL IP TABLE
	echo "$IP_OUTPUT"
    
    GREP_THIS_80="tcp dpt:80 redir ports $WEB_PORT_TO_FORWARD_TO_80"
    GREP_THIS_443="tcp dpt:443 redir ports $WEB_PORT_TO_FORWARD_TO_443"
    #GREP_THIS_444="tcp dpt:444 redir ports $WEB_PORT_TO_FORWARD_TO_444"
    
    IS8080TEXT="$(echo "$IP_OUTPUT" |  grep "$GREP_THIS_80")" || true
    IS443TEXT="$(echo "$IP_OUTPUT" |  grep "$GREP_THIS_443")" || true
    IS444TEXT="$(echo "$IP_OUTPUT" |  grep "tcp dpt:443 redir ports 8443")" || true
    
    
    if [[ $IS8080TEXT ]]; then
        echo "80=>$WEB_PORT_TO_FORWARD_TO_80 iptable rule already configured."
    else
        echo "Setting 80=>$WEB_PORT_TO_FORWARD_TO_80 iptable rule!"
        iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port "$WEB_PORT_TO_FORWARD_TO_80";
    fi
    
    if [[ $IS443TEXT ]]; then
        echo "443=>$WEB_PORT_TO_FORWARD_TO_443 iptable rule already configured."
    else
        echo "Setting 443=>$WEB_PORT_TO_FORWARD_TO_443 iptable rule!"
        iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port "$WEB_PORT_TO_FORWARD_TO_443";
    fi
	
    #if [[ $IS444TEXT ]]; then
    #    echo "444=>$WEB_PORT_TO_FORWARD_TO_444 iptable rule already configured."
    #else
    #    echo "Setting 443=>$WEB_PORT_TO_FORWARD_TO_444 iptable rule!"
    #    iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port "$WEB_PORT_TO_FORWARD_TO_444";
    #fi
}

makeLinks()
{
    echo "Making links to these scripts in the /tmp/ directory"
    for filename in $SCRIPTS_DIR/*.sh; do
        ln -s "$filename" /tmp/$(basename "$filename") -v || true
    done
}

compressScripts()
{
    tar -czvf /tmp/app.scripts.tar.gz $SCRIPTS_DIR
    chmod 777 /tmp/app.scripts.tar.gz
}
