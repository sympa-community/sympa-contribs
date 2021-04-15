#============================================================= -*-Perl-*-
#
# DESCRIPTION
#   Sympa 6.2 plugin for whitelist management
#
# AUTHORS
#   Steve Shipway
#   University of Auckland, New Zealand
#   September 2015
#
#   Luc Didry
#   Framasoft
#   June 2020
#
#============================================================================
# v0.1 - initial release for Sympa 6.1
# v0.2 - cope with situation where no robot subdir is used
# v1.0 - Sympa 6.2 conversion
# v1.1 - Strange processing of multiple @cap entries
# v1.2 - Simplify TT2 modifications and add fr translation

package modlist_plugin;
#use Sympa::Constants;
use strict;

our $VERSION   = 1.02;

our $FILENAME  = "modlist";

sub process {
    my $listref = shift; # reference to list object
    my $action;          # sub-action for this lca
    my %stash = ();      # variables to pass back to TT2 template
    my $rv    = "";
    my $sfdir ='';
    my @data  = ();         # file content as array
    my $data  = '';         # file content as single string

    $action = shift;     # extract plugin action
    $data   = join '/',@_; # rejoin all parameters
    $data   =~ s/\x00//g;  # remove nulls caused by multiple @cap parameters

    # Must run in list context
    return 'home' if(!ref $listref);

    # All use same TT2
    $stash{x_name}      = $FILENAME;
    $stash{x_ucfname}   = ucfirst $FILENAME;
    $stash{next_action} = "lca:whitelist";
    $stash{x_saved}=0;

    # Identify the search_filters directory.
    $sfdir        = $listref->{'dir'}."/search_filters";
    $stash{sfdir} = $sfdir;
    if ( ! -d $sfdir ) {
        mkdir $sfdir;
    }
    if ( ! -d $sfdir ) {
        $stash{x_saveerror} = "Unable to make list search_filters directory";
        return \%stash;
    }

    # IF IN SAVE CONTEXT then save the new content
    if ($action eq 'save') {
        $data =~ s/\s*[\r\n]\s+/\n/g; # kill blank lines
        if (open my $fh, '>', "${sfdir}/${FILENAME}.txt") {
            print $fh $data;
            close $fh;
            $stash{x_saved} = 1;
        } else {
            $rv                 = "Unable to save: $!";
            $stash{x_saveerror} = $rv;
        }
        $stash{x_data} = $data;

        my @rows       = split /\n/,$data;
        $stash{x_rows} = ($#rows + 1);
        return \%stash;
    }

    # Load the content
    if( -r "${sfdir}/${FILENAME}.txt") {
        open my $fh, '<', "${sfdir}/${FILENAME}.txt";
        @data = <$fh>;
        close $fh;
    } else {
        push @data, "# No $FILENAME found\n";
        push @data, "# list your email address patterns here\n";
    }
    $data          = join "", @data;
    $stash{x_data} = $data;
    $stash{x_rows} = ($#data + 1);

    return \%stash;
}

1;

