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

use strict;
use utf8;
use threads;
use locale;

use App::Feedmailer;
use Data::Dumper;
use Encode;
use Env;
use Getopt::Std;
use List::Util;
use Text::Trim;
use Text::Wrap;
use URI;
use DateTime;
use Email::Address;
use Email::Date::Format;
use XML::Feed;
use HTML::HeadParser;
use URI;

$Getopt::Std::STANDARD_HELP_VERSION = 1;

binmode( STDERR, ":encoding(UTF-8)" );
binmode( STDIN,  ":encoding(UTF-8)" );
binmode( STDOUT, ":encoding(UTF-8)" );

sub VERSION_MESSAGE {
    my ($fh) = @_;
    printf $fh "listentrys (%s)\n", $App::Feedmailer::PACKAGE_STRING;
}

sub HELP_MESSAGE {
    my ($fh) = @_;
    print $fh "No help message available yet.\n";
}

our %opts;
our $strftime = '%Y-%m-%d %T';
our @double : shared;
our $count_of_entries = 0;

getopts( "xs", \%opts )
  || die $!;

sub _print_entry {
    my ( $entry, $feed ) = @_;

    my $entry_link = $entry->link;
    if ( $opts{s} ) {
        $entry_link = App::Feedmailer::force_secure_scheme($entry_link);
    }

    my $date = App::Feedmailer::get_entry_date( $entry, $feed );
    ( my $title = $entry->title ) =~ s/\s+/ /g;
    Text::Trim::trim($title);

    my $author = App::Feedmailer::get_entry_author( $entry, $feed );

    #my $date = Email::Date::Format::email_date( $date->epoch );
    my $output = sprintf "%s\t%s\t%s\t%s",
      $date->strftime($strftime), $title,
      $entry_link, $author;

    if ( !$opts{x} ) {
        return App::Feedmailer::to_utf8($output);
    }
    my $summary;

    my ( $http_response, $err ) =
      App::Feedmailer::download( $entry_link, undef, $opts{s} );

    my $type = "text/html; charset=utf-8";
    my $data = $http_response->error_as_HTML;

    if ( $http_response->is_success ) {
        $type = $http_response->header("Content-Type");
        $data = $http_response->decoded_content;
    }

    my $p = HTML::HeadParser->new;
    $p->parse($data);

    ( $summary = $p->header('x-meta-description') ) =~ s/\s+/ /g;

    return App::Feedmailer::to_utf8("$output\t$summary");
}

sub handler_start {
    my ($uri) = @_;
    my @output;

    my ( $feed, $err ) = App::Feedmailer::get_feed( $uri, undef, $opts{s} );
    return if ($err);

    for ( $feed->entries ) {
        eval { push @output, _print_entry( $_, $feed ); };
        $@ && warn "E: $_: $@";
    }

    return @output;
}

sub handler_stop {
    for (@_) {
        next if ( App::Feedmailer::is_double( $_, \@double ) );
        print "$_\n";
        $count_of_entries++;
    }
}

for ( ( scalar(@ARGV) ) ? @ARGV : <STDIN> ) {
    chomp;
    threads->create( { "context" => "list" }, \&handler_start, $_ );
    App::Feedmailer::loop_threads( \&handler_stop );
}
App::Feedmailer::loop_last_threads( \&handler_stop );

warn "I: Found $count_of_entries entries\n";
exit( !$count_of_entries );

=pod

=encoding utf8

=head1 NAME

listentries - lists entries of a newsfeed

=head1 SYNOPSIS

B<listentries> [OPTION] <URI…>

B<listfeeds> [OPTION] <URI…> | B<listentries> [OPTION]

=head1 DESCRIPTION

Lists entries of an URI.

=head1 OPTIONS

=over

=item --version

=item --help

=item -x

Artikel werden ausführlicher u.a. mit Summary usw. ausgegeben.

=back

=head1 SEE ALSO

L<listfeeds(1p)>

=cut

