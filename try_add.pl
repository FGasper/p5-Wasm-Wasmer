#!/usr/bin/env perl

use strict;
use warnings;

use Wasm::Wasmer;
use File::Slurper;

my $wat = File::Slurper::read_binary('add.wat');

use Devel::Peek;

my $wasm = Wasm::Wasmer::wat2wasm($wat);

use Data::Dumper;
$Data::Dumper::Useqq = 1;

my $store = Wasm::Wasmer::Store->new();

my $module = Wasm::Wasmer::Module->new($store, $wasm);

my $instance = $module->create_instance();

print Dumper( ($instance->export_memories())[0]->data() );

my $got = $instance->call('add', 2, 194);

print Dumper [got => $got];
