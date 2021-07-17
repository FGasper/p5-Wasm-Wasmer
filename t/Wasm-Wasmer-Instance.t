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
    (func (export "add") (param $lhs i32) (param $rhs i32) (result i32)
        local.get $lhs
        local.get $rhs
        i32.add
    )

    ;; memory export:
    (memory (export "pagememory") 1)
    (data (i32.const 0) "Hello World!\00")

    ;; mutable global export:
    (global $gg (mut i32) (i32.const 123))
    (export "varglobal" (global $gg))

    (func (export "tellvarglobal") (result i32)
        global.get $gg
    )

    ;; constant global export:
    (global (export "constglobal") i32 (i32.const 333))
)
END

use constant _WAT_IMPORTS => <<'END';
(module

    ;; global import:
    ;; (import "my" "global" (global $g (mut i32)))

    ;; memory import:
    ;; (import "my" "memory" (memory $m 1))

    ;; function import:
    (import "my" "func" (func $mf (param i32 i32) (result i32 i32)))

    (func (export "callfunc") (result i32 i32)
        i32.const 0  ;; pass offset 0 to log
        i32.const 2  ;; pass length 2 to log
        call $mf
    )
)
END

__PACKAGE__->new()->runtests() if !caller;

sub test_func_import : Tests(2) {
    my $ok_wat = _WAT_IMPORTS;
    my $ok_wasm = Wasm::Wasmer::wat2wasm($ok_wat);

    my @cb_inputs;

    my $instance = Wasm::Wasmer::Module->new($ok_wasm)->create_instance(
        {
            my => {
                func => sub { @cb_inputs = @_; return (22, 33) },
            },
        },
    );

    my @got = ($instance->export_functions())[0]->call();

    is( \@cb_inputs, [0, 2], 'callback called');
    is( \@got, [22, 33], 'values from callback passed' );

    return;
}

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
            object {
                prop blessed => 'Wasm::Wasmer::Export::Function';
                call name => 'tellvarglobal';
            },
        ],
        'export_functions()',
    );

    return;
}

sub test_global_export : Tests(7) {
    my $ok_wat = _WAT;
    my $ok_wasm = Wasm::Wasmer::wat2wasm($ok_wat);

    my $instance = Wasm::Wasmer::Module->new($ok_wasm)->create_instance();

    my ($tellvarglobal_f) = grep { $_->name() eq 'tellvarglobal' } $instance->export_functions();

    is(
        [ $instance->export_globals() ],
        [
            object {
                prop blessed => 'Wasm::Wasmer::Export::Global';
                call name => 'varglobal';
                call get => 123;
                call mutability => Wasm::Wasmer::WASM_VAR;
            },
            object {
                prop blessed => 'Wasm::Wasmer::Export::Global';
                call name => 'constglobal';
                call get => 333;
                call mutability => Wasm::Wasmer::WASM_CONST;
            },
        ],
        'export_globals()',
    );

    is( $tellvarglobal_f->call(), 123, 'tellvarglobal - initial' );

    my ($global, $constglobal) = $instance->export_globals();

    is(
        $global->set(234),
        $global,
        'set() return',
    );

    is($global->get(), 234, 'set() did its thing');

    is( $tellvarglobal_f->call(), 234, 'tellvarglobal - after set()' );

    my $err = dies { $constglobal->set(11) };
    is( $err, match( qr<global> ), 'error on set of constant global' );

    is(
        [ $instance->export_globals() ],
        array {
            item object {
                call get => 234;
            };
            etc();
        },
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
