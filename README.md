# NAME

Dist::Requires - Identify prerequisites for a distribution

# VERSION

version 0.008

# SYNOPSIS

    use Dist::Requires;
    my $dr = Dist::Requires->new();

    # From a packed distribution archive file...
    my $prereqs = $dr->prerequisites(dist => 'Foo-Bar-1.2.tar.gz');

    # From an unpacked distribution directory...
    my $prereqs = $dr->prerequisites(dist => 'Foo-Bar-1.2');

# DESCRIPTION

[Dist::Requires](http://search.cpan.org/perldoc?Dist::Requires) reports the packages (and their versions) that are
required to configure, test, build, and install a distribution.  The
distribution may be either a packed distribution archive or an
unpacked distribution directory.  By default, the results will exclude
requirements that are satisfied by the perl core.

[Dist::Requires](http://search.cpan.org/perldoc?Dist::Requires) is intended for discovering requirements in the same
manner and context that [cpan](http://search.cpan.org/perldoc?cpan) and [cpanm](http://search.cpan.org/perldoc?cpanm) do it.  It is
specifically designed to support [Pinto](http://search.cpan.org/perldoc?Pinto), so I don't expect this
module to be useful to you unless you are doing something that deals
directly with the CPAN toolchain.

[Dist::Requires](http://search.cpan.org/perldoc?Dist::Requires) does __not__ recurse into dependencies, it does
__not__ scan source files for packages that you `use` or `require`,
it does __not__ search for distribution metadata on CPAN, and it does
__not__ generate pretty graphs.  If you need those things, please
["SEE ALSO"](#SEE ALSO).

# CONSTRUCTOR

## new( %attributes )

All of the attributes listed below can be set via the constructor, and
retrieved via accessor methods by the same name.  Once constructed,
the object is immutable and all attributes are read-only.

# ATTRIBUTES

## target\_perl => $PATH

The path to the perl executable that will be used to configure the
distribution.  Defaults to the perl that loaded this module.  NOTE:
this attribute is not configurable at this time.

## target\_perl\_version => $VERSION

The core module list for the specified perl version will be used to
filter the requirements.  This only matters if you're using the
default package filter.  Defaults to the version of the perl specified
by the `perl` attribute.  Can be specified as a decimal number, a
dotted version string, or a [version](http://search.cpan.org/perldoc?version) object.

## timeout => $INTEGER

Sets the timeout (in seconds) for running the distribution's
configuration step.  Defaults to 30 seconds.

## filter => $HASHREF

Given a hashref of MODULE\_NAME => VERSION pairs, any distribution
requirements that have the same version or less than those listed in
the hashref will be excluded from the output.  This defaults to the
modules and versions reported by [Module::CoreList](http://search.cpan.org/perldoc?Module::CoreList) for the version
of perl that was specified by the `target_perl_version` attribute.
If you don't want any filter to be applied, then just give a reference
to any empty hash.

# METHODS

## prerequisites( dist => $SOME\_PATH )

Returns the requirements of the distribution as a hash of PACKAGE\_NAME
=> VERSION pairs.  The `dist` argument can be the path to either a
distribution archive file (e.g. `Foo-Bar-1.2.tar.gz`) or an unpacked
distribution directory (e.g. `Foo-Bar-1.2`).  The requirements will
be filtered according to the values specified by the `filter`
attribute.

# BEWARE

[Dist::Requires](http://search.cpan.org/perldoc?Dist::Requires) will attempt to configure the distribution using
whatever build mechanism it provides (e.g. [Module::Build](http://search.cpan.org/perldoc?Module::Build) or
[ExtUtils::MakeMaker](http://search.cpan.org/perldoc?ExtUtils::MakeMaker) or [Module::Install](http://search.cpan.org/perldoc?Module::Install)) and then extract the
requirements from the resulting metadata files.  That means you could
be executing unsafe code.  However, this is no different from what
[cpanm](http://search.cpan.org/perldoc?cpanm) and [cpan](http://search.cpan.org/perldoc?cpan) do when you install a distribution.

# SEE ALSO

Neil Bowers has written an excellent comparison of various modules for
finding dependencies [here](http://neilb.org/reviews/dependencies.html).

[CPAN::Dependency](http://search.cpan.org/perldoc?CPAN::Dependency)

[CPAN::FindDependencies](http://search.cpan.org/perldoc?CPAN::FindDependencies)

[Devel::Dependencies](http://search.cpan.org/perldoc?Devel::Dependencies)

[Module::Depends](http://search.cpan.org/perldoc?Module::Depends)

[Module::Depends::Tree](http://search.cpan.org/perldoc?Module::Depends::Tree)

[Perl::PrereqScanner](http://search.cpan.org/perldoc?Perl::PrereqScanner)

# SUPPORT

## Perldoc

You can find documentation for this module with the perldoc command.

    perldoc Dist::Requires

## Websites

The following websites have more information about this module, and may be of help to you. As always,
in addition to those websites please use your favorite search engine to discover more resources.

- Search CPAN

The default CPAN search engine, useful to view POD in HTML format.

[http://search.cpan.org/dist/Dist-Requires](http://search.cpan.org/dist/Dist-Requires)

- CPAN Ratings

The CPAN Ratings is a website that allows community ratings and reviews of Perl modules.

[http://cpanratings.perl.org/d/Dist-Requires](http://cpanratings.perl.org/d/Dist-Requires)

- CPAN Testers

The CPAN Testers is a network of smokers who run automated tests on uploaded CPAN distributions.

[http://www.cpantesters.org/distro/D/Dist-Requires](http://www.cpantesters.org/distro/D/Dist-Requires)

- CPAN Testers Matrix

The CPAN Testers Matrix is a website that provides a visual overview of the test results for a distribution on various Perls/platforms.

[http://matrix.cpantesters.org/?dist=Dist-Requires](http://matrix.cpantesters.org/?dist=Dist-Requires)

- CPAN Testers Dependencies

The CPAN Testers Dependencies is a website that shows a chart of the test results of all dependencies for a distribution.

[http://deps.cpantesters.org/?module=Dist::Requires](http://deps.cpantesters.org/?module=Dist::Requires)

## Bugs / Feature Requests

[https://github.com/thaljef/Dist-Requires/issues](https://github.com/thaljef/Dist-Requires/issues)

## Source Code



[https://github.com/thaljef/Dist-Requires](https://github.com/thaljef/Dist-Requires)

    git clone git://github.com/thaljef/Dist-Requires.git

# AUTHOR

Jeffrey Ryan Thalhammer <jeff@imaginative-software.com>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Imaginative Software Systems.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
