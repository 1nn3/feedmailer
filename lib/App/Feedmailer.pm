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
# See http://github.com/user/feedmailer

#use v5.12;
use feature 'unicode_strings';
use feature 'say';

use strict;
use threads;
use threads::shared;

use Config::Tiny;
use Data::Dumper;
use DateTime;
use DateTime::Format::Strptime;
use Email::Address;
use Email::Date::Format;
use Encode;
use Encode::Guess;
use Env;
use Fcntl;
use File::Basename;
use File::HomeDir;
use File::Path;
use File::ShareDir;
use File::Spec;
use File::Temp;
use Getopt::Std;
use HTML::HeadParser;
use HTML::Strip;
use HTTP::Cookies;
use HTTP::Response;
use JSON;
use List::Util;
use Locale::Language;
use LWP::Protocol::socks;
use LWP::UserAgent;
use MIME::Charset;
use MIME::Lite;
use MIME::Lite::HTML;
use Path::Tiny;
use POSIX;
use Proc::PID::File;
use Template;
use Text::Trim;
use Text::Wrap;
use Tie::File;
use URI;
use URI::Fetch;
use XML::Feed;
use XML::Feed::Entry;
use XML::LibXML;

#use locale;
use utf8;
binmode( STDIN,  ":encoding(UTF-8)" );
binmode( STDOUT, ":encoding(UTF-8)" );
binmode( STDERR, ":encoding(UTF-8)" );

package App::Feedmailer {

    #    use v5.12;
    use feature 'unicode_strings';
    use feature 'say';

    #    use locale;
    use utf8;
    binmode( STDIN,  ":encoding(UTF-8)" );
    binmode( STDOUT, ":encoding(UTF-8)" );
    binmode( STDERR, ":encoding(UTF-8)" );

    our $BUGREPORT = 'user <user@host>';
    our $NAME      = 'App-Feedmailer';
    our $URL       = 'http://github.com/user/feedmailer';
    our $VERSION   = '1.00';

    our $PACKAGE_STRING = "$NAME $VERSION";

    # ~/.config/perl
    our $CONFIG_DIR = File::HomeDir->my_dist_config( $NAME, { create => 1 } );

    # ~/.local/share/perl
    our $DIST_DIR = File::HomeDir->my_dist_data( $NAME, { create => 1 } );

    # File::ShareDir::dist_dir works only if directory is installed
    # /usr/share/perl
    our $DISTDIR = File::ShareDir::dist_dir($NAME);

    our @dirs = ( $CONFIG_DIR, $DIST_DIR, $DISTDIR );

    our $BLACKLIST_FILE = "blacklist.text";
    our $CACHEFILE      = "cache.json";
    our $CONFIGFILE     = "config.ini";
    our $CONFIG_D       = "config.d";
    our $COOKIE_FILE    = "cookie";
    our $WHITELIST_FILE = "whitelist.text";

    our $tt;
    our $tt_cfg = { INCLUDE_PATH => get_file( "templates", @dirs ), };

    our $cache;    # = load_cache();

    our @whitelist;
    our @blacklist;

    our $cfg;      # = load_config($CONFIGFILE);

    # initializing and configure the template processing system
    $tt = Template->new($tt_cfg)
        || die $Template::ERROR;    # No appropriate encodings found!

    #my ( $cookie_fh, $cookie_fn ) = File::Temp::tempfile();
    our $cookie = {};               # empty and temporary cookie
    $COOKIE_FILE = get_file( $COOKIE_FILE, @dirs );
    $cookie      = HTTP::Cookies->new( file => $COOKIE_FILE, autosave => 1 );

    our $ua = LWP::UserAgent->new();
    $ua->cookie_jar($cookie);
    $ua->env_proxy;
    $ua->timeout( get_cfg_val( "ua_timeout", 180 ) );

    # identify
    $ua->agent($PACKAGE_STRING);
    $ua->from($BUGREPORT);

    if ( get_cfg_val( "use_cookie", 0 ) ) {
        $ua->cookie_jar($cookie);
    }

    sub get_cfg_val {
        my ( $key, $default_value ) = @_;
        return $cfg->{"_"}{$key}
            || $ENV{ uc("APP_FEEDMAILER_$key") }   #$ENV{ uc("${NAME}_$key") }
            || $default_value;
    }

    sub load_config {

        # read the configuration-file
        my ($path) = @_;
        $path //= $CONFIGFILE;

        my $cfg = Config::Tiny->new();
        $cfg = Config::Tiny->read($path) || warn Config::Tiny->errstr;

        # set default values (if undef)
        $cfg->{_}{from} //= $ENV{EMAIL} || $ENV{USER} || $ENV{LOGNAME};
        $cfg->{_}{to}   //= $ENV{EMAIL} || $ENV{USER} || $ENV{LOGNAME};
        $cfg->{_}{download}            //= "inline";
        $cfg->{_}{filter_date}         //= 7;
        $cfg->{_}{filter_lang}         //= "";
        $cfg->{_}{filter_list}         //= 1;
        $cfg->{_}{filter_size}         //= 0;
        $cfg->{_}{force_secure_scheme} //= 1;
        $cfg->{_}{keep_old}            //= 128;
        $cfg->{_}{max_threads}         //= 8;
        $cfg->{_}{cut_to}              //= 96;
        $cfg->{_}{subject}             //= "%E (%f)";
        $cfg->{_}{template}            //= "mail.tt.html";
        $cfg->{_}{ua_from}             //= $App::Feedmailer::BUGREPORT;
        $cfg->{_}{ua_proxy_uri}        //= undef;
        $cfg->{_}{ua_string}           //= $App::Feedmailer::PACKAGE_STRING;
        $cfg->{_}{ua_timeout}          //= 180;
        $cfg->{_}{x_mailer}            //= $App::Feedmailer::NAME;
        return $cfg;
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

        $path //= get_file( $CACHEFILE, @dirs );

        #	warn "Save cache: $path\n";

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
        $@ && warn "$path: $@";

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

        $path //= get_file( $CACHEFILE, @dirs );

        #	warn "Load cache: $path\n";

        my $fh = IO::File->new();
        if ( !$fh->open( $path, "r" ) ) {
            warn "$path: $!";
        }

        return JSON->new->decode( <$fh> || "{}" );
    }

  #** @method public get_feed ()
  # @brief Gets the XML::Feed of an feed URI by using the givin LWP::UserAgent
  #
  # TODO: Write a detailed description of the function.
  # @param $uri URI
  # @param $ua LWP::UserAgent
  # @param $force_secure_scheme boolean
  # @retval XML:Feed or undef
  #*

    sub get_feed {
        my ( $uri, $params ) = @_;
        my $feed;
        eval {
            my $response = download(@_);
            $feed = XML::Feed->parse( \$response->decoded_content )
                || die XML::Feed->errstr;
        };
        $@ && warn "$uri: $@";
        return $feed;
    }

    sub find_feeds {
        my ( $uri, $params ) = @_;    # $uri must be a string!
        $params->{force_secure_scheme} //= 0;
        if ( $params->{force_secure_scheme} ) {
            $uri = force_secure_scheme($uri)->as_string;
        }
        return XML::Feed->find_feeds($uri);
    }

    sub looks_like_number {
        my ($val) = @_;
        return $val =~ m/^[[:digit:]]+$/i;
    }

    sub looks_like_uri {
        my ($val) = @_;
        return $val
            =~ m/^[[:alnum:]]+:\/[[:alnum:]]*\/[[:alnum:]\._~:\/\?#\[\]@!\$\&'\(\)*+,;=% \-]+$/i;
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

    sub ig {
        my ( $string, $args ) = @_;

        $args->{whitelist} //= \@App::Feedmailer::whitelist;
        $args->{blacklist} //= \@App::Feedmailer::blacklist;

        my ( $ig, $re, $list ) = scalar( @{ $args->{whitelist} } ) > 0;

        # whitelist
        for ( @{ $args->{whitelist} } ) {
            if ( $string =~ m/$_/i ) {

                #warn "whitelist: '$string' matched '$_'\n";
                $ig   = 0;
                $re   = $_;
                $list = "whitelist";
                last;
            }
        }

        # blacklist
        for ( @{ $args->{blacklist} } ) {
            if ( $string =~ m/$_/i ) {

                #warn "blacklist: '$string' matched '$_'\n";
                $ig   = 1;
                $re   = $_;
                $list = "blacklist";
                last;
            }
        }

        if ( get_cfg_val( "invert_ig", 0 ) ) {
            $ig = !$ig;
        }

        #warn "ig is '$ig' for '$string' (in $list: $re)\n";
        return ( $ig, $re, $list );
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

=pod

=over

=item public download($uri, $params)

Downloads an URI with the givin LWP::UserAgent and returns a HTTP::Response

my $http_response = download(
    $uri,
    {
        ua => $ua, # LWP::UserAgent
        force_secure_scheme => $force_secure_scheme, # boolean
    }
);

Return value is an HTTP::Response object or undef on failure.

=back

=cut

    sub download {
        my ( $uri, $params ) = @_;
        $params->{ua}                  //= $ua->clone;
        $params->{force_secure_scheme} //= 0;
        $params->{proxy}               //= undef;
        $params->{ua_timeout}          //= 180;
        $params->{ua_local_address}    //= undef;

        my $http_response = HTTP::Response->new;
        eval {
            if ( $params->{ua_local_address} ) {
                $params->{ua}->local_address( $params->{ua_local_address} );
            }
            if ( $params->{ua_timeout} ) {
                $params->{ua}->timeout( $params->{ua_timeout} );
            }
            if ( $params->{proxy} ) {
                $params->{ua}->proxy( $uri->scheme, $params->{proxy} );
                warn "Using PROXY ", $params->{proxy}, " for ", $uri;
            }
            if ( $params->{force_secure_scheme} ) {
                $uri = force_secure_scheme($uri);
            }
            my $response = URI::Fetch->fetch(
                $uri,
                UserAgent     => $params->{ua},
                ForceResponse => 0,
            ) || die URI::Fetch->errstr;
            $http_response = $response->http_response;
        };
        $@ && warn "$uri: $@";
        return $http_response;
    }

=pod

=over

=item public get_canonical($uri, $http_response)

Return value is the canonical URI or undef on failure.

=back

=cut

    sub get_canonical {
        my ( $uri, $http_response ) = @_;
        $http_response //= download($uri);
        my $canonical;
        eval {
            my $dom = XML::LibXML->load_html(
                string => $http_response->decoded_content(),

                # try to recover parse errors
                recover => 1,

                # turn off the error output
                suppress_errors => 1,
            );
            foreach
                my $node ( $dom->findnodes('//link[@rel="canonical"]/@href') )
            {
                $canonical
                    = get_abs_uri( $uri, URI->new( $node->to_literal() ) );
                if ($canonical) {
                    last;
                }
            }
        };
        $@ && warn "$uri: $@";
        return $canonical;
    }

=pod

=over

=item public get_abs_uri($base, $rel)

Return value is an URI object or undef on failure.

=back

=cut

    sub get_abs_uri {
        my ( $base, $rel ) = @_;
        return
               URI->new_abs( $rel, URI->new($base) )
            || $rel
            || undef;
    }

=pod

=over

=item force_secure_scheme($uri)

Set the scheme to the secure version e.g. HTTPS instead of HTTP.

Return value is an URI object.

=back

=cut

    sub force_secure_scheme {
        my ($uri) = @_;
        if ( $uri->scheme eq "ftp" ) {
            $uri->scheme("ftps");
            warn "Using secure scheme ", $uri->scheme, " for ", $uri;
        }
        if ( $uri->scheme eq "http" ) {
            $uri->scheme("https");
            warn "Using secure scheme ", $uri->scheme, " for ", $uri;
        }

        return $uri;
    }

=pod

=over

=item clean_up($s)
    
=cut

    sub clean_up {
        my ($s) = @_;
        if ($s) {

            #$s = to_utf8( to_bin($s) ); # TODO
            #$s = to_utf8( $s ); # TODO
            $s = to_bin($s);    # TODO

            $s = HTML::Strip->new()->parse( $s || "" );    # TODO/FIX
            $s = Text::Trim::ltrim($s);
            $s = Text::Trim::rtrim($s);
            $s =~ s/[[:space:]]+/ /g;
            $s =~ s/[^[:print:]]+//g;
        }
        return $s;
    }

=pod

=item to_utf8

=cut

    sub to_utf8 {
        my ( $data, $encoder ) = @_;
        $encoder //= 'utf8';
        eval {
            #$data = Encode::encode( $encoder, $data );
            utf8::encode($data);
            my $num_octets = utf8::upgrade($data);

        };
        $@ && warn "$@";
        return $data;
    }

=pod

=item to_bin

=cut

    sub to_bin {
        my ( $data, $decoder ) = @_;
        $decoder //= 'Guess';
        eval {
            #$data = Encode::decode( $decoder, $data );
            utf8::decode($data);
            utf8::downgrade($data);
        };
        $@ && warn "$@";    # No appropriate encodings found!
        return $data;
    }

    sub list_config_d {
        my ($dir) = Path::Tiny::path(@_);
        my @ret;
        my $iter = $dir->iterator;
        while ( my $file = $iter->() ) {
            if ( $file !~ /\.ini$/ ) {

                # exclude non-INI files
                next;
            }
            if ( $file->is_dir() ) {
                push @ret, list_config_d($file);
                next;
            }
            push @ret, $file;
        }
        return @ret;
    }

=pod

=over

=item loop_threads ($handler_sub, $params)

Threads durchlaufen.

@param \&stop_handler Funktionsreferenze,
@param \%params

	sub stop_handler {;}
	loop_threads(\&stop_handler, {
	    # max_threads maximale Anzahl Threads/Slots
	    max_threads => 8,
	    # Zeit zum abarbeiten von Threads, damit "Slots" frei werden
	    sleep => 3,
	});

No return va=backlue.

=back

=cut

    sub loop_threads {

        my ( $handler_sub, $params ) = @_;

        # max_threads maximale Anzahl Threads/Slots
        $params->{max_threads} //= 8;

        # Zeit zum abarbeiten von Threads, damit "Slots" frei werden
        $params->{sleep} //= 3;

        do {

            for (
                ( $params->{max_threads} )
                ? threads->list(threads::joinable)
                : threads->list()
                )
            {
                &{$handler_sub}( $_->join );
            }

            # Keine "Slots" frei; D.h. warten bis Threads abgearbeitet wurden
            # und nochmal loop_threads durchlaufen

        } while ( $params->{max_threads}
            && threads->list >= $params->{max_threads}
            && sleep $params->{sleep} );

    }

=pod

=over

=item loop_last_threads ($handler_sub)

Restliche Threads durchlaufen.

@param \&stop_handler Funktionsreferenze,

No return value.

=back

=cut

    sub loop_last_threads {
        my ($handler_sub) = @_;
        loop_threads( $handler_sub, { max_threads => defined } );
    }

=pod

=over

=item listsplit ($portions, @array)

Teilt eine Liste in N gleiche Portionen auf.

Beachte: Bleibt ein Rest, sind es N+1 Portionen. Ist $portions >
scalar(@array), sind es nur scalar(@array) Portionen.

$portions Anzahl Portionen,
@list Die aufzuteilende Liste

Return Value @list portions as array of arrays

=back

=cut

    sub listsplit {
        my ( $portions, @array ) = @_;

        my @aoa = ();    # array of arrays

        if ( $portions > scalar(@array) ) {
            $portions = scalar(@array);
        }

        if ( $portions <= 0 ) {
            return @aoa;
        }

        my $portion_length = POSIX::floor( scalar(@array) / $portions );

        if ( $portion_length <= 0 ) {
            return @aoa;
        }

        for ( my $i = 0; $i < $portions; $i++ ) {
            push @aoa, [ splice( @array, 0, $portion_length ) ];
        }

        # rest if any
        my $rest = scalar(@array) % $portions;
        if ($rest) {
            push @aoa, [ splice( @array, 0, $rest ) ];
        }

        return @aoa;
    }

=pod

=over

=item get_file($rel_filepath, @directorys)

=back

=cut

    sub get_file {
        my ( $rel_filepath, @directorys ) = @_;

        if ( !scalar @directorys ) {
            @directorys = ( '.', @dirs );
        }

        for (@directorys) {
            File::Path::make_path($_);
            my $abs_filepath = File::Spec->catfile( $_, $rel_filepath );
            return $abs_filepath if ( -r $abs_filepath );
        }

        my $abs_filepath
            = File::Spec->catfile( get_file( '.', @directorys ),
            $rel_filepath );
        File::Path::make_path( File::Basename::dirname($abs_filepath) );
        return $abs_filepath;
    }

=pod

=over

=item file2list($list_ref, $file, $params)

Use Tie::File to load a file linewise into a list.
Directory will be created automaticly.

$list_ref Ref. to list,
$path Path to file,
$param Hash ref. { mode => mode for Tie::File }

	use Fcntl;
	file2list( \@list, "path/to/file", { mode => Fcntl::O_RDWR | Fcntl::O_CREAT } ); # default
	file2list( \@list, "path/to/file", { mode => Fcntl::O_RDONLY } );

Return value is the one from tie; see Tie::File.

=back

=cut

    sub file2list {
        my ( $list_ref, $file, $params ) = @_;
        $params->{mode} //= Fcntl::O_RDWR | Fcntl::O_CREAT;

        if ( ( Fcntl::O_CREAT & $params->{mode} ) == $params->{mode} ) {
            mkdir File::Basename::dirname($file);
        }

        #warn "Loading file: ", $file;fwarn

        return tie @{$list_ref}, 'Tie::File', $file,
            mode       => $params->{mode},
            discipline => ':encoding(UTF-8)';
    }

    sub print_error {
        my $format = shift;
        warn sprintf( "$format\n", @_ );
    }

    sub print_warning {
        my $format = shift;
        warn sprintf( "$format\n", @_ );
    }

    sub print_info {
        my $format = shift;
        warn sprintf( "$format\n", @_ );
    }

    sub load_args {
        my ( $file, $argv_ref ) = @_;

        if ( $file && $file ne '-' ) {
            open( my $fh, '<', $file )
                || die $!, ": ", $file;
            @{$argv_ref} = <$fh>;
        }
        elsif ( $file eq '-' || !@{$argv_ref} ) {
            @{$argv_ref} = <STDIN>;
        }
        chomp( @{$argv_ref} );
        return @{$argv_ref};
    }

    sub load_input_file {
        my ($file) = @_;
        if ( $file && $file ne '-' ) {
            open( my $fh, '<', $file )
                || die $!, ": ", $file;
            return $fh;
        }
    }

    1;

};

