#
# Regular cron jobs for the feedmailer package
#

# maintenance
0 4	* * *	root	[ -x /usr/bin/feedmailer_maintenance ] && /usr/bin/feedmailer_maintenance

#25 6	* * *	feedmailer	/usr/bin/feedmailer-cronjob
#52 6	* * 0	feedmailer	/usr/bin/chronic /usr/bin/feedmailer-abos2config

