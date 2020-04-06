Autoresponder message hook
==========================

Description
-----------

This is a simple autoresponder applicable to Sympa's mailing lists.

Installation
------------

  1. Copy `Autoresponder.pm` file into `$MODULEDIR/Sympa/Message/Plugin/`
     directory.

Configuration
-------------

  1. Prepare a mail template `mail_tt2/pre_distribute.autoresponder.tt2`.

  2. With your list, add following setting to `config`:
     ``` code
     message_hook
       pre_distribute Autoresponder
     ```
     Or, you may add "`Autoresponder`" to
     "Message hook / A hook on the messages before distribution" on
     "Edit List Configuration" - "Sending/receiving setup" page of your list.

Supported environments
----------------------

Sympa 6.2 or later with Perl 5.8.1 or later.

Author
------

IKEDA Soji <ikeda@conversion.co.jp>.

License
-------

This software is released under the MIT License.

