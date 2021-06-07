#!/usr/bin/env perl

use strict;
use warnings;

use Wasm::Wasmer;

use lib '../p5-Wasm-AssemblyScript/lib';
use Wasm::AssemblyScript;

use File::Slurper;
use Data::Dumper;
use JSON;

$| = 1;

my $wasm = File::Slurper::read_binary("wasi.wasm");

my $store = Wasm::Wasmer::Store->new();
print "created store\n";

my $module = Wasm::Wasmer::Module->new($wasm, $store);
print "created module\n";

my $instance = $module->create_wasi_instance();

my %exports = map {
    my $fn = $_;

    ( $fn->name() => sub { $fn->call(@_) } ),
} $instance->export_functions();

my $ascript = Wasm::AssemblyScript->new(
    ($instance->export_memories())[0]->data(),
    \%exports,
);

# This has to precede other WASI function calls:
$instance->start();

$instance->call('greet');

# This causes an “abort” error when “greet” runs … bug in the loader?
my $str = 'hi “hi”';
utf8::decode($str);
my $specimen = $ascript->new_text($str);
$instance->call('say', $specimen->ptr());
