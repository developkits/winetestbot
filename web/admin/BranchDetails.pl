# Branch details page
#
# Copyright 2010 VMware, Inc.
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

package BranchDetailsPage;

use ObjectModel::CGI::ItemPage;
use WineTestBot::Config;
use WineTestBot::Branches;

@BranchDetailsPage::ISA = qw(ObjectModel::CGI::ItemPage);

sub _initialize
{
  my $self = shift;

  $self->SUPER::_initialize(@_, CreateBranches());
}

package main;

my $Request = shift;

my $BranchDetailsPage = BranchDetailsPage->new($Request, "admin");
$BranchDetailsPage->GeneratePage();
