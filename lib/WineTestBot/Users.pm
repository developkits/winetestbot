# User collection and items
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

WineTestBot::Users - User collection

=cut

package WineTestBot::User;

use Digest::SHA1 qw(sha1_hex);
use URI::Escape;
use WineTestBot::Config;
use WineTestBot::Roles;
use WineTestBot::UserRoles;
use WineTestBot::Utils;
use WineTestBot::WineTestBotObjects;

use vars qw (@ISA @EXPORT);

require Exporter;
@ISA = qw(WineTestBot::WineTestBotItem Exporter);

sub InitializeNew
{
  my $self = shift;

  $self->Active(1);
  $self->Password("*");
}

sub GeneratePasswordHash
{
  my $self = shift;
  my $PlaintextPassword = shift;

  my $Salt;
  if (defined($_[0]))
  {
    $Salt = substr($_[0], 0, 9);
  }
  else
  {
    $Salt = "";
    foreach my $i (1..3)
    {
      my $PartSalt = "0000" . sprintf("%lx", int(rand(2 ** 16)));
      $Salt .= substr($PartSalt, -4);
    }
    $Salt = substr($Salt, 0, 9);
  }

  return $Salt . sha1_hex($Salt . $PlaintextPassword);
}

sub GetEMailRecipient
{
  my $self = shift;

  return BuildEMailRecipient($self->EMail, $self->RealName);
}

sub Activated
{
  my $self = shift;

  my $HashedPassword = $self->Password;
  return defined($HashedPassword) && length($HashedPassword) == 49;
}

sub WaitingForApproval
{
  my $self = shift;

  if ($self->Activated())
  {
    return !1;
  }

  return ! $self->ResetCode;
}

sub GenerateResetCode
{
  my $self = shift;

  if (! $self->ResetCode)
  {
    my $ResetCode = "";
    foreach my $i (1..8)
    {
      my $PartCode = "0000" . sprintf("%lx", int(rand(2 ** 16)));
      $ResetCode .= substr($PartCode, -4);
    }
    $self->ResetCode($ResetCode);
  }
}

sub AddDefaultRoles
{
  my $self = shift;

  my $UserRoles = $self->Roles;
  my $DefaultRoles = CreateRoles();
  $DefaultRoles->AddFilter("IsDefaultRole", [1]);
  foreach my $RoleKey (@{$DefaultRoles->GetKeys()})
  {
    if (! defined($UserRoles->GetItem($RoleKey)))
    {
      my $NewRole = $UserRoles->Add();
      my $OldKey = $NewRole->GetKey();
      $NewRole->Role($DefaultRoles->GetItem($RoleKey));
      $UserRoles->KeyChanged($OldKey, $RoleKey);
    }
  }
}

sub Approve
{
  my $self = shift;

  $self->GenerateResetCode();
  $self->AddDefaultRoles();

  my ($ErrProperty, $ErrMessage) = $self->Save();
  if (defined($ErrMessage))
  {
    return $ErrMessage;
  }

  my $URL = MakeSecureURL("/ResetPassword.pl?Name=" . uri_escape($self->Name) .
                          "&ResetCode=" . uri_escape($self->ResetCode));
  my $Recipient = $self->GetEMailRecipient();
  open (SENDMAIL, "|/usr/sbin/sendmail -oi -t -odq");
  print SENDMAIL <<"EOF";
From: <$RobotEMail> (Marvin)
To: $Recipient
Subject: winetestbot account request

Your request for an account has been approved. To pick a password and activate
your account, please go to:
$URL
EOF
  close(SENDMAIL);

  return undef;
}

sub SendResetCode
{
  my $self = shift;

  if (! $self->Active)
  {
    return "This account has been suspended";
  }
  if (! $self->Activated() && $self->WaitingForApproval())
  {
    return "Your account has not been approved yet";
  }

  $self->GenerateResetCode();

  my ($ErrProperty, $ErrMessage) = $self->Save();
  if (defined($ErrMessage))
  {
    return $ErrMessage;
  }

  my $URL = MakeSecureURL("/ResetPassword.pl?Name=" . uri_escape($self->Name) .
                          "&ResetCode=" . uri_escape($self->ResetCode));
  my $UserName = $self->Name;
  my $Recipient = $self->GetEMailRecipient();
  open (SENDMAIL, "|/usr/sbin/sendmail -oi -t -odq");
  print SENDMAIL <<"EOF";
From: <$RobotEMail> (Marvin)
To: $Recipient
Subject: winetestbot account request

password reset request for your account $UserName was received via the website.
You can pick a new password by going to:
$URL
EOF
  close(SENDMAIL);

  return undef;
}

sub ResetPassword
{
  my $self = shift;
  my ($ResetCode, $NewPassword) = @_;

  my $CorrectResetCode = $self->ResetCode;
  if (! defined($ResetCode) || ! defined($CorrectResetCode) ||
      $CorrectResetCode eq "" || $ResetCode ne $CorrectResetCode)
  {
    return "Unknown username or incorrect activation code";
  }

  $self->Password($self->GeneratePasswordHash($NewPassword));
  $self->ResetCode(undef);

  my ($ErrProperty, $ErrMessage) = $self->Save();
  return $ErrMessage;
}

sub Authenticate
{
  my $self = shift;
  my $PlaintextPassword = $_[0];

  if (! $self->Activated())
  {
    if ($self->WaitingForApproval())
    {
      return ("Your account has not been approved yet", undef);
    }
    else
    {
      return ("You need to activate your account, see email for instructions",
              undef);
    }
  }

  my $CorrectHashedPassword = $self->Password;
  my $HashedPassword =  $self->GeneratePasswordHash($PlaintextPassword,
                                                    $CorrectHashedPassword);
  if (! $PlaintextPassword || $CorrectHashedPassword ne $HashedPassword)
  {
    return ("Unknown username or incorrect password", undef);
  }

  if (! $self->Active)
  {
    return ("This account has been suspended", undef);
  }

  return (undef, $self);
}

sub FromLDAP
{
  my $self = shift;
  my ($LDAP, $UserName) = @_;

  $self->Name($UserName);
  $self->Password("*");
  $self->Active("Y");

  my $SearchFilter = $LDAPSearchFilter;
  $SearchFilter =~ s/%USERNAME%/$UserName/;
  my $Result = $LDAP->search(base => $LDAPSearchBase, filter => $SearchFilter,
                             attrs => [$LDAPRealNameAttribute, $LDAPEMailAttribute]);
  if ($Result->code != 0)
  {
    return "LDAP failure: " . $Result->error;
  }

  my $Entry = $Result->entry(0);
  if (! $Entry)
  {
    return "Unable to retrieve LDAP attributes";
  }
  $self->RealName($Entry->get_value($LDAPRealNameAttribute));
  $self->EMail($Entry->get_value($LDAPEMailAttribute));

  $self->AddDefaultRoles();

  return undef;
}

sub HasRole
{
  my $self = shift;
  my $RoleName = shift;

  my $Roles = $self->Roles;
  return defined($Roles->GetItem($RoleName));
}

package WineTestBot::Users;

use Net::LDAP;
use ObjectModel::BasicPropertyDescriptor;
use ObjectModel::DetailrefPropertyDescriptor;
use ObjectModel::PropertyDescriptor;
use WineTestBot::Config;
use WineTestBot::UserRoles;
use WineTestBot::WineTestBotObjects;

use vars qw (@ISA @EXPORT @PropertyDescriptors $CurrentUser);

require Exporter;
@ISA = qw(WineTestBot::WineTestBotCollection Exporter);
@EXPORT = qw(&CreateUsers &SetCurrentUser &GetCurrentUser &GetBatchUser
             &Authenticate);

BEGIN
{
  $PropertyDescriptors[0] =
    CreateBasicPropertyDescriptor("Name",      "Username",             1,  1, "A", 40);
  $PropertyDescriptors[1] =
    CreateBasicPropertyDescriptor("EMail",     "EMail",               !1,  1, "A", 40);
  $PropertyDescriptors[2] =
    CreateBasicPropertyDescriptor("Active",    "Active",              !1,  1, "B",  1);
  $PropertyDescriptors[3] =
    CreateBasicPropertyDescriptor("Password",  "Password",            !1, !1, "A", 49);
  $PropertyDescriptors[4] =
    CreateBasicPropertyDescriptor("RealName",  "Real name",           !1,  1, "A", 40);
  $PropertyDescriptors[5] =
    CreateBasicPropertyDescriptor("ResetCode", "Password reset code", !1, !1, "A", 32);
  $PropertyDescriptors[6] =
    CreateDetailrefPropertyDescriptor("Roles",   "Roles",    !1, !1, \&CreateUserRoles);

}

sub CreateItem
{
  my $self = shift;

  return WineTestBot::User->new($self);
}

sub CreateUsers
{
  return WineTestBot::Users::->new("Users", "Users", "User", \@PropertyDescriptors);
}

sub AuthenticateLDAP
{
  my $self = shift;
  my ($Name, $Password) = @_;

  my $LDAP = Net::LDAP->new($LDAPServer);
  if (! defined($LDAP))
  {
    return ("Can't connect to LDAP server: $@", undef);
  }

  my $BindDN = $LDAPBindDN;
  $BindDN =~ s/%USERNAME%/$Name/;
  my $Msg = $LDAP->bind($BindDN, password => $Password);
  if ($Msg->code)
  {
    return "Unknown username or incorrect password";
  }

  my $User = $self->GetItem($Name);
  if (defined($User))
  {
    return (undef, $User);
  }

  $User = $self->Add();
  my $ErrMessage = $User->FromLDAP($LDAP, $Name);
  if ($ErrMessage)
  {
    return $ErrMessage;
  }

  my $ErrKey;
  my $ErrProperty;
  ($ErrKey, $ErrProperty, $ErrMessage) = $self->Save();
  if ($ErrMessage)
  {
    return $ErrMessage;
  }

  return (undef, $User);
}

sub AuthenticateBuiltin
{
  my $self = shift;
  my ($Name, $Password) = @_;

  my $User = $self->GetItem($Name);
  if (! defined($User))
  {
    return "Unknown username or incorrect password";
  }

  return $User->Authenticate($Password);
}

sub Authenticate
{
  my $self = shift;

  return defined($LDAPServer) ? $self->AuthenticateLDAP(@_) :
                                $self->AuthenticateBuiltin(@_);
}

sub GetBatchUser
{
  my $class = shift;

  my $Users = $class->CreateUsers();
  return $Users->GetItem("batch");
}

sub SetCurrentUser
{
  $CurrentUser = shift;
}

sub GetCurrentUser
{
  return $CurrentUser;
}

1;
