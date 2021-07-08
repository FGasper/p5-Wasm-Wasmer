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

        # as-bind/wasi’s readAll() sometimes leaves a large section of the
        # returned buffer blank. For now we can’t trust this:
#        wasm_wasi => sub {
#            my $cpuser_kvbin = $instance->call_get("load_cpuser_file_wasi_KVBuffer", as_binary("superman"));
#my @pieces = split "\0", $cpuser_kvbin;
#use Data::Dumper;
#$Data::Dumper::Useqq = 1;
#die Dumper (odd => \@pieces ) if @pieces % 2;
#            my $cpuser_hr = { @pieces };
#        },

        perl => sub {
            my $cpuser = Cpanel::Config::LoadCpUserFile::load_or_die("superman");
        },
    },
);
