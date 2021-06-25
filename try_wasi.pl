#!/usr/bin/env perl

use strict;
use warnings;

use Wasm::Wasmer;

use lib '../p5-Wasm-AssemblyScript/lib';
use Wasm::AssemblyScript::Instance ('as_text');

use File::Slurper;
use Data::Dumper;
use JSON;

use Wasm::Wasmer::WASI ();

$| = 1;

my $wasm = File::Slurper::read_binary("wasi.wasm");

my $module = Wasm::Wasmer::Module->new($wasm);

my $instance = $module->create_wasi_instance();

$instance = Wasm::AssemblyScript::Instance::create($instance);

# This has to precede other WASI function calls:
# $instance->start();

$instance->call('greet');

# This causes an “abort” error when “greet” runs … bug in the loader?
my $str = 'hi “hi”';
utf8::decode($str);
$instance->call('say', as_text($str));
