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
# along with this progEntriesram. If not, see <http://www.gnu.org/licenses/>
#
# See http://github.com/1nn3/feedmailer

use locale;
use strict;
use threads;
use threads::shared;
use utf8;
use warnings;

use App::Feedmailer;
use Data::Dumper;
use Encode qw(decode encode);
use Fcntl;
use File::HomeDir;
use File::Spec;
use Getopt::Std;
use List::Util qw(first uniq);
use Locale::Language;
use LWP::Protocol::socks;
use LWP::UserAgent;
use MIME::Lite;
use MIME::Lite::HTML;
use POSIX qw(locale_h);
use Proc::PID::File;
use Template;
use Tie::File;
use URI;
use URI::Fetch;
use XML::Feed;
use XML::Feed::Entry;

$Getopt::Std::STANDARD_HELP_VERSION = 1;

binmode( STDIN,  ":encoding(UTF-8)" );
binmode( STDOUT, ":encoding(UTF-8)" );
binmode( STDERR, ":encoding(UTF-8)" );

# some global variables -- but not the bad one ;-)
our %opts;     # command-line options
our $cache;    # already known articles
our $whitelist;
our $blacklist;
our @doubles : shared;
our $tt;
our $tt_cfg = { INCLUDE_PATH => App::Feedmailer::get_file("templates"), };

package feed {

    use locale;
    use strict;
    use utf8;
    use warnings;

    use Data::Dumper;
    use Encode qw(decode encode);
    use File::Basename;
    use List::Util qw(first);
    use URI;

    fileparse_set_fstype("VMS");    # Unix

    use DateTime;
    use Email::Address;
    use Email::Date::Format qw(email_date);
    use Lingua::Identify qw(:language_identification);
    use Array::Utils qw(:all);
    use HTML::Strip;
    use MIME::Base64;

    use App::Feedmailer;

    binmode( STDIN,  ":encoding(UTF-8)" );
    binmode( STDOUT, ":encoding(UTF-8)" );
    binmode( STDERR, ":encoding(UTF-8)" );

    my $cut_to;
    my $download;
    my $feed;    # XML::Feed object
    my $filter_date;
    my $filter_lang;
    my $filter_list;
    my $filter_size;
    my $force_secure_scheme;
    my $from;
    my $hook;
    my $keep_old;
    my $key;     # scalar containing the key/id for the class-object
    my $subject;
    my $template;
    my $to;
    my $ua;      # LWP::UserAgent object
    my $uri;     # URI object

    my @old_cache;
    my @new_cache;

    sub new ($$) {
        my ( $class, $key, $cache_ref ) = @_;

        my $self = { key => $key, };
        bless $self, $class;

        $download            = $self->_get_cfg_val("download");
        $filter_date         = $self->_get_cfg_val("filter_date");
        $filter_lang         = $self->_get_cfg_val("filter_lang");
        $filter_list         = $self->_get_cfg_val("filter_list");
        $filter_size         = $self->_get_cfg_val("filter_size");
        $force_secure_scheme = $self->_get_cfg_val("force_secure_scheme");
        $from                = $self->_get_cfg_val("from");
        $hook                = $self->_get_cfg_val("hook");
        $keep_old            = $self->_get_cfg_val("keep_old");
        $cut_to              = $self->_get_cfg_val("cut_to");
        $subject             = $self->_get_cfg_val("subject");
        $template            = $self->_get_cfg_val("template");
        $to                  = $self->_get_cfg_val("to");

        @old_cache = @{$cache_ref};
        @new_cache = ();

        $uri = URI->new($key);

        $ua = LWP::UserAgent->new();
        $ua->agent( $self->_get_cfg_val("ua_string") );
        $ua->from( $self->_get_cfg_val("ua_from") );
        $ua->show_progress( $opts{v} );
        $ua->timeout( $self->_get_cfg_val("ua_timeout") );
        $ua->env_proxy;

        if ( $self->_get_cfg_val("ua_proxy_uri") ) {
            $ua->proxy( $uri->scheme, $self->_get_cfg_val("ua_proxy_uri") );
        }

        if ($force_secure_scheme) {
            $uri = App::Feedmailer::force_secure_scheme($uri);
        }

        ($feed) = App::Feedmailer::get_feed( $uri, $ua );

        return $self;
    }

    sub _get_cfg_val ($$) {
        my ( $self, $val, $default ) = @_;
        return $App::Feedmailer::cfg->{ $self->{"key"} }{$val}
          || App::Feedmailer::get_cfg_val( $val, $default );
    }

    sub _get_entry_id ($$) {
        my ( $self, $entry ) = @_;
        return
             URI->new( $entry->link )->as_string
          || $entry->id
          || $entry->title;
    }

    sub _get_entry_lang ($$) {
        my ( $self, $entry ) = @_;
        return langof(
            HTML::Strip->new->parse(
                $entry->content->body || $entry->title || ""
            )
        );
    }

    sub _get_entry_size ($$) {
        my ( $self, $entry ) = @_;
        use bytes;
        return length( $entry->content->body );
    }

    # returns the absolut URI of an entry
    sub _get_entry_uri ($$) {
        my ( $self, $entry ) = @_;
        my $uri_feed =
          URI->new( $feed->link ) || URI->new("http://www.example.net");
        my $uri_entry =
          URI->new( $entry->link ) || URI->new("http://www.example.net");
        my $absolut_uri =
          URI->new( $uri_entry->abs($uri_feed)
              || $uri_entry
              || URI->new("http://www.example.net") );
        return $absolut_uri;
    }

    sub _get_all_ids ($$) {
        my ($self) = @_;
        my @all_ids = ();
        for ( $feed->entries ) {
            push @all_ids, $self->_get_entry_id($_);
        }
        return @all_ids;
    }

    sub _cut_string ($$) {
        my ( $self, $str, $len ) = @_;
        if ( $len && length($str) > $len ) {
            $str = sprintf "%s…", substr( $str, 0, $len );
        }
        return $str;
    }

    sub _get_new_entrys ($$) {
        my ($self) = @_;
        my @new_entrys = ();
        for my $entry ( $feed->entries ) {
            my $id = $self->_get_entry_id($entry);

            next if ( grep { $_ eq $id; } @old_cache );

            my %a;

            $a{author} = App::Feedmailer::get_entry_author( $entry, $feed );
            $a{date}       = App::Feedmailer::get_entry_date( $entry, $feed );
            $a{delta_days} = DateTime->now->delta_days( $a{date} )->delta_days;
            $a{email_date} = email_date( $a{date}->epoch );
            $a{entry}      = $entry;
            $a{id}         = $id;
            $a{lang}       = $self->_get_entry_lang($entry);
            $a{size}       = $self->_get_entry_size($entry);
            $a{uri}        = $self->_get_entry_uri($entry);

            if ($force_secure_scheme) {
                $a->{uri} = App::Feedmailer::force_secure_scheme( $a->{uri} );
            }

            # text substitution

            $a{replace} = {
                '%' => '%',
                'a' => App::Feedmailer::get_string( $a{author} ),
                'B' => basename( $a{uri}->path ),
                'c' => $a{entry}->content->body,
                'C' => App::Feedmailer::get_string( $feed->copyright ),
                'd' => $a{email_date},
                'D' => App::Feedmailer::get_string( $feed->description ),
                'e' => App::Feedmailer::get_string( $a{entry}->title ),
                'E' => $self->_cut_string(
                    App::Feedmailer::get_string( $a{entry}->title ), $cut_to
                ),
                'f' => App::Feedmailer::get_string( $feed->title ),
                'F' => $self->_cut_string(
                    App::Feedmailer::get_string( $feed->title ), $cut_to
                ),

                #                'H' => $a{uri}->host,
                'l' => $a{uri}->as_string,
                'L' => $feed->link,
                'm' => $from,
                'P' => $a{uri}->path,
                'p' => $self->_get_cfg_val("ua_proxy_uri"),
                's' => $a{entry}->summary->body,
                't' => $to,
            };

            $a{tt_vars} = {
                "entry_title" =>
                  App::Feedmailer::get_string( $a{entry}->title ),
                "entry_title_cut" => $self->_cut_string(
                    App::Feedmailer::get_string( $a{entry}->title ), $cut_to
                ),
                "entry_link"         => $a{uri}->as_string,
                "entry_content_body" => $a{entry}->content->body,
                "entry_content_type" => $a{entry}->content->type,
                "feed_title"     => App::Feedmailer::get_string( $feed->title ),
                "feed_title_cut" => $self->_cut_string(
                    App::Feedmailer::get_string( $feed->title ), $cut_to
                ),
                "feed_link" => $feed->link,
                "feed_description" =>
                  App::Feedmailer::get_string( $feed->description ),
                "copyright" => App::Feedmailer::get_string( $feed->copyright ),
                "date"      => $a{email_date},
                "author"    => App::Feedmailer::get_string( $a{author} ),

                "text"     => $a{text},
                "charset"  => $a{charset},
                "encoding" => $a{encoding},

            };

            push @new_entrys, \%a;
        }

        return @new_entrys;
    }

    sub perform ($$) {
        my ($self) = @_;

        my @new_entrys = $self->_get_new_entrys();

        # implementation of the option -x
        if ( defined( $opts{'x'} ) && scalar(@old_cache) > 0 ) {
            my $count_of_new_entrys = scalar(@new_entrys);
            if ( $count_of_new_entrys > $opts{'x'} ) {
                warn
"$uri: The flood-detection attacks ($count_of_new_entrys new)";
                @new_cache = ( $opts{F} ) ? $self->_get_all_ids() : @old_cache;
                return ( \@new_cache );
            }
        }

        # update cache and perform all entrys
        for (@new_entrys) {

            push @new_cache, $_->{id};

            # implementation of the option -u and -U
            # don't act; just update the cache
            next if ( $opts{'U'} || $opts{'u'} );

          # implementation of the option -n
          # don't act older articles from new added feeds; only create the cache
            next if ( scalar(@old_cache) == 0 && $opts{'n'} );

            # don't act out-filtert articles
            next if ( $self->ig_entry($_) );

            # implementation of the option -1
            # don't act already known uris
            if ( my $doubles_replace = $opts{'1'} ) {
                $doubles_replace =~
                  s/\%(\%|\w+)/$_->{replace}{$1}/ge;    # text substitutions
                next if ( grep { $_ eq $doubles_replace; } @doubles );
                push @doubles, $doubles_replace;
            }

            # run hook/send mail
            my $success =
              ($hook) ? $self->run_hook($_) : $self->send_mail($_);

            # when failed remove entry from cache and retry next time
            if ( !$success ) {
                pop @new_cache;
                pop @doubles;
            }
        }

        @new_cache =
          ( $opts{F} )
          ? $self->_get_all_ids()
          : unique( @new_cache, $self->_get_all_ids() );

        # FIXME: Ugly Work-A-Round
        # Füge noch $keep_old IDs aus @old_cache zu @new_cache hinzu
        # Dies soll helfen, bereits gelesene Artikel besser zu erkennen
        # use List::Slice qw( head tail ); # not packaged in Debian
        # push @new_cache, head($keep_old, array_minus(@old_cache, @new_cache));
        push @new_cache, map { $_ // () }    # nur nicht-undef
          ( array_minus( @old_cache, @new_cache ) )[ 0 .. $keep_old ];

        return ( \@new_cache );
    }

    sub ig_entry ($$) {
        my ( $self, $a ) = @_;

        if ($filter_date) {
            return 1 if ( $a->{delta_days} > $filter_date );
        }

        if ($filter_size) {
            return 1 if ( $a->{size} > $filter_size );
        }

        if ($filter_lang) {
            return 1 if ( $a->{lang} !~ m/$filter_lang/i );
        }

        if ($filter_list) {
            return App::Feedmailer::ig( $a->{entry}->title,
                $whitelist, $blacklist );
        }

        return 0;
    }

    #** @method private run_hook ()
    # @brief Run hook-script
    #
    # TODO: Write a detailed description of the function.
    # @retval 0 on failure or 1 on success (opposite of exit code)
    #*
    sub run_hook ($$) {
        my ( $self, $a ) = @_;
        ( my $cmd = $hook ) =~ s/\%(\%|\w+)/$a->{replace}{$1}/ge;
        $a->{hook_return_value} = system($cmd);
        if ( $a->{hook_return_value} == 0 ) {
            return 1;
        }
        else {
            warn "Hook \"$cmd\" failed: ", $a->{hook_return_value};
            return 0;
        }
    }

    sub send_mail ($$) {
        my ( $self, $a ) = @_;

        # define mail-subject
        ( my $s = $subject ) =~ s/\%(\%|\w+)/$a->{replace}{$1}/ge;
        $s = Encode::encode( "MIME-B", $s );

        # define mail body
        my $tt_data = "";
        my $tt_vars = $a->{tt_vars};

        # template processing...
        $tt->process( $template, $tt_vars, \$tt_data )
          || warn $tt->error;

        # create mail
        my $mail = MIME::Lite->new(
            "From"     => $from,
            "To"       => $to,
            "Subject"  => $s,
            "Type"     => "multipart/mixed",
            "Date"     => $a->{email_date},
            "Reply-To" => $a->{author},
        );

        $mail->attach(
            "Type"     => "text/html; charset=utf-8",
            "Data"     => App::Feedmailer::to_bin($tt_data),
            "Encoding" => "base64",
        );

        my $type = $a->{entry}->content->type;
        my $data = $a->{entry}->content->body;

        if ( $type && $data ) {
            my $part = MIME::Lite->new(
                "Type"        => $type,
                "Data"        => App::Feedmailer::to_bin($data),
                "Encoding"    => "base64",
                "Disposition" => "inline",
            );
            $mail->attach($part);
        }

        if ( $download && $a->{uri} ) {

            # download the entry link (as attachment)

            my ($http_response) =
              App::Feedmailer::download( $a->{uri}, $ua );
            if ( $http_response->is_success ) {
                $type = $http_response->header("Content-Type");
                $data = $http_response->decoded_content;
            }
            else {
                $type = "text/html; charset=utf-8";
                $data = $http_response->error_as_HTML;
            }

            if ( $type && $data ) {
                my $part = MIME::Lite->new(
                    "Type"        => $type,
                    "Data"        => App::Feedmailer::to_bin($data),
                    "Encoding"    => "base64",
                    "Disposition" => $download,
                );
                $mail->attach($part);
            }

        }

        $mail->replace( "X-Mailer", $self->_get_cfg_val("x_mailer") );
        $mail->send();

        return $a->{send_mail_successful} = $mail->last_send_successful();
    }

    1;
};

package main {

    sub VERSION_MESSAGE {
        my ($fh) = @_;
        printf $fh "feedmailer (%s)\n", $App::Feedmailer::PACKAGE_STRING;
    }

    sub HELP_MESSAGE {
        my ($fh) = @_;
        print $fh "No help message available yet.\n";
    }

    sub BEGIN {
    }

    sub END {
    }

    sub thread_handler_start ($) {
        my ($key) = @_;
        if ( !$App::Feedmailer::cfg->{$key} ) {
            warn "$key: Not contained in configuration";
        }
        else {
            my $feed = feed->new( $key, \@{ $cache->{$key} } );
            return $key, $feed->perform;
        }
    }

    sub thread_handler_stop {
        my ( $key, $new_cache ) = @_;

        if ( defined($new_cache) ) {
            @{ $cache->{$key} } = @{$new_cache};
            App::Feedmailer::save_cache($cache);
        }
    }

    # read the command-line-options
    getopts( "c:t:f:s:x:X:Uu:nvq1:F", \%opts )
      || die "Error on processing of command-line-options";

    # set default values (if undef)
    $opts{f} //= $ENV{EMAIL} || $ENV{USER};
    $opts{S} //= "/usr/lib/sendmail -t -oi -oem";
    $opts{t} //= $ENV{EMAIL} || $ENV{USER};

    # check -c is a valid string representing an directory
    if ( $opts{'c'} && -d $opts{'c'} ) {
        $App::Feedmailer::CACHEFILE =
          File::Spec->catfile( ( $opts{'c'} ), "cache.json" );
        $App::Feedmailer::CONFIGFILE =
          File::Spec->catfile( ( $opts{'c'} ), "config.ini" );
    }

    # check -x has a numeric value
    if ( $opts{'x'}
        && !App::Feedmailer::looks_like_number( $opts{'x'} ) )
    {
        die "You has set -x but it doesn't looks like a number";
    }

    # check -u is a valid string representing an URI
    if ( $opts{'X'} && !App::Feedmailer::looks_like_uri( $opts{'X'} ) ) {
        die "You has set -X but it doesn't looks like an URI";
    }

    # check -X is a valid string representing an URI
    if ( $opts{'u'} && !App::Feedmailer::looks_like_uri( $opts{'u'} ) ) {
        die "You has set -u but it doesn't looks like an URI";
    }

    # implementation of the option -X, -u and -U
    if ( $opts{'U'} || $opts{'u'} || $opts{'X'} ) {
        if ( $opts{'x'} ) {
            warn "You has set -x but it will ignored";
            $opts{'x'} = undef;
        }
    }

    $App::Feedmailer::cfg = App::Feedmailer::load_config();

    # set default values (if undef)
    $App::Feedmailer::cfg->{_}{download}            //= "inline";
    $App::Feedmailer::cfg->{_}{filter_date}         //= 7;
    $App::Feedmailer::cfg->{_}{filter_lang}         //= "";
    $App::Feedmailer::cfg->{_}{filter_list}         //= 1;
    $App::Feedmailer::cfg->{_}{filter_size}         //= 0;
    $App::Feedmailer::cfg->{_}{force_secure_scheme} //= 0;
    $App::Feedmailer::cfg->{_}{from}                //= $opts{f};
    $App::Feedmailer::cfg->{_}{keep_old}            //= 128;
    $App::Feedmailer::cfg->{_}{max_threads}         //= 8;
    $App::Feedmailer::cfg->{_}{cut_to}              //= 96;
    $App::Feedmailer::cfg->{_}{subject}             //= "%E (%f)";
    $App::Feedmailer::cfg->{_}{template}            //= "mail.tt.html";
    $App::Feedmailer::cfg->{_}{to}                  //= $opts{t};
    $App::Feedmailer::cfg->{_}{ua_from} //= $App::Feedmailer::BUGREPORT;
    $App::Feedmailer::cfg->{_}{ua_proxy_uri} //= undef;
    $App::Feedmailer::cfg->{_}{ua_string}  //= $App::Feedmailer::PACKAGE_STRING;
    $App::Feedmailer::cfg->{_}{ua_timeout} //= 180;
    $App::Feedmailer::cfg->{_}{x_mailer}   //= $App::Feedmailer::NAME;

    # LOCK!
    my $dir = App::Feedmailer::get_file(".");
    if ( Proc::PID::File->running( dir => $dir ) ) {
        die "W: ${App::Feedmailer::NAME} is already running!\n";
    }

    # initializing and configure the template processing system
    $tt = Template->new($tt_cfg)
      || die $Template::ERROR;

    $cache     = App::Feedmailer::load_cache();
    $whitelist = App::Feedmailer::file2list( $App::Feedmailer::WHITELIST_FILE,
        Fcntl::O_RDONLY );
    $blacklist = App::Feedmailer::file2list( $App::Feedmailer::BLACKLIST_FILE,
        Fcntl::O_RDONLY );

    MIME::Lite->quiet( $opts{v} );
    MIME::Lite->send( 'sendmail', $opts{S}, Debug => $opts{v} );

    for ( $opts{'X'} || $opts{'u'} || uniq( keys %{$App::Feedmailer::cfg} ) ) {
        next if ( $_ eq "_" );

        threads->create( { "context" => "list" }, \&thread_handler_start,
            ($_) );
        App::Feedmailer::loop_threads( \&thread_handler_stop,
            $App::Feedmailer::cfg->{"_"}{"max_threads"} );
    }
    App::Feedmailer::loop_last_threads( \&thread_handler_stop );

    1;
};

=pod

=encoding utf8

=head1 NAME

feedmailer - sends RSS/ATOM feeds as mail or runs hooks

=head1 SYNOPSIS

B<feedmailer> [-t to] [-S alt. sendmail command]

B<feedmailer> -X <URI of feed> | -u <URI of feed>

=head1 OPTIONS

=head2 General options

=over

=item --version

=item --help

=item -q

Quiet: Inhibit the usual output.

=item -v

Verbose: Print more information about progress.

=item -c <path/to/directory>

An alternate configuration directroy.

=item -x <unsigned integer>

Limit for the flood detection.

If a feed has more then the given amount of new articels. Don't send mails (nor
execute hooks) and report this.

This option does not act on new added feeds.

=item -X <URI of feed>

Run hooks (or send mails) just for the given URI. Note: The option I<-x> will be
disabled.

You can use this option when option I<-x> has attacked and you will run hooks
(or send mails) for the feed anyway.

=item -u <URI of feed>

Update the cache for the given URI but don't send mails (nor execute hooks).
Note: The option I<-x> will be disabled.

You can use this option to update the cache e.g. when option I<-x> has attacked.

=item -U

Update the cache like option I<-u>, but for all configurated URIs.

=item -F

Always update the cache, also on failure.

=item -n Don't send mail for older articles of new added feeds.

Creates the cache for new added feeds but don't send mails (nor execute hooks).

=item -1 <string>

Act only once at double articels. Useful for Planets etc.

The detection algorithm is based on the string set as argument with
text-substitution.

As example use the weblink I<-1"%l">, the headline I<-1"%e"> (more general)
or the host and basename of path from the weblink I<-1"%H-%B"> for detection.

=back

=head2 URI/Feed and HTTP options

No options available yet.

=over

=back

=head2 Mail options

=over

=item -t <to>

To: Recipients.

The default for I<-t> is in that order: Environment variables I<EMAIL> or as fallback I<USER>.

=item -f <from>

From: Envelope Sender.

The default for I<-f> is same as for the option I<-t>.

=item -S <alt. sendmail command>

Sendmail: Alt. sendmail command. E.g:
 ssh [user@]hostname -c sendmail

See also: L<sendmail(8)>

=back

=head2 Hook options

No options available yet.

=over

=back

=head1 FILES

=over

=item ~/.App-Feedmailer/config.ini

A INI style configuration file. The subscription list.

The feed URIs and some options how to handel the feeds - see the example.

Example:

	download = ""               # string (set to "attachment", "inline" or "" for disable downloading)
	filter_date = 7             # integer (time difference in days. Entries older are ignored)
	filter_lang = ".*"          # regex (entries with not matching languages are ignored - Example: "en|de")
	filter_list = 1             # boolean (if true filtering against black- and whitlist is enabled)
	filter_size = 0             # integer (size in bytes. Entries larger are ignored)
	force_secure_scheme = 0     # boolean (use always the secure scheme e.g. HTTPS instead of HTTP)
	from = ""                   # string (email address)
	hook = ""                   # string (command to execute)
	keep_old = N                # integer (keep always min. N IDs in cache - This should help to better recognize already read articles)
	max_threads = 8             # integer
	cut_to = 96                 # integer (value for the cutted values e.g. %E, %F, ... in text-substitutions)
	subject = "%E (%f)"         # string
	template = "mail.tt.html"   # string (rel. filename)
	to = ""                     # string (email address)
	ua_proxy_uri = undef        # URI/string
	ua_timeout = 180            # integer (ms)
	x_mailer = "Feedmailer"     # string (value for the X-Mailer mail header field)
	
	[http://www.example.org/feed.xml]
		# Using global configuration values - see above - and some overrides
		hook = ""      # string (command to execute)
		to = ""        # string (email address)
		# don't identify
		ua_from = ""   # string
		ua_string = "" # string

Each value can also set globally by an enviromenet variable in upper-case like:

	env FEEDMAILER_<KEY>="<value>" feedmailer

Example howto load a feed from I2P Eepsite:

	[http://example.i2p/feed.xml]
		# e.g. for I2P HTTP proxy
		ua_proxy_uri = http://localhost:4444

Example howto load a feed from TOR hidden service:

	[http://example.onion/feed.xml]
		# e.g. for Tor SOCKS proxy
		ua_proxy_uri = http://localhost:9050

Text-substitution:

The keys I<subject> and I<hook> are support text-substition as follow.

	%a Author
        %B Basename of path from weblink of the article
	%c Article content data
	%C Copyright
	%d Date
	%D Feed description
	%e Headline of the article
	%E Headline of the article, cutted to cut_to chars
	%f Feed title
	%F Feed title, cutted to cut_to chars
	%H Host of the weblink from article
	%L Feed link
	%l Weblink to the article
	%m From: Envelope sender
	%P Path (without query) of the weblink from article
	%p Proxy URI
	%s Article summary data
	%% The %-sign
	%t To: Recipients

Template-processing:

In templates the following replacements are avalible.

	author
	copyright
	date
	entry_content_body
	entry_content_type
	entry_link
	entry_title, entry_title_cut
	feed_description
	feed_link
	feed_title, feed_title_cut

=item ~/.App-Feedmailer/whitelist

A plain-text file of Perl regex-pattern (line-wise; case-insensitive).

Whitelist: If an entry title don't matched these patterns Feedmailer will ignore the entry.

=item ~/.App-Feedmailer/blacklist

A plain-text file of Perl regex-pattern (line-wise; case-insensitive).

Blacklist: If an entry title matched these patterns Feedmailer will ignore the entry.

=item ~/.App-Feedmailer/cache.json

A JSON file stored the already known articles (as a cache).

=back

=head1 SEE ALSO

L<feedmailer-clean(1p)>, L<lsfeed(1p)>

=cut
