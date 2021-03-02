use diagnostics;
use strict;
use utf8;
use warnings;

use ExtUtils::MakeMaker;
use File::ShareDir::Install;

install_share dist => 'dist';

WriteMakefile(
    NAME         => 'App::Feedmailer',
    VERSION_FROM => 'lib/App/Feedmailer.pm',
    AUTHOR       => q{nobody <nobody>},

    #NO_MYMETA => 1,
    MAN1PODS => {
        'bin/feedmailer-clean.pl' => '$(INST_MAN1DIR)/feedmailer-clean.1p',
        'bin/feedmailer.pl'       => '$(INST_MAN1DIR)/feedmailer.1p',
        'bin/genfeed.pl'          => '$(INST_MAN1DIR)/genfeed.1p',
        'bin/listbookmarks.pl'    => '$(INST_MAN1DIR)/listbookmarks.1p',
        'bin/listentries.pl'      => '$(INST_MAN1DIR)/listentries.1p',
        'bin/listfeeds.pl'        => '$(INST_MAN1DIR)/listfeeds.1p',
        'bin/mergefeeds.pl'       => '$(INST_MAN1DIR)/mergefeeds.1p',
        'bin/newspaper.pl'        => '$(INST_MAN1DIR)/newspaper.1p',
        'bin/reporter.pl'         => '$(INST_MAN1DIR)/reporter.1p',
        'bin/send-uri.pl'         => '$(INST_MAN1DIR)/send-uri.1p',
    },
    MAN3PODS => {},
    PM       => {
        'bin/feedmailer-clean.pl'   => '$(INST_BIN)/feedmailer-clean',
        'bin/feedmailer-cronjob.sh' => '$(INST_BIN)/feedmailer-cronjob',
        'bin/feedmailer.pl'         => '$(INST_BIN)/feedmailer',
        'bin/genfeed.pl'            => '$(INST_BIN)/genfeed',
        'bin/justonefeedformat.awk' => '$(INST_BIN)/justonefeedformat',
        'bin/listbookmarks.pl'      => '$(INST_BIN)/listbookmarks',
        'bin/listentries.pl'        => '$(INST_BIN)/listentries',
        'bin/listfeeds.pl'          => '$(INST_BIN)/listfeeds',
        'bin/mergefeeds.pl'         => '$(INST_BIN)/mergefeeds',
        'bin/newspaper-cronjob.sh'  => '$(INST_BIN)/newspaper-cronjob',
        'bin/newspaper.pl'          => '$(INST_BIN)/newspaper',
        'bin/reporter.pl'           => '$(INST_BIN)/reporter',
        'bin/send-uri.pl'           => '$(INST_BIN)/send-uri',
        'lib/App/Feedmailer.pm'     => '$(INST_LIBDIR)/Feedmailer.pm',
    },
    PREREQ_PM => {
        'Array::Utils'         => undef,
        'Config::Tiny'         => undef,
        'Data::Dumper'         => undef,
        'DateTime'             => undef,
        'Email::Address'       => undef,
        'Email::Date'          => undef,
        'Encode::Guess'        => undef,
        'Encode'               => undef,
        'File::Basename'       => undef,
        'File::HomeDir'        => undef,
        'File::Path'           => undef,
        'File::Spec'           => undef,
        'Getopt::Std'          => undef,
        'HTML::HeadParser'     => undef,
        'HTML::Strip'          => undef,
        'List::Slice'          => undef,
        'List::Util'           => undef,
        'LWP::Protocol'        => undef,
        'LWP::Protocol::socks' => undef,
        'LWP::UserAgent'       => undef,
        'MIME::Base64'         => undef,
        'MIME::Lite'           => undef,
        'Proc::PID::File'      => undef,
        'Text::Trim'           => undef,
        'Text::Wrap'           => undef,
        'Tie::File'            => undef,
        'URI::Fetch'           => undef,
        'XML::Feed'            => undef,
        'XML::LibXML'          => undef,
    }
);

package MY;
use File::ShareDir::Install qw(postamble);

