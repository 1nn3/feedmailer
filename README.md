# Feedmailer aka. the lone gunman - A Feed-Aggregator (RSS/Atom to email gateway)
Topics: atom rss feedreader feed-aggregator feed-aggregator-daemon feedmailer

Feed aggregator that queries RSS/Atom feeds and delivers new articles by
email.  Using the Sendmail-Commandline-Interface and optional a Cronjob.

No need for a feedreader; use your email client!

But a 2nd main-feature is the option to run hooks.  With Feedmailer you
can execute any command as a hook for an article.

## Reqirements

The Perl programming language and some CPAN modules see Makefile.PL and
if a modul is not packaged in Debian see below.

## Installation

To install Feedmailer in your home directory just run:

	cpanm .

How to install a CPAN Perl module as a Debian package:

The following builds a package for a Perl CPAN module (Make sure
you have the pkg-perl-tools package installed):

	env DEB_BUILD_OPTIONS="nocheck" cpan2deb <MODUL>

Or use the CPAN shell to install modules into youre home directory:

	perl -MCPAN -e shell
	cpan> notest install <MODUL…>

After installation add the following cronjob:

	@daily feedmailer-cronjob

Or:

	@monthly abos2config
	@daily newspaper-cronjob

## Commands

	feedmailer (1p)         - sends RSS/ATOM feeds as mail or runs hooks
	feedmailer-clean (1p)   - cleans the cache.json file
	feedmailer-cronjob (1p) - schicke Reporter los die Nachrichten holen

## Scripting

Set hook:

	hook = perl -E 'print "%l\n";'

Run Feedmailer:

	feedmailer-cronjob -c ~/.feedmailer/subdir/

This should work with the default Feedmailer AppArmor profile.

## LICENSE AND COPYRIGHT

Feedmailer is free software. See COPYING and
http://www.gnu.org/licenses/gpl.html for more information.

