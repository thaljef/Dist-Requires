#!/usr/bin/env perl

use strict;
use warnings;

use ExtUtils::MakeMaker;

die "EUMM configuration failed" if $ENV{CONFIGURATION_SHOULD_FAIL};

WriteMakefile(
    NAME      => 'EUMM_FAIL',
    VERSION   => 0.1,
    AUTHOR    => 'nobody',
    ABSTRACT  => 'Dummy Distro',
    PREREQ_PM => {
        Foo => '1.0.3',
        Bar => '1.004_01',
        Baz => 0 },
);
