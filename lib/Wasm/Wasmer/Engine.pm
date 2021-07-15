package Wasm::Wasmer::Engine;

use Wasm::Wasmer;

=encoding utf-8

=head1 NAME

Wasm::Wasmer::Engine - Wasmer engine

=head1 SYNOPSIS

    my $engine = Wasm::Wasmer::Engine->new(
        compiler => 'llvm',
        engine => 'dylib',
    );

See L<Wasm::Wasmer::Store> for what you can do with $engine.

=head1 DESCRIPTION

This class represents a WASM “engine”.
See L<Wasmer’s documentation|https://docs.rs/wasmer-c-api/2.0.0/wasmer_c_api/wasm_c_api/engine> for a bit more context.

See L<Wasm::Wasmer::Store> for what you can do with $engine.

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

Instantiates this class, which wraps a Wasmer `wasm_engine_t`.

This accepts the arguments that in C would go into the `wasm_config_t`.
Currently that includes:

=over

=item * C<compiler> - C<cranelift>, C<llvm>, or C<singlepass>

=item * C<engine> - C<universal>, C<dylib>

=back

=cut

1;
