package SQL::Abstract::Query::Select;
use Moose;
use namespace::autoclean;

=head1 NAME

SQL::Abstract::Query::Select - An object that represents a SQL SELECT.

=head1 SYNOPSIS

You'll need to create an L<SQL::Abstract::Query> object first:

    use SQL::Abstract::Query;
    my $query = SQL::Abstract::Query->new();

Now you can create a select object and use it:

    my $select = $query->select(
        [qw( name email )],
        'users',
        { is_admin => 'is_admin', age => {'>=', 'min_age'} },
        \%attributes,
    );
    
    my $sql = $select->sql();
    my $sth = $dbh->prepare( $sql );
    
    my @bind_values = $select->values({ is_admin => 1, min_age => 18 });
    $sth->execute( @bind_values );
    
    while (my $row = $sth->fetchrow_array()) {
        print "$row->{name}: $row->{email}\n";
    }

Or you can bypass object creation and use an interface very similar
to L<SQL::Abstract>'s:

    my ($sql, @bind_values) = $query->select(
        [qw( name email )],
        'users',
        { is_admin => 1, age => {'>=', 18} },
        \%attributes,
    );

=head1 DESCRIPTION

This module extends L<SQL::Abstract>'s select() method by wrapping it
up in to an object that can be re-used and adding additional functionality.

=cut

with 'SQL::Abstract::Query::Base';

use Carp qw( croak );
use Clone qw( clone );
use List::MoreUtils qw( zip any );
use List::Util qw( first );

around 'BUILDARGS' => sub{
    my $orig  = shift;
    my $class = shift;

    if (@_ and ref($_[0])) {
        my ($query, $fields, $from, $where, $attributes) = @_;

        $attributes ||= {};
        my $args = {
            query  => $query,
            fields => $fields,
            from   => $from,
            %$attributes,
        };

        $args->{where} = $where if $where;

        return $class->$orig( $args );
    }

    return $class->$orig( @_ );
};

=head1 ATTRIBUTES

=head2 fields

An array ref of field names or a scalar.  This is passed unmodified to
L<SQL::Abstract>.

=cut

has fields => (
    is       => 'ro',
    isa      => 'ArrayRef|Str',
    required => 1,
);

=head2 from

The FROM section of the SELECT query.  Can be either a Scalar which will be quoted,
an array ref of either scalars or arrays, or a scalar ref wich will not be quoted.

A single table, quoted:

    from => 'users'
    FROM "users"

An arbitrary string, not quoted:

    from => \'users'
    FROM users

A list of table names, some may be quoted, some not, separated by commas:

    from => ['users', \'user_emails']
    FROM "users", user_emails

A list of table names, the first one with an alias:

    from => [ {name => users, as => 'u'}, 'user_emails' ]
    FROM "users" "u", "user_emails"

A join with aliases:

    from => [ {users => 'u'}, {user_emails => e, using => 'user_id'} ]
    FROM "users" "u" JOIN "user_emails" "e" ON ( "e"."user_id" = "u"."user_id" )

Another join but using "on" instead of "using", and adding another non-join table:

    from => [ {users => 'u'}, {user_emails => 'e', on=>{ 'e.user_id' => \'= u.user_id' }}, 'logs' ]
    FROM "users" "u" JOIN "user_emails" "e" ON ( "e"."user_id" = u.user_id ), logs

Note that the FROM part of the SELECT is not handled by L<SQL::Abstract> at all.

=cut

has from => (
    is       => 'ro',
    isa      => 'Str|ArrayRef[Str|HashRef]|ScalarRef',
    required => 1,
);

=head2 where

The WHERE clause which can be a hash ref, an array ref, or a scalar.  This gets
passed to L<SQL::Abstract> unmodified.

=cut

has where => (
    is => 'ro',
    isa => 'HashRef|ArrayRef|Str',
);

=head2 group_by

The GROUP BY clause which can be a scalar or an array reference.  L<SQL::Abstract>
does not natively support GROUP BY so this module generates the SQL itself.  Here are
some samples:

Group by a single column:

    group_by => 'foo'
    GROUP BY "foo"

Group by several columns:

    group_by => ['foo', 'bar']
    GROUP BY "foo", "bar"

=cut

has group_by => (
    is  => 'ro',
    isa => 'Str|ArrayRef',
);

=head2 order_by

The ORDER BY clause which can be a scalar or an array reference.  This order_by
is not processed by L<SQL::Abstract> at all and is instead handled by this module
completely.  Here are some samples of valid input and what the SQL would look like:

Order by a single column:

    order_by => 'foo'
    ORDER BY "foo"

Order by several columns:

    order_by => ['foo', 'bar']
    ORDER BY "foo", "bar"

Order by several columns, setting the ordering direction:

    order_by => [ [foo => 'asc'], 'bar' ]
    ORDER BY "foo" ASC, "bar"

=cut

has order_by => (
    is  => 'ro',
    isa => 'Str|HashRef|ArrayRef',
);

=head2 limit

The maximum number of rows that the query should return.  This can
be either an integer or a string for use with values().

=cut

has limit => (
    is => 'ro',
    isa => 'Str',
);

=head2 offset

The number of rows to offset the query by.  For example, if you had 20
rows and set the limit to 10 and the offset to 5 you'd get rows 5
through 14 (where row 1 is the first row).  The setting of offset will
be ignored if the limit is not also set.

This can be either an integer or a string for use with values().

=cut

has offset => (
    is  => 'ro',
    isa => 'Str',
);

sub _build_abstract_result {
    my ($self) = @_;

    my ($from, @from_values) = $self->_apply_from();

    my ($sql, @bind_values) = $self->query->abstract->select(
        $from,
        $self->fields(),
        $self->where(),
    );

    $self->_apply_group_by( \$sql );

    $self->_apply_order_by( \$sql );

    $self->_apply_limit( \$sql, \@bind_values );

    return [$sql, @from_values, @bind_values];
}

sub _apply_from {
    my ($self) = @_;

    my $from = $self->from();
    return $from if ref($from) ne 'ARRAY';

    my $abstract = $self->query->abstract();

    my $sql = '';
    my @bind_values;
    my $previous_table;
    foreach my $table (@$from) {
        if (!ref $table) {
            $sql .= ', ' if $sql;
            $sql .= $self->_quote( $table );
            $previous_table = { name => $table, common => $table };
            next;
        }
        elsif (ref($table) eq 'SCALAR') {
            $sql .= ', ' if $sql;
            $sql .= $table;
            next;
        }
        elsif (ref($table) ne 'HASH') {
            croak 'A non scalar or hash entry found in the from attribute';
        }

        $table = clone( $table );

        if (!$table->{name}) {
            my $key = first {
                my $key = $_;
                return (any { $key eq $_ } qw( on using join )) ? 0 : 1;
            } keys %$table;
            $table->{name} = $key;
            $table->{as}   = $table->{$key};
        }

        $table->{common} = $table->{as} || $table->{name};

        my $is_join = ($table->{join} or $table->{on} or $table->{using}) ? 1 : 0;

        if ($sql) {
            $sql .= ',' if !$is_join;
            $sql .= ' ';
        }

        my @parts;

        if ($is_join) {
            if ($table->{join}) {
                push @parts, 'LEFT' if $table->{join} eq 'left';
            }
            push @parts, 'JOIN';
        }

        push @parts, $self->_quote( $table->{name} );
        push @parts, $self->_quote( $table->{as} ) if $table->{as};

        if ($table->{using}) {
            my $right = '= ' . $self->_quote( $previous_table->{common} . '.' . $table->{using} );
            $table->{on} = { $table->{common} . '.' . $table->{using} => \$right };
        }

        if ($table->{on}) {
            my ($where_sql, @where_values) = $abstract->where( $table->{on} );
            $where_sql =~ s{^ WHERE }{}s;

            # SQL::Abstract has an annoying habit if adding too many braces in some situations.
            my $start_braces = ($where_sql =~ m{^([( ]+)}s)[0];
            my $end_braces = ($where_sql =~ m{([) ]+)$}s)[0];
            $start_braces =~ s{ }{}g;
            $end_braces =~ s{ }{}g;
            my $braces_count = (length($start_braces) <= length($end_braces)) ? length($start_braces) : length($end_braces);
            foreach (1..$braces_count) {
                $where_sql =~ s{^ *\( *(.+?) *\) *$}{$1};
            }

            push @parts, 'ON', '(', $where_sql, ')';
            push @bind_values, @where_values;
        }

        $sql .= join(' ', @parts);
        $previous_table = $table;
    }

    return( \$sql, @bind_values );
}

sub _apply_group_by {
    my ($self, $sql) = @_;

    my $group_by = $self->group_by();
    return if !$group_by;

    my $abstract = $self->query->abstract();

    $$sql .= ' GROUP BY ';
    if (ref $group_by) {
        $$sql .= join(', ', map { $self->_quote( $_ ) } @$group_by);
    }
    else {
        $$sql .= $self->_quote( $group_by );
    }

    return;
}

sub _apply_order_by {
    my ($self, $sql) = @_;

    my $order_by = $self->order_by();
    return if !$order_by;

    my $abstract = $self->query->abstract();

    $$sql .= ' ORDER BY ';
    if (ref $order_by) {
        my @parts;
        foreach my $field (@$order_by) {
            if (ref($field) eq 'ARRAY' and @$field==2) {
                push @parts, $self->_quote( $field->[0] ) . ' ' . uc( $field->[1] );
                next;
            }

            push @parts, $self->_quote( $field );
        }

        $$sql .= join(', ', @parts);
    }
    else {
        $$sql .= $self->_quote( $order_by );
    }

    return;
}

sub _apply_limit {
    my ($self, $sql, $bind_values) = @_;

    my $limit = $self->limit();

    return if !$limit;

    my $offset = $self->offset();
    my $abstract = $self->query->abstract();
    my $dialect = $self->query->limit_dialect();

    if ($dialect eq 'offset') {
        $$sql .= ' LIMIT ?';
        push @$bind_values, $limit;

        if (defined $offset) {
            $$sql .= ' OFFSET ?';
            push @$bind_values, $offset;
        }
    }
    elsif ($dialect eq 'xy') {
        $$sql .= ' LIMIT';
        if (defined $offset) {
            $$sql .= ' ?,';
            push @$bind_values, $offset;
        }
        $$sql .= ' ?';
        push @$bind_values, $limit;
    }
    elsif ($dialect eq 'rownum') {
        my $inner_table   = $self->_quote('A');
        my $outer_table   = $self->_quote('B');
        my $rownum_column = $self->_quote('r');

        $$sql = "SELECT * FROM ( SELECT $inner_table.*, ROWNUM $rownum_column FROM ( " . $$sql . " ) $inner_table WHERE ROWNUM <= ? + ? ) $outer_table WHERE $rownum_column > ?";
        push @$bind_values, $limit, $offset, $offset;
    }

    return;
}

__PACKAGE__->meta->make_immutable;
1;
__END__

=head1 AUTHOR

Aran Clary Deltac <bluefeet@gmail.com>

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

