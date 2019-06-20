# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4

# Autoresponder message hook for Sympa
#
# Copyright 2020 IKEDA Soji
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.

package Sympa::Message::Plugin::Autoresponder;

use strict;
use warnings;

use Sympa;
use Sympa::Log;

our $VERSION = '0.001_01';

my $log = Sympa::Log->instance;

use constant gettext_id => 'Autoresponder message hook';

sub pre_distribute {
    my $module  = shift;    # "Sympa::Message::Plugin::Autoresponder"
    my $name    = shift;    # "pre_distribute"
    my $message = shift;    # Message object
    my %options = @_;

    my $subject = $message->{decoded_subject};
    my $list    = $message->{context};
    my $sender  = $message->{sender};

    # Won't respond to these messages (See RFC 3834, 2):
    #
    # - Message which contains an Auto-Submitted header field, where that
    #   field has any value other than "no".
    my $auto_submitted =
        lc($message->head->mime_attr('Auto-Submitted') || '');
    if ($auto_submitted and $auto_submitted ne 'no') {
        $log->syslog(
            'info',
            '%s: Responding refused: Contains an Auto-Submitted header field',
            $message
        );
        return 1;
    }
    # - The destination of response would be a null address.
    unless ($message->{envelope_sender}
        and $message->{envelope_sender} ne '<>') {
        $log->syslog('info',
            '%s: Responding refused: Destination would be a null addrees',
            $message);
        return 1;
    }
    # - Commonly used as return addresses by responders.
    if (   0 == index $sender, 'owner-'
        or 0 < index $sender, '-request@'
        or 0 == index $sender, 'mailer-daemon@') {    #FIXME: any more?
        $log->syslog('info',
            '%s: Responding refused: Commonly used return addresses',
            $message);
        return 1;
    }
    # - Checking that the subject message has a content-type and content
    #   appropriate to that service.
    unless ($message->get_header('Content-Type')) {
        $log->syslog('info', '%s: Responding refused: No content type',
            $message);
        return 1;
    }
    my $eff_type = lc($message->head->mime_type || '');
    unless (0 == index $eff_type, 'text/'
        or 0 == index $eff_type, 'multipart/') {
        $log->syslog('info',
            '%s: Responding refused: Inappropriate content type "%s"',
            $message, $eff_type);
        return 1;
    }
    # - To avoid unwanted side-effects.
    if ($sender eq Sympa::get_address($list)
        or grep { $sender eq Sympa::get_address($list, $_) }
        qw(owner editor return_path subscribe unsubscribe)
        or $sender eq Sympa::get_address($list->{'domain'})
        or grep { $sender eq Sympa::get_address($list->{'domain'}, $_) }
        qw(owner return_path listmaster)) {
        $log->syslog('info',
            '%s: Responding refused: To avoid unwanted side-effects',
            $message);
        return 1;
    }
    # - Message which contains any header or content which makes it appear to
    #   the responder that a response would not be appropriate.
    if (grep {
            my $f = lc($_ || '');
            grep { $f eq $_ } qw(junk bulk list);
        } $message->get_header('Precedence')
    ) {
        $log->syslog('info',
            '%s: Responding refused: Inappropriate Precedence field',
            $message);
        return 1;
    }
    if (grep { $message->get_header($_) }
        qw(List-Id
        List-Help List-Unsubscribe List-Subscribe List-Post List-Owner
        List-Archive
        Archived-At)
    ) {
        $log->syslog('info', '%s: Responding refused: List-* field or such',
            $message);
        return 1;
    }
    # - Other reason.
    if ($message->{spam_status} and $message->{spam_status} eq 'spam') {
        $log->syslog('info', '%s: Responding refused: Possible spam',
            $message);
        return 1;
    }

    # Send response
    my $tpl = "$name.autoresponder";
    if (Sympa::send_file(
            $list, $tpl, $sender,
            {   auto_submitted => 'auto-replied',
                subject        => $subject,
                msg            => $message,
            }
        )
    ) {
        $log->syslog('info', '%s: Sent auto-response to %s',
            $message, $sender);
    }

    return 1;
}

1;
