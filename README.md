# To build:

1. Install [Wasmer](http://wasmer.io) somewhere. Maybe globally.

2. With the `wasmer` binary in your PATH, do the usual Perl module build
steps: `perl Makefile.PL` then `make`.

3. Run `perl -Mblib -MWasm::Wasmer -e1` to confirm success.

# To run demos:

These assume that Wasm::AssemblyScript will be available
in a sibling directory to `p5-wasm-wasmer`.
