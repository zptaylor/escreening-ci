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
    if [ -d "$JAVA_LOCATION" ]; then
        echo Setting JAVA_HOME to "$JAVA_LOCATION"
        export JAVA_HOME="$JAVA_LOCATION"
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
    echo sudoRunning $SUDO_CMD $@
    $SUDO_CMD $@
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
    showlog
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
    echo Copying WAR file $APP_WAR to $APP_WAR_TOMCAT
    cp -p $APP_WAR $APP_WAR_TOMCAT
}
deploy()
{
    if [ "$USER" != "$TOMCAT_USER" ]
    then
        setPermissions
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
    showlog
    
    exit 0
}
showlog()
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
    showlog
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











# realpath-lib : realpath library for bash file path resolution and validation.
# No external dependencies - it relies on the bash builtins 'cd' and 'echo' and
# a little bit of script-foo path munching. Designed for portability. Versioning
# is according to issue date.
#
# Version : see $RPL_VERSION
#
# Usage   : source /path/to/realpath-lib
#
# Output  : (none)
#
# Functions:
#
# Each of the below returns the status conditions as:
#
# 0 : Pass.
# 1 : Fail : no file found/symlink broken/not regular file errors.
# 2 : Fail : physical file path asembly/resolution error.
# 3 : Fail : logical or physical path assembly/construction error.
# 4 : Fail : exceeded symlink max specified recursion error.
# 5 : Fail : exceeded symlink system limit recusion error.
# 6 : Fail : symlink circular reference detection error.
# 7 : Fail : the utility 'ls' does not exist error.
#
# The argument to each function is:
#
# </path/to/source.ext> an absolute path, a relative path or a local file.
#
# get_realpath  </path/to/source.ext> : returns the file path of a file.
# get_dirname   </path/to/source.ext> : returns the directory of a file.
# get_filename  </path/to/source.ext> : returns the file name of a path.*
# get_stemname  </path/to/source.ext> : returns the stem name of a path.**
# get_extension </path/to/source.ext> : returns the stem name of a path.***

# The following function succeeds or exits execution.  Use with care.
#
# validate_realpath </path/to/source.ext> : returns nothing, exits on error.****
#
# *    the filename is the file name and extension eg. 'source.ext'.
# **   the stemname is the file name without the extension eg. 'source'. Note
#      that a file name such as 'source.tar.gz' will be returned as 'source'.
# ***  the extension is the full extension string of the file name eg. ext.
#      Note that 'source.tar.gz' will return the extension 'tar.gz'.
# **** WARNING: using validate_path at shell level will kill the shell!
#
# How to test return values:
#
# get_realpath "$1" &>/dev/null
# code=$?
# if (( $code ))   # Non-zero.
# then
#     # Do failure actions.
#     return $code # Failure.
# fi
# return $code     # Success.
#
# Copyright (C) Applied Numerics Ltd 2013 under the brand name AsymLabs (TM)
# and published under the terms of the MIT license. Although we have not
# yet encountered any issues, there is no warrany of any type given so you
# must use it at your own risk. You have been warned.
#
# Comments are welcomed and may be forwarded to the author at:
#
# mailto:dv@angb.co

# Created by G R Summers Fri 27 Sep 2013 11:30:11 BST
# Updated by G R Summers Sat 05 Oct 2013 06:19:30 BST
# Updated by G R Summers Tue 12 Nov 2013 15:17:38 GMT
# Updated by G R Summers Tue 13 Nov 2013 17:04:14 GMT
# Updated by G R Summers Fri 15 Nov 2013 10:58:48 GMT
# Updated by G R Summers Sun 17 Nov 2013 11:33:36 GMT
# Updated by G R Summers Mon 18 Nov 2013 21:25:55 GMT
# Updated by G R Summers Tue 19 Nov 2013 10:10:47 GMT

#### DO NOT ALTER THESE SETTINGS!

# RPL_VERSION.  This is used for testing and identification purposes and should
# not be altered.
readonly RPL_VERSION='2013.11.19.00'

# RPL_SYMLINK_LIMIT.  This is the symlink recusion limit that overrides the
# custom environment setting of $set_max_depth that follows and should
# not be altered.  This is set to avoid infinite recursion and possible kernel
# recursion related errors.
readonly RPL_SYMLINK_LIMIT='40'

#### ENVIRONMENT SETTINGS

# IMPORTANT: By default realpath-lib is set to emulate the popular but not
# always available command 'readlink -f'.  The default setting: 1) does not
# require that files exist, 2) attempts to resolve (unwind) symlinks and
# chains 3) throws status 6 (and no path is emitted) if a circular reference
# is encountered and 3) links or files that do not exist or are broken still
# return the full path, as if they were there (as 'readlink -f' does).  This
# behaviour can be changed by changing the environment settings below.

# set_logical. By default the physical file system will be used, meaning that
# symlinks will be resolved to the physical system.  This is done so that the
# script will emulate the expected result of the command 'readlink -f'.
#
# Otherwise uncomment (set) the following to use only the logical file system,
# and physical locations will not be resolved.
#
# set_logical='true'

# set_strict.  By default target files are not verified. The default will tra-
# verse the chain of symlinks, throwing status 4, 5 or 6, if a link cannot be
# resolved. A useful feature is that these chains are unwound when a non-zero
# status is thrown, so by capturing stderr the full ordered sequence of link
# paths can be examined.  Therefore the default setting can be useful for diag-
# nostic purposes.
#
# To carry out strict file verification, enable set_strict.  Under this envi-
# ronment, files that are not regular, files that do not exist or symlinks that
# are broken will throw status 1 and no path will be emitted.
#
# Drawbacks of the default setting, however, are that execution may take more
# more time and errors could occur associated with kernel symlink recursion
# limits.  For this reason a control variable $set_max_depth is provided
# in the following sections.
#
# set_strict='true'

# set_max_depth.  Symlink recursion depth - take care if increasing this,
# there could be a self referencing or extended recursion that will exceed the
# built-in (default 20) or kernel limits.
# defalult:  set_max_depth=5
if [[ -z "$set_max_depth" ]]
then
    set_max_depth=5
fi

#### PRIVATE METHODS AND DATA

# _exit_states : simple exit states array that corresponds (one to one) with
# the array _exit_solutions[] below.
readonly _exit_states=(
    'Normal exit status, exited successfully'
    'No file found, special file type or broken symlink issues'
    'General path to file assembly/construction issues'
    'Physical path to file assembly/resolution issues'
    'Exceeded symlink recursion depth (max=$set_max_depth)'
    'Exceeded symlink recursion limit (built-in or kernel)'
    'Symlink circular reference issue has been detected'
    "Cannot locate utility 'ls', cannot proceed further"
    'Unspecified or unknown condition, posssible issues'
)

# _exit solutions : used with error logs - do not alter! Must have one entry
# for each of _exit_states[].
readonly _exit_solutions=(
    'No solution is needed for normal exit status'
    'Check that file path exists, is not special and is not broken'
    'Path may be empty, may have syntax errors and/or special symbols'
    'Path may be empty, may have syntax errors and/or special symbols'
    "Alter max ($set_max_depth) by increasing 'set_max_depth'"
    'No solution offered for exceeding symlink recursion limit'
    'Symlink circular reference should be investigated manually'
    "Enable 'set_logical=true' or install Posix utility 'ls'"
    'Cannot provide solution for unspecified or unknown errors'
)

# _unroll array : unroll an array passed by reference, in this case the history
# of links.
function _unroll(){
    local _el                # element.
    local _cntr=0            # counter.
    local _array=$1[@]       # array by ref.
    for _el in ${!_array}    # unroll array.
    do
        printf 'L [%02d] -> %s\n' "$_cntr" "$_el" 1>&2
        (( _cntr++ ))
    done
}

# _log_error code [fatal] : log according to return value (private function).
# use optional argument 'fatal' to exit execution - send to stderr.
function _log_error(){
    local _code _maxm
    _code=$1
    _maxm=$(( ${#_exit_states[@]} - 1 ))
    (( $_code > $_maxm )) && _code=$_maxm
    printf 'E [%02d] %s ...\n-----> %s ...\n' "$_code" "${_exit_states[$_code]}" "${_exit_solutions[$_code]}" 1>&2
    [[ "$2" = 'fatal' ]] && exit $_code
}

# _file "path/to/file" : print the file of a given path (private function).
function _file(){
    [[ -n "$1" ]] && printf '%s' "${1##*/}"
}

# _stem "path/to/file" : print file stem of a given path (private function).
function _stem(){
    [[ -n "$1" ]] && {
        local _name="$(_file "$1")"
        printf '%s' "${_name%%.*}"
    }
}

# _extn "path/to/file" : print extension of a given path (private function).
function _extn(){
    [[ -n "$1" ]] && {
        local _name="$(_file "$1")"
        local _stem="${_name%%.*}"
        printf '%s' "${_name#*"${_stem}."}"
    }
}

# _directory "path/to/file" : get the directory of a path (private function)
function _directory(){
    [[ -n "$1" ]] && printf '%s' "${1%/*}"
}

# _cd "path/to/file" : change to the directory of a path (private function).
function _cd(){
    cd "$(_directory "$1")" 2>/dev/null
}

#### PUBLIC INTERFACE METHODS

# get_dirname "path/to/file" : gets the directory name of a path to file. Pass
# return condition from get_realpath.
function get_dirname(){
    # declare locals before assignment!
    local _path _code
    _path="$(get_realpath "$1")"
    _code=$? # capture status
    (( $_code )) && return $_code || echo "$( _directory "$_path" )"
}

# get_filename "path/to/file" : gets a file name from a path to file. Pass
# return condition from get_realpath.
function get_filename(){
    # declare locals before assignment!
    local _path _code
    _path="$(get_realpath "$1")"
    _code=$? # capture status
    (( $_code )) && return $_code || echo "$( _file "$_path" )"
}

# get_stemname "path/to/file" : gets a stem name (removes directory and
# extension).  Pass return condition from get_realpath.
function get_stemname(){
    # declare locals before assignment!
    local _path _code
    _path="$(get_realpath "$1")"
    _code=$? # capture status
    (( $_code )) && return $_code || echo "$( _stem "$_path" )"
}

# get_extension "path/to/file" : gets a file extenion (removes directory
# and stem name).  Pass return condition from get_realpath.
function get_extension(){
    # declare locals before assignment!
    local _path _code
    _path="$(get_realpath "$1")"
    _code=$? # capture status
    (( $_code )) && return $_code || echo "$( _extn "$_path" )"
}

# validate_realpath "path/to/file" : dies on any non-zero error state.
function validate_realpath(){
    local _code
    ( get_realpath "$1" )
    _code=$?
    (( $_code )) && exit $_code
}

#### GET_REALPATH

# get_realpath "path/to/file" : echo the realpath as logical or physical,
# depending upon the environment settings.
#
# Fri Nov 15 10:08:53 GMT 2013 : Major revision includes the introduction of
# recursion and production of error messages to stderr.  Also added errors
# related to recursion depth controls.
#
# DESIGN NOTE: Errors are permitted ONLY within this function by design.  All
# other functions reflect return values, or exit based upon the conditions
# generated and emitted by this function.  This is done to ensure that return
# conditions and error messages are not duplicated.
function get_realpath(){
    # 0 : Pass.
    # 1 : Fail : no file found/symlink broken/not regular file errors.
    # 2 : Fail : physical file path assembly/resolution error.
    # 3 : Fail : logical or physical path assembly/construction error.
    # 4 : Fail : exceeded symlink max specified recursion error.
    # 5 : Fail : exceeded symlink system limit recusion error.
    # 6 : Fail : symlink circular reference detection error.
    # 7 : Fail : the utility 'ls' does not exist error.
    
    # File must exist, must be regular, and symlink cannot be broken.
    if [[ -n "$set_strict" ]]; then
        [[ ! -f "$1" ]] && {
            _log_error 1                               # emit error 1.
            return 1                                   # throw status 1.
        }
    fi
    
    # Declare locals/initialize some.
    local _el         # element of array
    local _ls         # ls command result
    local _lk         # next symlink path
    local _lkdir      # symlink directory
    local _lkfile     # symlink file name
    local _pd='pwd'   # present directory
    local _cntr=0     # recursion counter
    local _path="$1"  # path string cache
    local -a _paths   # paths history array
    
    # Begin procedures.
    if [[ -z "$set_logical" ]]
    then
        
        # Reset _pd
        _pd='pwd -P'
        
        # Look for symlinked file.
        if [[ -L "$_path" ]]; then
            
            # Check that ls exists or throw.
            hash ls || {
                _log_error 7                           # emit error 7.
                return 7                               # throw status 7.
            }
            
            # Recurse through link chain.
            while [[ -L "$_path" ]]
            do
                
                # Set temporaries, assemble path or throw.
                _ls="$( ls -dl "$_path" 2>/dev/null )" &&
                _lk="$( printf '%s' "${_ls#*"${_path} -> "}" )" &&
                _lkdir="$( _cd "$_path"; _cd "$_lk"; $_pd )" &&
                _lkfile="$(_file "$_lk")" && {
                    [[ -z "$_lkdir" ]] && _path="$_lkfile" || _path="$_lkdir"/"$_lkfile"
                    } || {
                    _log_error 3                       # emit error 3.
                    return 3                           # throw status 3.
                }
                
                # Enforce circular reference detection. This is a brute force
                # method, stores history.  If detected, unwinds full chain
                # history to stderr and throws.
                (( $_cntr )) && {                      # min two elements.
                    for _el in ${_paths[@]}
                    do
                        [[ "$_el" == "$_path" ]] && {  # find duplicate.
                            _paths[$_cntr]="$_path"    # insert duplicate.
                            _unroll _paths             # unroll paths.
                            _log_error 6               # emit error 6.
                            return 6                   # throw status 6.
                        }
                    done
                }
                
                # Store history.
                _paths[$_cntr]="$_path"
                
                # Increment.
                (( _cntr++ ))
                
                # Enforce user specified maximum recursion $set_max_depth or
                # throw.
                (( $_cntr == $set_max_depth )) && {
                    _unroll _paths                     # unroll paths.
                    _log_error 4                       # emit error 4.
                    return 4                           # throw status 4.
                }
                
                # Enforce built-in depth limit $RPL_SYMLINK_LIMIT - overrides
                # custom environment set_max_depth and throws.
                (( $_cntr == $RPL_SYMLINK_LIMIT )) && {
                    _unroll _paths                     # unroll paths.
                    _log_error 5                       # emit error 5.
                    return 5                           # throw status 5.
                }
                
            done
            
            echo "$_path"                              # emit path.
            return 0                                   # throw status 0.
            
        fi
        
    fi
    
    # Resolve links, assemble path or throw.
    _lkdir="$( _cd "$_path"; $_pd )" &&
    _lkfile="$(_file "$_path")" && {
        [[ -z "$_lkdir" ]] && _path="$_lkfile" || _path="$_lkdir"/"$_lkfile"
        } || {
        _log_error 3                                   # emit error 3.
        return 3                                       # throw status 3.
    }
    
    echo "$_path"                                      # emit path.
    return 0                                           # throw status 0.
    
}

# end realpath-lib
