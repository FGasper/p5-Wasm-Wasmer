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

This class represents a parsed WebAssembly module. It’s the
essential hub for all interactions with L<Wasm::Wasmer>.

=head1 METHODS

=head2 $obj = I<CLASS>->new( $WASM_BIN [, $STORE ] )

Parses a WebAssembly module in binary (C<.wasm>) format
and returns a I<CLASS> instance representing that.

(To use text/C<.wat> format instead, see L<Wasm::Wasmer>’s C<wat2wasm()>.)

Optionally associates the parse of that module with a
L<Wasm::Wasmer::Store> instance.

=head2 $instance = I<OBJ>->create_instance( \@IMPORTS )

Creates a L<Wasm::Wasmer::Instance> instance from I<OBJ> with the
(optional) given @IMPORTS. (NB: @IMPORTS is given via I<reference>.)

Each @IMPORTS member is an arrayref. Options are:

=over

=item * To represent a function, give:

    [ Wasm::Wasmer::WASM_EXTERN_FUNC, $namespace, $name, sub { .. } ]

=item * To represent a global, give:

    [ Wasm::Wasmer::WASM_EXTERN_GLOBAL, $type, $value ]

… where C<$type> is one of:

=over

=item * Wasm::Wasmer::WASM_I32_VAL

=item * Wasm::Wasmer::WASM_I64_VAL

=item * Wasm::Wasmer::WASM_F32_VAL

=item * Wasm::Wasmer::WASM_F64_VAL

=back

=back

(WebAssembly’s other import types are currently unimplemented.)

=head2 $instance = I<OBJ>->create_wasi_instance( [$WASI] )

Creates a L<Wasm::Wasmer::Instance> instance from I<OBJ>.
That object’s WebAssembly imports will be the L<WASI|https://wasi.dev>
interface.

The optional $WASI argument is a L<Wasm::Wasmer::WASI> instance.
Omitting this argument is equivalent to giving
C<Wasm::Wasmer::WASI-E<gt>new()> as its value.

=cut

1;
