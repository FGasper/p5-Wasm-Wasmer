#!/usr/bin/env perl

use cPstrict;

use Wasm::Wasmer;

use lib '../p5-Wasm-AssemblyScript/lib';
use Wasm::AssemblyScript::Instance ('as_text');

use File::Slurper;
use Data::Dumper;
use JSON::XS;

$| = 1;

my $wasm = File::Slurper::read_binary("parse_cpuser.wasm");

my $module = Wasm::Wasmer::Module->new($wasm);

my $instance = Wasm::AssemblyScript::Instance::create_wasi(
    $module,
    undef,
    {
        cpanel => {
            slurp_text => sub ($asc, $path_ptr) {
                my $path = $asc->_ascript->get($path_ptr);
                return as_text(File::Slurper::read_text($path));
            },
        },
    },
    {
        env => {
            abort => sub ($asc, $msg_ptr, $file_ptr, $line, $col) {
                my $msg = $asc->get($msg_ptr);
                my $file = $asc->get($file_ptr);

                Carp::croak "abort: $msg at $file:$line:$col";
            },
        },
    },
);

use Benchmark;
my $cpuser_json = $instance->call_get("load_cpuser_file_JSON");
my $cpuser_hr = JSON::XS::decode_json($cpuser_json);
