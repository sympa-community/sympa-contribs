## Presentation

Mailman2sympa is a set of scripts aimed to facilitate the migration
of mailing list managed by mailman to sympa.

The problem with such scripts is that they are used only once by
an individual. So it may be difficult to find a permanent
project manager.

I hope that each user will have the good idea to send back all
enhancement they would have to apply to the package.

## Features

The version 0.0.3 of the package can do the following tasks:

- create one list in sympa for each list found in the
  mailman space.

- create the subscribers files et config files for each list
  with the appropriates attributes, when still relevant.

- creates an aliases file to be concatenated at the bottom
  of `/etc/aliases`.

- split the archives stored by mailman into the mhonarc
  archive directory

- in the limited extent, restore the Content-type header
  when the message is multipart, so that mhonarc may 
  nicely process attachments.

- load the subscribers files into the database. Can specify
  a different database `(NEW_DATABASE)` for testing. Change
  `NEW_DATABASE=DATABASE` for migration

This scripts gave me a good result, but I'm not sure they
would for you. If you have problems, I can take an hand,
but as my lists have already been migrated, I donr't have
anymore a test bed to run the software.

You can contact me at pallart@illico.org

Hope this helps.

Philippe Allart


DumperSwitchboard problem - edit $MAILMAN_HOME/bin/dumpdb as follows:
http://arkiv.netbsd.se/?ml=mailman-users&a=2007-07&t=4791032

### Required packages:
- gawk
- libdbd-csv-perl
- procmail (for archive migration)
- perl-JSON
- jq
- python2 (pickle and json modules)
