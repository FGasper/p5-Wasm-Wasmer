#!/usr/bin/env perl

use strict;
use warnings;

use Wasm::Wasmer;

use lib '../p5-Wasm-AssemblyScript/lib';
use Wasm::AssemblyScript;

use File::Slurper;
use Data::Dumper;

$| = 1;

my $wasm = File::Slurper::read_binary("concat.wasm");

my $store = Wasm::Wasmer::Store->new();
print "created store\n";

my $module = Wasm::Wasmer::Module->new($store, $wasm);
print "created module\n";

printf "wef: %s\n", Wasm::Wasmer::WASM_EXTERN_FUNC;

my $instance = $module->create_instance(
    [
        [
            Wasm::Wasmer::WASM_EXTERN_FUNC, 'env', 'abort',
            sub {
                use Data::Dumper;
                print STDERR Dumper('in env abort', [@_]);
                return;
            },
        ],
    ],
);

print "created instance\n";

my %exports = map {
    my $fn = $_;

    ( $fn->name() => sub { $fn->call(@_) } ),
} $instance->export_functions();

my $ascript = Wasm::AssemblyScript->new(
    ($instance->export_memories())[0]->data(),
    \%exports,
);

print "created ascript\n";

my $hello = $ascript->new_text('Hello, ')->pin();
my $world = $ascript->new_text('world!')->pin();

print "created strings\n";

my $got = $instance->call('concat', $hello->ptr(), $world->ptr());

my $got_str = $ascript->get_text($got);

print Dumper $got_str;

1;
