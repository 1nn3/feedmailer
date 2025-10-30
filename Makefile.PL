use diagnostics;
use strict;
use utf8;
use warnings;

use ExtUtils::MakeMaker;
use File::ShareDir::Install;

install_share dist => 'dist';

WriteMakefile(
    NAME          => 'App::Feedmailer',
    VERSION_FROM  => 'lib/App/Feedmailer.pm',
    AUTHOR        => q{user <user@host>},
    ABSTRACT_FROM => 'pod/feedmailer.pod',

    #NO_MYMETA => 1,which lasts until the end of that BLOCK.
    MAN1PODS => {
        'pod/feedmailer.pod'         => '$(INST_MAN1DIR)/feedmailer.1p',
        'pod/feedmailer-clean.pod'   => '$(INST_MAN1DIR)/feedmailer-clean.1p',
        'pod/feedmailer-cronjob.pod' =>
            '$(INST_MAN1DIR)/feedmailer-cronjob.1p',
        'pod/genfeed.pod'          => '$(INST_MAN1DIR)/genfeed.1p',
        'pod/mergefeeds.pod'       => '$(INST_MAN1DIR)/mergefeeds.1p',
        'pod/send-uri.pod'         => '$(INST_MAN1DIR)/send-uri.1p',
        'pod/listentries.pod'      => '$(INST_MAN1DIR)/listentries.1p',
        'pod/listfeeds.pod'        => '$(INST_MAN1DIR)/listfeeds.1p',
        'pod/newspaper-helper.pod' => '$(INST_MAN1DIR)/newspaper-helper.1p',
    },
    MAN3PODS => {},

    #PM => { 'lib/App/Feedmailer.pm' => '$(INST_LIBDIR)/Feedmailer.pm', },
    EXE_FILES => [
        'bin/feedmailer-clean',
        'bin/feedmailer', 'bin/genfeed', 'bin/get-canonical-uri',
        'bin/mergefeeds', 'bin/listentries',
        'bin/listfeeds',  'bin/feedmailer-cronjob', 'bin/newspaper-helper',
        'bin/justonefeedformat', 'bin/newspaper-cronjob', 'bin/unsortuniq', 'bin/abos2config'

    ],
    PREREQ_PM => {
        'Array::Utils'         => undef,
        'Config::Tiny'         => undef,
        'DateTime'             => undef,
        'Email::Address'       => undef,
        'Email::Date'          => undef,
        'Encode::Guess'        => undef,
        'Encode'               => undef,
        'File::HomeDir'        => undef,
        'HTML::HeadParser'     => undef,
        'HTML::Strip'          => undef,
        'Lingua::Identify'     => undef,
        'List::Slice'          => undef,
        'Locale::Language'     => undef,
        'LWP::Protocol::socks' => undef,
        'LWP::Protocol'        => undef,
        'LWP::UserAgent'       => undef,
        'MIME::Lite::HTML'     => undef,
        'MIME::Lite'           => undef,    # libmime-lite-perl
        'Path::Tiny'           => undef,    # libpath-tiny-perl
        'Proc::PID::File'      => undef,    # libproc-pid-file-perl
        'Template'             => undef,    # libtemplate-perl
        'JSON'                 => undef,    # libjson-perl
        'Text::Trim'           => undef,
        'Text::Wrap'           => undef,
        'URI::Fetch'           => undef,
        'XML::Feed'            => undef,
        'XML::LibXML'          => undef,
        'MIME::Types'          => undef,
        'MIME::Charset'        => undef,
        'Log::Log4perl'        => undef,    # liblog-log4perl-perl
    }
);

package MY;
use File::ShareDir::Install qw(postamble);

