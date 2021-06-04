#!/usr/bin/env perl

use strict;
use warnings;

use Wasm::Wasmer;

use lib '../p5-Wasm-AssemblyScript/lib';

use File::Slurper;
use Data::Dumper;

$| = 1;

my $wasm = File::Slurper::read_binary("callback.wasm");

my $store = Wasm::Wasmer::Store->new();
print "created store\n";

my $module = Wasm::Wasmer::Module->new($store, $wasm);
print "created module\n";

printf "wef: %s\n", Wasm::Wasmer::WASM_EXTERN_FUNC;

my $instance = $module->create_instance(
    [
        [
            Wasm::Wasmer::WASM_EXTERN_FUNC, 'callback', 'sayhi',
            sub {
                print "Hello from your callback!\n";
                return;
            },
        ],
        [
            Wasm::Wasmer::WASM_EXTERN_FUNC, 'callback', 'count',
            sub {
                my ($start, $end) = @_;

                printf "%s\n", join(', ', $start .. $end);

                return $end - $start;
            },
        ],
    ],
);

print "created instance\n";

$instance->call('call_sayhi');

my $got = $instance->call('call_count', 5, 11);

1;
