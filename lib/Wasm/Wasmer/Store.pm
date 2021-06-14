package Wasm::Wasmer::Store;

use Wasm::Wasmer;

=encoding utf-8

=head1 NAME

Wasm::Wasmer::Store

=head1 SYNOPSIS

    my $store = Wasm::Wasmer::Store->new();

… or, to use a pre-built L<Wasm::Wasmer::Engine> instance:

    my $store = Wasm::Wasmer::Store->new($engine);

See L<Wasm::Wasmer::Module> for what you can do with $store.

=cut

1;
