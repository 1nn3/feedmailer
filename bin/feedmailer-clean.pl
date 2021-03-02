#!/usr/bin/perl
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

use diagnostics;
use strict;
use warnings;

use App::Feedmailer;
use Data::Dumper;
use Getopt::Std;
use Proc::PID::File;

$Getopt::Std::STANDARD_HELP_VERSION = 1;

sub VERSION_MESSAGE {
    my ($fh) = @_;
    printf $fh "feedmailer-clean (%s)\n", $App::Feedmailer::PACKAGE_STRING;
}

sub HELP_MESSAGE {
    my ($fh) = @_;
    print $fh "No help message avalibale yet.\n";
}

# Global variables
our %opts;     # command-line options
our $cache;    # already known articles
our $cfg;      # configuration

my $dir = App::Feedmailer::get_file(".");
if ( Proc::PID::File->running( dir => $dir ) ) {
    die "W: ${App::Feedmailer::NAME} is already running!\n";
}

$App::Feedmailer::cfg = App::Feedmailer::load_config();
$cache                = App::Feedmailer::load_cache();

for my $key ( keys %{$cache} ) {

    my $is_in_cfg = 0;

    for ( keys %{$App::Feedmailer::cfg} ) {
        if ( $_ eq $key ) {
            $is_in_cfg = 1;
            last;
        }
    }

    delete( $cache->{$key} ) if ( !$is_in_cfg );
}

App::Feedmailer::save_cache($cache);

=pod

=encoding utf8

=head1 NAME

feedmailer-clean - cleans the cache.json file

=head1 SYNOPSIS

B<feedmailer-clean>

=head1 OPTIONS

=head2 General options

=over

=item --version

=item --help

=back

=head1 SEE ALSO

L<feedmailer(1p)>

=cut

