# sympatoldap

This script is intended to run as a daemon on a sympa server.

Its purpose is to create LDAP entries for every list (and its aliases) whose
status is `open` on the LDAP server.

Its status is WORK IN PROGRESS, but seems to behave correctly in debug mode.

## Warnings

* does not work for sympa servers with no robots (list data must look like
  /var/path/to/ROBOT/list)
* comments are in french
* attributes used for LDAP are hard-coded for the moment:
  - `mgrpRFC822MailMember` is used to "forward" mail
  - `mgmanHidden` is used to manage visibility of list
  - thus the LDAP entry looks like:

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



