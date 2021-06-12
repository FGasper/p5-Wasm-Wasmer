package Wasm::Wasmer::WASI;

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Wasm::Wasmer::WASI - Customized WASI configuration

=head1 SYNOPSIS

    my $wasi = Wasm::Wasmer::WASI->new(
        name => 'name-of-program',  # empty string by default

        args => [ '--foo', 'bar' ],

        stdin => 'inherit',
        stdout => 'inherit',    # or 'capture'
        stderr => 'inherit',    # ^^ likewise

        env => [
            key1 => value1,
            key2 => value2,
            # ...
        ],

        preopen_dirs => [ '/path/to/dir' ],
        map_dirs => {
            '/alias/dir' => '/real/path',
            # ...
        },
    );

    my $instance = $module->create_wasi_instance($wasi);

=head1 DESCRIPTION

This module implements controls for Wasmer’s WASI implementation.
As shown above, you use it to define the imports to give to a newly-created
instance of a given module. From there you can run your program as you’d
normally do.

=cut

#----------------------------------------------------------------------

use Carp ();

my %NEW_EXPECT_OPT = map { ($_ => 1) } (
    'name',
    'args',
    'stdin', 'stdout', 'stderr',
    'env',
    'preopen_dirs',
    'map_dirs',
);

my %STDIN_OPTS = map { $_ => 1 } ('inherit');
my %STDOUT_STDERR_OPTS = map { $_ => 1 } ('inherit', 'capture');

#----------------------------------------------------------------------

sub new {
    my ($class, %opts) = @_;

    my $name = $opts{'name'};
    if (defined $name) {
        if (-1 != index($name, "\0")) {
            Carp::croak "Name ($name) must not include NUL bytes!";
        }
    }
    else {
        $name = q<>;
    }

    my @extra = sort grep { !$NEW_EXPECT_OPT{$_} } keys %opts;
    die "Unknown: @extra" if @extra;

    if (my $args_ar = $opts{'args'}) {
        my @bad = grep { -1 != index($_, "\0") } @$args_ar;
        Carp::croak "Arguments (@bad) must not include NUL bytes!" if @bad;
    }

    my $v;

    $v = $opts{'stdin'};
    if (defined $v && !$STDIN_OPTS{$v}) {
        Carp::croak "Bad stdin: $v";
    }

    for my $opt ('stdout', 'stderr') {
        $v = $opts{$opt};

        if (defined $v && !$STDOUT_STDERR_OPTS{$v}) {
            Carp::croak "Bad $opt: $v";
        }
    }

    if (my $env_ar = $opts{'env'}) {
        Carp::croak "Uneven environment list!" if @$env_ar % 2;

        my @bad = grep { -1 != index($_, "\0") } @$env_ar;
        Carp::croak "Environment (@bad) must not include NUL bytes!" if @bad;
    }

    my $preopen_dirs_ar = $opts{'preopen_dirs'};
    my $map_dirs_hr = $opts{'map_dirs'};

    my @all_paths = (
        ($preopen_dirs_ar ? @$preopen_dirs_ar : ()),
        ($map_dirs_hr ? %$map_dirs_hr : ()),
    );

    my @bad_paths = grep { -1 != index($_, "\0") } @all_paths;
    if (@bad_paths) {
        require List::Util;
        @bad_paths = sort( List::Util::uniq(@bad_paths) );

        Carp::croak "Paths (@bad_paths) must not include NUL bytes!";
    }

    return $class->_new($name, \%opts);
}

1;
