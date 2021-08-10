package Wasm::Wasmer::Function::Import;

use strict;
use warnings;

use parent 'Wasm::Wasmer::Function';

=encoding utf-8

=head1 NAME

Wasm::Wasmer::Function::Import - Imported WebAssembly function

=head1 SYNOPSIS

    my $store = Wasm::Wasmer::Store->new();

    my $func = $store->create_function(
        params => [ Wasm::Wasmer::WASM_I32, Wasm::Wasmer::WASM_I64 ],
        results => [ Wasm::Wasmer::WASM_F32 ],
        code => sub { .. },
    );

    my $module = Wasm::Wasmer::Module->new($wasm_bin, $store);

    my $instance = $module->create_instance(
        {
            the_imports => {
                myfunc => $func,
            },
        },
    );

=head1 DESCRIPTION

This class extends L<Wasm::Wasmer::Function> to represent an imported
WebAssembly function. It is not instantiated directly.

The only difference between this class and its base class is that the
C<call()> method triggers an exception. That may change in the future
if Wasmer adds support for calling host functions; as of this writing
it causes the process to end suddenly.

=cut

use Carp ();

sub call {
    Carp::confess "Call to imported function (unsupported by Wasmer)";
}

1;
