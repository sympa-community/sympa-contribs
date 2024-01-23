# sympa-contribs

A repository for contributions to Sympa that won't fit in the code but could be
useful to others anyway.

Create a directory for your contrib and please provide a README.md at the root
of your contribution to help people understanding what it does and how to use
it You can also update this README by giving a brief description of your contribution and putting a direct link to your readme file.

## Current contributions

### Plugins

* [message_plugin_autoresponder](plugins/message_plugin_autoresponder/README.md): A simple autoresponder applicable to Sympa's mailing lists.
* [Whitelist](https://github.com/sshipway/sympa-6.2-plugins): Allow whitelists and Modlists as well as Blacklists for posting, managed via the web interface

### Custom scenario conditions

* [alreadyhaveopenedlists](custom-conditions/alreadyhaveopenedlists/README.md): checks if the sender already owns more than X opened lists
* [publisher](custom-conditions/publisher/README.md): defines users permitted to send messages to a list

### Utils

Tools for sysadmins.

* [datasources_utils](utils/datasources_utils/README.md): view and test list datasources and custom attributes datasources
* [mailman2sympa](utils/mailman2sympa/README.md): mailman 2.x migration scripts
* [sympatoldap](utils/sympatoldap/README.md): creates LDAP entries for every list (and its aliases) whose status is open on the LDAP server
* [splitting_daemons_logs](utils/splitting_daemons_logs/README.md): split Sympa processus logs into separated files
* [sqlite2mysql](utils/sqlite2mysql/README.md): attempt to convert sqlite to mysql
