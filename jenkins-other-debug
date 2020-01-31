#!/bin/bash

echo "-----Starting deployment!-----"
cd /app/escreening/scripts
echo "-----Source environment!-----"
. ./env

APP_WAR="/var/lib/jenkins/workspace/DEV Escreening Others/escreening/target/escreening.war"
echo "-----Setting location for source WAR "$(echo $APP_WAR)!"-----"

echo "-----Shutdown tomcat!-----"
sudo -u $TOMCAT_USER $TOMCAT_DIR/bin/shutdown.sh || true

echo "-----Copy Properties!-----"
cp -v "$APP_PROPERTIES_ORIGINAL" "$APP_PROPERTIES"
echo "-----Timestamp: $(ls -lah "$APP_WAR")-----" || true

echo "-----Copy Tomcat from $(echo APP_WAR) to $(echo $APP_WAR_TOMCAT)-----"
cp -v "$APP_WAR" "$APP_WAR_TOMCAT"

echo "-----Starting Tomcat with Debugger on!-----"
sudo -u $TOMCAT_USER $TOMCAT_DIR/bin/catalina.sh jpda start &
