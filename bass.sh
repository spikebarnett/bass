#!/bin/bash
# Bash Webserver Written by cbarnett@liquidweb.com
# If you use this as a webserver, you're going to have a bad time. It has had exactly 0 thought put towards security.

# TODO parse PHP, Perl, ect, before passing anything to the browser. Pass headers set by the script, if any, then send content. If no headers were set, send aproppriate headers, then content.

# Set defaults to be overriden later by cmdline options.
LOGFILE="/var/log/bass.log"
DOCROOT=`pwd`
ALLOWFILE="/etc/bass/allow"
DENYFILE="/etc/bass/deny"
INDEXES="1"

DBUG="1"

function log
{
  Red='\e[0;31m'; Green='\e[0;32m'; Yellow='\e[0;33m'; Blue='\e[0;34m'; NoColor='\e[0m';
  case $1 in
  FAIL)
    echo -e "[$Red$1$NoColor] `date '+%Y-%m-%d %H:%M:%S'` $2" >> $LOGFILE; ;;
  WARN)
    echo -e "[$Yellow$1$NoColor] `date '+%Y-%m-%d %H:%M:%S'` $2" >> $LOGFILE; ;;
  INFO)
    echo -e "[$Green$1$NoColor] `date '+%Y-%m-%d %H:%M:%S'` $2" >> $LOGFILE; ;;
  DBUG)
    if [[ "$DBUG" == "1" ]]; then echo -e "[$Blue$1$NoColor] `date '+%Y-%m-%d %H:%M:%S'` $2" >> $LOGFILE; fi; ;;
  *)
    echo -e "[$Red"'FAIL'"$NoColor] `date '+%Y-%m-%d %H:%M:%S'` Bad log command ($1) $2" >> $LOGFILE
  esac
}

function check_allow
{
  if [! -e $ALLOWFILE ]; then touch $ALLOWFILE; fi
  if [! -e $DENYFILE ]; then touch $DENYFILE; fi

  ALLOW=`grep -c $1 $ALLOWFILE`
  if [[ "$ALLOW" -ge "1" ]]
  then
    log "DBUG" "($IPADDR) IP allowed by server configuration: $1"
  else
    DENY=`grep -c $1 $DENYFILE`
    if [[ "$DENY" -ge "1" ]]
    then
      log "WARN" "($IPADDR) IP denied by server configuration: $1"
      echo -ne "HTTP/1.1 403 Forbidden\r\nContent-type: text/html\r\n\r\n403 - Forbidden</br>Go fuck yourself!\r\n\r\n"
      exit
    else
      log "DBUG" "($IPADDR) IP not allowed or denied by server configuration: $1"
    fi
  fi
}

function check_valid
{
  if [ -e "$1$2" ]
  then
    PERMS=`stat -c'%a' "$1$2"`
    if [[ $PERMS =~ ^[0-7][0-7][456]$ ]]
    then
      log "DBUG" "($IPADDR) File Validated: $2"
    else
      log "DBUG" "($IPADDR) File failed validation: $2"
      serve_403 $1 $2 # Perms bad, run!
    fi
  else
    log "DBUG" "($IPADDR) File failed validation: $2"
    serve_404 $1 $2 # Where are you?
  fi
}

function check_ht
{
# TODO Add .htaccess / .htpasswd support
echo "Does nothing yet"
}

function serve_404
{
  log "WARN" "($IPADDR) No such file or directory: $1$2"
  echo -ne "HTTP/1.1 404 Not Found\r\nContent-type: text/html\r\n\r\n404 - Not found\r\n\r\n"
  exit
}

function serve_403
{
  log "WARN" "($IPADDR) Not allowed: $1$2"
  echo -ne "HTTP/1.1 403 Forbidden\r\nContent-type: text/html\r\n\r\n403 - Forbidden\r\n\r\n"
  exit
}

function serve_505
{   
  log "FAIL" "($IPADDR) $1 Not Supported"
  echo -ne "HTTP/1.1 505 HTTP Version Not Supported\r\nContent-type: text/html\r\n\r\n505 - HTTP Version Not Supported\r\n\r\n"
  exit
} 

function serve_dir
{
  if [[ "$INDEXES" == "0" ]]
  then
    serve_403
  else
    log "DBUG" "($IPADDR) Serving Dir: $2"
    echo -ne "HTTP/1.1 200 OK\r\nContent-type: text/html;charset=UTF-8\r\n\r\n"
    echo -ne "LISTING $2<br/>\r\n<br/><a href=\"../\">../</a>\r\n"
    ls -AF $1$2|while read file
    do
      echo -ne "<br/><a href=\"$file\">$file</a>\r\n"
    done
  fi
}

function serve_php
{
# TODO parse PHP, Perl, ect, before passing anything to the browser. Pass headers set by the script, if any, then send content. If no headers were set, send aproppriate headers, then content.

  log "DBUG" "($IPADDR) Serving PHP: $2"
  echo -ne "HTTP/1.1 200 OK\r\nContent-type: text/html\r\n\r\n"
  php-cgi -f "$1$2" $3
}

function serve_file
{
  SIZE=`stat -c'%s' "$1$2"`
  log "DBUG" "($IPADDR) Serving File: $2"
  echo -ne "HTTP/1.1 200 OK\r\nContent-type: $3\r\nContent-length $SIZE\r\n\r\n"
  cat "$1$2"
}

########################## Parse Arguments ###########################
for arg in $@
do
  case $arg in
    listen=*)
      LISTENIP=`echo $arg|cut -d= -f2`
    ;;
    docroot=*)
      DOCROOT=`echo $arg|cut -d= -f2`
      DOCROOT=${DOCROOT%/}
    ;;
    logfile=*)
      LOGFILE=`echo $arg|cut -d= -f2`
    ;;
    ipaddr=*)
      IPADDR=`echo $arg|cut -d= -f2`
    ;;
  esac
done

if [ -z $LISTENIP ]
then
########################## Process Requests ##########################
  read REQUEST
  log "DBUG" "($IPADDR) Proccess $REQUEST"
  REQUEST=`echo $REQUEST|tr -d '\n'|tr -d '\r'`
  ACTION=`echo $REQUEST|cut -d' ' -f1`
  FILE=`echo $REQUEST|cut -d' ' -f2|cut -d? -f1`
  ARGS=`echo $REQUEST|cut -d' ' -f2|cut -s -d? -f2|sed 's/\&/ /g'`
  PROTO=`echo $REQUEST|cut -d' ' -f3`
  MIME=`file -i $DOCROOT$FILE|cut -d' ' -f2`
  PERMS=`stat -c'%a' "$DOCROOT$FILE"`
  FULL="$DOCROOT$FILE"

  if [[ "$DBUG" == "1" ]]
  then
    echo -e "REQ:\t$REQUEST"
    echo -e "ACTION:\t$ACTION"
    echo -e "FULL:\t$FULL"
    echo -e "PERMS:\t$PERMS"
    echo -e "FILE:\t$FILE"
    echo -e "ARGS:\t$ARGS"
    echo -e "PROTO:\t$PROTO"
    echo -e "MIME:\t$MIME"
    echo -e "IPADDR:\t$IPADDR"
    echo
  fi

  check_allow $IPADDR
  check_valid $DOCROOT $FILE

  case $PROTO in
  HTTP/1.1)
    case "$ACTION" in
    GET)
      case "$MIME" in
################ "Acurate" MIME types ################
      application/x-not-regular-file) # Prolly a dir
        if [ -d "$DOCROOT$FILE" ]
        then
          serve_dir "$DOCROOT" "$FILE"
        else
          serve_403
        fi
      ;;
      image/*)
        serve_file "$DOCROOT" "$FILE" "$MIME"
      ;;
################ Other MIME types ################
      text/*) # Maybe PHP, who knows?
        if [[ $FILE == *\.php* ]]
        then
          serve_php "$DOCROOT" "$FILE" "$ARGS" # Still might not be PHP... :/
        else
          serve_file "$DOCROOT" "$FILE" "$MIME" # Prolly cool to serve this, prolly...
        fi
      ;;
      cannot)
        serve_404 "$DOCROOT" "$FILE" # Not sure how you got passed check_valid...
      ;;
      *)
        serve_file "$DOCROOT" "$FILE" "application/x-download"
      ;;
      esac
    ;;
    *)
      server_403
    ;;
    esac
  ;;
  *)
    serve_505 "$PROTO"
  ;;
  esac
else
############################ Daemon Start ############################
  log "INFO" "Starting server on $LISTENIP at $DOCROOT"
  if [[ "$DBUG" == "1" ]]; then
    socat -T 30 -d -d -d -d TCP-L:$LISTENIP,reuseaddr,fork SYSTEM:"$0 \"docroot=$DOCROOT\" logfile=\"$LOGFILE\"  \"ipaddr=\$SOCAT_PEERADDR\""
  else
    socat -T 30 TCP-L:$LISTENIP,reuseaddr,fork SYSTEM:"$0 \"docroot=$DOCROOT\" logfile=\"$LOGFILE\"  \"ipaddr=\$SOCAT_PEERADDR\""
  fi
  log "INFO" "Stopping server on $LISTENIP at $DOCROOT"
fi
