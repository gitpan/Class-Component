package Class::Component::Plugin;

use strict;
use warnings;
use base qw( Class::Accessor::Fast Class::Data::Inheritable );

__PACKAGE__->mk_accessors(qw/ config /);
__PACKAGE__->mk_classdata( '__attr_cache' => {} );

use Carp::Clan qw/Class::Component/;
use Class::Inspector;
use UNIVERSAL::require;

sub new {
    my($class, $config) = @_;
    my $self = bless {}, $class;
    $self->config($config);
    $self->init;
    $self;
}

sub init {}

sub register {
    my($self, $c) = @_;

    for my $method (@{ Class::Inspector->methods(ref $self) || [] }) {
        next unless my $code = $self->can($method);
        next unless my $attrs = $self->__attr_cache->{$code};

        for my $attr (@{ $attrs }) {
            next unless my($key, $value) = ($attr =~ /^(.*?)(?:\(\s*(.+?)\s*\))?$/);
            if (defined $value) {
                ($value =~ s/^'(.*)'$/$1/) || ($value =~ s/^"(.*)"$/$1/);
            }

            my $attr_class = "Class::Component::Attribute::$key";
            next unless Class::Inspector->installed($attr_class);
            $attr_class->require or croak "'$key' is not supported attribute";
            $attr_class->register($self, $c, $method, $value, $code);
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

    package MyClass::Plugin::Hello;
    use strict;
    use warnings;
    use base 'Class::Component::Plugin';
    sub hello :Method {
        my($self, $context, $args) = @_;
        'hello'
    }
    sub hello_hook :Hook('hello') {
        my($self, $context, $args) = @_;
        'hook hello'
    }

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
