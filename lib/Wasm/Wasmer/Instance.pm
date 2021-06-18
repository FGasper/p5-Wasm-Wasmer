package Wasm::Wasmer::Instance;

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Wasm::Wasmer::Instance

=head1 SYNOPSIS

    my $instance = $module->create_instance(
        {
            env => {
                alert => sub { .. },
            },
        }
    );

    $instance->call( 'dothething', 23, 34 );

=head1 DESCRIPTION

This class represents an active instance of a given module.

=head1 METHODS

Instances of this class are created via L<Wasm::Wasmer::Module>
instances. They expose the following methods:

=head2 @ret = I<OBJ>->call( $FUNCNAME, @INPUTS )

Calls the exported function named $FUNCNAME, passing the given @INPUTS
and returning the returned values as a list.

@INPUTS B<must> match the function’s export signature in both type and
length; e.g., if a function expects (i32, f64) and you pass (4.3, 12),
or give too many or too few parameters, an exception will be thrown.

If the function returns multiple items, scalar context is forbidden.
(Void context is always allowed, though.)

=cut

1;
