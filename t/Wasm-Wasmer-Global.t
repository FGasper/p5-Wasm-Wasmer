#!/usr/bin/env perl

package t::Wasm::Wasmer::Global;

use strict;
use warnings;

use Test2::V0 -no_utf8 => 1;
use Test2::Tools::Explain;
use Test2::Plugin::NoWarnings;

use parent 'Test::Class';

use Encode;

use Wasm::Wasmer;
use Wasm::Wasmer::Module;

use constant _WAT => Encode::decode_utf8(<<'END');
(module
   (global (export "é-const") i32 (i32.const 42))
   (global (export "é-mut") (mut i32) (i32.const 24))
)
END

__PACKAGE__->new()->runtests() if !caller;

sub test_globals : Tests(4) {
    my $wasm = Wasm::Wasmer::wat2wasm(_WAT);

    my @globals = do {
        my $module   = Wasm::Wasmer::Module->new($wasm);
        my $i = $module->create_instance();

        map { $i->export( Encode::decode_utf8($_) ) } (
            "é-const",
            "é-mut",
        );
    };

    is(
        \@globals,
        [
            object {
                prop blessed    => 'Wasm::Wasmer::Global';
                call mutability => Wasm::Wasmer::WASM_CONST;
                call get        => 42;
            },
            object {
                prop blessed    => 'Wasm::Wasmer::Global';
                call mutability => Wasm::Wasmer::WASM_VAR;
                call get        => 24;
            },
        ],
        'export() outputs expected objects',
    );

    my $got = $globals[1]->set(244);
    is( $got,               $globals[1], 'set() returns $self' );
    is( $globals[1]->get(), 244,         'set() updates the value' );

    my $err = dies { $globals[0]->set(233) };

    is(
        $err,
        check_set(
            match qr<i32>,
            match qr<constant>,
            match(qr<global>),
        ),
        'error on set() of a constant',
    );

    return;
}
