package SQL::Abstract::Query::Update;
use Moose;
use namespace::autoclean;

=head1 NAME

SQL::Abstract::Query::Update - An object that represents a SQL UPDATE.

=cut

with 'SQL::Abstract::Query::Base';

around 'BUILDARGS' => sub{
    my $orig  = shift;
    my $class = shift;

    if (@_ and ref($_[0])) {
        my ($query, $table, $field_values, $where, $attributes) = @_;

        $attributes ||= {};
        my $args = {
            query        => $query,
            table        => $table,
            field_values => $field_values,
            %$attributes,
        };

        $args->{where} = $where if $where;

        return $class->$orig( $args );
    }

    return $class->$orig( @_ );
};

=head1 ATTRIBUTES

=head2 table

=cut

has table => (
    is       => 'ro',
    isa      => 'SQL::Abstract::Query::Types::Table',
    required => 1,
);

=head2 field_values

=cut

has field_values => (
    is       => 'ro',
    isa      => 'SQL::Abstract::Query::Types::FieldValues',
    coerce   => 1,
    required => 1,
);

=head2 where

=cut

has where => (
    is => 'ro',
    isa => 'HashRef|ArrayRef|Str',
);

sub _build_abstract_result {
    my ($self) = @_;

    my $abstract = $self->query->abstract();

    my ($sql, @bind_values) = $abstract->update(
        $self->table(),
        $self->field_values(),
        $self->where(),
    );

    return [$sql, @bind_values];
}

__PACKAGE__->meta->make_immutable;
1;
__END__

=head1 AUTHOR

Aran Clary Deltac <bluefeet@gmail.com>

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

