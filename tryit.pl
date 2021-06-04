#!/usr/bin/env perl

use strict;
use warnings;

use Wasm::Wasmer;

my $wat = <<'END';
(module
  (func $add (param $lhs i32) (param $rhs i32) (result i32)
    local.get $lhs
    local.get $rhs
    i32.add)
  (export "add" (func $add))
)
END

use Devel::Peek;

my $wasm = Wasm::Wasmer::wat2wasm($wat);

use Data::Dumper;
$Data::Dumper::Useqq = 1;
print Dumper $wasm;

my $store = Wasm::Wasmer::Store->new();

print STDERR "made store\n";

my $module = Wasm::Wasmer::Module->new($store, $wasm);

print STDERR "made module\n";

my $instance = $module->create_instance();

print STDERR "made instance\n";

my $got = $instance->call('add', 2, 194);

print Dumper [got => $got];

my ($fn) = grep { $_->name() eq 'add' } $instance->export_functions();

print Dumper( $fn, funccall => $fn->call(2, 77) );

#----------------------------------------------------------------------
undef $instance;
print "freed instance\n";

undef $module;
print "freed module\n";

undef $store;
print "undef’d store\n";
