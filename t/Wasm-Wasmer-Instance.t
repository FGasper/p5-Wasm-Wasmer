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

    (func (export "needsparams") (param i32 i32))
)
END

use constant _WAT_FUNCTYPES => <<'END';
(module

    ;; function import:
    (import "my" "func" (func $mf (param i32 i64 f32 f64) (result i32 i64 f32 f64)))

    (func (export "callfunc") (param i32 i64 f32 f64) (result i32 i64 f32 f64)
        local.get 0
        local.get 1
        local.get 2
        local.get 3
        call $mf
    )
)
END

use constant _WAT_FUNC_PERL_CONTEXT => <<'END';
(module

    ;; function import:
    (import "my" "voidfunc" (func $vf))
    (import "my" "scalarfunc" (func $sf (result i32)))

    (func (export "voidfunc")
        call $vf
    )

    (func (export "scalarfunc") (result i32)
        call $sf
    )
)
END

__PACKAGE__->new()->runtests() if !caller;

sub test_func_import_types : Tests(2) {
    my $ok_wat  = _WAT_FUNCTYPES;
    my $ok_wasm = Wasm::Wasmer::wat2wasm($ok_wat);

    my @cb_inputs;

    my $instance = Wasm::Wasmer::Module->new($ok_wasm)->create_instance(
        {
            my => {
                func => sub { @cb_inputs = @_; return @cb_inputs },
            },
        },
    );

    my @values = ( 1, 2, 1.5, 2.5 );

    my @got = $instance->call( callfunc => @values );
    is( \@cb_inputs, \@values, 'callback receives expected values' );
    is( \@got,       \@values, 'all values go through as expected' );
}

sub test_func_import_context : Tests(2) {
    my $ok_wat  = _WAT_FUNC_PERL_CONTEXT;
    my $ok_wasm = Wasm::Wasmer::wat2wasm($ok_wat);

    my $wantarray;

    my $instance = Wasm::Wasmer::Module->new($ok_wasm)->create_instance(
        {
            my => {
                voidfunc   => sub { $wantarray = wantarray; () },
                scalarfunc => sub { $wantarray = wantarray; 1 },
            },
        },
    );

    $instance->call('scalarfunc');
    is( $wantarray, q<>, '1 return -> scalar context' );

    $instance->call('voidfunc');
    is( $wantarray, undef, '0 returns -> void context' );

    return;
}

sub test_func_import : Tests(7) {
    my $ok_wat  = _WAT_IMPORTS;
    my $ok_wasm = Wasm::Wasmer::wat2wasm($ok_wat);

    my @cb_inputs;

    my $instance = Wasm::Wasmer::Module->new($ok_wasm)->create_instance(
        {
            my => {
                func => sub { @cb_inputs = @_; return ( 22, 33 ) },
            },
        },
    );

    my @got = $instance->call('callfunc');

    is( \@cb_inputs, [ 0,  2 ],  'callback called' );
    is( \@got,       [ 22, 33 ], 'values from callback passed' );

    #--------------------------------------------------

    $instance = Wasm::Wasmer::Module->new($ok_wasm)->create_instance(
        {
            my => {
                func => sub { @cb_inputs = @_; return ( 1, 2, 3 ) },
            },
        },
    );

    my $err = dies {
        diag explain [ $instance->call('callfunc') ];
    };

    is(
        $err,
        check_set(
            match(qr<my.*func>),    # name
            match(qr<2>),           # expected
            match(qr<3>),           # received
        ),
        'error when callback mismatches expected returns count',
    );

    $err = dies {
        diag explain [ scalar $instance->call('callfunc') ];
    };

    is(
        $err,
        check_set(
            match(qr<callfunc>),    # name
            match(qr<scalar>),      # expected
        ),
        'error when list-returning WASM function called in scalar context',
    );

    #----------------------------------------------------------------------

    $err = dies {
        diag explain [ $instance->call('needsparams') ];
    };

    is(
        $err,
        check_set(
            match(qr<needsparams>),
            match(qr<2>),
            match(qr<0>),
        ),
        'No params given to function that needs 2',
    );

    $err = dies {
        diag explain [ $instance->call( 'needsparams', 7 ) ];
    };

    is(
        $err,
        check_set(
            match(qr<needsparams>),
            match(qr<2>),
            match(qr<1>),
        ),
        '1 param given to function that needs 2',
    );

    $err = dies {
        diag explain [ $instance->call( 'needsparams', 7, 7, 7 ) ];
    };

    is(
        $err,
        check_set(
            match(qr<needsparams>),
            match(qr<2>),
            match(qr<3>),
        ),
        '3 params given to function that needs 2',
    );

    return;
}

sub test_func_export_add : Tests(2) {
    my $ok_wat  = _WAT;
    my $ok_wasm = Wasm::Wasmer::wat2wasm($ok_wat);

    my $instance = Wasm::Wasmer::Module->new($ok_wasm)->create_instance();

    is(
        [ $instance->export_functions() ],
        [
            object {
                prop blessed            => 'Wasm::Wasmer::Export::Function';
                call name               => 'add';
                call [ call => 22, 33 ] => 55;
            },
            object {
                prop blessed => 'Wasm::Wasmer::Export::Function';
                call name    => 'tellvarglobal';
            },
        ],
        'export_functions()',
    );

    my $err = dies { $instance->call('hahahaha') };
    is(
        $err,
        match(qr<hahahaha>),
        'error on call() to nonexistent function export',
    );

    return;
}

sub test_global_export : Tests(7) {
    my $ok_wat  = _WAT;
    my $ok_wasm = Wasm::Wasmer::wat2wasm($ok_wat);

    my $instance = Wasm::Wasmer::Module->new($ok_wasm)->create_instance();

    my ($tellvarglobal_f) = grep { $_->name() eq 'tellvarglobal' } $instance->export_functions();

    is(
        [ $instance->export_globals() ],
        [
            object {
                prop blessed    => 'Wasm::Wasmer::Export::Global';
                call name       => 'varglobal';
                call get        => 123;
                call mutability => Wasm::Wasmer::WASM_VAR;
            },
            object {
                prop blessed    => 'Wasm::Wasmer::Export::Global';
                call name       => 'constglobal';
                call get        => 333;
                call mutability => Wasm::Wasmer::WASM_CONST;
            },
        ],
        'export_globals()',
    );

    is( $tellvarglobal_f->call(), 123, 'tellvarglobal - initial' );

    my ( $global, $constglobal ) = $instance->export_globals();

    is(
        $global->set(234),
        $global,
        'set() return',
    );

    is( $global->get(), 234, 'set() did its thing' );

    is( $tellvarglobal_f->call(), 234, 'tellvarglobal - after set()' );

    my $err = dies { $constglobal->set(11) };
    is( $err, match(qr<global>), 'error on set of constant global' );

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

sub test_memory_export : Tests(11) {
    my $ok_wat  = _WAT;
    my $ok_wasm = Wasm::Wasmer::wat2wasm($ok_wat);

    my $instance = Wasm::Wasmer::Module->new($ok_wasm)->create_instance();

    is(
        [ $instance->export_memories() ],
        [
            object {
                prop blessed   => 'Wasm::Wasmer::Export::Memory';
                call name      => 'pagememory';
                call data_size => 2**16;
                call [ get => () ], "Hello World!" . ( "\0" x 65524 );
                call [ get => 0, 12 ] => "Hello World!";
                call [ get => 6, 12 ] => "World!\0\0\0\0\0\0";
                call_list [ set => 'Harry', 6 ] => [];
            },
        ],
        'export_memories()',
    );

    is(
        [ $instance->export_memories() ],
        [
            object {
                call [ get => 0, 13 ]           => "Hello Harry!\0";
                call_list [ set => 'Sally', 6 ] => [];
                call [ get => 0, 13 ]           => "Hello Sally!\0";

            },
        ],
        'export_memories() - redux',
    );

    #--------------------------------------------------

    my $mem = ( $instance->export_memories() )[0];

    my $err = dies { $mem->set("\x{100}") };
    ok( $err, 'set() with wide character', explain $err);

    $mem->set("HELLO");
    is(
        $mem->get( 0, 11 ),
        "HELLO Sally",
        'set() with no offset',
    );

    $mem->set( "hahaha", -6 );
    is(
        $mem->get(-10),
        "\0\0\0\0hahaha",
        'set() with negative offset',
    );

    $err = dies { $mem->set( "hahahaha", 65534 ) };
    is(
        $err,
        check_set(
            match(qr<65534>),
            match(qr<8>),
            match(qr<65542>),
            match(qr<65536>),
        ),
        'set(): excess',
        explain $err,
    );

    $err = dies { $mem->set( "hahahaha", -3 ) };
    is(
        $err,
        check_set(
            match(qr<65533>),
            match(qr<8>),
            match(qr<65541>),
            match(qr<65536>),
        ),
        'set() with negative offset: excess',
        explain $err,
    );

    #----------------------------------------------------------------------

    $err = dies { $mem->get(); 1 };
    is(
        $err,
        check_set(
            match(qr<get>),
            match(qr<void>),
        ),
        'get() fails in void context',
    );

    $err = dies { () = $mem->get(65536) };
    is(
        $err,
        check_set(
            match(qr<65536>),
        ),
        'get() fails if given offset matches the byte length',
        explain $err,
    );

    $err = dies { () = $mem->get( 65534, 5 ) };
    is(
        $err,
        check_set(
            match(qr<65534>),
            match(qr<5>),
            match(qr<65539>),
            match(qr<65536>),
        ),
        'get() fails if offset + length exceed the byte length',
        explain $err,
    );

    is( $mem->get( 65534, 2 ), 'ha', 'last 2 bytes w/ offset & length' );

    return;
}

1;
