#!perl

use strict;
use warnings;

use Test::Most;

use FindBin qw($Bin);
use Path::Class qw(dir file);

use Dist::Requires;

#--------------------------------------------------------------------------

my $dists_dir = dir($Bin, 'dists');
my @builders  = qw(EUMM MB);

#--------------------------------------------------------------------------
# No filter

{
    my $expect = { Foo => 'v1.0.3', Bar => '1.004_01', Baz => 0 };
    my $filter = {};

    for my $builder (@builders) {
        my $dist = $dists_dir->subdir($builder)->file("$builder-0.1.tar.gz");
        my $dr = Dist::Requires->new(filter => $filter);
        my %got = $dr->prerequisites(dist => $dist);

        # Ignore prereqs imposed by toolchain
        delete $got{'ExtUtils::MakeMaker'};
        delete $got{'Module::Build'};

        is_deeply(\%got, $expect, "Prereqs for $dist");
    }
}

#--------------------------------------------------------------------------
# With filter

{
    my $expect = {Foo => 'v1.0.3', Baz => 0};
    my $filter = {Foo => 'v1.0.1', Bar => '2.1'};

    for my $builder (@builders) {
        my $dist = $dists_dir->subdir($builder)->file("$builder-0.1.tar.gz");
        my $dr = Dist::Requires->new(filter => $filter);
        my %got = $dr->prerequisites(dist => $dist);

        # Ignore prereqs imposed by toolchain
        delete $got{'ExtUtils::MakeMaker'};
        delete $got{'Module::Build'};

        is_deeply(\%got, $expect, "Filtered prereqs for $dist");
    }
}

#--------------------------------------------------------------------------
# Failures

{

  local $ENV{CONFIGURATION_SHOULD_FAIL} = 1;

   for my $builder ( qw(EUMM_FAIL MB_FAIL) ) {
        my $dr = Dist::Requires->new;
        my $dist = $dists_dir->subdir($builder)->file("$builder-0.1.tar.gz");
        dies_ok { $dr->prerequisites(dist => $dist) };
    }
}

#--------------------------------------------------------------------------
done_testing;
