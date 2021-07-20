package Wasm::Wasmer::Module;

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Wasm::Wasmer::Module

=head1 SYNOPSIS

    my $module = Wasm::Wasmer::Module->new( $wasm_bin );

… or, to use a pre-built L<Wasm::Wasmer::Store> instance:

    my $module = Wasm::Wasmer::Module->new( $wasm_bin, $store );

… then:

    my $instance = $module->create_instance();

… or, for L<WASI|http://wasi.dev>:

    my $wasi = Wasm::Wasmer::WASI->new( .. );

    my $instance = $module->create_wasi_instance($wasi);

You can also specify imports; see below.

=head1 DESCRIPTION

This class represents a parsed WebAssembly module.

See L<Wasmer’s documentation|https://docs.rs/wasmer-c-api/2.0.0/wasmer_c_api/wasm_c_api/module> for a bit more context.

=head1 METHODS

=head2 $obj = I<CLASS>->new( $WASM_BIN [, $STORE ] )

Parses a WebAssembly module in binary (C<.wasm>) format
and returns a I<CLASS> instance representing that.

(To use text/C<.wat> format instead, see L<Wasm::Wasmer>’s C<wat2wasm()>.)

Optionally associates the parse of that module with a
L<Wasm::Wasmer::Store> instance.

=head2 $instance = I<OBJ>->create_instance( [ \%IMPORTS ] )

Creates a L<Wasm::Wasmer::Instance> instance from I<OBJ> with the
(optional) given %IMPORTS. (NB: %IMPORTS is given via I<reference>.)

%IMPORTS is an optional hash-of-hashrefs that describes the set of
imports to give to the new instance.

Here’s a simple example that gives a function C<ns>.C<give2> to WebAssembly
that just returns the number 2:

    my $instance = $module->create_instance(
        {
            ns => {
                give2 => sub { 2 },
            },
        },
    );

Other import types are rather more complex because they’re interactive;
thus, you have to create them:

    my $const = $module->create_global( i32 => 42 );
    my $var = $module->create_global( i32 => 42, Wasm::Wasmer::WASM_VAR );

    my $memory = $module->create_memory( min => 3, max => 5 );

(Tables are currently unsupported.)

=head2 $instance = I<OBJ>->create_wasi_instance( $WASI, [ \%IMPORTS ] )

Creates a L<Wasm::Wasmer::Instance> instance from I<OBJ>.
That object’s WebAssembly imports will be the L<WASI|https://wasi.dev>
interface.

$WASI argument is either undef or a L<Wasm::Wasmer::WASI> instance.
Undef is equivalent to C<Wasm::Wasmer::WASI-E<gt>new()>.

The optional %IMPORTS reference (I<reference>!) is as for C<create_instance()>.
Note that you can override WASI imports with this, if you so desire.

=head2 $global = I<OBJ>->create_global( $VALUE )

Creates a L<Wasm::Wasmer::Import::Global> instance. See that module’s
documentation for more details.

=head2 $bytes = I<OBJ>->serialize()

Serializes the in-memory module for later use. (cf. C<deserialize()> below)

=cut

=head1 STATIC FUNCTIONS

=head2 $module = deserialize( $SERIALIZED_BIN [, $STORE ] )

Like this class’s C<new()> method but takes a serialized module
rather than WASM code.

=cut

use Wasm::Wasmer;

1;
