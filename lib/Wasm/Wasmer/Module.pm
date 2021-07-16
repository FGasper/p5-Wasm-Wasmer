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

%IMPORTS is an optional hash-of-hashrefs that indicates namespace and name of
each import.

Example usage:

    my $instance = $module->create_instance(
        {
            env => {
                abort => sub { die "@_" },
            },

            custom => {
                myglobal => \234,
            },
        },
    );

For now this interface supports function imports only. Other import types can
be added as needed.

=head2 $instance = I<OBJ>->create_wasi_instance( $WASI, [ \%IMPORTS ] )

Creates a L<Wasm::Wasmer::Instance> instance from I<OBJ>.
That object’s WebAssembly imports will be the L<WASI|https://wasi.dev>
interface.

$WASI argument is either undef or a L<Wasm::Wasmer::WASI> instance.
Undef is equivalent to C<Wasm::Wasmer::WASI-E<gt>new()>.

The optional %IMPORTS reference (I<reference>!) is as for C<create_instance()>.
Note that you can override WASI imports with this, if you so desire.

=head2 $bytes = I<OBJ>->serialize()

Serializes the in-memory module for later use. (cf. C<deserialize()> below)

=cut

=head1 STATIC FUNCTIONS

=head2 $module = deserialize( $SERIALIZED_BIN [, $STORE ] )

Like this class’s C<new()> method but takes a serialized module
rather than WASM code.

=cut

1;
