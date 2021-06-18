package Wasm::Wasmer;

use XSLoader;

our $VERSION = '0.01_01';

XSLoader::load();

=encoding utf-8

=head1 NAME

Wasm::Wasmer - Run L<WebAssembly|https://webassembly.org/> via L<http://wasmer.io/Wasmer|Wasmer> in Perl

=head1 SYNOPSIS

    use Wasm::Wasmer;

    my $wasm = Wasm::Wasmer::wat2wasm( <<END );
        (module
        (type (func (param i32 i32) (result i32)))
        (func (type 0)
            local.get 0
            local.get 1
            i32.add)
        (export "sum" (func 0)))
    END

    my $instance = Wasm::Wasmer::Module->new($wasm)->create_instance();

    # Prints 7:
    print $instance->call('sum', 2, 5) . $/;

=head1 DESCRIPTION

This module provides an XS binding for L<http://wasmer.io/Wasmer|Wasmer>’s C API, yielding
a simple, fast way to run WebAssembly in Perl.

=head1 SEE ALSO

L<Wasm::Wasmtime> is an FFI binding to L<https://github.com/bytecodealliance/wasmtime>,
a similar project to Wasmer.

L<Wasm> provides syntactic sugar around Wasm::Wasmtime.

=cut

1;
