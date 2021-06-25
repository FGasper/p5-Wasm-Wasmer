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

my $instance = $module->create_instance(
    {
        env => {
            abort => sub {
                use Data::Dumper;
                print STDERR Dumper('in env abort', [@_]);
                return;
            },
        },
    },
);

my $asc = Wasm::AssemblyScript::Instance::create($instance);

my $got_str = $asc->call_text('concat', as_text('hello'), as_text('world'));

print $got_str;

1;
