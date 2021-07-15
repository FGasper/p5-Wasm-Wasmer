#!/usr/bin/env perl

package t::Wasm::Wasmer::Module;

use strict;
use warnings;

use Test2::V0 -no_utf8 => 1;
use Test2::Tools::Explain;
use Test2::Plugin::NoWarnings;

use parent 'Test::Class';

use Wasm::Wasmer;
use Wasm::Wasmer::Module;

use constant _WAT => <<'END';
(module
   (global (export "constGlobal") i32 (i32.const 42))
   (global (export "mutGlobal") (mut i32) (i32.const 24))
)
END

__PACKAGE__->new()->runtests() if !caller;

sub test_globals : Tests(4) {
    my $wasm = Wasm::Wasmer::wat2wasm(_WAT) or die 'bad wat';

    my @globals = do {
        my $module = Wasm::Wasmer::Module->new($wasm);
        my $instance = $module->create_instance();

        $instance->export_globals();
    };

    is(
        \@globals,
        [
            object {
                prop blessed => 'Wasm::Wasmer::Global';
                call name => 'constGlobal';
                call mutability => Wasm::Wasmer::WASM_CONST;
                call get => 42;
            },
            object {
                prop blessed => 'Wasm::Wasmer::Global';
                call name => 'mutGlobal';
                call mutability => Wasm::Wasmer::WASM_VAR;
                call get => 24;
            },
        ],
        'export_globals() outputs expected objects',
    );

    my $got = $globals[1]->set(244);
    is($got, $globals[1], 'set() returns $self');
    is( $globals[1]->get(), 244, 'set() updates the value' );

    my $err = dies { $globals[0]->set(233) };

    is(
        $err,
        match( qr<constGlobal> ),
        'error on set() of a constant',
    );

    return;
}
