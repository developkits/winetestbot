#!/usr/bin/perl -Tw
#
# Send job log to submitting user
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

use WineTestBot::Config;
use WineTestBot::Jobs;
use WineTestBot::Log;
use WineTestBot::StepsTasks;

sub FatalError
{
  my ($ErrMessage, $Job) = @_;

  my $JobKey = defined($Job) ? $Job->GetKey() : "0";

  LogMsg "SendLog: $JobKey $ErrMessage";

  exit 1;
}

sub SendLog
{
  my $Job = shift;
  if ($Job->User->EMail eq "/dev/null")
  {
    return;
  }

  my $StepsTasks = CreateStepsTasks($Job);
  my @SortedKeys = sort @{$StepsTasks->GetKeys()};

#  open (SENDMAIL, "|/bin/cat");
  open (SENDMAIL, "|/usr/sbin/sendmail -oi -t -odq");
  print SENDMAIL "From: <$RobotEMail> (Marvin)\n";
  print SENDMAIL "To: ", $Job->User->GetEMailRecipient(), "\n";
  print SENDMAIL "Subject: WineTestBot job ", $Job->Id, " finished\n";
  print SENDMAIL <<"EOF";
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==13F70BD1-BA1B-449A-9CCB-B6A8E90CED47=="

--==13F70BD1-BA1B-449A-9CCB-B6A8E90CED47==
Content-Type: text/plain; charset="UTF-8"
MIME-Version: 1.0
Content-Transfer-Encoding: 8bit
Content-Disposition: inline

VM                   Status    Number of test failures
EOF
  foreach my $Key (@SortedKeys)
  {
    my $StepTask = $StepsTasks->GetItem($Key);
    my $TestFailures = $StepTask->TestFailures;
    if (! defined($TestFailures))
    {
      $TestFailures = "";
    }
    printf SENDMAIL "%-20s %-9s %s\n", $StepTask->VM->Name, $StepTask->Status,
                    $TestFailures;
  }

  foreach my $Key (@SortedKeys)
  {
    my $StepTask = $StepsTasks->GetItem($Key);

    print SENDMAIL "\n=== ", $StepTask->VM->Name, " (",
                   $StepTask->VM->Description, ") ===\n";

    my $TaskDir = "$DataDir/jobs/" . $Job->Id . "/" . $StepTask->StepNo .
                  "/" . $StepTask->TaskNo;
    if (open LOGFILE, "<$TaskDir/log")
    {
      my $HasLogEntries = !1;
      my $PrintedSomething = !1;
      my $CurrentDll = "";
      my $PrintedDll = "";
      my $Line;
      while (defined($Line = <LOGFILE>))
      {
        $HasLogEntries = 1;
        $Line =~ s/\s*$//;
        if ($Line =~ m/^([^:]+):[^ ]+ start [^ ]+ -$/)
        {
          $CurrentDll = $1;
        }
        if ($Line =~ m/: Test failed: / || $Line =~ m/ done \(-/ ||
            $Line =~ m/ done \(258\)/)
        {
          if ($PrintedDll ne $CurrentDll)
          {
            print SENDMAIL "\n$CurrentDll:\n";
            $PrintedDll = $CurrentDll;
          }
          if ($Line =~ m/^[^:]+:([^ ]+) done \(-/)
          {
            print SENDMAIL "$1: Crashed\n";
          }
          elsif ($Line =~ m/^[^:]+:([^ ]+) done \(258\)/)
          {
            print SENDMAIL "$1: Timeout\n";
          }
          else
          {
            print SENDMAIL "$Line\n";
          }
          $PrintedSomething = 1;
        }
      }
      close LOGFILE;

      if (open ERRFILE, "<$TaskDir/err")
      {
        my $First = 1;
        while (defined($Line = <ERRFILE>))
        {
          if ($First)
          {
            print SENDMAIL "\n";
            $First = !1;
          }
          $HasLogEntries = 1;
          $Line =~ s/\s*$//;
          print SENDMAIL "$Line\n";
          $PrintedSomething = 1;
        }
        close ERRFILE;
      }

      if (! $PrintedSomething)
      {
        print SENDMAIL $HasLogEntries ? "No test failures found\n" : "Empty log\n";
      }
    }
    elsif (open ERRFILE, "<$TaskDir/err")
    {
      my $HasErrEntries = !1;
      my $Line;
      while (defined($Line = <ERRFILE>))
      {
        $HasErrEntries = 1;
        $Line =~ s/\s*$//;
        print SENDMAIL "$Line\n";
      }
      close ERRFILE;
      if (! $HasErrEntries)
      {
        print "Empty log";
      }
    }
  }

  foreach my $Key (@SortedKeys)
  {
    my $StepTask = $StepsTasks->GetItem($Key);

    print SENDMAIL <<"EOF";
--==13F70BD1-BA1B-449A-9CCB-B6A8E90CED47==
Content-Type: text/plain; charset="UTF-8"
MIME-Version: 1.0
Content-Transfer-Encoding: 8bit
EOF
    print SENDMAIL "Content-Disposition: attachment; filename=",
                   $StepTask->VM->Name, ".log\n\n";

    my $TaskDir = "$DataDir/jobs/" . $Job->Id . "/" . $StepTask->StepNo .
                  "/" . $StepTask->TaskNo;

    my $PrintSeparator = !1;
    if (open LOGFILE, "<$TaskDir/log")
    {
      my $Line;
      while (defined($Line = <LOGFILE>))
      {
        $Line =~ s/\s*$//;
        print SENDMAIL "$Line\n";
        $PrintSeparator = 1;
      }
      close LOGFILE;
    }

    if (open ERRFILE, "<$TaskDir/err")
    {
      my $Line;
      while (defined($Line = <ERRFILE>))
      {
          if ($PrintSeparator)
          {
            print SENDMAIL "\n";
            $PrintSeparator = !1;
          }
        $Line =~ s/\s*$//;
        print SENDMAIL "$Line\n";
      }
      close ERRFILE;
    }
  }
  
  print SENDMAIL "--==13F70BD1-BA1B-449A-9CCB-B6A8E90CED47==--\n";
  close(SENDMAIL);
}

$ENV{PATH} = "/usr/bin:/bin";
delete $ENV{ENV};

my $JobId = $ARGV[0];
if (! $JobId)
{
  die "Usage: SendLog.pl JobId";
}

# Untaint parameters
if ($JobId =~ /^(\d+)$/)
{
  $JobId = $1;
}
else
{
  FatalError "Invalid JobId $JobId\n";
}

my $Jobs = CreateJobs();
my $Job = $Jobs->GetItem($JobId);
if (! defined($Job))
{
  FatalError "Job $JobId doesn't exist\n";
}

SendLog($Job);

LogMsg "SendLog: log for job $JobId sent\n";

exit;