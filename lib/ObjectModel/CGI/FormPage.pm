# Base class for web pages containing a form
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

ObjectModel::CGI::FormPage - Base class for web forms

=cut

package ObjectModel::CGI::FormPage;

use ObjectModel::CGI::Page;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(ObjectModel::CGI::Page Exporter);

sub _initialize
{
  my $self = shift;
  my $PropertyDescriptors = shift;

  $self->SUPER::_initialize(@_);

  $self->{PropertyDescriptors} = $PropertyDescriptors;
  $self->{HasRequired} = !1;
  $self->{ActionPerformed} = !1;
}

sub GetPropertyDescriptors
{
  my $self = shift;

  return $self->{PropertyDescriptors};
}

sub GetPropertyDescriptorByName
{
  my $self = shift;
  my $Name = shift;

  my $PropertyDescriptors = $self->GetPropertyDescriptors();
  foreach my $PropertyDescriptor (@{$PropertyDescriptors})
  {
    if ($PropertyDescriptor->GetName() eq $Name)
    {
      return $PropertyDescriptor;
    }
  }

  return undef;
}

sub GeneratePage
{
  my $self = shift;

  if ($self->GetParam("Action"))
  {
    $self->{ActionPerformed} = $self->OnAction($self->GetParam("Action"));
  }

  $self->SUPER::GeneratePage(@_);
}

sub GenerateTitle
{
  my $self = shift;

  my $Title = $self->GetTitle();
  if ($Title)
  {
    print "<h1>$Title</h1>\n";
  }
}

sub GenerateBody
{
  my $self = shift;

  print "<div class='ItemBody'>\n";
  $self->GenerateTitle();
  print "<div class='Content'>\n";
  my $Text = $self->GetHeaderText();
  if ($Text)
  {
    print "<p>$Text</p>\n";
  }
  $self->GenerateFormStart();
  $self->GenerateErrorDiv();

  $self->GenerateFields();
  $self->GenerateRequiredLegend();

  if (defined($self->{ErrMessage}))
  {
    my $PropertyDescriptor;
    if (defined($self->{ErrField}))
    {
      $PropertyDescriptor = $self->GetPropertyDescriptorByName($self->{ErrField});
    }
    if (! defined($PropertyDescriptor) ||
        $self->DisplayProperty($PropertyDescriptor))
    {
      $self->GenerateErrorPopup();
    }
  }
  $self->GenerateActions();
  $self->GenerateFormEnd();
  $Text = $self->GetFooterText();
  if ($Text)
  {
    print "<p>$Text</p>\n";
  }
  print "</div>\n";
  print "</div>\n";
}

sub GenerateFormStart
{
  print "<form action='" . $ENV{"SCRIPT_NAME"} .
       "' method='post' enctype='multipart/form-data'>\n";
}

sub GenerateFields
{
  my $self = shift;

  my $PropertyDescriptors = $self->GetPropertyDescriptors();
  foreach my $PropertyDescriptor (@{$PropertyDescriptors})
  {
    my $Display = $self->DisplayProperty($PropertyDescriptor);
    if ($Display)
    {
      print "<div class='ItemProperty'><label>",
            $self->CGI->escapeHTML($self->GetDisplayName($PropertyDescriptor)) .
            "</label>";
      $self->GenerateField($PropertyDescriptor, $Display);
      print "</div>\n";
    }
  }
}

sub GenerateRequiredLegend
{
  my $self = shift;

  if ($self->{HasRequired})
  {
    print "<div class='ItemProperty'><label><span class='Required'>*</span></label>Required field</div>\n";
  }
}

sub GenerateActions
{
  my $self = shift;

  print "<div class='ItemActions'>\n";
  foreach my $Action (@{$self->GetActions()})
  {
    print "<input type='submit' name='Action' value='$Action'/>\n";
  }
  print "</div>\n";
}

sub GenerateFormEnd
{
  print "</form>\n";
}

sub GetPropertyValue
{
  return undef;
}

sub GetDisplayValue
{
  my $self = shift;
  my $PropertyDescriptor = shift;

  my $Value;
  if (defined($self->GetParam($PropertyDescriptor->GetName())))
  {
    $Value = $self->GetParam($PropertyDescriptor->GetName());
  }
  else
  {
    $Value = $self->GetPropertyValue($PropertyDescriptor);
  }

  return $Value;
}

sub GetDisplayName
{
  my $self = shift;
  my $PropertyDescriptor = shift;

  return $PropertyDescriptor->GetDisplayName();
}

sub GetInputType
{
  my $self = shift;
  my $PropertyDescriptor = shift;

  if ($PropertyDescriptor->GetType() eq "B")
  {
    return "checkbox";
  }

  return "text";
}

sub GenerateField
{
  my $self = shift;
  my ($PropertyDescriptor, $Display) = @_;

  my $Value = $self->GetDisplayValue($PropertyDescriptor);
  if ($Display == "rw")
  {
    my $InputType = $self->GetInputType($PropertyDescriptor);
    print "<div class='ItemValue'>";
    if ($InputType eq "checkbox")
    {
      print "<input type='checkbox' name='", $PropertyDescriptor->GetName(),
            "' ";
      if ($Value)
      {
        print "checked='checked' ";
      }
      print "/>";
    }
    elsif ($InputType eq "textarea")
    {
      my $MaxLength = $PropertyDescriptor->GetMaxLength();
      print "<textarea name='", $PropertyDescriptor->GetName(), "' cols='";
      if ($MaxLength < 50)
      {
        print "$MaxLength' rows='1";
      }
      else
      {
        print "50' rows='", int(($MaxLength + 49) / 50);
      }
      print "'>";
      if ($Value)
      {
        print $self->CGI->escapeHTML($Value), "'";
      }
      print "</textarea>";
      $self->GenerateRequired($PropertyDescriptor);
    }
    else
    {
      print "<input type='$InputType' name='", $PropertyDescriptor->GetName(),
            "' maxlength='", $PropertyDescriptor->GetMaxLength(), "' size='",
            $PropertyDescriptor->GetMaxLength(), "'";
      if ($Value && $InputType ne "password")
      {
        print " value='", $self->CGI->escapeHTML($Value), "'";
      }
      print " />";
      $self->GenerateRequired($PropertyDescriptor);
    }
    print "</div>";
  }
  else
  {
    if ($Value)
    {
      print $self->CGI->escapeHTML($Value);
    }
    else
    {
      print "&nbsp;";
    }
  }
}

sub GenerateRequired
{
  my $self = shift;
  my $PropertyDescriptor = shift;

  if ($PropertyDescriptor->GetIsRequired())
  {
    $self->{HasRequired} = 1;
    print "&nbsp;<span class='Required'>*</span>";
  }
}

sub GetTitle
{
  return undef;
}

sub GetHeaderText
{
  return undef;
}

sub GetFooterText
{
  return undef;
}

sub DisplayProperty
{
  my $self = shift;
  my $PropertyDescriptor = $_[0];

  if ($PropertyDescriptor->GetClass() eq "Detailref")
  {
    return "";
  }

  return "rw";
}

sub GetActions
{
  return [];
}

sub SaveProperty
{
  die "Pure virtual function FormPage::SaveProperty called";
}

sub Save
{
  my $self = shift;

  my @ParamNames = $self->GetParam();
  foreach my $ParameterName (@ParamNames)
  {
    my $PropertyDescriptor = $self->GetPropertyDescriptorByName($ParameterName);
    if (defined($PropertyDescriptor))
    {
      if (! $self->SaveProperty($PropertyDescriptor,
          $self->GetParam($ParameterName)))
      {
        return !1;
      }
    }
  }

  foreach my $PropertyDescriptor (@{$self->{Collection}->GetPropertyDescriptors})
  {
    if ($PropertyDescriptor->GetClass() eq "Basic" &&
        $PropertyDescriptor->GetType() eq "B" &&
        $self->DisplayProperty($PropertyDescriptor) eq "rw" &&
        ! defined($self->GetParam($PropertyDescriptor->GetName())))
    {
      if (! $self->SaveProperty($PropertyDescriptor, !1))
      {
        return !1;
      }
    }
  }

  my $ErrKey;
  ($ErrKey, $self->{ErrField}, $self->{ErrMessage}) = $self->{Collection}->Save();
  return ! defined($self->{ErrMessage});
}

sub OnAction
{
  my $self = shift;
  my $Action = $_[0];

  die "No action defined for $Action";
}

sub Validate
{
  my $self = shift;

  my $PropertyDescriptors = $self->GetPropertyDescriptors();
  foreach my $PropertyDescriptor (@{$PropertyDescriptors})
  {
    my $Value = $self->GetParam($PropertyDescriptor->GetName());
    my $ErrMessage = $PropertyDescriptor->ValidateValue($Value, 1);
    if ($ErrMessage)
    {
      $self->{ErrMessage} = $ErrMessage;
      $self->{ErrField} = $PropertyDescriptor->GetName();
      return !1;
    }
  }

  return 1;
}

1;
