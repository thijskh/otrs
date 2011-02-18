# --
# Kernel/System/GenericInterface/Webservice.pm - GenericInterface webservice config backend
# Copyright (C) 2001-2011 OTRS AG, http://otrs.org/
# --
# $Id: Webservice.pm,v 1.12 2011-02-18 10:37:42 sb Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::GenericInterface::Webservice;

use strict;
use warnings;

use YAML;
use Kernel::System::Valid;
use Kernel::System::GenericInterface::DebugLog;
use Kernel::System::GenericInterface::WebserviceHistory;

use Kernel::System::VariableCheck qw(IsHashRefWithData);

use vars qw(@ISA $VERSION);
$VERSION = qw($Revision: 1.12 $) [1];

=head1 NAME

Kernel::System::Webservice

=head1 SYNOPSIS

Webservice configuration backend.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object

    use Kernel::Config;
    use Kernel::System::Encode;
    use Kernel::System::Log;
    use Kernel::System::Main;
    use Kernel::System::DB;
    use Kernel::System::GenericInterface::DebugLog;
    use Kernel::System::GenericInterface::Webservice;

    my $ConfigObject = Kernel::Config->new();
    my $EncodeObject = Kernel::System::Encode->new(
        ConfigObject => $ConfigObject,
    );
    my $LogObject = Kernel::System::Log->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
    );
    my $MainObject = Kernel::System::Main->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
        LogObject    => $LogObject,
    );
    my $DBObject = Kernel::System::DB->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
        LogObject    => $LogObject,
        MainObject   => $MainObject,
    );
    my $DebugLogObject = Kernel::System::GenericInterface::DebugLog->new(
        ConfigObject        => $ConfigObject,
        EncodeObject        => $EncodeObject,
        LogObject           => $LogObject,
        MainObject          => $MainObject,
        DBObject            => $DBObject,
    );
    my $WebserviceObject = Kernel::System::GenericInterface::Webservice->new(
        ConfigObject   => $ConfigObject,
        LogObject      => $LogObject,
        DBObject       => $DBObject,
        MainObject     => $MainObject,
        EncodeObject   => $EncodeObject,
        DebugLogObject => $DebugLogObject,
    );

=cut

sub new {
    my ( $Webservice, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Webservice );

    # check needed objects
    for my $Object (qw(DBObject ConfigObject LogObject MainObject EncodeObject)) {
        $Self->{$Object} = $Param{$Object} || die "Got no $Object!";
    }

    $Self->{ValidObject}    = Kernel::System::Valid->new( %{$Self} );
    $Self->{DebugLogObject} = Kernel::System::GenericInterface::DebugLog->new( %{$Self} );
    $Self->{WebserviceHistoryObject}
        = Kernel::System::GenericInterface::WebserviceHistory->new( %{$Self} );

    return $Self;
}

=item WebserviceAdd()

add new Webservices

returns id of new webservice if successful or undef otherwise

    my $ID = $WebserviceObject->WebserviceAdd(
        Name    => 'some name',
        Config  => $ConfigHashRef,
        ValidID => 1,
        UserID  => 123,
    );

=cut

sub WebserviceAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Key (qw(Name Config ValidID UserID)) {
        if ( !$Param{$Key} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $Key!" );
            return;
        }
    }

    # dump config as string
    my $Config = YAML::Dump( $Param{Config} );

    # sql
    return if !$Self->{DBObject}->Do(
        SQL =>
            'INSERT INTO gi_webservice_config (name, config, valid_id, '
            . ' create_time, create_by, change_time, change_by)'
            . ' VALUES (?, ?, ?, current_timestamp, ?, current_timestamp, ?)',
        Bind => [
            \$Param{Name}, \$Config, \$Param{ValidID},
            \$Param{UserID}, \$Param{UserID},
        ],
    );

    return if !$Self->{DBObject}->Prepare(
        SQL  => 'SELECT id FROM gi_webservice_config WHERE name = ?',
        Bind => [ \$Param{Name} ],
    );
    my $ID;
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
        $ID = $Row[0];
    }

    # add history
    return if !$Self->{WebserviceHistoryObject}->WebserviceHistoryAdd(
        WebserviceID => $ID,
        Config       => $Param{Config},
        UserID       => $Param{UserID},
    );

    return $ID;
}

=item WebserviceGet()

get Webservices attributes

    my $Webservice = $WebserviceObject->WebserviceGet(
        ID => 123,
    );

Returns:

    $Webservice = {
        ID         => 123,
        Name       => 'some name',
        Config     => $ConfigHashRef,
        ValidID    => 123,
        CreateTime => '2011-02-08 15:08:00',
        ChangeTime => '2011-02-08 15:08:00',
    };

=cut

sub WebserviceGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{ID} ) {
        $Self->{LogObject}->Log( Priority => 'error', Message => 'Need ID!' );
        return;
    }

    # sql
    return if !$Self->{DBObject}->Prepare(
        SQL => 'SELECT name, config, valid_id, create_time, change_time '
            . 'FROM gi_webservice_config WHERE id = ?',
        Bind => [ \$Param{ID} ],
    );
    my %Data;
    while ( my @Data = $Self->{DBObject}->FetchrowArray() ) {
        my $Config = YAML::Load( $Data[1] );

        %Data = (
            ID         => $Param{ID},
            Name       => $Data[0],
            Config     => $Config,
            ValidID    => $Data[2],
            CreateTime => $Data[3],
            ChangeTime => $Data[4],
        );
    }
    return \%Data;
}

=item WebserviceUpdate()

update Webservice attributes

returns 1 if successful or undef otherwise

    my $Success = $WebserviceObject->WebserviceUpdate(
        ID      => 123,
        Name    => 'some name',
        Config  => $ConfigHashRef,
        ValidID => 1,
        UserID  => 123,
    );

=cut

sub WebserviceUpdate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Key (qw(ID Name Config ValidID UserID)) {
        if ( !$Param{$Key} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $Key!" );
            return;
        }
    }

    # dump config as string
    my $Config = YAML::Dump( $Param{Config} );

    # check if config and valid_id is the same
    return if !$Self->{DBObject}->Prepare(
        SQL  => 'SELECT config, valid_id FROM gi_webservice_config WHERE id = ?',
        Bind => [ \$Param{ID} ],
    );
    my $ConfigCurrent;
    my $ValidIDCurrent;
    while ( my @Data = $Self->{DBObject}->FetchrowArray() ) {
        $ConfigCurrent  = $Data[0];
        $ValidIDCurrent = $Data[1];
    }
    return 1 if $ValidIDCurrent eq $Param{ValidID} && $Config eq $ConfigCurrent;

    # sql
    return if !$Self->{DBObject}->Do(
        SQL => 'UPDATE gi_webservice_config SET name = ?, config = ?, '
            . ' valid_id = ?, change_time = current_timestamp, '
            . ' change_by = ? WHERE id = ?',
        Bind => [
            \$Param{Name}, \$Config, \$Param{ValidID}, \$Param{UserID},
            \$Param{ID},
        ],
    );

    # add history
    return if !$Self->{WebserviceHistoryObject}->WebserviceHistoryAdd(
        WebserviceID => $Param{ID},
        Config       => $Param{Config},
        UserID       => $Param{UserID},
    );
    return 1;
}

=item WebserviceDelete()

delete a Webservice

returns 1 if successful or undef otherwise

    my $Success = $WebserviceObject->WebserviceDelete(
        ID      => 123,
        UserID  => 123,
    );

=cut

sub WebserviceDelete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Key (qw(ID UserID)) {
        if ( !$Param{$Key} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $Key!" );
            return;
        }
    }

    # check if exists
    my $Webservice = $Self->WebserviceGet(
        ID => $Param{ID},
    );
    return if !IsHashRefWithData($Webservice);

    # delete history
    return if !$Self->{WebserviceHistoryObject}->WebserviceHistoryDelete(
        WebserviceID => $Param{ID},
        UserID       => $Param{UserID},
    );

    # delete web service
    return if !$Self->{DBObject}->Do(
        SQL  => 'DELETE FROM gi_webservice_config WHERE id = ?',
        Bind => [ \$Param{ID} ],
    );

    # delete debug log entries
    return if !$Self->{DebugLogObject}->LogDelete(
        NoErrorIfEmpty => 1,
        WebserviceID   => $Param{ID},
    );

    return 1;
}

=item WebserviceList()

get Webservice list

    my $List = $WebserviceObject->WebserviceList();

    or

    my $List = $WebserviceObject->WebserviceList(
        Valid => 0, # optional, defaults to 1
    );

=cut

sub WebserviceList {
    my ( $Self, %Param ) = @_;

    my $SQL = 'SELECT id, name FROM gi_webservice_config';
    if ( !defined $Param{Valid} || $Param{Valid} eq 1 ) {
        $SQL .= ' WHERE valid_id IN (' . join ', ', $Self->{ValidObject}->ValidIDsGet() . ')';
    }

    return if !$Self->{DBObject}->Prepare( SQL => $SQL );

    my %Data;
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
        $Data{ $Row[0] } = $Row[1];
    }
    return \%Data;
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

=head1 VERSION

$Revision: 1.12 $ $Date: 2011-02-18 10:37:42 $

=cut
