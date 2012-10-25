
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  'ABSTRACT' => 'A JSON-RPC 2.0 server.',
  'AUTHOR' => 'JT Smith <RIZEN@cpan.org>',
  'BUILD_REQUIRES' => {},
  'CONFIGURE_REQUIRES' => {
    'ExtUtils::MakeMaker' => '6.30'
  },
  'DISTNAME' => 'JSON-RPC-Dispatcher',
  'EXE_FILES' => [],
  'LICENSE' => 'perl',
  'NAME' => 'JSON::RPC::Dispatcher',
  'PREREQ_PM' => {
    'JSON' => '2.16',
    'Log::Any' => '0.11',
    'Moose' => '0.93',
    'Plack' => '0.9913',
    'Test::More' => '0'
  },
  'VERSION' => '0.0506',
  'test' => {
    'TESTS' => 't/*.t'
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



