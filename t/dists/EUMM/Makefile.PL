#!/usr/bin/perl

use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME      => 'EUMM',
    VERSION   => 0.1,
    AUTHOR    => 'nobody',
    ABSTRACT  => 'Dummy Distro',
    PREREQ_PM => {
        Foo => '1.0.3',
        Bar => '1.004_01',
        Baz => 0 },
);
