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

my $wasm = File::Slurper::read_binary("validate_ipv4.wasm");

my $module = Wasm::Wasmer::Module->new($wasm);
print "created module\n";

my ($ascript_rdr, $ascript_wtr);

my $instance = $module->create_instance(
    {
        env => {
            abort => sub {
                my ($msg, $filename, $line, $col) = @_;

                $msg = $ascript_rdr->get_text($msg);
                $filename = $ascript_rdr->get_text($filename);

                die "$filename: $msg (line $line, col $col)";
            },
        },
    },
);

print "created instance\n";

$ascript_rdr = Wasm::AssemblyScript->new(
    ($instance->export_memories())[0]->data(),
);

my %exports = map {
    my $fn = $_;

    ( $fn->name() => sub { $fn->call(@_) } ),
} $instance->export_functions();

() = ($instance->export_memories())[0]->data();

$ascript_wtr = Wasm::AssemblyScript->new(
    ($instance->export_memories())[0]->data(),
    \%exports,
);

my $specimen = $ascript_wtr->new_text('1.2.3.04')->pin();

print `ps aux | grep $$`;

$instance->call('validate_ipv4', $specimen->ptr()) for 1 .. 10000;

print `ps aux | grep $$`;

my $got = $instance->call('validate_ipv4', $specimen->ptr());

my $got_str = $ascript_wtr->get_text($got);
print Dumper( gotstr => $got_str );

my $got_ar = JSON::decode_json($got_str);

print Dumper $got_ar;

1;
