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
use threads::shared;
use utf8;

use App::Feedmailer;
use Fcntl;
use Getopt::Std;
use List::Util;
use XML::Feed;

binmode( STDIN,  ":encoding(UTF-8)" );
binmode( STDOUT, ":encoding(UTF-8)" );
binmode( STDERR, ":encoding(UTF-8)" );

$Getopt::Std::STANDARD_HELP_VERSION = 1;

my $VERSION = $App::Feedmailer::VERSION;

sub VERSION_MESSAGE {
    my ($fh) = @_;
    printf $fh "mergefeeds (%s)\n", $App::Feedmailer::PACKAGE_STRING;
}

sub HELP_MESSAGE {
    my ($fh) = @_;
    print $fh "No help message available yet.\n";
}

our $count_of_entrys : shared;
our @double : shared;
our %opts;

getopts( "1:a:CF:f:l:st:", \%opts )
  || die $!;

$opts{1} //= '%l';
$opts{a} //= 'nobody <nobody@example.net>';
$opts{l} //= "http://www.example.net";
$opts{t} //= "News";
$opts{f} //= "./whitelist.txt";
$opts{F} //= "./blacklist.txt";

my $whitelist = App::Feedmailer::file2list( $opts{f}, Fcntl::O_RDONLY );
my $blacklist = App::Feedmailer::file2list( $opts{F}, Fcntl::O_RDONLY );

my @feed_args = ();
my $feed      = XML::Feed->new(@feed_args) or die XML::Feed->errstr;
$feed->author( Email::Address->parse( $opts{a} ) );
$feed->id( $feed->link() );
$feed->link( $feed->link() );
$feed->modified( DateTime->now );
$feed->self_link( $opts{l} );
$feed->title( $opts{t} );

sub _get_new_entrie {
    my ($entrie) = @_;
    my $link =
      ( $opts{C} )
      ? App::Feedmailer::get_canonical( $entrie->link, $opts{s} )
      : $entrie->link;
    return {
        content  => $entrie->content,
        link     => $link,
        modified => App::Feedmailer::get_entry_date( $entrie, $feed ),
        author   => App::Feedmailer::get_entry_author( $entrie, $feed ),
        replace  => {
            '%' => '%',
            'e' => $entrie->title,
            'l' => $entrie->link,
        },
        summary => $entrie->summary,
        title   => $entrie->title,
    };
}

sub handler_start {
    my ($uri) = @_;
    my @entrie_list;

    for ( App::Feedmailer::find_feeds( $uri, $opts{s} ) ) {

        my ($feed) = App::Feedmailer::get_feed( $_, undef, $opts{s} );

        for ( $feed->entries ) {
            eval { push( @entrie_list, _get_new_entrie($_) ); };
            $@ && warn "E: $_: $@";

        }
    }
    return ( \@entrie_list );
}

sub handler_stop {
    my ($entrie_list) = @_;
    for ( @{$entrie_list} ) {

        if ( App::Feedmailer::ig( $_->{title}, $whitelist, $blacklist ) ) {

            #warn "I: Ignore: ", $_->{title}, "\n";
            next;
        }

        ( my $id = $opts{1} ) =~ s/\%(\%|\w+)/$_->{replace}{$1}/ge;

        if ( App::Feedmailer::is_double( $id, \@double ) ) {

            #warn "I: Is double: ", $_->{title}, "\n";
            next;
        }

        my $a = XML::Feed::Entry->new();
        $a->author( $_->{author} );
        $a->content( $_->{content} );
        $a->id( $_->{link} );
        $a->issued( $_->{modified} );
        $a->link( $_->{link} );
        $a->modified( $_->{modified} );
        $a->summary( $_->{summary} );
        $a->title( $_->{title} );

        $feed->add_entry($a);
    }
}

for ( ( scalar(@ARGV) ) ? @ARGV : <STDIN> ) {
    chomp;
    threads->create( { "context" => "list" }, \&handler_start, $_ );
    App::Feedmailer::loop_threads( \&handler_stop );
}
App::Feedmailer::loop_last_threads( \&handler_stop );

print App::Feedmailer::to_utf8( $feed->as_xml );

my $count_of_entrys = scalar( $feed->entries );
warn "I: Feed includes $count_of_entrys articles\n";
exit( !$count_of_entrys );

=pod

=encoding utf8

=head1 NAME

mergefeeds - Erzeut aus mehreren Newsfeed einen neuen

=head1 SYNOPSIS

B<mergefeeds> <options> -- <URI…> >newfeed.xml

B<mergefeeds> <websites…> | B<mergefeeds> <options> >newfeed.xml

=head1 DESCRIPTION

Erzeut aus mehreren Newsfeeds einen neuen.

=head1 OPTIONS

=over

=item --version

=item --help

=item -a <string>

Feed author.

=item -l <URI>

Feed link.

=item -t <string>

Feed title.

=item -C

Use canonical link.

=item -f <path/to/whitelist>

Filter: Datei mit RE Pattern, auf die ein Artikel passen muss.

Standardwert: ./whitelist.txt

=item -F <path/to/blacklist>

Filter: Datei mit RE Pattern, auf die ein Artikel nicht passen darf.

Standardwert: ./blacklist.txt

=back

=head1 RETURN VALUE

Wenn der Feed KEINE Artikel enthält B<1> (failure).

Wenn der Feed Artikel enthält B<0> (success).

=head1 FILES

=over

=item .

Das Aktuelle Arbeitsverzeichnis.

=item ./whitelist.txt

=item ./blacklist.txt

=back

=cut

