#!/usr/bin/env perl

use cPstrict;

use Wasm::Wasmer;

use lib '../p5-Wasm-AssemblyScript/lib';
use Wasm::AssemblyScript::Instance ('as_text', 'as_binary');

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
            slurp_binary => sub ($asc, $path_ptr) {
                my $path = $asc->_ascript->get($path_ptr);
                return as_binary(File::Slurper::read_binary($path));
            },
        },
    },
);

use Benchmark;
use Cpanel::Config::LoadCpUserFile;

Benchmark::cmpthese(
    10000,
    {
        wasm => sub {
            my $cpuser_kvbin = $instance->call_get("load_cpuser_file_KVBuffer", as_binary("superman"));
            my $cpuser_hr = { split "\0", $cpuser_kvbin };
        },
        perl => sub {
            my $cpuser = Cpanel::Config::LoadCpUserFile::load_or_die("superman");
        },
    },
);
