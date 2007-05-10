package Class::Component;

use strict;
use warnings;
our $VERSION = '0.03';

for my $method (qw/ load_components load_plugins new register_method register_hook remove_method remove_hook call run_hook NEXT /) {
    no strict 'refs';
    *{__PACKAGE__."::$method"} = sub { Class::Component::Implement->$method(@_) };
}

for my $name (qw/ config components plugins methods hooks /) {
    my $method = "class_component_$name";
    no strict 'refs';
    *{__PACKAGE__."::$method"} = sub { shift->{"_$method"} };
}

sub import {
    my($class, %args) = @_;
    return unless $class eq 'Class::Component';
    my $pkg = caller(0);

    unless ($pkg->isa('Class::Component')) {
        no strict 'refs';
        unshift @{"$pkg\::ISA"}, $class;
    }

    Class::Component::Implement->init($pkg, %args);
}

sub load_component_resolver {}
sub load_plugin_resolver {}

sub class_component_reinitialize {
    my($class, %args) = @_;
    Class::Component::Implement->init($class, %args);
}

package # hide from PAUSE
    Class::Component::Implement;

use strict;
use warnings;
use base qw( Class::Data::Inheritable );

my $default_components = {};
my $default_plugins    = {};
my $reload_plugin_maps = {};

use UNIVERSAL::require;

use Carp::Clan qw/Class::Component/;
use Class::Inspector;

sub init {
    my($class, $c, %args) = @_;
    $c = ref($c) || $c;

    $default_components->{$c} ||= [];
    $default_plugins->{$c}    ||= [];

    delete $reload_plugin_maps->{$c};
    $reload_plugin_maps->{$c} = \&_reload_plugin if $args{reload_plugin};
}

sub shared_configs {
    my($class, $from, $to) = @_;

    $default_components->{$to} = $default_components->{$from};
    $default_plugins->{$to}    = $default_plugins->{$from};
    $reload_plugin_maps->{$to} = $reload_plugin_maps->{$from};
}

sub load_components {
    my($class, $c, @components) = @_;

    for my $component (@components) {
        $class->_load_component($c, $component);
    }
}

sub _load_component {
    my($class, $c, $component, $reload) = @_;
    $c = ref $c || $c;

    my $pkg;
    if (($pkg = $component) =~ s/^\+// || ($pkg = $c->load_component_resolver($component))) {
        if (Class::Inspector->installed($pkg)) {
            $pkg->require or croak $@;
        } else {
            croak "$pkg is not installed";
        }
    } else {
        for my $comp ("$c\::Component::$component", "Class::Component::Component::$component") {
            next unless Class::Inspector->installed($comp);
            $comp->require or croak $@;
            $pkg = $comp;
        }
        croak "$pkg is not installed" unless $pkg;
    }

    unless ($reload) {
        for my $default (@{ $default_components->{$c} }) {
            return if $pkg eq $default;
        }
    }

    no strict 'refs';
    unshift @{"$c\::ISA"}, $pkg;
    push @{ $default_components->{$c} }, $pkg unless $reload;
}

sub load_plugins {
    my($class, $c, @plugins) = @_;

    return $class->load_plugins_default($c, @plugins) unless ref $c;

    for my $plugin (@plugins) {
        $class->_load_plugin($c, $plugin);
    }
}

sub load_plugins_default {
    my($class, $c, @plugins) = @_;

    LOOP:
    for my $plugin (@plugins) {
        for my $default (@{ $default_plugins->{$c} }) {
            next LOOP if $plugin eq $default;
        }
        push @{ $default_plugins->{$c} }, $plugin;
    }
}

sub _load_plugin {
    my($class, $c, $plugin) = @_;

    my $pkg;
    if (($pkg = $plugin) =~ s/^\+// || ($pkg = $c->load_plugin_resolver($plugin))) {
        $pkg->require or croak $@;
    } else {
        $pkg = ref($c) . "::Plugin::$plugin";
        $pkg->require or croak $@;
    }

    my $class_component_plugins = $c->class_component_plugins;
    for my $default (@{ $class_component_plugins }) {
        return if $pkg eq ref($default);
    }

    my $obj = $pkg->new($c->class_component_config->{$plugin} || {});
    push @{ $class_component_plugins }, $obj;
    $obj->register($c);
}

sub new {
    my($class, $c, $args) = @_;
    $args ||= {};

    my $self = bless {
        %{ $args },
        _class_component_plugins         => [],
        _class_component_components      => $default_components->{$c},
        _class_component_methods         => {},
        _class_component_hooks           => {},
        _class_component_config          => $args->{config} || {},
        _class_component_default_plugins => $default_plugins->{$c},
    }, $c;

    $self->load_plugins(@{ $default_plugins->{$c} }, @{ $args->{load_plugins} || [] });

    $self;
}

sub register_method {
    my($class, $c, @methods) = @_;
    while (my($method, $plugin) = splice @methods, 0, 2) {
        $c->class_component_methods->{$method} = $plugin
    }
}

sub register_hook {
    my($class, $c, @hooks) = @_;
    while (my($hook, $obj) = splice @hooks, 0, 3) {
        $c->class_component_hooks->{$hook} = [] unless $c->class_component_hooks->{$hook};
        push @{ $c->class_component_hooks->{$hook} }, $obj;
    }
}

sub remove_method {
    my($class, $c, @methods) = @_;
    while (my($method, $plugin) = splice @methods, 0, 2) {
        next unless ref($c->class_component_methods->{$method}) eq $plugin;
        delete $c->class_component_methods->{$method};
    }
}

sub remove_hook {
    my($class, $c, @hooks) = @_;
    while (my($hook, $remove_obj) = splice @hooks, 0, 3) {
        my $i = -1;
        for my $obj (@{ $c->class_component_hooks->{$hook} }) {
            $i++;
            next unless ref($obj->{plugin}) eq $remove_obj->{plugin} && $obj->{method} eq $remove_obj->{method};
            splice @{ $c->class_component_hooks->{$hook} }, $i, 1;
        }
        delete $c->class_component_hooks->{$hook} unless @{ $c->class_component_hooks->{$hook} };
    }
}

sub call {
    my($class, $c, $method, @args) = @_;
    return unless my $plugin = $c->class_component_methods->{$method};
    $class->reload_plugin($c, $plugin);
    $plugin->$method($c, @args);
}

sub run_hook {
    my($class, $c, $hook, $args) = @_;
    return unless my $hooks = $c->class_component_hooks->{$hook};
    $class->reload_plugin($c, $hooks->[0]->{plugin});

    my @ret;
    for my $obj (@{ $hooks }) {
        my($plugin, $method) = ($obj->{plugin}, $obj->{method});
        my $ret = $plugin->$method($c, $args);
        push @ret, $ret;
    }
    \@ret;
}

sub _reload_plugin {
    my($class, $c, $pkg) = @_;
    return if Class::Inspector->loaded(ref($pkg) || $pkg);

    $default_components->{ref $c} = $c->class_component_components;
    $default_plugins->{ref $c}    = $c->class_component_plugins;

    for my $component (@{ $default_components->{ref $c} }) {
        $class->_load_component($c, '+' . (ref($component) || $component), 1);
    }

    for my $plugin (@{ $c->class_component_plugins }) {
        $class->_load_plugin($c, '+' . (ref($plugin) || $plugin));
    }

}

sub reload_plugin {
    my($class, $c) = @_;
    return unless my $code = $reload_plugin_maps->{ref $c};
    goto $code;
}


sub NEXT {
    my($class, $prot, $method, @args) = @_;
    my $c = ref($prot) || $prot;
    my $from = caller(1);

    my $isa_list = $class->_fetch_isa_list($c);
    my $isa_mark = {};
    $class->_mark_isa_list($isa_list, $isa_mark, 0);
    my @isa = $class->_sort_isa_list($isa_list, $isa_mark, 0);

    my @next_classes;
    my $f = 0;
    for my $pkg (@isa) {
        if ($f) {
            push @next_classes, $pkg;
       } else {
            next unless $pkg eq $from;
            $f = 1;
        }
    }

    for my $pkg (@next_classes) {
        my $next = "$pkg\::$method";
        return $prot->$next(@args) if $pkg->can($method);
    }

    for my $pkg (@next_classes) {
        my $next = "$pkg\::$method";
        return $prot->$next(@args) if $pkg->can('AUTOLOAD');
    }
}

sub _fetch_isa_list {
    my($class, $base) = @_;

    my $isa_list = { pkg => $base, isa => [] };
    no strict 'refs';
    for my $pkg (@{"$base\::ISA"}) {
        push @{ $isa_list->{isa} }, $class->_fetch_isa_list($pkg);
    }
    $isa_list;
}

sub _mark_isa_list {
    my($class, $isa_list, $isa_mark, $nest) = @_;

    for my $list (@{ $isa_list->{isa} }) {
        $class->_mark_isa_list($list, $isa_mark, $nest + 1);
    }
    my $pkg = $isa_list->{pkg};
    $isa_mark->{$pkg} = { nest => $nest, count => 0 } if !$isa_mark->{$pkg} || $isa_mark->{$pkg}->{nest} < $nest;
    $isa_mark->{$pkg}->{count}++;
}

sub _sort_isa_list {
    my($class, $isa_list, $isa_mark, $nest) = @_;

    my @isa;
    my $pkg = $isa_list->{pkg};
    unless (--$isa_mark->{$pkg}->{count}) {
        push @isa, $pkg;
    }

    for my $list (@{ $isa_list->{isa} }) {
        my @ret = $class->_sort_isa_list($list, $isa_mark, $nest + 1);
        push @isa, @ret;
    }

    @isa;
}

package Class::Component;

1;
__END__

=head1 NAME

Class::Component - pluggable component framework

=head1 SYNOPSIS

base class

  package MyClass;
  use strict;
  use warnings;
  use Class::Component;
  __PACKAGE__->load_component(qw/ Autocall /);
  __PACKAGE__->load_plugins(qw/ Default /);

application code

  use strict;
  use warnings;
  use MyClass;
  my $obj = MyClass->new({ load_plugins => [qw/ Hello /] });
  $obj->hello;
  $obj->run_hook( hello => $args );

=head1 DESCRIPTION

Class::Component is pluggable component framework.
The compatibilities such as dump and load such as YAML are good. 

=head1 METHODS

=over 4

=item new

constructor

=item load_components

  __PACKAGE__->load_components(qw/ Sample /);

The candidate is the order of MyClass::Component::Sample and Class::Component::Sample. 
It is used to remove + when there is + in the head. 

=item load_plugins

  __PACKAGE__->load_plugins(qw/ Default /);

The candidate is the MyClass::Plugin::Default.
It is used to remove + when there is + in the head. 

=item register_method

  $obj->register_method( 'method name' => 'MyClass::Plugin::PluginName' );

Method attribute is usually used and set. See Also L<Class::Component::Plugin>. 

=item register_hook

  $obj->register_hook( 'hook name' => { plugin => 'MyClass::Plugin::PluginName', method => 'hook method name' } );

Hook attribute is usually used and set. See Also L<Class::Component::Plugin>.

=item remove_method

  $obj->remove_method( 'method name' => 'MyClass::Plugin::PluginName' );

=item remove_hook

  $obj->remove_hook( 'hook name' => { plugin => 'MyClass::Plugin::PluginName', method => 'hook method name' } );

=item call

  $obj->call('plugin method name' => @args)
  $obj->call('plugin method name' => %args)

=item run_hook

  $obj->run_hook('hook name' => $args)

=back

=head1 PROPERTIES

=over 4

=item class_component_config

=item class_component_components

=item class_component_plugins

=item class_component_methods

=item class_component_hooks

=back

=head1 METHODS for COMPONENT

=over 4

=item NEXT

  $self->NEXT('methods name', @args);

It is behavior near maybe::next::method of Class::C3. 

=item class_component_reinitialize

=back

=head1 INTERFACES

=over 4

=item load_component_resolver

=item load_plugin_resolver

=back

=head1 INITIALIZE OPTIONS

=over 4

=item reload_plugin

  use Class::Component reload_plugin => 1;

or

  MyClass->class_component_reinitialize( reload_plugin => 1 );

Plugin/Component of the object made with YAML::Load etc. is done and require is done automatically. 

=back

=head1 AUTHOR

Kazuhiro Osawa E<lt>ko@yappo.ne.jpE<gt>

=head1 SEE ALSO

L<Class::Component::Plugin>

=head1 EXAMPLE

L<Number::Object>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
