#!/usr/bin/perl

package CustomCondition::alreadyhaveopenedlists;

use strict;
use warnings;

use Sympa::List;
use Sympa::Log;

my $log = Sympa::Log->instance;

sub verify {
    my $email = shift or return;
    my $robot = shift or return;
    my $min   = shift || 2;

    my @lists = Sympa::List::get_which($email, $robot, 'owner');
    my $opened = 0;
    for my $list (@lists) {
        $opened++ if $list->{'admin'}{'status'} eq 'open';
    }
    if ($opened >= $min) {
        $log->syslog('info', 'User %s can open a new list on robot %s without moderation (already has %d lists opened, asked for %d)', $email, $robot, $opened, $min);
        return 1;
    } else {
        return 0;
    }
}

1;
