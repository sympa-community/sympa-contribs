# sympatoldap

This script is intended to run as a daemon on a sympa server.

Its purpose is to create LDAP entries for every list (and its aliases) whose
status is `open` on the LDAP server.

Its status is WORK IN PROGRESS, but seems to behave correctly in debug mode.

## How-to

To run this on your sympa server:

* put `sympatoldap.pl` in `/usr/local/sbin/` (or any other directory you choose)
* put `sympatoldap.conf` in `/usr/local/etc/` (or any other directory you choose)
* edit `sympatoldap.pl` and change the line :

      my $confile = "/usr/local/etc/sympatoldap.conf";
  with the path to where you put `sympatoldap.conf`
* edit `sympatoldap.conf` to adapt to your settings
* pick either `sympatoldap.sysv` or `sympatoldap.service` and copy where
  needed, in most cases:
  - `/etc/init.d/sympatoldap` for `sympatoldap.sysv`
  - `/etc/systemd/system/sympatoldap.service` for `sympatoldap.service`
* activate the service:
  - `service sympatoldap start`
  - `systemctl start sympatoldap`
* do not forget to activate at boot if needed.

## Warnings

* does not work for sympa servers with no robots (list data must look like
  /var/path/to/ROBOT/list)
* comments are in french
* attributes used for LDAP are hard-coded for the moment:
  - `mgrpRFC822MailMember` is used to "forward" mail
  - `mgmanHidden` is used to manage visibility of list
  - thus the LDAP entry looks like:

```LDIF
    dn: cn=<LIST>,<CONFIG.FILE-lists.public>
    objectClass: top
    objectClass: inetMailGroup
    objectClass: groupOfUniqueNames
    objectClass: inetLocalMailRecipient
    objectClass: inetMailGroupManagement
    mgmanHidden: true || false
    description: <SUBJECT>
    owner: <OWNER-MAIL-1>
    owner: <OWNER-MAIL-2>
    inetMailGroupStatus: active
    mgrpRFC822MailMember: <LIST>@<ROBOT>
    mailHost: <ROBOT>
    mail: <LIST>@<DOMAIN>
    cn: <LIST>
```

## TODOs, roadmap and ideas

* extract `$attrs` and `$classes` from script and put them in config file to be
  less specific and more adjustable
* clean config file: some variables are not used
* is it a good idea to automatically create in sympa robot lists which exist in
  LDAP directory and whose mailHost is the robot?
* translate comments
* test and adapt for ldaps on port 636


