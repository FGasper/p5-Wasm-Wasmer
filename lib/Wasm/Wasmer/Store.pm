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

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

Instantiates this class, which wraps Wasmer `wasm_engine_t` and
`wasm_store_t` instances.

This accepts the arguments that in C would go into the `wasm_config_t`.
Currently that includes:

=over

=item * C<compiler> - C<cranelift>, C<llvm>, or C<singlepass>

=item * C<engine> - C<universal>, C<dylib>

=back

=cut

use Wasm::Wasmer;

1;
