package SQL::Abstract::Query::Base;
use Moose::Role;

=head1 NAME

SQL::Abstract::Query::Base - A role providing base functionality for query objects.

=cut

requires(qw( _build_abstract_result ));

use List::MoreUtils qw( zip );
use Moose::Util::TypeConstraints;

subtype 'SQL::Abstract::Query::Types::FieldValues',
    as 'HashRef';

coerce 'SQL::Abstract::Query::Types::FieldValues',
    from 'ArrayRef',
    via { return { zip( @$_, @$_ ) } };

subtype 'SQL::Abstract::Query::Types::Table',
    as 'Str';

has query => (
    is       => 'ro',
    isa      => 'SQL::Abstract::Query',
    required => 1,
);

has abstract_result => (
    is         => 'ro',
    isa        => 'ArrayRef',
    lazy_build => 1,
);

sub original_values {
    my ($self) = @_;
    return @{ $self->_original_values() };
}

has _original_values => (
    is         => 'ro',
    isa        => 'ArrayRef',
    lazy_build => 1,
);
sub _build__original_values {
    my ($self) = @_;
    my @values = @{ $self->abstract_result() };
    shift( @values );
    return \@values;
}

has sql => (
    is         => 'ro',
    isa        => 'Str',
    lazy_build => 1,
);
sub _build_sql {
    my ($self) = @_;
    return $self->abstract_result->[0];
}

sub call {
    my $class = shift;

    my $self = $class->new( @_ );

    return(
        $self->sql(),
        $self->original_values(),
    );
}

sub values {
    my ($self, $field_values) = @_;

    my @values;
    foreach my $value ($self->original_values()) {
        push @values, $field_values->{$value};
    }

    return @values;
}

sub _quote {
    my $self = shift;
    return $self->query->abstract->_quote( @_ );
}

1;
__END__

=head1 AUTHOR

Aran Clary Deltac <bluefeet@gmail.com>

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

