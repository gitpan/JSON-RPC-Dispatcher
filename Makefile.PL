
use strict;
use warnings;



use ExtUtils::MakeMaker;

WriteMakefile(
  DISTNAME  => 'JSON-RPC-Dispatcher',
  NAME      => 'JSON::RPC::Dispatcher',
  AUTHOR    => "JT\ Smith\ \<RIZEN\@cpan\.org\>",
  ABSTRACT  => "A\ JSON\-RPC\ 2\.0\ server\.",
  VERSION   => '0.0300',
  EXE_FILES => [ qw() ],
  (eval { ExtUtils::MakeMaker->VERSION(6.31) } ? (LICENSE => 'perl') : ()),
  PREREQ_PM    => {
    "Test::More" => '0',
    "Plack" => '0.9023',
    "Plack::Request" => '0.09',
    "JSON" => '2.16',
    "Sub::Name" => '0.04',
    "Moose" => '0.93',
  },
  test => {TESTS => 't/*.t'}
);

