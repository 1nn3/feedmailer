#!/usr/bin/env perl
# list Firefox bookmarks

use strict;

use JSON;

sub ls {
    my ($json) = @_;

    if ( $json->{type} eq "text/x-moz-place" ) {
        printf( "%s\n", $json->{uri} );
    }

    for ( @{ $json->{children} } ) {
        ls($_);
    }
}

for (@ARGV) {
    my $fh = IO::File->new();
    $fh->open( $_, "r" ) || die "$_: $!";

    ls( JSON->new->decode(<$fh>) );
}

=pod

=encoding utf8

=head1 NAME

listbookmarks - list Firefox bookmarks

=head1 SYNOPSIS

B<listbookmarks> -- <path/to/bookmarks.json…> | B<listfeeds>

=head1 DESCRIPTION

Listet alle URLs eines Firefox Bookmark-Backups auf.

=head1 OPTIONS

=over

=item --version

=item --help

=back

=cut

