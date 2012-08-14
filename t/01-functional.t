#!perl

use strict;
use warnings;

use FindBin qw($Bin);
use Path::Class qw(dir file);

use Test::Most (tests => 4);

use Dist::Requires;

my $dists_dir = dir($Bin, 'dists');
my $expect = { Foo => 'v1.0.3', Bar => '1.004_01', Baz => 0 };
my $filter = {};

#--------------------------------------------------------------------------
# No filter

for my $dist_dir ($dists_dir->children) {
    my $dr = Dist::Requires->new(filter => $filter);
    my %got = $dr->prerequisites(dist => $dist_dir);

    # Ignore prereqs imposed by toolchain
    delete $got{'ExtUtils::MakeMaker'};
    delete $got{'Module::Build'};

    is_deeply(\%got, $expect, "Prereqs for $dist_dir");
}

#--------------------------------------------------------------------------
# With filter

$expect = {Foo => 'v1.0.3', Baz => 0};
$filter = {Foo => 'v1.0.1', Bar => '2.1'};

for my $dist_dir ($dists_dir->children) {
    my $dr = Dist::Requires->new(filter => $filter);
    my %got = $dr->prerequisites(dist => $dist_dir);

    # Ignore prereqs imposed by toolchain
    delete $got{'ExtUtils::MakeMaker'};
    delete $got{'Module::Build'};

    is_deeply(\%got, $expect, "Filtered prereqs for $dist_dir");
}
