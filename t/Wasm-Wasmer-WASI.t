#!/usr/bin/env perl

package t::Wasm::Wasmer::WASI;

use strict;
use warnings;

use Test2::V0 -no_utf8 => 1;
use Test2::Tools::Explain;
use Test2::Plugin::NoWarnings;

use parent 'Test::Class';

use Wasm::Wasmer;
use Wasm::Wasmer::Module;
use Wasm::Wasmer::WASI;

use constant _WAT => <<'END';
(module

    (import "wasi_snapshot_preview1" "fd_write" (func $fdwrite (param i32 i32 i32 i32) (result i32)))

    (memory (export "memory") 1)

    ;; function export:
    (func (export "fd_write") (param i32 i32 i32 i32) (result i32)
        local.get 0
        local.get 1
        local.get 2
        local.get 3
        call $fdwrite
    )
)
END

__PACKAGE__->new()->runtests() if !caller;

sub test_fd_write : Tests(4) {
    my $ok_wasm = Wasm::Wasmer::wat2wasm(_WAT);

    my $wasi = Wasm::Wasmer::WASI->new(
        stdout => 'capture',
        stderr => 'capture',
    );

    my @tt = (
        [ 1 => 'read_stdout' ],
        [ 2 => 'read_stderr' ],
    );

    for my $t_ar (@tt) {
        my ( $wasi_fd, $read_fn ) = @$t_ar;

        my $instance = Wasm::Wasmer::Module->new($ok_wasm)->create_wasi_instance(
            $wasi,
        );

        my $mem     = ( $instance->export_memories() )[0];
        my $payload = 'hello';

        # Cribbed from as-wasi’s use of fd_write and wasi.rs:
        # Payload at offset 32, (addr, len) at offset 16.

        $mem->set( $payload,                          32 );
        $mem->set( pack( 'LL', 32, length $payload ), 16 );

        my $wasi_errno = $instance->call(
            'fd_write',
            $wasi_fd,    # WASI FD to write to
            16,          # iovecs are at offset 16.
            1,           # There’s 1 iovec.
            8,           # Write the # of bytes written to offset 8.
        );

        die "WASI errno: $wasi_errno" if $wasi_errno;

        my $wrote = unpack 'L', $mem->get( 8, 4 );
        is( $wrote, length($payload), 'bytes written' );

        is(
            $wasi->$read_fn(32),
            $payload,
            "$read_fn() reads captured output",
        );
    }

    return;
}

1;
