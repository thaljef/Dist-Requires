package Dist::Requires;

# ABSTRACT: Identify requirements for a distribution

use Moose;
use Moose::Util::TypeConstraints;

use Carp;
use CPAN::Meta;
use Module::CoreList;
use Archive::Extract;
use IPC::Run qw(run timeout);
use Path::Class qw(dir file);
use File::Temp;
use Cwd;

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
# Some custom types

class_type 'Version', { class => 'version' };
coerce 'Version', from 'Str', via { version->parse($_) };
coerce 'Version', from 'Num', via { version->parse($_) };
# TODO: Put those on CPAN as MooseX::Types::Version

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

=attr target_perl_version => $FLOAT

The core module list for the specified perl version will be used to
filter the requirements.  This only matters if you're using the
default package filter.  Defaults to the version of the perl specified
by the C<perl> attribute.  Can be specified as a decimal number, a
dotted version string, or a L<version> object.

=cut

has target_perl_version => (
    is         => 'ro',
    isa        => 'Version',
    coerce     => 1,
    lazy       => 1,
    default    => sub { version->parse( $] ) },
    # TODO: lazy_build => 1,
);

#-----------------------------------------------------------------------------

=attr timeout => $INT

Sets the timeout (in seconds) for running the distribution's
configuration step.  Defaults to 15 seconds.

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
    lazy_build => 1,
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
=> VERSION pairs.  The c<dist> argument can be the path to either a
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

    my $old_cwd = getcwd();
    # Cwd::chdir() also sets $ENV{PWD}, which may be used by some dists!
    Cwd::chdir($dist_dir) or croak "Unable to chdir to $dist_dir: $!";

    my $try_eumm = sub {
        if ( -e 'Makefile.PL' ) {
            return $self->_run( [$self->target_perl(), 'Makefile.PL'] ) && -e 'Makefile';
        }
    };


    my $try_mb = sub {
        if ( -e 'Build.PL' ) {
            return $self->_run( [$self->target_perl(), 'Build.PL'] ) && -e 'Build';
        }
    };

    my $ok = $try_mb->() || $try_eumm->() || croak "Failed to configure $dist_dir";

    Cwd::chdir($old_cwd) or croak "Unable to chdir to $old_cwd: $!";

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

__PACKAGE__->meta->make_immutable();

#-----------------------------------------------------------------------------

1;

=head1 SYNOPSIS

  use Dist::Requires;
  my $dr = Dist::Requires->new();

  # From a distribution archive file...
  my $prereqs = $dr->prerequisites(dist => 'Foo-Bar-1.2.tar.gz');

  # From an unpacked distribution directory...
  my $prereqs = $dr->prerequisites(dist => 'Foo-Bar-1.2');

=head1 DESCRIPTION

L<Dist::Requires> answers the question "Which packages are required to
install a distribution with a particular version of perl?"  The
distribution can be in an archive file or unpacked into a directory.
By default, the requirements will only include packages that are newer
than the ones in the perl core (if they were in the core at all).  You
can turn this feature off to get all requirements.  You can also
control which version of perl to consider.

=head1 CONSTRUCTOR

=head2 new( %attributes )

All of the attributes listed below can be set via the constructor, and
retrieved via accessor methods by the same name.  Once constructed,
the object is immutable and all attributes are read-only.

=head1 LIMITATIONS

Much of L<Dist::Requires> was inspired (even copied) from L<CPAN> and
L<cpanm>.  However, both of those are much more robust and better at
handling old versions of toolchain modules, broken metadata, etc.
L<Dist::Requires> requires relatively new toolchain modules, and will
probably only work if given a well-packaged distribution with sane
metadata.  Perhaps L<Dist::Metadata> will become more robust in the
future.

=head1 BEWARE

L<Dist::Requires> will attempt to configure the distribution using
whatever build mechanism it provides (i.e. L<Module::Build> or
L<ExtUtils::MakeMaker>) and then extract the requirements from the
resulting metadata files.  That means you could be executing unsafe
code.  However, this is no different from what L<cpanm> and L<cpan> do
when you install a distribution.

=head1 SEE ALSO

L<Module::Depends>

=for Pod::Coverage BUILD

=cut
