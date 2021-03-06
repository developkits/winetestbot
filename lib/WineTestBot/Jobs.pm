# Job collection and items
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

WineTestBot::Jobs - Job collection

=cut


package WineTestBot::Job;

use WineTestBot::Branches;
use WineTestBot::Engine::Notify;
use WineTestBot::WineTestBotObjects;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(WineTestBot::WineTestBotItem Exporter);

sub _initialize
{
  my $self = shift;

  $self->SUPER::_initialize(@_);

  $self->{OldStatus} = undef;
}

sub InitializeNew
{
  my $self = shift;

  $self->Archived(!1);
  $self->Branch(CreateBranches()->GetDefaultBranch());
  $self->Status("queued");
  $self->Submitted(time());

  $self->SUPER::InitializeNew();
}

sub Status
{
  my $self = shift;

  my $CurrentStatus = $self->SUPER::Status;
  if (! @_)
  {
    return $CurrentStatus;
  }

  my $NewStatus = $_[0];
  if (! defined($CurrentStatus) || $NewStatus ne $CurrentStatus)
  {
    $self->SUPER::Status($NewStatus);
    $self->{OldStatus} = $CurrentStatus;
  }

  return $NewStatus;
}

sub OnSaved
{
  my $self = shift;

  $self->SUPER::OnSaved(@_);

  if (defined($self->{OldStatus}))
  {
    my $NewStatus = $self->Status;
    if ($NewStatus ne $self->{OldStatus})
    {
      JobStatusChange($self->GetKey(), $self->{OldStatus}, $NewStatus);
    }
  }
}

sub UpdateStatus
{
  my $self = shift;

  my $Steps = $self->Steps;
  my $HasQueuedStep = !1;
  my $HasRunningStep = !1;
  my $HasCompletedStep = !1;
  my $HasFailedStep = !1;
  my @SortedSteps = sort { $a->No <=> $b->No } @{$Steps->GetItems()};
  foreach my $Step (@SortedSteps)
  {
    my $Status = $Step->Status;
    if ($Status eq "queued" || $Status eq "running")
    {
      my $Tasks = $Step->Tasks;
      my $HasQueuedTask = !1;
      my $HasRunningTask = !1;
      my $HasCompletedTask = !1;
      my $HasFailedTask = !1;
      foreach my $TaskKey (@{$Tasks->GetKeys()})
      {
        my $Task = $Tasks->GetItem($TaskKey);
        $Status = $Task->Status;
        if ($HasFailedStep && $Status eq "queued")
        {
          $Status = "skipped";
          $Task->Status("skipped");
        }
        $HasQueuedTask = $HasQueuedTask || $Status eq "queued";
        $HasRunningTask = $HasRunningTask || $Status eq "running";
        $HasCompletedTask = $HasCompletedTask || $Status eq "completed";
        $HasFailedTask = $HasFailedTask || $Status eq "failed";
      }
      if ($HasFailedStep)
      {
        $Step->Status("skipped");
      }
      elsif ($HasRunningTask || ($HasQueuedTask && ($HasCompletedTask ||
                                                    $HasFailedTask)))
      {
        $Step->Status("running");
      }
      elsif ($HasFailedTask)
      {
        $Step->Status("failed");
      }
      elsif ($HasCompletedTask || ! $HasQueuedTask)
      {
        $Step->Status("completed");
      }
      else
      {
        $Step->Status("queued");
      }
      $Step->Save();
    }

    $Status = $Step->Status;
    $HasQueuedStep = $HasQueuedStep || $Status eq "queued";
    $HasRunningStep = $HasRunningStep || $Status eq "running";
    $HasCompletedStep = $HasCompletedStep || $Status eq "completed";
    my $Type = $Step->Type;
    $HasFailedStep = $HasFailedStep ||
                     ($Status eq "failed" &&
                      ($Type eq "build" || $Type eq "reconfig"));
  }

  if ($HasRunningStep || ($HasQueuedStep && ($HasCompletedStep ||
                                             $HasFailedStep)))
  {
    $self->Status("running");
  }
  elsif ($HasFailedStep)
  {
    if (! defined($self->Ended))
    {
      $self->Ended(time);
    }
    $self->Status("failed");
  }
  elsif ($HasCompletedStep || ! $HasQueuedStep)
  {
    if (! defined($self->Ended))
    {
      $self->Ended(time);
    }
    $self->Status("completed");
  }
  else
  {
    $self->Status("queued");
  }
  $self->Save();
}

sub Cancel
{
  my $self = shift;

  my $Steps = $self->Steps;
  foreach my $StepKey (@{$Steps->GetKeys()})
  {
    my $Step = $Steps->GetItem($StepKey);
    my $Status = $Step->Status;
    if ($Status eq "queued" || $Status eq "running")
    {
      my $Tasks = $Step->Tasks;
      foreach my $TaskKey (@{$Tasks->GetKeys()})
      {
        my $Task = $Tasks->GetItem($TaskKey);
        if ($Task->Status eq "queued")
        {
          $Task->Status("skipped");
          $Task->Save();
        }
      }
    }
  }

  foreach my $StepKey (@{$Steps->GetKeys()})
  {
    my $Step = $Steps->GetItem($StepKey);
    my $Status = $Step->Status;
    if ($Status eq "queued" || $Status eq "running")
    {
      my $Tasks = $Step->Tasks;
      foreach my $TaskKey (@{$Tasks->GetKeys()})
      {
        my $Task = $Tasks->GetItem($TaskKey);
        if ($Task->Status eq "running")
        {
          if (defined($Task->ChildPid))
          {
            kill "TERM", $Task->ChildPid;
          }
        }
      }
    }
  }

  return undef;
}

sub GetEMailRecipient
{
  my $self = shift;

  if (defined($self->Patch) && defined($self->Patch->FromEMail))
  {
    return $self->Patch->FromEMail;
  }

  if ($self->User->EMail eq "/dev/null")
  {
    return undef;
  }

  return $self->User->GetEMailRecipient();
}

sub GetDescription
{
  my $self = shift;

  if (defined($self->Patch) && defined($self->Patch->FromEMail))
  {
    return $self->Patch->Subject;
  }

  return $self->Remarks;
}


package WineTestBot::Jobs;

use POSIX qw(:errno_h);
use ObjectModel::BasicPropertyDescriptor;
use ObjectModel::DetailrefPropertyDescriptor;
use ObjectModel::ItemrefPropertyDescriptor;
use ObjectModel::PropertyDescriptor;
use WineTestBot::Branches;
use WineTestBot::Config;
use WineTestBot::Log;
use WineTestBot::Patches;
use WineTestBot::Steps;
use WineTestBot::Users;
use WineTestBot::VMs;
use WineTestBot::WineTestBotObjects;

use vars qw(@ISA @EXPORT @PropertyDescriptors);

require Exporter;
@ISA = qw(WineTestBot::WineTestBotCollection Exporter);
@EXPORT = qw(&CreateJobs);

my @PropertyDescriptors;

BEGIN
{
  $PropertyDescriptors[0] =
    CreateBasicPropertyDescriptor("Id", "Job id", 1, 1, "S",  5);
  $PropertyDescriptors[1] =
    CreateBasicPropertyDescriptor("Archived", "Job is archived", !1, 1, "B", 1);
  $PropertyDescriptors[2] =
    CreateItemrefPropertyDescriptor("Branch", "Branch", !1, 1, \&CreateBranches, ["BranchName"]);
  $PropertyDescriptors[3] =
    CreateItemrefPropertyDescriptor("User", "Author", !1, 1, \&WineTestBot::Users::CreateUsers, ["UserName"]);
  $PropertyDescriptors[4] =
    CreateBasicPropertyDescriptor("Priority", "Priority", !1, 1, "N", 1);
  $PropertyDescriptors[5] =
    CreateBasicPropertyDescriptor("Status", "Status", !1, 1, "A", 9);
  $PropertyDescriptors[6] =
    CreateBasicPropertyDescriptor("Remarks", "Remarks", !1, !1, "A", 50);
  $PropertyDescriptors[7] =
    CreateBasicPropertyDescriptor("Submitted", "Submitted", !1, !1, "DT", 19);
  $PropertyDescriptors[8] =
    CreateBasicPropertyDescriptor("Ended", "Ended", !1, !1, "DT", 50);
  $PropertyDescriptors[9] =
    CreateItemrefPropertyDescriptor("Patch", "Submitted from patch", !1, !1, \&WineTestBot::Patches::CreatePatches, ["PatchId"]);
  $PropertyDescriptors[10] =
    CreateDetailrefPropertyDescriptor("Steps", "Steps", !1, !1, \&CreateSteps);
}

sub CreateItem
{
  my $self = shift;

  return WineTestBot::Job->new($self);
}

sub CreateJobs
{
  return WineTestBot::Jobs->new("Jobs", "Jobs", "Job", \@PropertyDescriptors);
}

sub CompareJobPriority
{
  my $Compare = $a->Priority <=> $b->Priority;
  if ($Compare == 0)
  {
    $Compare = $a->Id <=> $b->Id;
  }

  return $Compare;
}

sub CompareTaskStatus
{
  my $Compare = $b->Status cmp $a->Status;
  if ($Compare == 0)
  {
    $Compare = $a->No <=> $b->No;
  }

  return $Compare;
}

sub ScheduleOnHost
{
  my $self = shift;
  my $Host = $_[0];

  my $HostVMs = CreateVMs();
  $HostVMs->FilterHost([$Host]);
  my ($RevertingVMs, $RunningVMs) = $HostVMs->CountRevertingRunningVMs();
  my $PoweredOnExtraVMs = $HostVMs->CountPoweredOnExtraVMs();
  my %DirtyVMsBlockingJobs;

  $self->AddFilter("Status", ["queued", "running"]);
  my @SortedJobs = sort CompareJobPriority @{$self->GetItems()};

  my $DirtyIndex = 0;
  my $RevertPriority;
  foreach my $Job (@SortedJobs)
  {
    my $Steps = $Job->Steps;
    $Steps->AddFilter("Status", ["queued", "running"]);
    my @SortedSteps = sort { $a->No <=> $b->No } @{$Steps->GetItems()};
    if (@SortedSteps != 0)
    {
      my $Step = $SortedSteps[0];
      $Step->HandleStaging($Job->GetKey());
      my $Tasks = $Step->Tasks;
      $Tasks->AddFilter("Status", ["queued", "running"]);
      my @SortedTasks = sort CompareTaskStatus @{$Tasks->GetItems()};
      foreach my $Task (@SortedTasks)
      {
        if ($Task->Status eq "queued" &&
            $HostVMs->ItemExists($Task->VM->GetKey()))
        {
          my $VM = $HostVMs->GetItem($Task->VM->GetKey());
          if ($VM->Status eq "idle" &&
              (! defined($MaxRunningVMs) || $RunningVMs < $MaxRunningVMs) &&
              $RevertingVMs == 0 &&
              (! defined($RevertPriority) || $Job->Priority <= $RevertPriority))
          {
            $VM->Status("running");
            my ($ErrProperty, $ErrMessage) = $HostVMs->Save();
            if (defined($ErrMessage))
            {
              return $ErrMessage;
            }
            $ErrMessage = $Task->Run($Job->Id, $Step->No);
            if (defined($ErrMessage))
            {
              return $ErrMessage;
            }
            $Job->UpdateStatus;
            $RunningVMs++;
          }
          elsif ($VM->Status eq "dirty")
          {
            my $VMKey = $VM->GetKey();
            if (! defined($DirtyVMsBlockingJobs{$VMKey}) ||
                $Job->Priority < $DirtyVMsBlockingJobs{$VMKey})
            {
              $DirtyVMsBlockingJobs{$VMKey} = $DirtyIndex;
              $DirtyIndex++;
            }
          }
        }
      }
    }
  }

  if ($RunningVMs != 0)
  {
    return undef;
  }

  my @DirtyVMsByIndex = sort { $DirtyVMsBlockingJobs{$a} <=> $DirtyVMsBlockingJobs{$b} } keys %DirtyVMsBlockingJobs;
  my $VMKey;
  foreach $VMKey (@DirtyVMsByIndex)
  {
    my $VM = $HostVMs->GetItem($VMKey);
    if (! defined($MaxRevertingVMs) || $RevertingVMs < $MaxRevertingVMs)
    {
      if ($VM->Type eq "extra" || $VM->Type eq "retired")
      {
        if (! defined($MaxExtraPoweredOnVms) || $PoweredOnExtraVMs < $MaxExtraPoweredOnVms)
        {
          $VM->RunRevert();
          $PoweredOnExtraVMs++;
          $RevertingVMs++;
        }
      }
      else
      {
        $VM->RunRevert();
        $RevertingVMs++;
      }
    }
  }
  foreach $VMKey (@{$HostVMs->GetKeys()})
  {
    my $VM = $HostVMs->GetItem($VMKey);
    if (! defined($DirtyVMsBlockingJobs{$VMKey}) &&
        (! defined($MaxRevertingVMs) || $RevertingVMs < $MaxRevertingVMs) &&
        $VM->Status eq 'dirty' && $VM->Type ne "extra" &&
        $VM->Type ne "retired")
    {
      $VM->RunRevert();
      $RevertingVMs++;
    }
  }

  return undef;
}

sub Schedule
{
  my $self = shift;

  my $VMs = CreateVMs();
  my %Hosts;
  foreach my $VMKey (@{$VMs->GetKeys()})
  {
    $Hosts{$VMs->GetItem($VMKey)->VmxHost} = 1;
  }
  my $ErrMessage;
  foreach my $Host (keys %Hosts)
  {
    my $HostErrMessage = $self->ScheduleOnHost($Host);
    if (! defined($ErrMessage))
    {
      $ErrMessage = $HostErrMessage;
    }
  }

  return $ErrMessage;
}

sub Check
{
  my $self = shift;

  $self->AddFilter("Status", ["queued", "running"]);
  foreach my $JobKey (@{$self->GetKeys()})
  {
    my $Job = $self->GetItem($JobKey);
    my $Steps = $Job->Steps;
    my $HasQueuedStep = !1;
    my $HasRunningStep = !1;
    my $HasCompletedStep = !1;
    my $HasFailedStep = !1;
    my @SortedSteps = sort { $a->No <=> $b->No } @{$Steps->GetItems()};
    foreach my $Step (@SortedSteps)
    {
      my $Status = $Step->Status;
      if ($Status eq "queued" || $Status eq "running")
      {
        my $Tasks = $Step->Tasks;
        my $HasQueuedTask = !1;
        my $HasRunningTask = !1;
        my $HasCompletedTask = !1;
        my $HasFailedTask = !1;
        foreach my $TaskKey (@{$Tasks->GetKeys()})
        {
          my $Task = $Tasks->GetItem($TaskKey);
          my $Dead = !1;
          if (defined($Task->ChildPid) && ! kill 0 => $Task->ChildPid)
          {
            $Dead = ($! == ESRCH);
          }
          if ($Dead)
          {
            $Task->ChildPid(undef);
            my $Status = $Task->Status;
            if ($Status eq "queued" || $Status eq "running")
            {
              my $OldUMask = umask(002);
              my $TaskDir = "$DataDir/jobs/" . $Job->Id . "/" .  $Step->No . "/" .
                            $Task->No;
              mkdir $TaskDir;
              my $TASKLOG;
              if (open TASKLOG, ">>$TaskDir/log")
              {
                print TASKLOG "Child process died unexpectedly\n";
                close TASKLOG;
              }
              umask($OldUMask);
              LogMsg "Child process for task ", $Job->Id, "/", $Step->No, "/",
                     $Task->No, " died unexpectedly\n";
              $Task->Status("failed");
  
              my $VM = $Task->VM;
              $VM->Status('dirty');
              $VM->Save();
            }
            $Task->Save();
          }
          $Status = $Task->Status;
          if ($HasFailedStep && $Status eq "queued")
          {
            $Status = "skipped";
            $Task->Status("skipped");
          }
          $HasQueuedTask = $HasQueuedTask || $Status eq "queued";
          $HasRunningTask = $HasRunningTask || $Status eq "running";
          $HasCompletedTask = $HasCompletedTask || $Status eq "completed";
          $HasFailedTask = $HasFailedTask || $Status eq "failed";
        }
        if ($HasFailedStep)
        {
          $Step->Status("skipped");
        }
        elsif ($HasRunningTask || ($HasQueuedTask && ($HasCompletedTask ||
                                                      $HasFailedTask)))
        {
          $Step->Status("running");
        }
        elsif ($HasFailedTask)
        {
          $Step->Status("failed");
        }
        elsif ($HasCompletedTask || ! $HasQueuedTask)
        {
          $Step->Status("completed");
        }
        else
        {
          $Step->Status("queued");
        }
        $Step->Save();
      }

      $Status = $Step->Status;
      $HasQueuedStep = $HasQueuedStep || $Status eq "queued";
      $HasRunningStep = $HasRunningStep || $Status eq "running";
      $HasCompletedStep = $HasCompletedStep || $Status eq "completed";
      my $Type = $Step->Type;
      $HasFailedStep = $HasFailedStep ||
                       ($Status eq "failed" &&
                        ($Type eq "build" || $Type eq "reconfig"));
    }

    if ($HasRunningStep || ($HasQueuedStep && ($HasCompletedStep ||
                                               $HasFailedStep)))
    {
      $Job->Status("running");
    }
    elsif ($HasFailedStep)
    {
      if (! defined($Job->Ended))
      {
        $Job->Ended(time);
      }
      $Job->Status("failed");
    }
    elsif ($HasCompletedStep || ! $HasQueuedStep)
    {
      if (! defined($Job->Ended))
      {
        $Job->Ended(time);
      }
      $Job->Status("completed");
    }
    else
    {
      $Job->Status("queued");
    }
    $Job->Save();
  }

  return undef;
}

sub FilterNotArchived
{
  my $self = shift;

  $self->AddFilter("Archived", [!1]);
}

1;
