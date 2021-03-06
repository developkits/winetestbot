# Merged job steps/tasks
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

WineTestBot::StepsTasks - Job step/tasks collection

=cut

package WineTestBot::StepTask;

use WineTestBot::Config;
use WineTestBot::WineTestBotObjects;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(WineTestBot::WineTestBotItem Exporter);

sub GetTitle
{
  my $self = shift;

  my $Title = "";
  if ($self->Type eq "single")
  {
    if ($self->FileType eq "exe32")
    {
      $Title .= "32 bit ";
    }
    elsif ($self->FileType eq "exe64")
    {
      $Title .= "64 bit ";
    }
    $Title .= $self->CmdLineArg;
  }
  elsif ($self->Type eq "build")
  {
    $Title = "build";
  }
  $Title =~ s/\s*$//;

  if ($Title)
  {
    $Title = $self->VM->Name . " (" . $Title . ")";
  }
  else
  {
    $Title = $self->VM->Name;
  }

  return $Title;
}

package WineTestBot::StepsTasks;

use ObjectModel::BasicPropertyDescriptor;
use ObjectModel::ItemrefPropertyDescriptor;
use ObjectModel::PropertyDescriptor;
use WineTestBot::Steps;
use WineTestBot::Tasks;
use WineTestBot::VMs;
use WineTestBot::WineTestBotObjects;

use vars qw(@ISA @EXPORT @PropertyDescriptors);

require Exporter;
@ISA = qw(WineTestBot::WineTestBotCollection Exporter);
@EXPORT = qw(&CreateStepsTasks);

BEGIN
{
  $PropertyDescriptors[0] =
    CreateBasicPropertyDescriptor("Id", "Id", 1,  1, "N", 4);
  $PropertyDescriptors[1] =
    CreateBasicPropertyDescriptor("StepNo", "Step no", !1,  1, "N", 2);
  $PropertyDescriptors[2] =
    CreateBasicPropertyDescriptor("TaskNo", "Task no", ! 1,  1, "N", 2);
  $PropertyDescriptors[3] =
    CreateBasicPropertyDescriptor("Type", "Step type", !1, 1, "A", 6);
  $PropertyDescriptors[4] =
    CreateBasicPropertyDescriptor("Status", "Status",  !1,  1, "A", 9);
  $PropertyDescriptors[5] =
    CreateItemrefPropertyDescriptor("VM", "VM", !1,  1, \&CreateVMs, ["VMName"]);
  $PropertyDescriptors[6] =
    CreateBasicPropertyDescriptor("Timeout", "Timeout", !1, 1, "N", 4);
  $PropertyDescriptors[7] =
    CreateBasicPropertyDescriptor("FileName", "File name",  !1,  1, "A", 64);
  $PropertyDescriptors[8] =
    CreateBasicPropertyDescriptor("FileType", "File Type",  !1,  1, "A", 64);
  $PropertyDescriptors[9] =
    CreateBasicPropertyDescriptor("CmdLineArg", "Command line args", !1, !1, "A", 256);
  $PropertyDescriptors[10] =
    CreateBasicPropertyDescriptor("ChildPid", "Process id of child process", !1, !1, "N", 5);
  $PropertyDescriptors[11] =
    CreateBasicPropertyDescriptor("Started", "Execution started", !1, !1, "DT", 19);
  $PropertyDescriptors[12] =
    CreateBasicPropertyDescriptor("Ended", "Execution ended", !1, !1, "DT", 19);
  $PropertyDescriptors[13] =
    CreateBasicPropertyDescriptor("TestFailures", "Number of test failures", !1, !1, "N", 5);

}

sub _initialize
{
  my $self = shift;
  my $Job = $_[0];

  $self->SUPER::_initialize(@_);

  my $Steps = $Job->Steps;
  foreach my $StepKey (@{$Steps->GetKeys()})
  {
    my $Step = $Steps->GetItem($StepKey);
    my $Tasks = $Step->Tasks;
    foreach my $TaskKey (@{$Tasks->GetKeys()})
    {
      my $Task = $Tasks->GetItem($TaskKey);
      my $StepTask = $self->CreateItem();
      $StepTask->Id(100 * $Step->No + $Task->No);
      $StepTask->StepNo($Step->No);
      $StepTask->TaskNo($Task->No);
      $StepTask->Type($Step->Type);
      $StepTask->Status($Task->Status);
      $StepTask->VM($Task->VM);
      $StepTask->Timeout($Task->Timeout);
      if ($Step->InStaging)
      {
        my $FileName = $Step->FileName;
        if ($FileName =~ m/^[\da-fA-F]+ (.*)$/)
        {
          $StepTask->FileName("$1");
        }
        else
        {
          $StepTask->FileName("unknown");
        }
      }
      else
      {
        $StepTask->FileName($Step->FileName);
      }
      $StepTask->FileType($Step->FileType);
      $StepTask->CmdLineArg($Task->CmdLineArg);
      $StepTask->ChildPid($Task->ChildPid);
      $StepTask->Started($Task->Started);
      $StepTask->Ended($Task->Ended);
      $StepTask->TestFailures($Task->TestFailures);

      $self->{Items}{$StepTask->GetKey()} = $StepTask;
    }
  }

  $self->{Loaded} = 1;
}

sub CreateItem
{
  my $self = shift;

  return WineTestBot::StepTask->new($self);
}

sub CreateStepsTasks
{
  my $Job = shift;

  return WineTestBot::StepsTasks->new(undef, "Tasks", undef,
                                      \@PropertyDescriptors, $Job);
}

1;
