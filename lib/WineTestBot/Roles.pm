# Role collection and items
#
# Copyright 2009 Ge van Geldorp
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA

use strict;

=head1 NAME

WineTestBot::Roles - Role collection

=cut

package WineTestBot::Role;

use WineTestBot::WineTestBotObjects;

use vars qw (@ISA @EXPORT);

require Exporter;
@ISA = qw(WineTestBot::WineTestBotItem Exporter);

sub HasRole
{
  my $self = shift;
  my $RoleName = shift;
}

package WineTestBot::Roles;

use ObjectModel::PropertyDescriptor;
use ObjectModel::BasicPropertyDescriptor;
use WineTestBot::WineTestBotObjects;

use vars qw (@ISA @EXPORT @PropertyDescriptors);

require Exporter;
@ISA = qw(WineTestBot::WineTestBotCollection Exporter);
@EXPORT = qw(&CreateRoles);

BEGIN
{
  $PropertyDescriptors[0] =
    CreateBasicPropertyDescriptor("Name", "Role name", 1,  1, "A", 40);
  $PropertyDescriptors[1] =
    CreateBasicPropertyDescriptor("IsDefaultRole", "Should new users get this role by default", !1, 1, "B", 1);
}

sub CreateItem
{
  my $self = shift;

  return WineTestBot::Role->new($self);
}

sub CreateRoles
{
  return WineTestBot::Roles::->new("Roles", "Roles", "Role",
                                   \@PropertyDescriptors);
}

1;
