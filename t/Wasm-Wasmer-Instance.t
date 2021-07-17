#!/usr/bin/env perl

package t::Wasm::Wasmer::Instance;

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
  (func $add (param $lhs i32) (param $rhs i32) (result i32)
    local.get $lhs
    local.get $rhs
    i32.add
  )
  (export "add" (func $add))
)
END

__PACKAGE__->new()->runtests() if !caller;

sub test_func_export_add : Tests(1) {
    my $ok_wat = _WAT;
    my $ok_wasm = Wasm::Wasmer::wat2wasm($ok_wat);

    my $instance = Wasm::Wasmer::Module->new($ok_wasm)->create_instance();

    is(
        [ $instance->export_functions() ],
        [
            object {
                prop blessed => 'Wasm::Wasmer::Export::Function';
                call name => 'add';
                call [ call => 22, 33 ] => 55;
            },
        ],
        'export_functions()',
    );

    return;
}

1;
