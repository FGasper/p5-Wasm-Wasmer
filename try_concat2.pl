#!/usr/bin/env perl

use strict;
use warnings;

use Wasm::Wasmer;

use lib '../p5-Wasm-AssemblyScript/lib';
use Wasm::AssemblyScript::Instance ('as_text');

use File::Slurper;
use Data::Dumper;

$| = 1;

my $wasm = File::Slurper::read_binary("concat.wasm");

my $module = Wasm::Wasmer::Module->new($wasm);

my $instance = Wasm::AssemblyScript::Instance::create(
    $module,
    {
        env => {
            abort => sub {
                use Data::Dumper;
                print STDERR Dumper('in env abort', [@_]);
                return;
            },
        },

        concat => {
            logi => sub {
                use Data::Dumper;
                print STDERR Dumper('in logi', [@_]);
                return;
            },
        },
    },
);

my $got_str = $instance->call_get('concat', as_text('hello'), as_text('world'));

print $got_str;

1;
