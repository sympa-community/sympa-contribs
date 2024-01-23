#!/bin/sh

. ./conf/mailman2sympa.conf

./scripts/loadsubscribers.pl

# [ -x "${SYMPA_SMTPSCRIPTS}"/upgrade_sympa_passwd.pl ] && "${SYMPA_SMTPSCRIPTS}"/upgrade_sympa_passwd.pl
