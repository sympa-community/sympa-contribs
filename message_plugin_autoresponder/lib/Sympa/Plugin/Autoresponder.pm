package Sympa::Message::Plugin::Autoresponder;

use strict;
use warnings;

use Sympa;
use Sympa::Log;

my $log = Sympa::Log->instance;

use constant gettext_id => 'Autoresponder message hook';

sub post_archive {
    my $module  = shift;    # "Sympa::Message::Plugin::Autoresponder"
    my $name    = shift;    # "post_archive"
    my $message = shift;    # Message object
    my %options = @_;

    my $subject = $message->{decoded_subject};
    my $list    = $message->{context};
    my $sender  = $message->{sender};

    # Send response
    my $tpl = 'post_archive.autoresponder';
    unless (
        Sympa::send_file(
            $list, $tpl, $sender,
            {   auto_submitted => 'auto-replied',
                subject        => $subject,
                msg            => $message,
            }
        )
    ) {
        $log->syslog('notice', 'Unable to send template "%s" to %s',
            $tpl, $sender);
    }

    return 1;
}

1;
