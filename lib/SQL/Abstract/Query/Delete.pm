package SQL::Abstract::Query::Delete;
use Moose;
use namespace::autoclean;

=head1 NAME

SQL::Abstract::Query::Delete - An object that represents a SQL DELETE.

=head1 DESCRIPTION

The delete query is a very lightweight wrapper around L<SQL::Abstract>'s delete()
method and provides no additional SQL syntax.

=cut

with 'SQL::Abstract::Query::Base';

around 'BUILDARGS' => sub{
    my $orig  = shift;
    my $class = shift;

    if (@_ and ref($_[0])) {
        my ($query, $table, $where, $attributes) = @_;

        $attributes ||= {};
        my $args = {
            query => $query,
            table => $table,
            %$attributes,
        };

        $args->{where} = $where if $where;

        return $class->$orig( $args );
    }

    return $class->$orig( @_ );
};

=head1 ATTRIBUTES

=head2 table

The table to delete rows from.  Gets passed straight on to L<SQL::Abstract>.

=cut

has table => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

=head2 where

The where clause, optional.  Gets passed on, unmodified, to L<SQL::Abstract>.

=cut

has where => (
    is => 'ro',
    isa => 'HashRef|ArrayRef|Str',
);

sub _build_abstract_result {
    my ($self) = @_;

    my ($sql, @bind_values) = $self->query->abstract->delete(
        $self->table(),
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

