#!/usr/local/cpanel/3rdparty/bin/perl

use Wasm::Wasmer;

my $wasm = Wasm::Wasmer::wat2wasm( <<END );
    (module
      (type (func (param i32 i32) (result i32)))
      (func (type 0)
        local.get 0
        local.get 1
        i32.add)
      (export "sum" (func 0)))
END

my $instance = Wasm::Wasmer::Module->new($wasm)->create_instance();

print $instance->call('sum', 2, 5) . $/;
