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

  ;; function export:
  (func $add (param $lhs i32) (param $rhs i32) (result i32)
    local.get $lhs
    local.get $rhs
    i32.add
  )
  (export "add" (func $add))

  ;; memory export:
  (memory $0 1)
  (data (i32.const 0) "Hello World!\00")
  (export "pagememory" (memory $0))

  ;; global export:
  (global $g (mut i32) (i32.const 123))
  (export "myglobal" (global $g))
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

sub test_global_export : Tests(4) {
    my $ok_wat = _WAT;
    my $ok_wasm = Wasm::Wasmer::wat2wasm($ok_wat);

    my $instance = Wasm::Wasmer::Module->new($ok_wasm)->create_instance();

    is(
        [ $instance->export_globals() ],
        [
            object {
                prop blessed => 'Wasm::Wasmer::Export::Global';
                call name => 'myglobal';
                call get => 123;
            },
        ],
        'export_globals()',
    );

    my ($global) = ($instance->export_globals())[0];

    is(
        $global->set(234),
        $global,
        'set() return',
    );

    is($global->get(), 234, 'set() did its thing');

    is(
        [ $instance->export_globals() ],
        [
            object {
                call get => 234;
            },
        ],
        'set() did its thing (new export_globals())',
    );

    return;
}

sub test_memory_export : Tests(2) {
    my $ok_wat = _WAT;
    my $ok_wasm = Wasm::Wasmer::wat2wasm($ok_wat);

    my $instance = Wasm::Wasmer::Module->new($ok_wasm)->create_instance();

    is(
        [ $instance->export_memories() ],
        [
            object {
                prop blessed => 'Wasm::Wasmer::Export::Memory';
                call name => 'pagememory';
                call data_size => 2**16;
                call [ substr => () ], "Hello World!" . ("\0" x 65524);
                call [ substr => 0, 12 ] => "Hello World!";
                call [ substr => 6, 12 ] => "World!\0\0\0\0\0\0";
                call_list [ set => 'Harry', 6 ] => [];
            },
        ],
        'export_memories()',
    );

    is(
        [ $instance->export_memories() ],
        [
            object {
                call [ substr => 0, 13 ] => "Hello Harry!\0";
                call_list [ set => 'Sally', 6 ] => [];
                call [ substr => 0, 13 ] => "Hello Sally!\0";

            },
        ],
        'export_memories() - redux',
    );

    return;
}

1;
