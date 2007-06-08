package Class::Component::Component::Autocall::SingletonMethod;

use strict;
use warnings;

use Carp::Clan qw/Class::Component/;
use Class::Inspector;
use Scalar::Util ();


sub register_method {
    my($self, @methods) = @_;

    $self->NEXT( register_method => @methods );

    my %add_methods;
    while (my($method, $plugin) = splice @methods, 0, 2) {
        $add_methods{$method} = $plugin
    }
    return unless %add_methods;

    my $singleton_class;
    my $pkg = ref($self);
    my $ref_addr = Scalar::Util::refaddr($self);
    unless ($pkg =~ /::_Singletons::\d+$/) {
        $singleton_class = "$pkg\::_Singletons::$ref_addr";
        ## no critic
        eval "{package $singleton_class;use base '$pkg';1;}";
        ## use critic
        bless $self, $singleton_class if ref($self);
        Class::Component::Implement->component_isa_list->{$singleton_class} = Class::Component::Implement->component_isa_list->{$pkg};
    } else {
        $singleton_class = $pkg;
    }

    for my $method (keys %add_methods) {
        no strict 'refs';
        *{"$singleton_class\::$method"} = sub { shift->call($method, @_) };
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
