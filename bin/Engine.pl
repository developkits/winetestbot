#!/usr/bin/perl -Tw
#
# WineTestBot engine
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

my $Dir;
sub BEGIN
{
  $0 =~ m=^(.*)/[^/]*$=;
  $Dir = $1;
}
use lib "$Dir/../lib";

use Errno qw(EAGAIN);
use Fcntl;
use MIME::Parser;
use POSIX ":sys_wait_h";
use Socket;
use ObjectModel::BackEnd;
use WineTestBot::Config;
use WineTestBot::Engine::Events;
use WineTestBot::Jobs;
use WineTestBot::Log;
use WineTestBot::Patches;
use WineTestBot::PendingPatchSets;
use WineTestBot::Utils;
use WineTestBot::VMs;

sub FatalError
{
  LogMsg "Engine: ", @_;

  exit 1;
}

sub HandlePing
{
  return "1pong\n";
}

sub HandleJobSubmit
{
  my $JobKey = $_[0];

  my $Jobs = CreateJobs();
  my $Job = $Jobs->GetItem($JobKey);
  if (! $Job)
  {
    LogMsg "Engine: JobSubmit for non-existing job $JobKey\n";
    return "0Job $JobKey not found";
  }
  # We've already determined that JobKey is valid, untaint it
  $JobKey =~ m/^(.*)$/;
  $JobKey = $1;

  my $ErrMessage;
  my $Steps = $Job->Steps;
  foreach my $StepKey (@{$Steps->GetKeys()})
  {
    my $Step = $Steps->GetItem($StepKey);
    $ErrMessage = $Step->HandleStaging($JobKey);
    if (defined($ErrMessage))
    {
      LogMsg "Engine: staging problem: $ErrMessage\n";
    }
  }

  $ErrMessage = $Jobs->Schedule();
  if (defined($ErrMessage))
  {
    LogMsg "Engine: schedule problem: $ErrMessage\n";
  }

  return "1OK";
}

sub HandleJobStatusChange
{
  my ($JobKey, $OldStatus, $NewStatus) = @_;

  if (! defined($OldStatus) || ! defined($NewStatus))
  {
    LogMsg "Engine: invalid status in jobstatuschange message\n";
    return "0Invalid status";
  }

  # Untaint parameters
  if ($JobKey =~ /^(\d+)$/)
  {
    $JobKey = $1;
  }
  else
  {
    LogMsg "Engine: Invalid JobKey $JobKey in jobstatuschange message\n";
  }

  if ($OldStatus eq "running" && $NewStatus ne "running")
  {
    $ActiveBackEnds{'WineTestBot'}->PrepareForFork();
    my $Pid = fork;
    if (defined($Pid) && ! $Pid)
    {
      exec("$BinDir/${ProjectName}SendLog.pl $JobKey");
    }
    if (defined($Pid) && ! $Pid)
    {
      LogMsg "Engine: Unable to exec ${ProjectName}SendLog.pl : $!\n";
      exit;
    }
    if (! defined($Pid))
    {
      LogMsg "Engine: Unable to fork for ${ProjectName}SendLog.pl : $!\n";
    }
  }

  return "1OK";
}

sub HandleJobCancel
{
  my $JobKey = $_[0];

  my $Job = CreateJobs()->GetItem($JobKey);
  if (! $Job)
  {
    LogMsg "Engine: JobCancel for non-existing job $JobKey\n";
    return "0Job $JobKey not found";
  }
  # We've already determined that JobKey is valid, untaint it
  $JobKey =~ m/^(.*)$/;
  $JobKey = $1;

  my $ErrMessage = $Job->Cancel();
  if (defined($ErrMessage))
  {
    LogMsg "Engine: cancel problem: $ErrMessage\n";
    return "0$ErrMessage";
  }

  return "1OK";
}

sub HandleTaskComplete
{
  my $ErrMessage = CreateJobs()->Schedule();
  if (defined($ErrMessage))
  {
    LogMsg "Engine: schedule problem in HandleTaskComplete: $ErrMessage\n";
  }

  return "1OK";
}

sub HandleVMStatusChange
{
  my ($VMKey, $OldStatus, $NewStatus) = @_;

  if (! defined($OldStatus) || ! defined($NewStatus))
  {
    LogMsg "Engine: invalid status in vmstatuschange message\n";
    return "0Invalid status";
  }

  if ($OldStatus eq "reverting" || $OldStatus eq "running" ||
      $NewStatus eq "idle" || $NewStatus eq "dirty")
  {
    my $ErrMessage = CreateJobs()->Schedule();
    if (defined($ErrMessage))
    {
      LogMsg "Engine: schedule problem in HandleVMStatusChange: $ErrMessage\n";
      return "0$ErrMessage";
    }
  }

  return "1OK";
}

sub CheckForWinetestUpdate
{
  my $Bits = $_[0];

  $ActiveBackEnds{'WineTestBot'}->PrepareForFork();
  my $Pid = fork;
  if (defined($Pid) && ! $Pid)
  {
    exec("$BinDir/CheckForWinetestUpdate.pl $Bits");
  }
  if (defined($Pid) && ! $Pid)
  {
    LogMsg "Engine: Unable to exec CheckForWinetestUpdate.pl : $!\n";
    exit;
  }
  if (! defined($Pid))
  {
    LogMsg "Engine: Unable to fork for CheckForWinetestUpdate.pl : $!\n";
  }
}

sub CheckForWinetestUpdate32
{
  CheckForWinetestUpdate(32);
}

sub CheckForWinetestUpdate64
{
  CheckForWinetestUpdate(64);
}

sub GiveUpOnWinetestUpdate
{
  DeleteEvent("CheckForWinetestUpdate32");
  DeleteEvent("CheckForWinetestUpdate64");
  LogMsg "Engine: Giving up on winetest.exe update\n";
}

sub HandleExpectWinetestUpdate
{
  if (EventScheduled("GiveUpOnWinetestUpdate"))
  {
    DeleteEvent("GiveUpOnWinetestUpdate");
  }
  else
  {
    AddEvent("CheckForWinetestUpdate32", 300, 1, \&CheckForWinetestUpdate32);
    AddEvent("CheckForWinetestUpdate64", 300, 1, \&CheckForWinetestUpdate64);
  }
  AddEvent("GiveUpOnWinetestUpdate", 3660, 0, \&GiveUpOnWinetestUpdate);

  return "1OK";
}

sub HandleFoundWinetestUpdate
{
  my $Bits = $_[0];

  if ($Bits =~ m/^(32|64)$/)
  {
    $Bits = $1;
  }
  else
  {
    LogMsg "Engine: invalid number of bits in foundwinetestupdate message\n";
    return "0Invalid number of bits";
  }

  DeleteEvent("CheckForWinetestUpdate${Bits}");
  if (! EventScheduled("CheckForWinetestUpdate32") &&
      ! EventScheduled("CheckForWinetestUpdate64"))
  {
    DeleteEvent("GiveUpOnWinetestUpdate");
  }

  my $ErrMessage = CreateJobs()->Schedule();
  if (defined($ErrMessage))
  {
    LogMsg "Engine: schedule problem in HandleFoundWinetestUpdate: $ErrMessage\n";
  }

  return "1OK";
}

sub HandleNewWinePatchesSubmission
{
  # Validate file name
  if ($_[0] !~ m/([0-9a-fA-F]{32}_wine-patches)/)
  {
    return "0Invalid file name";
  }
  my $FullMessageFileName = "$DataDir/staging/$1";

  # Create a working dir
  my $WorkDir = "$DataDir/staging/" . GenerateRandomString(32) . "_work";
  while (-e $WorkDir)
  {
    $WorkDir = "$DataDir/staging/" . GenerateRandomString(32) . "_work";
  }
  mkdir $WorkDir;

  # Process the patch
  my $Parser = new MIME::Parser;
  $Parser->output_dir($WorkDir);
  my $Entity = $Parser->parse_open($FullMessageFileName);
  CreatePatches()->NewSubmission($Entity);

  # Clean up
  system("rm -rf $WorkDir");
  unlink($FullMessageFileName);

  return "1OK";
}

sub HandlePatchNotification
{
  # Validate file name
  if ($_[0] !~ m/([0-9a-fA-F]{32}_patchnotification)/)
  {
    return "0Invalid file name";
  }
  my $FullMessageFileName = "$DataDir/staging/$1";

  my $LatestPatchId;
  if (open(NOTIFICATION, "<$FullMessageFileName"))
  {
    my $Line;
    while (defined($Line = <NOTIFICATION>) && ! defined($LatestPatchId))
    {
      if ($Line =~ m/^The latest patch is (\d+)$/)
      {
        $LatestPatchId = $1;
      }
    }
    close(NOTIFICATION);
  }

  unlink($FullMessageFileName);

  if (! defined($LatestPatchId))
  {
    return "0No patch id found in message";
  }

  my $MaxExistingPatchId = 0;
  my $Patches = CreatePatches();
  foreach my $PatchKey (@{$Patches->GetKeys()})
  {
    if ($MaxExistingPatchId < $Patches->GetItem($PatchKey)->Id)
    {
      $MaxExistingPatchId = $Patches->GetItem($PatchKey)->Id;
    }
  }

  if ($MaxExistingPatchId < $LatestPatchId)
  {
    $ActiveBackEnds{'WineTestBot'}->PrepareForFork();
    my $Pid = fork;
    if (defined($Pid) && ! $Pid)
    {
      exec("$BinDir/RetrievePatches.pl " . ($MaxExistingPatchId + 1) . " " .
           $LatestPatchId);
    }
    if (defined($Pid) && ! $Pid)
    {
      LogMsg "Engine: Unable to exec RetrievePatches.pl : $!\n";
      exit;
    }
    if (! defined($Pid))
    {
      LogMsg "Engine: Unable to fork for RetrievePatches.pl : $!\n";
    }
  }

  return "1OK";
}

sub HandlePatchRetrieved
{
  # Validate file name
  if ($_[0] !~ m/([0-9a-fA-F]{32}_patch_\d+)/)
  {
    return "0Invalid file name";
  }
  my $FullFileName = "$DataDir/staging/$1";
  if ($_[1] !~ m/^(\d+)$/)
  {
    return "0Invalid patch id";
  }
  my $PatchId = $1;
  my $Patches = CreatePatches();
  if (defined($Patches->GetItem($PatchId)))
  {
    LogMsg "Engine: patch $PatchId already exists\n";
    return "1OK";
  }

  # Create a working dir
  my $WorkDir = "$DataDir/staging/" . GenerateRandomString(32) . "_work";
  while (-e $WorkDir)
  {
    $WorkDir = "$DataDir/staging/" . GenerateRandomString(32) . "_work";
  }
  mkdir $WorkDir;

  # Process the patch
  my $Parser = new MIME::Parser;
  $Parser->output_dir($WorkDir);
  my $Entity = $Parser->parse_open($FullFileName);
  my $ErrMessage = CreatePatches()->NewPatch($PatchId, $Entity);

  # Clean up
  system("rm -rf $WorkDir");
  unlink($FullFileName);

  return defined($ErrMessage) ? "0" . $ErrMessage : "1OK";
}

sub HandleBuildNotification
{
  # Validate build number
  if ($_[0] !~ m/^(\d+)$/)
  {
    return "0Invalid build number";
  }
  my $BuildNo = $1;

  $ActiveBackEnds{'WineTestBot'}->PrepareForFork();
  my $Pid = fork;
  if (defined($Pid) && ! $Pid)
  {
    exec("$BinDir/${ProjectName}RetrieveBuild.pl $BuildNo");
  }
  if (defined($Pid) && ! $Pid)
  {
    LogMsg "Engine: Unable to exec ${ProjectName}BuildHandler.pl : $!\n";
    exit;
  }
  if (! defined($Pid))
  {
    LogMsg "Engine: Unable to fork for ${ProjectName}BuildHandler.pl : $!\n";
  }

  return "1OK";
}

sub HandleGetScreenshot
{
  # Validate VM name
  if ($_[0] !~ m/^(\w+)$/)
  {
    LogMsg "Engine: GetScreenshot: invalid VM name\n";
    return "0Invalid VM name";
  }
  my $VMName = $1;

  my $VMs = CreateVMs();
  my $VM = $VMs->GetItem($VMName);
  if (! defined($VM))
  {
    LogMsg "Engine: GetScreenshot: unknown VM $VMName\n";
    return "0Unknown VM $VMName";
  }

  my ($ErrMessage, $ImageSize, $ImageBytes) = $VM->CaptureScreenImage();
  if (defined($ErrMessage))
  {
    LogMsg "Engine: GetScreenshot: $ErrMessage\n";
    return "0$ErrMessage";
  }

  return "1" . $ImageBytes;;
}

sub HandleClientCmd
{
  my $Cmd = shift;
  if ($Cmd eq "ping")
  {
    return HandlePing(@_);
  }
  if ($Cmd eq "jobsubmit")
  {
    return HandleJobSubmit(@_);
  }
  if ($Cmd eq "jobstatuschange")
  {
    return HandleJobStatusChange(@_);
  }
  if ($Cmd eq "jobcancel")
  {
    return HandleJobCancel(@_);
  }
  if ($Cmd eq "taskcomplete")
  {
    return HandleTaskComplete(@_);
  }
  if ($Cmd eq "vmstatuschange")
  {
    return HandleVMStatusChange(@_);
  }
  if ($Cmd eq "expectwinetestupdate")
  {
    return HandleExpectWinetestUpdate(@_);
  }
  if ($Cmd eq "foundwinetestupdate")
  {
    return HandleFoundWinetestUpdate(@_);
  }
  if ($Cmd eq "newwinepatchessubmission")
  {
    return HandleNewWinePatchesSubmission(@_);
  }
  if ($Cmd eq "patchnotification")
  {
    return HandlePatchNotification(@_);
  }
  if ($Cmd eq "patchretrieved")
  {
    return HandlePatchRetrieved(@_);
  }
  if ($Cmd eq "buildnotification")
  {
    return HandleBuildNotification(@_);
  }
  if ($Cmd eq "getscreenshot")
  {
    return HandleGetScreenshot(@_);
  }

  LogMsg "Engine: Unknown command $Cmd\n";
  return "0Unknown command $Cmd\n";
}

sub ClientRead
{
  my $Client = shift;

  my $Buf;
  my $GotSomething = !1;
  while (my $Len = sysread($Client->{Socket}, $Buf, 128))
  {
    $Client->{InBuf} .= $Buf;
    $GotSomething = 1;
  }

  return $GotSomething;
}

sub SafetyNet
{
  my $Jobs = CreateJobs();
  $Jobs->Check();
  $Jobs = undef;
  $Jobs = CreateJobs();
  $Jobs->Schedule();

  if (opendir STAGING, "$DataDir/staging")
  {
    my @DirEntries = readdir STAGING;
    closedir STAGING;
    foreach my $DirEntry (@DirEntries)
    {
      if ($DirEntry =~ m/[0-9a-fA-F]{32}_wine-patches/)
      {
        HandleNewWinePatchesSubmission($DirEntry);
      }
      elsif ($DirEntry =~ m/[0-9a-fA-F]{32}_patchnotification/)
      {
        HandlePatchNotification($DirEntry);
      }
    }
  }

  my $Set = WineTestBot::PendingPatchSets::CreatePendingPatchSets();
  my $ErrMessage = $Set->CheckForCompleteSet();
  if (defined($ErrMessage))
  {
    LogMsg "Engine: while checking completeness of patch series: $ErrMessage\n";
  }
}

sub PrepareSocket
{
  my $Socket = $_[0];

  my $Flags = 0;
  if (fcntl($Socket, F_GETFL, $Flags))
  {
    $Flags |= O_NONBLOCK;
    if (! fcntl($Socket, F_SETFL, $Flags))
    {
      LogMsg "Unable to make socket non-blocking during set: $!";
      return !1;
    }
  }
  else
  {
    LogMsg "Unable to make socket non-blocking during get: $!";
    return !1;
  }

  if (fcntl($Socket, F_GETFD, $Flags))
  {
    $Flags |= FD_CLOEXEC;
    if (! fcntl($Socket, F_SETFD, $Flags))
    {
      LogMsg "Unable to make socket close-on-exit during set: $!";
      return !1;
    }
  }
  else
  {
    LogMsg "Unable to make socket close-on-exit during get: $!";
    return !1;
  }


  return 1;
}

sub REAPER
{
  my $Child;
  # If a second child dies while in the signal handler caused by the
  # first death, we won't get another signal. So must loop here else
  # we will leave the unreaped child as a zombie. And the next time
  # two children die we get another zombie. And so on.
  while (0 < ($Child = waitpid(-1, WNOHANG)))
  {
    ;
  }
  $SIG{CHLD} = \&REAPER; # still loathe SysV
}

sub main 
{
  $ENV{PATH} = "/usr/bin:/bin";
  delete $ENV{ENV};
  $SIG{CHLD} = \&REAPER;

  $WineTestBot::Engine::Notify::RunningInEngine = 1;

  my $SockName = "$DataDir/socket/engine";
  my $uaddr = sockaddr_un($SockName);
  my $proto = getprotobyname('tcp');

  my $Sock;
  my $paddr;

  unlink($SockName);
  if (! socket($Sock,PF_UNIX,SOCK_STREAM,0))
  {
    FatalError "Unable to create socket: $!\n";
  }
  if (! bind($Sock, $uaddr))
  {
    FatalError "Unable to bind socket: $!\n";
  }
  chmod 0777, $SockName;
  if (! listen($Sock, SOMAXCONN))
  {
    FatalError "Unable to listen on socket: $!\n";
  }
  PrepareSocket($Sock);

  SafetyNet();
  AddEvent("SafetyNet", 600, 1, \&SafetyNet);

  my @Clients;
  while (1)
  {
    my $ReadyRead = "";
    my $ReadyWrite = "";
    my $ReadyExcept = "";
    vec($ReadyRead, fileno($Sock), 1) = 1;
    foreach my $Client (@Clients)
    {
      vec($ReadyRead, fileno($Client->{Socket}), 1) = 1;
      if ($Client->{OutBuf} ne "")
      {
        vec($ReadyWrite, fileno($Client->{Socket}), 1) = 1;
      }
      vec($ReadyExcept, fileno($Client->{Socket}), 1) = 1;
    }

    my $Timeout = RunEvents();
    my $NumFound = select($ReadyRead, $ReadyWrite, $ReadyExcept, $Timeout);
    if (vec($ReadyRead, fileno($Sock), 1))
    {
      my $NewClientSocket;
      if (accept($NewClientSocket, $Sock))
      {
        if (PrepareSocket($NewClientSocket))
        {
          $Clients[@Clients] = {Socket => $NewClientSocket,
                                InBuf => "",
                                OutBuf => ""};
        }
        else
        {
          close($NewClientSocket);
        }
      }
      elsif ($! != EAGAIN)
      {
        LogMsg "Engine: socket accept failed: $!\n";
      }
    }

    my $ClientIndex = 0;
    foreach my $Client (@Clients)
    {
      my $Client = $Clients[$ClientIndex];
      my $NeedClose = !1;
      if (vec($ReadyRead, fileno($Client->{Socket}), 1))
      {
        $NeedClose = ! ClientRead($Client);

        if (0 < length($Client->{InBuf}) &&
            substr($Client->{InBuf}, length($Client->{InBuf}) - 1, 1) eq "\n")
        {
          $Client->{OutBuf} = HandleClientCmd(split ' ', $Client->{InBuf});
          $Client->{InBuf} = "";
        }
      }
      if (vec($ReadyWrite, fileno($Client->{Socket}), 1))
      {
        my $Len = syswrite($Client->{Socket}, $Client->{OutBuf},
                  length($Client->{OutBuf}));
        if (! defined($Len))
        {
          LogMsg "Engine: Error writing reply to client: $!\n";
          $NeedClose = 1;
        }
        else
        {
          $Client->{OutBuf} = substr($Client->{OutBuf}, $Len);
          if ($Client->{OutBuf} eq "")
          {
            $NeedClose = 1;
          }
        }
      }
      if (vec($ReadyExcept, fileno($Client->{Socket}), 1))
      {
        LogMsg "Except condition on client connection\n";
        $NeedClose = 1;
      }
      if ($NeedClose)
      {
        close $Client->{Socket};
        splice(@Clients, $ClientIndex, 1);
      }
      else
      {
        $ClientIndex++;
      }
    }
  }

  return 0;
}

exit main();
