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
use Template;
use Text::Wrap;

binmode( STDIN,  ":encoding(UTF-8)" );
binmode( STDOUT, ":encoding(UTF-8)" );
binmode( STDERR, ":encoding(UTF-8)" );

$Getopt::Std::STANDARD_HELP_VERSION = 1;

my $VERSION = $App::Feedmailer::VERSION;

sub VERSION_MESSAGE {
    my ($fh) = @_;
    printf $fh "newspaper (%s)\n", $App::Feedmailer::PACKAGE_STRING;
}

sub HELP_MESSAGE {
    my ($fh) = @_;
    print $fh "No help message available yet.\n";
}

our %opts;
our @double : shared;

our $tt_cfg = { INCLUDE_PATH => App::Feedmailer::get_file("templates"), };
our $tt = Template->new($tt_cfg)
  || die $Template::ERROR;

getopts( "1:Cc:h:x:z", \%opts )
  || die $!;

$opts{1} //= '%e';
$opts{c} //= "./newspaper.cache.txt";
$opts{h} //= "./newspaper.headlines.txt";
$opts{k} //= 256;
$opts{x} //= "newspaper.tt.txt";

my $count_of_entrys = 0;

my $headlines;
my $has_headlines = -e $opts{h};
if ($has_headlines) {
    $headlines = App::Feedmailer::file2list( $opts{h}, Fcntl::O_RDONLY );
}
else {
    # show all news
    push @{$headlines}, ".*";
}

my $cache;
my $has_cache = -e $opts{c};
if ($has_cache) {
    $cache =
      App::Feedmailer::file2list( $opts{c}, Fcntl::O_RDWR | Fcntl::O_CREAT );
}

my %statistic;

sub get_matchlist {
    my ( $string, @regexlist ) = @_;
    my @matchlist;
    for (@regexlist) {
        if ( $string =~ m/$_/i ) {
            push @matchlist, $_;
        }
    }
    return @matchlist;
}

sub handler_start {
    my ($uri)   = @_;
    my @entries = ();
    my ($feed)  = App::Feedmailer::get_feed($uri);
    for ( $feed->entries ) {
        push(
            @entries,
            {
                link    => $_->link,
                replace => {
                    '%' => '%',
                    'e' => $_->title,
                    'l' => $_->link,
                },
                title => $_->title,
            }
        );
    }
    return ( \@entries );
}

sub handler_stop {
    my ($entries) = @_;
    for ( @{$entries} ) {

        ( my $id = $opts{1} ) =~ s/\%(\%|\w+)/$_->{replace}{$1}/ge;

        next if ( App::Feedmailer::is_double( $id, \@double ) );

        for my $match ( get_matchlist( $_->{title}, @{$headlines} ) ) {
            $statistic{$match}{count}++;
            push @{ $statistic{$match}{entries} }, $_;
        }

    }
}

for ( ( scalar(@ARGV) ) ? List::Util::uniq(@ARGV) : <STDIN> ) {
    chomp;
    threads->create( { "context" => "list" }, \&handler_start, $_ );
    App::Feedmailer::loop_threads( \&handler_stop );
}

App::Feedmailer::loop_last_threads( \&handler_stop );

for ( @{$headlines} ) {

    next if ( !$opts{z} && !$statistic{$_}{count} );

    print App::Feedmailer::to_utf8("$statistic{$_}{count}	$_\n");

    next if ( !$opts{x} );

    for ( @{ $statistic{$_}{entries} } ) {
        $count_of_entrys++;

        my $title =
          Text::Wrap::wrap( "", "",
            App::Feedmailer::get_string( $_->{title} ) ),

          my $link =
          ( $opts{C} )
          ? App::Feedmailer::get_canonical( $_->{link} )
          : $_->{link};

        next if ( App::Feedmailer::is_double( $link, $cache ) );

        my $tt_data = "";
        my $tt_vars = {
            "title" => $title,
            "link"  => $link,

        };

        my $template = $opts{x};
        $tt->process( $template, $tt_vars, \$tt_data )
          || return $tt->error;
        print App::Feedmailer::to_utf8($tt_data);
    }
}

if ($has_cache) {

    # Nur die letzen $keep links behalten
    @{$cache} =
      List::Util::head( $opts{k} * scalar( @{$headlines} ), @{$cache} );
}

exit( !$count_of_entrys );

=pod

=encoding utf8

=head1 NAME

newspaper - print a statistic of feeds

=head1 SYNOPSIS

B<newspaper> <options> -- <URI…>

B<listfeeds> <URI…> | B<newspaper>

=head1 DESCRIPTION

Prints a statistic of feeds based on the headlines and a regex list.

=head1 OPTIONS

=over

=item --version

=item --help

=item -h <path/to/regex.list>

Filter: Datei mit RE Pattern, auf die ein Artikel passen muss.

Standardwert: ./newspaper.headlines.txt

If no newspaper.headlines.txt then .* is assumed.

=item -c <path/to/cache>

Cache.

Standardwert: ./newspaper.cache.txt

Cache aktiveren:

	touch ./newspaper.cache.txt

Cache deaktiveren:

	newspaper -c /dev/null

Or:
	
	rm ./newspaper.cache.txt

=item -C

Canonical link.
	
=item -x <template>

Title.

=back

=head1 FILES

=over

=item ./newspaper.headlines.txt

=item ./newspaper.cache.txt

=back

=head1 SEE ALSO

L<listfeeds(1p)>, L<mergefeeds(1p)>

=cut

