package Wasm::Wasmer::Store;

use Wasm::Wasmer;

=encoding utf-8

=head1 NAME

Wasm::Wasmer::Store

=head1 SYNOPSIS

    my $store = Wasm::Wasmer::Store->new();

For more fine-grained control over compilation and performance
you can pass options like, e.g.:

    my $store = Wasm::Wasmer::Store->new(
        compiler => 'llvm',
        engine => 'dylib',
    );

See L<Wasm::Wasmer::Module> for what you can do with $store.

=cut

=head1 DESCRIPTION

This class represents a WASM “store” and “engine” pair.
See Wasmer’s
L<store|https://docs.rs/wasmer-c-api/2.0.0/wasmer_c_api/wasm_c_api/store>
and
L<engine|https://docs.rs/wasmer-c-api/2.0.0/wasmer_c_api/wasm_c_api/engine>
modules for a bit more context.

=cut

=head1 CONSTRUCTOR

=head2 $obj = I<CLASS>->new( %OPTS )

Instantiates this class, which wraps Wasmer C<wasm_engine_t> and
C<wasm_store_t> instances.

This accepts the arguments that in C would go into the C<wasm_config_t>.
Currently that includes:

=over

=item * C<compiler> - C<cranelift>, C<llvm>, or C<singlepass>

=item * C<engine> - C<universal>, C<dylib>

=back

NB: Your Wasmer may not support all of the above.

=head2 IMPORTS

To import a global or memory into WebAssembly you first need to create
a Perl object to represent that WebAssembly object.

The following create WebAssembly objects the store and return Perl objects
that interact with those WebAssembly objects.

(NB: The Perl objects do I<not> trigger destruction of the WebAssembly objects
when they go away. Only destroying the store achieves that.)

=head3 $obj = I<OBJ>->create_memory( %OPTS )

Creates a WebAssembly memory and a Perl L<Wasm::Wasmer::Memory> instance
to interface with it. %OPTS are:

=over

=item * C<initial> (required)

=item * C<maximum>

=back

The equivalent JavaScript interface is C<WebAssembly.Memory()>; see L<its documentation|https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/WebAssembly/Memory/Memory> for more details.

=head3 Globals

Rather than a single method, this class exposes separate methods to create
globals of different types:

=over

=item * I<OBJ>->create_i32_const($VALUE)

=item * I<OBJ>->create_i32_mut($VALUE)

=item * I<OBJ>->create_i64_const($VALUE)

=item * I<OBJ>->create_i64_mut($VALUE)

=item * I<OBJ>->create_f32_const($VALUE)

=item * I<OBJ>->create_f32_mut($VALUE)

=item * I<OBJ>->create_f64_const($VALUE)

=item * I<OBJ>->create_f64_mut($VALUE)

=back

Each of the above creates a WebAssembly global and a Perl
L<Wasm::Wasmer::Global> instance to interface with it.

=head3 Tables

(Unsupported for now.)

=cut

use Wasm::Wasmer;

1;
