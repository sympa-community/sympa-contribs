#!/bin/sh

. ./conf/mailman2sympa.conf

./scripts/loadsubscribers.pl

# [ -x "${SYMPA_SMTPSCRIPTS}"/crypt_passwd.pl ] && "${SYMPA_SMTPSCRIPTS}"/crypt_passwd.pl
