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

my $wasm = File::Slurper::read_binary("try_cpuser.wasm");

my $module = Wasm::Wasmer::Module->new($wasm);
print "created module\n";

my $instance = $module->create_wasi_instance();

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
print "got from loadFile: $got_ptr\n";

my $addr = $memory->data();
my $len = $memory->data_size();
print "memory at $addr ($len bytes)\n";

my $memory_contents = unpack "P$len", pack("Q", $addr);
print "slurped memory contents\n";
use Data::Dumper;
$Data::Dumper::Useqq = 1;

my $text_out = $ascript->get_text($got_ptr);

print $text_out;
