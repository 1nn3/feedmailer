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

package App::Feedmailer {

    use Config::Tiny;
    use Data::Dumper;
    use DateTime;
    use Email::Address;
    use Encode;
    use Encode::Guess;
    use Env;
    use Fcntl;
    use File::Basename;
    use File::HomeDir;
    use File::Path;
    use File::ShareDir;
    use File::Spec;
    use JSON;
    use List::Util;
    use LWP::Protocol::socks;
    use LWP::UserAgent;
    use MIME::Charset;
    use Text::Trim;
    use Tie::File;
    use URI;
    use URI::Fetch;
    use XML::Feed;
    use XML::LibXML;

    binmode( STDIN,  ":encoding(UTF-8)" );
    binmode( STDOUT, ":encoding(UTF-8)" );
    binmode( STDERR, ":encoding(UTF-8)" );

    our $NAME    = 'App-Feedmailer';
    our $VERSION = '1';

    our $BLACKLIST_FILE = "blacklist";
    our $BUGREPORT      = 'nobody <nobody@example.net>';
    our $CACHEFILE      = get_file("cache.json");
    our $CONFIGFILE     = get_file("config.ini");
    our $PACKAGE_STRING = "$NAME $VERSION";
    our $URL            = 'http://github.com/1nn3/feedmailer';
    our $WHITELIST_FILE = "whitelist";

    our $cfg;

    sub get_cfg_val {
        my ( $val, $default ) = @_;
        return
             $cfg->{"_"}{$val}
          || $ENV{ uc("${NAME}_$val") }
          || $default;
    }

    sub get_file {
        my ($rel_file) = @_;
        my @dirs = (
            File::Spec->catdir( ( File::HomeDir::my_home, ".$NAME" ) ),
            File::HomeDir->my_dist_config( $NAME, { create => 1 } ),
            File::HomeDir->my_dist_data( $NAME, { create => 1 } ),

            # File::ShareDir::dist_dir works only if directory is installed
            File::ShareDir::dist_dir($NAME),
        );

        for (@dirs) {
            File::Path::make_path($_);
            my $abs_file = File::Spec->catfile( ($_), $rel_file );
            return $abs_file if ( -r $abs_file );
        }

        my $abs_file = File::Spec->catfile( ( get_file("./") ), $rel_file );
        File::Path::make_path( File::Basename::dirname($abs_file) );

        # Das Verz. exsitiert nun und somit kann $rel_file ggf. angelegt werden
        return ($abs_file);
    }

    sub load_config {

        # read the configuration-file
        my ($path) = @_;
        $path //= $CONFIGFILE;
        return Config::Tiny->read($path) || die Config::Tiny->errstr;
    }

    #** @method private save_cache ()
    # @brief Saves the cache; wich stored a list of all already known articles
    #
    # TODO: Write a detailed description of the function.
    # @param @cache List of all already known articles
    # @retval undef Cache/List could not be saved
    #*
    sub save_cache {
        my ( $cache, $path ) = @_;

        $path //= $CACHEFILE;

        #	warn "I: Save cache: $path\n";

        my $fh = IO::File->new();
        if ( !$cache || !$fh->open( $path, "w" ) ) {
            die "$path: $!";
        }

        my $json_text = JSON->new->allow_nonref(1)->encode($cache);

        eval {
            flock( $fh, Fcntl::LOCK_EX );
            print $fh $json_text;
            flock( $fh, Fcntl::LOCK_UN );
        };
        $@ && warn "E: $path: $@";

    }

    #** @method private load_cache ()
    # @brief Loads the cache; a list of all already known articles
    #
    # TODO: Write a detailed description of the function.
    # @retval @cache List of all already known articles
    # @retval undef Cache/List could not be loaded
    #*
    sub load_cache {
        my ($path) = @_;

        $path //= $CACHEFILE;

        #	warn "I: Load cache: $path\n";

        my $fh = IO::File->new();
        if ( !$fh->open( $path, "r" ) ) {
            warn "$path: $!";
        }

        return JSON->new->decode( <$fh> || "{}" );
    }

    sub force_secure_scheme {
        my ($uri) = @_;
        $uri = URI->new($uri);
        $uri->scheme("ftps")  if ( $uri->scheme eq "ftp" );
        $uri->scheme("https") if ( $uri->scheme eq "http" );
        return $uri;
    }

    sub to_utf8 {
        my ( $data, $decoder ) = @_;

        if ( $data && !Encode::is_utf8($data) ) {
            $data = Encode::decode( ($decoder) ? $decoder : 'Guess', $data );
        }

        return $data;
    }

    sub to_bin {
        my ( $data, $encoder ) = @_;

        if ( $data && Encode::is_utf8($data) ) {
            $data = Encode::encode( ($encoder) ? $encoder : 'utf-8', $data );
        }

        return $data;
    }

#** @method public download ()
# @brief Downloads an URI with the givin LWP::UserAgent and returns a HTTP::Response
#
# TODO: Write a detailed description of the function.
# @param $uri URI
# @param $ua LWP::UserAgent
# @param $force_secure_scheme Boolean
# @retval (HTTP::Response, $@)
#*
    sub download {
        my ( $uri, $ua, $force_secure_scheme ) = @_;

        if ( !$ua ) {
            $ua = LWP::UserAgent->new();
            $ua->agent($PACKAGE_STRING);
            $ua->from($BUGREPORT);
            $ua->timeout( get_cfg_val( "ua_timeout", 180 ) );
        }

        my $uri_fetch_response = URI::Fetch::Response->new;
        my $http_response      = HTTP::Response->new;

        eval {
            $uri_fetch_response = URI::Fetch->fetch( $uri, UserAgent => $ua )
              || die URI::Fetch->errstr;
            $http_response = $uri_fetch_response->http_response;
        };
        $@ && warn "E: $uri: $@";

        return ( $http_response, $@ );
    }

    #** @method private get_string ()
    # @brief subsitute multiple spaces from string and trim string
    #
    # TODO: Write a detailed description of the function.
    # @param $string String
    # @retval String
    #*

    sub get_string {
        my ($str) = @_;
        $str //= "";
        $str =~ s/\s+/ /g;
        $str =~ s/^\s+|\s+$//g;
        return to_utf8( Text::Trim::trim( to_bin($str) ) );
    }

    #** @method public get_feed ()
    # @brief Gets the XML::Feed of an feed URI by using the givin LWP::UserAgent
    #
    # TODO: Write a detailed description of the function.
    # @param $uri URI
    # @param $ua LWP::UserAgent
    # @retval (XML:Feed, $@)
    #*
    sub get_feed {
        my ( $uri, $ua, $force_secure_scheme ) = @_;
        my $feed = XML::Feed->new;
        warn "I: Loading feed: ", $uri, "\n";
        eval {
            my ($http_response) = download( $uri, $ua, $force_secure_scheme );
            if ( $http_response->is_success ) {
                $feed = XML::Feed->parse( \$http_response->decoded_content )
                  || die XML::Feed->errstr;
            }
        };
        $@ && warn "E: $uri: $@";

        return ( $feed, $@ );
    }

    sub find_feeds {
        my ( $uri, $force_secure_scheme ) = @_;
        if ($force_secure_scheme) {
            $uri = App::Feedmailer::force_secure_scheme($uri);
        }
        warn "I: Searching feeds on $uri ...\n";

        return XML::Feed->find_feeds($uri);
    }

    sub looks_like_number {
        my ($val) = @_;
        return $val =~ m/^[[:digit:]]+$/i;
    }

    sub looks_like_uri {
        my ($val) = @_;
        return $val =~
m/^[[:alnum:]]+:\/[[:alnum:]]*\/[[:alnum:]\._~:\/\?#\[\]@!\$\&'\(\)*+,;=% \-]+$/i;
    }

    sub get_entry_date {
        my ( $entry, $feed ) = @_;
        return
             $entry->modified
          || $entry->issued
          || $feed->modified
          || DateTime->now;
    }

    sub get_entry_author {
        my ( $entry, $feed ) = @_;
        my $author = $entry->author || $feed->author;
        return join ", ", Email::Address->parse($author);
    }

    sub loop_threads {
        my ( $handler_sub, $max_threads ) = @_;
        $max_threads //= 8;

        do {

            for (
                ($max_threads)
                ? threads->list(threads::joinable)
                : threads->list()
              )
            {
                &{$handler_sub}( $_->join );
            }

            # Keine "Slots" frei; D.h. warten bis Threads abgearbeitet wurden
            # und nochmal loop_threads durchlaufen

          } while ( $max_threads
            && threads->list >= $max_threads
            && sleep 3 );

    }

    sub loop_last_threads {
        my ($handler_sub) = @_;
        loop_threads( $handler_sub, defined );
    }

    sub ig {
        my ( $string, $whitelist, $blacklist ) = @_;

        my $ig = scalar(@$whitelist) > 0;

        # whitelist
        for ( @{$whitelist} ) {
            if ( $string =~ m/$_/i ) {
                $ig = 0;
                last;
            }
        }

        # blacklist
        for ( @{$blacklist} ) {
            if ( $string =~ m/$_/i ) {
                $ig = 1;
                last;
            }
        }

        return $ig;
    }

    sub is_double {
        my ( $string, $double ) = @_;
        if ( grep { $_ eq $string; } @{$double} ) {
            return 1;
        }
        else {
            push @{$double}, $string;
            return 0;
        }
    }

    #** @method file2list ()
    # @brief Use Tie::File to load a file linewise into a list
    #
    # use Fcntl;
    # my $list_rw = file2list( "path/to/file", Fcntl::O_RDWR | Fcntl::O_CREAT);
    # my $list_ro = file2list( "path/to/file", Fcntl::O_RDONLY);
    #
    # Directory will be created automaticly.
    #
    # @param $path Path to file
    # @param $mode Mode for Tie::File
    # $retval Ref. to list containing the file linewise
    #*
    sub file2list {
        my ( $file, $mode ) = @_;

        mkdir dirname($file);

        my @list;
        tie @list, 'Tie::File', $file, mode => $mode;
        return \@list;
    }

    sub get_canonical {
        my ( $uri, $ua, $force_secure_scheme ) = @_;

        my ($http_response) = download( $uri, $ua, $force_secure_scheme );

        my $dom = XML::LibXML->load_html(
            string          => $http_response->decoded_content(),
            recover         => 1,
            suppress_errors => 1,
        );

        for ( $dom->findnodes('//link[@rel="canonical"]/@href') ) {
            return $_->to_literal();
        }

        return $uri;
    }

    1;

};

