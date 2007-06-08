package Class::Component::Component::Autocall::InjectMethod;

use strict;
use warnings;

use Carp::Clan qw/Class::Component/;

sub register_method {
    my($self, @methods) = @_;
    my $class = ref($self) || $self;

    $self->NEXT( register_method => @methods );                                                                                                                
    while (my($method, $plugin) = splice @methods, 0, 2) {
        no strict 'refs';
        no warnings 'redefine';
        *{"$class\::$method"} = sub { $plugin->$method(shift, @_) };
#        $self->class_component_methods->{$method} = $plugin
    }
}

sub remove_method {
    my($self, @methods) = @_;
    $self->NEXT( remove_method => @methods );
    while (my($method, $plugin) = splice @methods, 0, 2) {
        no strict 'refs';
        delete ${ref($self) . "::"}{$method};
    }
}

1; 
