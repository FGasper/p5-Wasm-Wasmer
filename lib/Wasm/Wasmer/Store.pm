package Wasm::Wasmer::Store;

use Wasm::Wasmer;

=encoding utf-8

=head1 NAME

Wasm::Wasmer::Store

=head1 SYNOPSIS

    my $store = Wasm::Wasmer::Store->new();

The above auto-creates a L<Wasm::Wasmer::Engine> instance.
For more fine-grained control over compilation and performance,
use a pre-built engine, e.g.:

    my $store = Wasm::Wasmer::Store->new($engine);

See L<Wasm::Wasmer::Module> for what you can do with $store.

=cut

=head1 DESCRIPTION

This class represents a WASM “store”.
See L<Wasmer’s documentation|https://docs.rs/wasmer-c-api/2.0.0/wasmer_c_api/wasm_c_api/store> for a bit more context.

=cut

=head1 METHODS

=head2 $obj = I<CLASS>->new( [ $ENGINE ] )

Instantiates this class. $ENGINE is optional.

=head2 $yn = I<OBJ>->validate_module( $WASM_BYTES )

Wraps the WASM C API’s L<wasm_module_validate()|https://docs.rs/wasmer-c-api/2.0.0/wasmer_c_api/wasm_c_api/module/fn.wasm_module_validate.html>.

=cut

use Wasm::Wasmer;

1;
