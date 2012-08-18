#!/usr/bin/perl

use strict;
use warnings;
use Module::Build;

die "Configuration failed" if $ENV{CONFIGURATION_SHOULD_FAIL};

my $builder = Module::Build->new(
    dist_name      => 'MB_FAIL',
    dist_author    => 'nobody',
    dist_version   => 0.1,
    dist_abstract  => 'Dummy Dist',
    module_name    => 'MB',
    build_requires => {
        Foo   => '1.0.3',
        Bar   => '1.004_01',
    },
    requires       => {
        Baz   => 0,
    },
);

$builder->create_build_script;
