# Split sympa logs

**Disclaimer**: this has been used in production on a Debian Stretch server, with Sympa 6.2.16 with SysVinit service

By default, all sympa logs are sent to `rsyslog`, which put them in `/var/log/syslog`.

If you want to ease seeking things in logs, you may want to put each processus log to a dedicated log file.

1. create `/var/log/sympa`:

    mkdir /var/log/sympa
    chown root:adm /var/log/sympa
    chmod 750 /var/log/sympa

2. put the provided `rsyslog.d/sympa.conf` in `/etc/rsyslog.d/` and restart `rsyslog`
3. put the provided `logrotate.d/sympa` in `/etc/logrotate.d/`

That's all 🙂
