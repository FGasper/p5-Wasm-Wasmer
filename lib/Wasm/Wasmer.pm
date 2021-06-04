package Wasm::Wasmer;

use XSLoader;

our $VERSION = '0.01_01';

XSLoader::load();

#----------------------------------------------------------------------

package Wasm::Wasmer::WasiInstance;

use parent -norequire => 'Wasm::Wasmer::Instance';

# The WASM C API includes wasi_get_start_function(), but that doesn’t
# provide any way of getting the name of the function. It’s neater for now
# just to do it this way.
use constant _WASI_START_FUNCNAME => '_start';

sub start {
    my $self = shift;

    return $self->call( _WASI_START_FUNCNAME, @_ );
}

1;
