
use strict;
use warnings;



use ExtUtils::MakeMaker 6.11;



my %WriteMakefileArgs = (
                       'test' => {
                                   'TESTS' => 't/*.t'
                                 },
                       'NAME' => 'JSON::RPC::Dispatcher',
                       'DISTNAME' => 'JSON-RPC-Dispatcher',
                       'CONFIGURE_REQUIRES' => {
                                                 'ExtUtils::MakeMaker' => '6.11'
                                               },
                       'AUTHOR' => 'JT Smith <RIZEN@cpan.org>',
                       'BUILD_REQUIRES' => {},
                       'ABSTRACT' => 'A JSON-RPC 2.0 server.',
                       'EXE_FILES' => [],
                       'VERSION' => '0.0503',
                       'PREREQ_PM' => {
                                        'Test::More' => '0',
                                        'Plack' => '0.9913',
                                        'Log::Any' => '0.11',
                                        'JSON' => '2.16',
                                        'Moose' => '0.93'
                                      },
                       'LICENSE' => 'perl'
                     );


delete $WriteMakefileArgs{LICENSE}
  unless eval { ExtUtils::MakeMaker->VERSION(6.31) };

WriteMakefile(%WriteMakefileArgs);



