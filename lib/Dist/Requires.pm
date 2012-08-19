# ABSTRACT: Identify requirements for a distribution

package Dist::Requires;

use Moose;
use MooseX::Types::Perl qw(VersionObject);

use Carp;
use CPAN::Meta;
use Module::CoreList;
use Archive::Extract;
use IPC::Run qw(run timeout);
use Path::Class qw(dir file);
use File::Temp;
use Cwd::Guard;

# We don't use these directly, but they will be required to perform
# configuration of our dists.  We want versions that will at least
# generate a META.yml file for us (or maybe even MYMETA.yml!)
use ExtUtils::MakeMaker 6.58;
use Module::Build 0.21;

use version;
use namespace::autoclean;

#-----------------------------------------------------------------------------

# VERSION

#-----------------------------------------------------------------------------

=attr target_perl => $PATH

The path to the perl executable that will be used to configure the
distribution.  Defaults to the perl that loaded this module.  NOTE:
this attribute is not configurable at this time.

=cut

has target_perl => (
    is       => 'ro',
    isa      => 'Str',  # TODO: make this a Path::Class::File
    default  => $^X,
    init_arg => undef,
);

=attr target_perl_version => $VERSION

The core module list for the specified perl version will be used to
filter the requirements.  This only matters if you're using the
default package filter.  Defaults to the version of the perl specified
by the C<perl> attribute.  Can be specified as a decimal number, a
dotted version string, or a L<version> object.

=cut

has target_perl_version => (
    is         => 'ro',
    isa        => VersionObject,
    default    => sub { version->parse( $] ) },
    coerce     => 1,
    lazy       => 1,
);

#-----------------------------------------------------------------------------

=attr timeout => $INTEGER

Sets the timeout (in seconds) for running the distribution's
configuration step.  Defaults to 30 seconds.

=cut

has timeout => (
    is      => 'ro',
    isa     => 'Int',
    default => 30,
);

#-----------------------------------------------------------------------------

=attr filter => $HASHREF

Given a hashref of MODULE_NAME => VERSION pairs, any distribution
requirements that have the same version or less than those listed in
the hashref will be excluded from the output.  This defaults to the
modules and versions reported by L<Module::CoreList> for the version
of perl that was specified by the C<target_perl_version> attribute.
If you don't want any filter to be applied, then just give a reference
to any empty hash.

=cut

has filter => (
    is         => 'ro',
    isa        => 'HashRef',
    builder    => '_build_filter',
    lazy       => 1,
);

#-----------------------------------------------------------------------------

sub _build_filter {
    my ($self) = @_;

    # version.pm doesn't always strip trailing zeros
    my $tpv           = $self->target_perl_version->numify() + 0;
    my $core_packages = $Module::CoreList::version{$tpv};  ## no critic (PackageVar)

    return { __versionize_values( %{$core_packages} ) };
}

#-----------------------------------------------------------------------------

sub _build_target_perl_version {
    my ($self) = @_;

    my $perl = $self->target_perl();
    my $version = qx{$perl -e 'print $]'};  ## no critic (Backtick)
    croak "Unable to determine the version of $perl: $!" if $?;

    return $version;
}

#-----------------------------------------------------------------------------

sub BUILD {
    my ($self) = @_;

    my $tpv = $self->target_perl_version()->numify();
    $tpv += 0;  # version.pm doesn't always strip trailing zeros

    croak "The target_perl_version ($tpv) cannot be greater than this perl ($])"
        if $tpv > $];

    croak "Unknown version of perl: $tpv"
        if not exists $Module::CoreList::version{$tpv};  ## no critic (PackageVar)

    return $self;
}

#-----------------------------------------------------------------------------

=method prerequisites( dist => $SOME_PATH )

Returns the requirements of the distribution as a hash of PACKAGE_NAME
=> VERSION pairs.  The C<dist> argument can be the path to either a
distribution archive file (e.g. F<Foo-Bar-1.2.tar.gz>) or an unpacked
distribution directory (e.g. F<Foo-Bar-1.2>).  The requirements will
be filtered according to the values specified by the C<filter>
attribute.

=cut

sub prerequisites {
    my ( $self, %args ) = @_;

    my $dist          = $args{dist};
    my $dist_dir      = $self->_resolve_dist($dist);
    my %dist_requires = $self->_get_dist_requires($dist_dir);
    my %my_requires   = $self->_filter_requires(%dist_requires);

    return %my_requires;
}

#-----------------------------------------------------------------------------

sub _resolve_dist {
    my ($self, $dist) = @_;

    croak "$dist does not exist"  if not -e $dist;
    croak "$dist is not readable" if not -r $dist;

    return -d $dist ? dir($dist) : $self->_unpack_dist($dist);
}

#-----------------------------------------------------------------------------

sub _unpack_dist {
    my ($self, $dist) = @_;

    my $tempdir = dir( File::Temp::tempdir(CLEANUP => 1) );
    my $ae = Archive::Extract->new( archive => $dist );
    $ae->extract( to => $tempdir ) or croak $ae->error();

    # Originally, we just returned the first entry in $ae->files() as
    # the $dist_root, but that proved to be unreliable.  Better to
    # actually look in $tempdir and see what is there.  For a well
    # packaged archive, $tempdir should contain exactly one child and
    # that child should be a directory.

    my @children = $tempdir->children();
    croak "$dist did not unpack into a single directory" if @children != 1;

    my $dist_root = $children[0];
    croak "$dist did not unpack into a directory" if not -d $dist_root;

    return $dist_root;
}

#-----------------------------------------------------------------------------

sub _get_dist_requires {
    my ($self, $dist_dir) = @_;

    $self->_configure($dist_dir);

    my $dist_meta = $self->_find_dist_meta($dist_dir);

    my %requires = $self->_extract_requires($dist_meta);

    return __versionize_values(%requires);
}

#-----------------------------------------------------------------------------

sub _configure {
    my ( $self, $dist_dir ) = @_;

    my $guard = Cwd::Guard->new($dist_dir)
      or croak "chdir failed: $Cwd::Guard::Error";

    local $ENV{PWD} = $dist_dir->stringify;

    # It seems we can't always rely on the exit status from running
    # the configuration.  So instead we just check for the presence of
    # the expected build sript.

    my $try_eumm = sub {
        if ( -e 'Makefile.PL' ) {
            $self->_run( [$self->target_perl(), 'Makefile.PL'] );
            return -e 'Makefile';
        }
    };


    my $try_mb = sub {
        if ( -e 'Build.PL' ) {
            $self->_run( [$self->target_perl(), 'Build.PL'] );
            return -e 'Build';
        }
    };

    my $ok = $try_mb->() || $try_eumm->() || croak "Failed to configure $dist_dir";

    return $ok;
}

#-----------------------------------------------------------------------------

sub _find_dist_meta {
    my ( $self, $dist_dir ) = @_;

    for my $meta_file ( qw(MYMETA.json MYMETA.yml META.json META.yml) ) {
        my $meta_file_path = file($dist_dir, $meta_file);
        next if not -e $meta_file_path;
        my $meta = eval { CPAN::Meta->load_file($meta_file_path) } || undef;
        return $meta if $meta;
    }

    # If we get here, then we are screwed!
    croak "Cannot find any useful metadata in $dist_dir";
}

#------------------------------------------------------------------------------

sub _extract_requires {
    my ( $self, $meta ) = @_;

    my $meta_struct = $meta->as_struct();
    my %prereqs;

    for my $phase ( qw( configure build test runtime ) ) {
      my $p = $meta_struct->{prereqs}{$phase} || {};
      %prereqs =  ( %prereqs, %{ $p->{requires} || {} } );
    }

    return %prereqs;
}

#-----------------------------------------------------------------------------

sub _filter_requires {
    my ($self, %requires) = @_;

    my $filter = $self->filter();
    while ( my ($package, $version) = each %requires ) {
        next if not exists $filter->{$package};
        delete $requires{$package} if $version <= $filter->{$package};
    };

    # Always exclude perl itself
    delete $requires{perl};

    return %requires;
}

#-----------------------------------------------------------------------------

sub _run {
    my ( $self, $cmd ) = @_;

    # trick AutoInstall
    local $ENV{PERL5_CPAN_IS_RUNNING} = local $ENV{PERL5_CPANPLUS_IS_RUNNING} = $$;

    # e.g. skip CPAN configuration on local::lib
    local $ENV{PERL5_CPANM_IS_RUNNING} = $$;

    # use defaults for any intereactive prompts
    local $ENV{PERL_MM_USE_DEFAULT} = 1;

    # skip man page generation
    local $ENV{PERL_MM_OPT} = $ENV{PERL_MM_OPT};
    $ENV{PERL_MM_OPT} .= " INSTALLMAN1DIR=none INSTALLMAN3DIR=none";

    my ($in, $out);
    my $ok = run( $cmd, \$in, \$out, \$out, timeout( $self->timeout() ) );
    $ok or croak "Configuration failed: $out";

    return $ok;
}

#-----------------------------------------------------------------------------

sub __versionize_values {
    my (%h) = @_;

    for my $key (keys %h) {
        my $value = $h{$key} || 0;
        $value =~ s{ }{}g;  # Some have trailing spaces?
        $h{$key} = version->parse( $value );
    }

    return %h;
}

#-----------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;

#-----------------------------------------------------------------------------

1;

=for Pod::Coverage BUILD

=head1 SYNOPSIS

  use Dist::Requires;
  my $dr = Dist::Requires->new();

  # From a packed distribution archive file...
  my $prereqs = $dr->prerequisites(dist => 'Foo-Bar-1.2.tar.gz');

  # From an unpacked distribution directory...
  my $prereqs = $dr->prerequisites(dist => 'Foo-Bar-1.2');

=head1 DESCRIPTION

L<Dist::Requires> reports the packages (and their versions) that are
required to configure, test, build, and install a distribution.  The
distribution may be either a packed distribution archive or an
unpacked distribution directory.  By default, the results will exclude
requirements that are satisfied by the perl core.

L<Dist::Requires> is intended for discovering requirements in the same
manner and context that L<cpan> and L<cpanm> do it.  It is
specifically designed to support L<Pinto>, so I don't expect this
module to be useful to you unless you are doing something that deals
directly with the CPAN toolchain.

L<Dist::Requires> does B<not> recurse into dependencies, it does
B<not> scan source files for packages that you C<use> or C<require>,
it does B<not> search for distribution metadata on CPAN, and it does
B<not> generate pretty graphs.  If you need those things, please
L</SEE ALSO>.

=head1 CONSTRUCTOR

=head2 new( %attributes )

All of the attributes listed below can be set via the constructor, and
retrieved via accessor methods by the same name.  Once constructed,
the object is immutable and all attributes are read-only.

=head1 BEWARE

L<Dist::Requires> will attempt to configure the distribution using
whatever build mechanism it provides (e.g. L<Module::Build> or
L<ExtUtils::MakeMaker> or L<Module::Install>) and then extract the
requirements from the resulting metadata files.  That means you could
be executing unsafe code.  However, this is no different from what
L<cpanm> and L<cpan> do when you install a distribution.

=head1 SEE ALSO

Neil Bowers has written an excellent comparison of various modules for
finding dependencies L<here|http://neilb.org/reviews/dependencies.html>.

L<CPAN::Dependency>

L<CPAN::FindDependencies>

L<Devel::Dependencies>

L<Module::Depends>

L<Module::Depends::Tree>

L<Perl::PrereqScanner>

=cut
