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
use threads;
use utf8;
use warnings;

use App::Feedmailer;
use Getopt::Std;
use XML::Feed;

$Getopt::Std::STANDARD_HELP_VERSION = 1;

my $VERSION = $App::Feedmailer::VERSION;

sub VERSION_MESSAGE {
    my ($fh) = @_;
    printf $fh "listfeeds (%s)\n", $App::Feedmailer::PACKAGE_STRING;
}

sub HELP_MESSAGE {
    my ($fh) = @_;
    print $fh "No help message available yet.\n";
}

our $count_of_feeds = 0;
our @double : shared;
our %opts;

getopts( "ds", \%opts )
  || die $!;

sub _print_feed {
    my ( $uri, $feed ) = @_;
    my $output;
    if ( $opts{s} ) {
        $uri = App::Feedmailer::force_secure_scheme($uri);
    }
    if ( $opts{d} ) {
        $output = sprintf "%s\t%s\t%d\t%s", $uri, $feed->format,
          scalar( $feed->entries ),
          App::Feedmailer::get_string( $feed->language );
    }
    else {
        $output = sprintf "%s", $uri;
    }
    return App::Feedmailer::to_utf8($output);
}

sub handler_start {
    my ($uri) = @_;
    my @output;

    my @feeds = App::Feedmailer::find_feeds( $uri, $opts{s} );

    if ( !scalar(@feeds) ) {
        warn "W: No feeds found so try given URI itself: ", $uri, "\n";
        push @feeds, $uri;
    }

    for (@feeds) {
        my ( $feed, $err ) = App::Feedmailer::get_feed( $_, undef, $opts{s} );
        next if ($err);

        eval { push @output, _print_feed( $_, $feed ); };
        $@ && warn "E: $_: $@";
    }

    return @output;
}

sub handler_stop {
    for (@_) {
        next if ( App::Feedmailer::is_double( $_, \@double ) );
        print "$_\n";
        $count_of_feeds++;
    }
}

for ( ( scalar(@ARGV) ) ? @ARGV : <STDIN> ) {
    chomp;
    threads->create( { "context" => "list" }, \&handler_start, $_ );
    App::Feedmailer::loop_threads( \&handler_stop );
}
App::Feedmailer::loop_last_threads( \&handler_stop );

warn "I: Found $count_of_feeds feeds\n";
exit( !$count_of_feeds );

=pod

=encoding utf8

=head1 NAME

listfeeds - lists feeds of a website

=head1 SYNOPSIS

B<listfeeds> [OPTION] <URI…>

B<listfeeds> <URI…> | B<listentries>

B<listfeeds> <URI…> | B<mergefeeds>

=head1 DESCRIPTION

Lists feeds of an URI.

=head1 OPTIONS

=over

=item --version

=item --help

=item -d

Gibt auch Details zum Feed aus, wie z.B. das Fromat.

=back

=head1 EXAMPLES

=over

=item Newsfeed Format bestimmten

Um nur ein spezielles Format zu bekommen, kann folgender Filter hier Atom
vor RSS ausgeben:

	listfeed -d <URI…> | justonefeedformat | listentries

=back

=head1 SEE ALSO

L<listentries(1p)>, L<mergefeeds(1p)>

=cut

