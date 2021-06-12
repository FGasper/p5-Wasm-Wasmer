#!/usr/bin/env perl

use strict;
use warnings;

use Wasm::Wasmer;
use Wasm::Wasmer::WASI;

use lib '../p5-Wasm-AssemblyScript/lib';
use Wasm::AssemblyScript;

use File::Slurper;
use Data::Dumper;
use JSON;

$| = 1;

my $wasm = File::Slurper::read_binary("try_cpuser.wasm");

my $module = Wasm::Wasmer::Module->new($wasm);

my $wasi = Wasm::Wasmer::WASI->new(
    preopen_dirs => ['/'],
    map_dirs => { '/' => '/' },
);

my $instance = $module->create_wasi_instance($wasi);

undef $wasi;

my %exports = map {
    my $fn = $_;

    ( $fn->name() => sub { $fn->call(@_) } ),
} $instance->export_functions();

my $memory = ($instance->export_memories())[0];

my $ascript = Wasm::AssemblyScript->new(
    $memory->data(),
    \%exports,
);

$instance->start();

my $path_in = $ascript->new_text('/var/cpanel/users/superman');

my $got_ptr = $instance->call('loadFile', $path_in->ptr());

my $text_out = $ascript->get_arraybuffer($got_ptr);

print $text_out;
