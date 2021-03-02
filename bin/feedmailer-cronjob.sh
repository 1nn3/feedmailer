#!/usr/bin/env -S LC_ALL=C chronic flock -n ${HOME}/.feedmailer-cronjob.lock sh
# @daily feedmailer-cronjob

set -e

#tmp="`mktemp`"
#trap "rm -f -- '$tmp'" 0 1 2 3 15

#nm-online -x -q

export USER="${LOGNAME:-$USER}"
export EMAIL="$USER"

feedmailer-clean
feedmailer ${@:--n -x 12 -1 %l -F}

