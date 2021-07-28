package Wasm::Wasmer;

use strict;
use warnings;

use Wasm::Wasmer::Function;
use Wasm::Wasmer::Memory;
use Wasm::Wasmer::Global;
use Wasm::Wasmer::Table;
use Wasm::Wasmer::Store;
use Wasm::Wasmer::Module;
use Wasm::Wasmer::Instance;

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

This distribution provides an XS binding for L<http://wasmer.io/Wasmer|Wasmer>,
yielding a simple, fast way to run WebAssembly (WASM) in Perl.

=head1 MODULE RELATIONSHIPS

We mostly follow the relationships from
L<Wasmer’s C API|https://docs.rs/wasmer-c-api>:

=head2 * L<Wasm::Wasmer::Store> manages Wasmer’s global state, including
storage of any imports & exports. It contains compiler & engine
configuration as well. This object is auto-created by default.

=head2 * L<Wasm::Wasmer::Module> uses a L<Wasm::Wasmer::Store> instance
to represent a parsed WASM module. (This one you have to instantiate
manually.)

=head2 * L<Wasm::Wasmer::Instance> uses a L<Wasm::Wasmer::Module> instance
to represent an in-progress WASM program. You’ll instantiate these
via methods on the L<Wasm::Wasmer::Module> object.

=head1 CHARACTER ENCODING

Generally speaking, strings that in common usage are human-readable
(e.g., names of imports & exports) are character strings. Ensure
that you’ve properly character-decoded such strings, or any non-ASCII
characters will cause encoding bugs.

(TIP: Always incorporate code points 128-255 into your testing.)

Binary payloads (e.g., memory contents) are byte strings.

=head1 SEE ALSO

L<Wasm::Wasmtime> is an FFI binding to L<https://github.com/bytecodealliance/wasmtime>,
a similar project to Wasmer.

L<Wasm> provides syntactic sugar around Wasm::Wasmtime.

=head1 FUNCTIONS

This namespace defines the following:

=head2 $bin = wat2wasm( $TEXT )

Converts WASM text format to its binary-format equivalent. $TEXT
should be (character-decoded) text.

=head1 TODO

=over

=item * Add table support.

=back

=cut

1;
