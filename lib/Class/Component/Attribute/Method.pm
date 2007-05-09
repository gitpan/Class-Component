package Class::Component::Attribute::Method;

use strict;
use warnings;
use base 'Class::Component::Attribute';

sub register {
    my($class, $plugin, $c, $method, $value) = @_;

    $c->register_method( $method => $plugin );
}

1;
