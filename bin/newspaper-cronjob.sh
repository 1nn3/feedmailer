#!/usr/bin/env -S LC_ALL=C flock -n ${HOME}/.newspaper-cronjob.lock sh
# @daily newspaper-cronjob
# Schicke Reporter los die Nachrichten zu holen und Breite zur Zeitung auf

set -e

#tmp="`mktemp`"
#trap "rm -f -- '$tmp'" 0 1 2 3 15

#nm-online -x -q

mkdir -p $HOME/public_html

_reporter () {
	while read REPLY; do
		cd ~/.App-Feedmailer/reporter/$REPLY
		reporter ~/.App-Feedmailer/reporter/$REPLY \
			>$HOME/public_html/$REPLY.xml \
			2>/dev/null \
			|| true
	done
}

cd ~/.App-Feedmailer/reporter
export all_proxy=
export http_proxy=
export https_proxy=
_reporter <<!
debian
news
podcasts
wissen
!

date +"Die Nachrichten für %A den %d. %B %Y!"
cd ~/.App-Feedmailer/newspaper
USER="${USER:-$LOGNAME}"
export all_proxy=
export http_proxy=
export https_proxy=
newspaper <<!
http://localhost/~$USER/news.xml
http://localhost/~$USER/podcasts.xml
http://localhost/~$USER/wissen.xml
!

