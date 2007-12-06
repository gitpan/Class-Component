use inc::Module::Install;
name 'Class-Component';
all_from 'lib/Class/Component.pm';

requires $_ for (qw/
    Carp::Clan
    Class::Accessor::Fast
    Class::Data::Inheritable
    Class::Inspector
    UNIVERSAL::require
/);

features(
    'Plaggerize' => [
        -default => 0,
        recommends('Encode'),
        recommends('YAML'),
    ],
    'ANSI Color Logging for Plaggerize' => [
        -default => 0,
        recommends('Term::ANSIColor'),
    ],
);

build_requires 'Test::More';
#use_test_base;
auto_include;
WriteAll;
