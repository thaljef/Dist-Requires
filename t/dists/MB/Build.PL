#!/usr/bin/perl

use strict;
use warnings;
use Module::Build;

my $build = Module::Build->new(
    dist_name      => 'MB',
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

$build->create_build_script();
