#!/usr/bin/perl
     
# Answering procedure for a distribution list
# Author: B. Marchal (University of Lorraine)
# Date: November 2020 (version 2.0)
#
# According to the proposal https://www.sympa.org/contribs/vacation
#
# Modifications:
# * add the list itself in the excludes to avoid loops
# * no sending if the message comes from a list (ListId <> "")
# * at least one date is mandatory (start or end)
# * storage in a database of the date of the message to function as a regular answering machine. ie no systematic sending if a previous message has already been sent

# The variable $duration contains the number of days

# To set up using the 'sympa' database, we need to create a new table:

# --------------------
#  CREATE TABLE IF NOT EXISTS `vacation_table` (
#    `user_vacation` varchar(100) NOT NULL,
#    `list_vacation` varchar(100) NOT NULL,
#    `robot_vacation` varchar(100) NOT NULL,
#    `date_epoch_vacation` int(11) NOT NULL
#  ) ENGINE=InnoDB DEFAULT CHARSET=utf8;

#  --
#  -- Index for the table `vacation_table`
#  --
#  ALTER TABLE `vacation_table`
#    ADD PRIMARY KEY (`user_vacation`,`list_vacation`,`robot_vacation`);
# --------------------

# To use, just put a line in a scenario like:
# CustomCondition::newvacation([list->address],[custom_vars->vacation_start],[custom_vars->vacation_end],[custom_vars->vacation_exclude_list],[sender],[msg_header->Subject],[msg_header->List-Id][0]) smtp,smime,md5,dkim -> do_it
#
#
use lib '/usr/share/sympa/lib';

package CustomCondition::newvacation;
     
use strict;
     
use English qw(-no_match_vars);
use MIME::EncWords;
     
use Sympa::Log;
use Sympa::List;
     
use Exporter;
our @EXPORT_OK = qw(verify);
     
my $log = Sympa::Log->instance;

# ---------------------- #
# To be modified locally #
# ---------------------- #
my $duration = 7; # Number of days without vacation message for a couple (sender, list)
my $debug=1; # Set to 1 if you want a line with all parameters in sympa.log


##############################
sub verify {
    eval { require DateTime::Format::DateParse; };

    if ($EVAL_ERROR) {
	$log->syslog(
	    'err',
	    'Error requiring DateTime::Format::DateParse : %s (%s)',
	    "$EVAL_ERROR",
	    ref($EVAL_ERROR)
            );
	return -1;
    }
     
    # Get parameters
    my $list_address = shift;
    my $vacation_start = shift;
    my $vacation_end = shift;
    my $vacation_exclude = shift;
    my $sender = shift;
    my $subject = shift;
    my $listId  = shift;
     
    $subject = shift @$subject if ref $subject eq 'ARRAY';
    $subject = MIME::EncWords::decode_mimewords($subject);

    $log->syslog(
	'notice',
	'vacation : Received parameters : list = "%s" vacation_start = "%s" vacation-end = "%s" vacation_exclude = "%s" sender = "%s" subject = "%s" listId = "%s"',
	$list_address,
	$vacation_start,
	$vacation_end,
	$vacation_exclude,
	$sender,
	$subject,
	$listId
	) if ($debug);

    # No vacation message if the message comes from a list (ListId <> "")
    return -1 if ( $listId ne "");

    # We add the list in $vacation_exclude to avoid loops
    $vacation_exclude .= ','.$list_address;

    return -1 if ($vacation_start eq "" and $vacation_end eq ""); # At least one of the two variables must be defined

    $vacation_start = "2012-01-01" if ($vacation_start eq "");
    $vacation_end   = "2100-12-31" if ($vacation_end eq "");

    # Parse dates
    my $dt_start = DateTime::Format::DateParse->parse_datetime($vacation_start);
    my $dt_end   = DateTime::Format::DateParse->parse_datetime($vacation_end);

    unless($dt_start) {
	$log->syslog(
	    'err',
	    'Vacation : Unable to parse date "%s"',
	    $vacation_start
           );
	return -1;
    }
     
    unless($dt_end) {
	$log->syslog(
	    'err',
	    'Vacation : Unable to parse date "%s"',
	    $vacation_end
            );
	return -1;
    }
     
    $vacation_start = $dt_start->epoch();
    $vacation_end   = $dt_end->epoch();
     
    # Check time range, return if not vacation
    return -1 unless time >= $vacation_start and time <= $vacation_end;
     
    # Check if sender is in $vacation_exclude
    return -1 if (grep /^$sender$/, split /,/, $vacation_exclude);

    # We did not come from the evaluation of a message, the subject is empty
    return -1 if ( ! $subject ); 

    # A message for the list has been received for less than $duration days
    return -1 if ( query_vacation ($sender, $list_address)); 

    # We are in vacation range, notify sender
     
    # Retreive List object
    my ($list_name, $robot) = split(/@/, $list_address);
    my $list = Sympa::List->new($list_name, $robot);
     
    # Send notification
    my $tpl = 'vacation';
    $log->syslog(
	'notice',
	'Vacation : Envoi du template "%s" to %s',
	$tpl,
	$sender
	) if ( $debug);

   unless (
	Sympa::send_file(
	    $list,
	    $tpl,
	    $sender,
	    {
		'auto_submitted' => 'auto-replied',
		'vacation_start' => $vacation_start,
		'vacation_end' => $vacation_end,
		'subject' => $subject
	    }
	)
       ) {

	$log->syslog(
	    'notice',
	    'Vacation : Unable to send template "%s" to %s',
	    $tpl,
	    $sender
            );
    }
     
    return -1;
}

##############################
sub query_vacation {
# This function tests if there is an entry in the vacation_table table for the triplet (sender, list, robot).
# If this entry exists, it parses the date to see if a message has been received for less than $duration days.
# If the triplet does not exist or if the date is too old, we update the database with the date epoch
#
# We return true (1) if the vacation message must be sent, false (0) otherwise

    my $sender = shift;
    my $list_address = shift;

    my ($list_name, $list_robot) = split(/@/, $list_address);
    my $date_epoch = time();
    $log->syslog(
	'notice',
	'QueryVacation : Paramètres : sender = %s liste = %s date "%d" ',
	$sender,
	$list_address,
	$date_epoch
	) if ( $debug);
    my $return = 1;

    my $sdm = Sympa::DatabaseManager->instance;
    my $sth;

    unless (
        $sdm 
	) {
        $log->syslog('err', 'Unable to connect to database');
        return 1;
    }
    
    unless (
	 $sth = $sdm->do_prepared_query(
            q{SELECT date_epoch_vacation
              FROM vacation_table
              WHERE user_vacation = ? AND list_vacation = ? AND robot_vacation = ?
	      ORDER BY date_epoch_vacation DESC
	      LIMIT 1},
            $sender, $list_name, $list_robot
        )
    ) {
	$log->syslog('err', 'cannot retrieve a date from the database for sender %s and list %s',
		     $sender,
		     $list_address);
    }
    my $date = ($sth)? $sth->fetchrow : 0;

    $log->syslog(
	'notice',
	'Vacation : Date retournée "%d" ',
	$date
	) if ( $debug);
    if ( $date < ( $date_epoch - $duration * 24 * 3600 ) ) {
	# if the date is $duration days earlier, the entry is updated, otherwise, it is inserted
	unless (
	    $sth = ($date)? 
	    $sdm->do_prepared_query(
		q{UPDATE vacation_table
                 SET date_epoch_vacation = ? 
                 WHERE user_vacation = ? AND list_vacation = ? AND robot_vacation = ? },
		$date_epoch, $sender, $list_name, $list_robot
	    )
	    :
	    $sdm->do_prepared_query(
		q{INSERT
                  INTO vacation_table
		  (user_vacation,list_vacation,robot_vacation,date_epoch_vacation)
                  VALUES (?, ?, ?, ?) },
		$sender, $list_name, $list_robot, $date_epoch
	    )

	    ) {
	    $log->syslog('err', 'Unable to update/insert for sender %s and list %s',
			 $sender,
			 $list_address);
	}
	$log->syslog(
	    'notice',
	    'Vacation : INSERT/UPDATE base '
	    ) if ($debug);
	$return=0;
    }

    $sth->finish;
    return $return;
}


# Packages must return true
1;

