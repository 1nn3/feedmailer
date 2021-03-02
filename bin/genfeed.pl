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

use utf8;
use strict;
use locale;

use App::Feedmailer;
use DateTime;
use DateTime::Format::Strptime;
use Email::Address;
use Fcntl;
use Getopt::Std;
use HTML::HeadParser;
use Tie::File;
use XML::Feed;

binmode( STDIN,  ":encoding(UTF-8)" );
binmode( STDOUT, ":encoding(UTF-8)" );
binmode( STDERR, ":encoding(UTF-8)" );

$Getopt::Std::STANDARD_HELP_VERSION = 1;

my $VERSION = $App::Feedmailer::VERSION;

sub VERSION_MESSAGE {
    my ($fh) = @_;
    printf $fh "reporter (%s)\n", $App::Feedmailer::PACKAGE_STRING;
}

sub HELP_MESSAGE {
    my ($fh) = @_;
    print $fh "No help message available yet.\n";
}

our $count_of_entrys : shared;
our @double : shared;
our %opts;

getopts( "a:f:F:l:p:st:uw", \%opts )
  || die $!;

$opts{a} //= 'Nobody <nobody@example.net>';
$opts{l} //= "http://example.net";
$opts{t} //= "NEWS - all you can read";

my $whitelist = App::Feedmailer::file2list( $opts{f}, Fcntl::O_RDONLY );
my $blacklist = App::Feedmailer::file2list( $opts{F}, Fcntl::O_RDONLY );

my $parser = DateTime::Format::Strptime->new(
    pattern  => '%Y-%m-%d-%H-%M-%S',
    on_error => sub { warn Dumper $@, return DateTime->now; }
    ,    # 'undef', # 'croak',
);

my @feed_args = ();
my $feed = XML::Feed->new(@feed_args) or die XML::Feed->errstr;
$feed->author( Email::Address->parse( $opts{a} ) );
$feed->id( $feed->link() );
$feed->link( $feed->link() );
$feed->modified( DateTime->now );
$feed->self_link( $opts{l} );
$feed->title( $opts{t} );

sub _get_all_ids {
    my () = @_;
    my @all_ids = ();
    for ( $feed->entries ) {
        push @all_ids, $_->id;
    }
    return @all_ids;
}

sub _add_entry {
    my ( $dt, $title, $uri, $author, $summary, $content ) = @_;

    return if ( App::Feedmailer::is_double( $_, _get_all_ids ) );

    my $entry = XML::Feed::Entry->new();

    $entry->author($author)   if ($author);
    $entry->content($content) if ($content);
    $entry->id($uri);
    $entry->link($uri);
    $entry->modified( $dt || DateTime->now );
    $entry->summary($summary) if ($summary);
    $entry->title($title);

    $feed->add_entry($entry);

    $count_of_entrys++;
}

sub _get_p {
    my ($uri) = @_;
    $ua->proxy( $uri->scheme, $opts{p} ) if ( $opts{p} );    # set proxy
    my $p = HTML::HeadParser->new;
    my ($http_response) =
      App::Feedmailer::download( $uri, $ua, $opts{s} );
    $p->parse( $http_response->decoded_content );
    return ( $http_response, $p );
}

for ( ( scalar(@ARGV) ) ? List::Util::uniq(@ARGV) : <STDIN> ) {
    chomp;

    next if ( App::Feedmailer::is_double( $_, \@double ) );

    my ( $http_response, $p ) = _get_p($_);
    next if ( !$http_response->is_success );

    my $title = $p->header('Title');

    next
      if ( $opts{f}
        && App::Feedmailer::ig( $title, $whitelist, $blacklist ) );    # ignore

    my $author = join ", ",
      Email::Address->parse( $p->header('X-Meta-Author') );

    my $content = $http_response->decoded_content;
    my $dt      = $parser->parse_datetime( $p->header('X-Meta-Date') );
    my $summary = $p->header('X-Meta-Description');

    my $link =
      ( $opts{C} )
      ? App::Feedmailer::get_canonical($_)
      : $_;

    _add_entry( $dt, $title, $link, $author, $summary, $content );

}

print App::Feedmailer::to_utf8( $feed->as_xml );
warn "I: Feed includes $count_of_entrys articles\n";
exit( !$count_of_entrys );

=pod

=encoding utf8

=head1 NAME

genfeed - Generiert einen neuen Feed

=head1 SYNOPSIS

B<lsfeed> -u <websites…> | B<genfeed> -u [-f path/to/file] >feed.xml

=head1 DESCRIPTION

Generiert einen neuen feed aus den angegebenen websites.

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

=item -f <path/to/whitelist>

Filter: Datei mit Pattern, auf die ein Artikel passen muss.

=item -F <path/to/blacklist>

Filter: Datei mit Pattern, auf die ein Artikel nicht passen darf.

=back

=head1 RETURN VALUE

Wenn der Feed KEINE Artikel enthält B<1> (failure).

Wenn der Feed Artikel enthält B<0> (success).

=head1 SEE ALSO

L<lsfeed(1p)>, L<feedmailer(1p)>

=cutuse LWP::Protocol::socks;

