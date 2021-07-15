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

sub test_new : Tests(2) {
    isa_ok(
        Wasm::Wasmer::Store->new(),
        [ 'Wasm::Wasmer::Store' ],
        'plain new()'
    );

    isa_ok(
        Wasm::Wasmer::Store->new( Wasm::Wasmer::Engine->new() ),
        ['Wasm::Wasmer::Store'],
        'new($engine)',
    );

    return;
}

sub test_validate_module : Tests(2) {
    my $ok_wat = '(module)';
    my $ok_wasm = Wasm::Wasmer::wat2wasm($ok_wat);

    my $store = Wasm::Wasmer::Store->new();

    ok($store->validate_module($ok_wasm), 'valid wasm');
    ok(!$store->validate_module('//////'), 'invalid wasm');

    return;
}

1;
