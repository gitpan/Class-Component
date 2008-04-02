package Class::Component::Plugin;

use strict;
use warnings;
use base qw( Class::Accessor::Fast Class::Data::Inheritable );

__PACKAGE__->mk_accessors(qw/ config /);
__PACKAGE__->mk_classdata( '__attr_cache' => {} );
__PACKAGE__->mk_classdata( '__methods_cache' );

use Carp::Clan qw/Class::Component/;
use Class::Inspector;
use UNIVERSAL::require;

sub new {
    my($class, $config, $c) = @_;
    my $self = bless {}, $class;
    $self->config($config);
    $self->init($c);
    $self;
}

sub init {}

sub class_component_plugin_attribute_detect {
    my($self, $attr) = @_;
    return unless my($key, $value) = ($attr =~ /^(.*?)(?:\(\s*(.+?)\s*\))?$/);
    return ($key, $value) unless defined $value;

    my $pkg    = ref $self;
    # from Attribute::Handlers
    my $evaled = eval "package $pkg; no warnings; local \$SIG{__WARN__} = sub{ die \@_ }; [$value]"; ## no critic
    $@ and croak "$pkg: $value: $@";
    my $data   = $evaled || [$value];
    $value     = (@{ $data } > 1) ? $data : $data->[0];

    return ($key, $value);
}

sub register {
    my($self, $c) = @_;

    unless ($self->__methods_cache) {
        my @methods;
        for my $method (@{ Class::Inspector->methods(ref $self) || [] }) {
            next unless my $code = $self->can($method);
            next unless my $attrs = $self->__attr_cache->{$code};
            push @methods, { method => $method, code => $code, attrs => $attrs };
        }
        $self->__methods_cache( \@methods );
    }
    for my $data (@{ $self->__methods_cache }) {
        for my $attr (@{ $data->{attrs} }) {
            next unless my($key, $value) = $self->class_component_plugin_attribute_detect($attr);

            for my $isa_pkg (@{ Class::Component::Implement->isa_list_cache($c) }) {
                my $attr_class = "$isa_pkg\::Attribute::$key";
                next unless Class::Inspector->installed($attr_class);
                $attr_class->require or croak "'$key' is not supported attribute";
                $attr_class->register($self, $c, $data->{method}, $value, $data->{code});
            }
        }
    }
}

sub MODIFY_CODE_ATTRIBUTES {
    my($class, $code, @attrs) = @_;
    $class->__attr_cache->{$code} = [@attrs];
    return ();
}

1;
__END__

=head1 NAME

Class::Component::Plugin - plugin base for pluggable component framework

=head1 SYNOPSIS

Your plugins should succeed to Class::Component::Plugin by your name space, and use it. 

    package MyClass::Plugin;
    use strict;
    use warnings;
    use base 'Class::Component::Plugin';
    1;

for instance, the init phase is rewritten. 

    package MyClass::Plugin;
    use strict;
    use warnings;
    use base 'Class::Component::Plugin';
    __PACKAGE__->mk_accessors(qw/ base_config /);

    sub init {
        my($self, $c) = @_;
        $self->base_config($self->config);
        $self->config($self->config->{config});
    }
    1;


    package MyClass::Plugin::Hello;
    use strict;
    use warnings;
    use base 'MyClass::Plugin';
    sub hello :Method {
        my($self, $context, $args) = @_;
        'hello'
    }
    sub hello_hook :Hook('hello') {
        my($self, $context, $args) = @_;
        'hook hello'
    }

=head1 HOOK POINTS

=over 4

=item init

init phase your plugins

=item class_component_plugin_attribute_detect

=back

=head1 ATTRIBUTES

=over 4

=item Method

register_method is automatically done. 

=item Hook

register_hook is automatically done. 

=back

=head1 AUTHOR

Kazuhiro Osawa E<lt>ko@yappo.ne.jpE<gt>

=head1 SEE ALSO

L<Class::Component>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
