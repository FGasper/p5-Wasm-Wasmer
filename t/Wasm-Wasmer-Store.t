#!/usr/bin/env perl

package t::Wasm::Wasmer::Store;

use strict;
use warnings;

use Test2::V0 -no_utf8 => 1;
use Test2::Tools::Explain;
use Test2::Plugin::NoWarnings;

use parent 'Test::Class';

use Wasm::Wasmer;
use Wasm::Wasmer::Store;
use Wasm::Wasmer::Engine;

__PACKAGE__->new()->runtests() if !caller;

sub test_new : Tests(4) {
    isa_ok(
        Wasm::Wasmer::Store->new(),
        [ 'Wasm::Wasmer::Store' ],
        'plain new()'
    );

    my $err = dies { Wasm::Wasmer::Store->new( foo => 123 ) };

    is(
        $err,
        match( qr<foo> ),
        'fail on unrecognized parameter',
    );

    $err = dies { Wasm::Wasmer::Store->new( compiler => 123 ) };
    is(
        $err,
        check_set(
            match( qr<compiler> ),
            match( qr<123> ),
        ),
        'fail on bad “compiler” value',
    );

    $err = dies { Wasm::Wasmer::Store->new( engine => 123 ) };
    is(
        $err,
        check_set(
            match( qr<engine> ),
            match( qr<123> ),
        ),
        'fail on bad “engine” value',
    );

    return;
}

1;
