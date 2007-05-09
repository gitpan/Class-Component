package Class::Component::Component::SingletonMethod;

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
        bless $self, $singleton_class;
        no strict 'refs';
        unshift @{"$singleton_class\::ISA"}, $pkg;
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

sub load_component_resolver {
    my($self, $component) = @_;

    return unless (my $pkg = ref($self)) =~ s/::_Singletons::\d+$//;
    $component = "$pkg\::Component::$component";
    return unless Class::Inspector->installed($component);
    $component;
}

sub load_plugin_resolver {
    my($self, $plugin) = @_;

    return unless (my $pkg = ref($self)) =~ s/::_Singletons::\d+$//;
    $plugin = "$pkg\::Plugin::$plugin";
    return unless Class::Inspector->installed($plugin);
    $plugin;
}

1;
