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
use File::Spec;
use Path::Tiny;
use Fcntl;
use Getopt::Std;
use Config::Any;
use File::Basename;

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

sub list_abo_dirs {
    my ($reporter_dir) = @_;
    my @dirs;
    my $dir = Path::Tiny::path($reporter_dir);
    warn "I: Searching for abos is $dir ...\n";
    my $iter = $dir->iterator;
    while ( my $file = $iter->() ) {
        next if !$file->is_dir();
        push @dirs, $file;
    }
    return @dirs;
}

sub list_abo_files {
    my (@dirs) = @_;
    my @files;
    for (@dirs) {
        my $dir = Path::Tiny::path( $_, "abos" );
        warn "I: Searching for abos is $dir ...\n";
        my $iter = $dir->iterator;
        while ( my $file = $iter->() ) {
            next if $file->is_dir();
            next if $file =~ /~$/;
            push @files, $file;
        }
    }
    return @files;
}

our %opts;
getopts( "o:t:", \%opts )
  || die $!;
$opts{o} //= ".";
$opts{t} //= "News"; # File::Basename::basename($_);

for ( ( scalar(@ARGV) ) ? List::Util::uniq(@ARGV) : <STDIN> ) {
    chomp;

    #for ( list_abo_dirs($_) ) {

        chomp;
        my @abos = list_abo_files($_);
        my $config = Config::Any->load_files( { files => \@abos } );
        my @feeds;
        for ( @{$config} ) {
            my ( $filename, $config ) = %{$_};
            for ( keys %{$config} ) {
                push @feeds, qx(listfeeds -s -d \"$_\" | justonefeedformat);
            }
        }

        if ( !Cwd::chdir $_ ) {

            # Fehlgeschlagen
            warn "$!: $_";
            next;
        }

        my $return_value = system( "mergefeeds", "-t", $opts{t}, @feeds);
        if ( $return_value == 0 ) {
            exit 0;
        }
        else {
            warn "Command failed: $return_value";
            exit 1;
        }
    #}
}

=pod

=encoding utf8

=head1 NAME

reporter - Not implemented yet

=head1 SYNOPSIS

B<reporter>

=head1 DESCRIPTION

Not implemented yet.

=head1 OPTIONS

=over

=item --version

=item --help

=back

=head1 SEE ALSO

L<newspaper(1p)>

=cut

