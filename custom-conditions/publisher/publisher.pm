#!/usr/bin/perl

package CustomCondition::publisher;

use strict;

# Log parameters
use Sympa::Log;
my $log = Sympa::Log->instance;

use Conf;
my $etc = $Conf::Conf{'etc'};

# Publisher permissions file
my $PUBLISHER_CONF_FILENAME = "publisher.conf";
my $permissionsFile = $etc . "/" . $PUBLISHER_CONF_FILENAME;

# Mandatory verification sub
sub verify {
    my $listname = shift or return;
    my $sender   = shift or return;

    # Permissions file is read line by line
    if (open(my $permissionsFileFH, '<:encoding(UTF-8)', $permissionsFile)) {
        while (my $readPermission = <$permissionsFileFH>) {
            chomp $readPermission;

            # Blank spaces from any line are removed from every line
            $readPermission =~ s/\s+//g;

            # The text to the left of the first # symbol is removed from the comments
            # and splitted into the two variables
            my @permission = split(':',(split('#',$readPermission))[0]);
            my $allowedList = $permission[0];
            my $allowedSender = $permission[1];

            # These two variables are compared against those two passed by the Send scenario
            if ((lc $allowedList eq lc $listname) && (lc $allowedSender eq lc $sender)) {
                # If a match is found it is logged, the permissions file closed and the user is allowed to publish to the list
                $log->syslog('notice', 'CustomCondition::publisher User %s published to list %s', $sender, $listname);
                close $permissionsFileFH;
                return 1;
            }
        }

        # If no match is found, the permissions file is closed and the user is not allowed to publish to the list
        # This is not logged in order to not fill log files with unnecessary entries
        close $permissionsFileFH;
        return 0;
    } else {
        # If the permissions file could not be read, the error is logged and the user is not allowed to publish to the list
        $log->syslog('err', 'CustomCondition::publisher Unable to open PermissionsFile: %s', $permissionsFile);
        return 0;
    }
}

# Packages must return true.
1;