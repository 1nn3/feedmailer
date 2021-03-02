#!/usr/bin/env perl
# Feedmailer
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>
#
# See http://github.com/1nn3/feedmailer

use locale;
use strict;

use App::Feedmailer;
use LWP::Protocol::socks;
use LWP::UserAgent;
use MIME::Lite::HTML;
use URI;
use URI::Fetch;

use Data::Dumper;
use Encode qw(decode encode);
use Getopt::Std;
use List::Util qw(first);

$Getopt::Std::STANDARD_HELP_VERSION = 1;

binmode( STDIN,  ":encoding(UTF-8)" );
binmode( STDERR, ":encoding(UTF-8)" );
binmode( STDOUT, ":encoding(UTF-8)" );

sub VERSION_MESSAGE {
    my ($fh) = @_;
    printf $fh "send-uri (Feedmailer) %s\n", $App::Feedmailer::VERSION;
}

sub HELP_MESSAGE {
    my ($fh) = @_;
    print $fh "No help message available yet.\n";
}

# Global variables
our %opts;    # command-line options

# read the command-line-options
getopts( "t:f:s:u:p:v", \%opts )
  || die "Error on processing of command-line-options";

my $uri = URI->new( $opts{u} )
  || die "No URI given.";

my %param = ();
$param{Subject} = $opts{s} || $uri->as_string;
$param{To}      = $opts{t} || $ENV{EMAIL} || $ENV{USER};
$param{From}    = $opts{f} || $ENV{EMAIL} || $ENV{USER};
$param{Proxy}          = $opts{p};
$param{remove_jscript} = 1;
$param{Debug}          = $opts{v};

MIME::Lite->quiet( $opts{v} );
MIME::Lite->send(
    "sendmail",
    $opts{S} || "/usr/lib/sendmail -t -oi -oem",
    Debug => $opts{v},
);

my $mail = MIME::Lite::HTML->new(%param)->parse( $uri->as_string );

# send mail
$mail->send();

exit !$mail->last_send_successful();    # opposite for exit code

=pod

=encoding utf8

=head1 NAME

send-uri - send URI as e-mail

=head1 SYNOPSIS

B<send-uri> [OPTION]...

=head1 DESCRIPTION

Sends a website as e-mail.

=head1 OPTIONS

=over

=item --version

=item --help

=item -u <URI/URL of webpage>

URI of website to send as e-mail.

=item -s <subject>

Subject of the e-mail.

The default value is the URI as string.

=item -t <to>

To: Recipients.

The default for I<-t> is in that order: Environment variables
I<EMAIL> or as fallback I<USER>.

=item -f <from>

From: Envelope Sender.

The default for I<-f> is same as for the option I<-t>.

=item -v

Verbose: Print more information about progress.

=item -S <alt. sendmail command>

Sendmail: Alt. sendmail command. E.g:
 ssh [user@]hostname -c sendmail

See also: L<sendmail(8)>

=back

=head1 SEE ALSO

L<feedmailer(1p)>

=cut

