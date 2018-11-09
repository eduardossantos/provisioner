#!/bin/bash
STEP=0

bump_step(){
  STEP=$(($STEP+1))
  log "${BLU}[INFO]    ($STEP) $1${NC}"
}

log()       { echo -e "${BWHT}["$(date "+%Y%m%d${NC}T${BWHT}%H%M%S")"]${NC} $*"; }
#| tee -a "$LOG_FILE" >&2 ;
separator() { SEP=$(printf '%*s' 105 | tr ' ' '#') && log "${GRN}[INFO]    $SEP${NC}"; }
info()      { log "${GRN}[INFO]    $1${NC}"; }
warning()   { log "${YEL}[WARN]    $1${NC}"; }
error()     { log "${RED}[ERROR]   $1${NC}"; }
fatal()     { log "${MAG}[FATAL]   $1${NC}"; exit 1 ; }
debug()     { if [ "${DEBUG}" == "true" ]; then log "${CYN}[DEBUG]   :: ${FUNCNAME[1]} :: $1 ${NC}"; fi }

json_escape () {
    printf '%s' $1 | python -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

multi_debug() {
  if [ "${DEBUG}" == "true" ]; then
    IFS=$'\n'
    for line in $1
    do
      log "${CYN}[DEBUG]   :: ${FUNCNAME[1]} :: $line${NC}"
    done
  fi
}

multi_info() {
  IFS=$'\n'
  for line in $1
  do
    log "${GRN}[INFO]    :: $line${NC}"
  done
}

is_no_colors(){
    debug
    [ ! -z "${NO_COLORS}" ] && [ "$NO_COLORS" == "true" ]
}

set_colors(){
  debug
  export RED="\033[0;31m" BLU="\033[0;34m" GRN="\033[0;32m" YEL="\033[33;m"
  export CYN="\033[0;36m" MAG="\033[35m" BWHT="\033[1m" NC="\033[0m"
  debug "Colors ON"
}

unset_colors(){
  debug
  export RED='' BLU='' YEL='' CYN='' GRN='' MAG=''
  export NC='' BWHT=''
}
