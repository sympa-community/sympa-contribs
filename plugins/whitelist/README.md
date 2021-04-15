# Whitelist/Modlist Extension for Sympa 6.2

## Authors

Steve Shipway, University of Auckland, 2012 - 2015
Luc Didry, Framasoft, 2020

## Purpose

This adds Whitelist and Modlist functionality to Sympa, by using an included scenario, and a custom action module to hold the required Perl code.

Note that this will only work in Sympa 6.2.x and not under 6.1.x

## Installing

NOTE: Your installation may use different directories to hold the various files.
Change the paths to what is appropriate for your system.

1. Copy `whitelist.pm` and `modlist.pm` to the `custom_actions` directory.
   These are the custom actions.
   If you only copy the w`hitelist.pm` then modlist functionality will be disabled.
   Either put them at the top level, or at robot level as you prefer.

2. Create default empty `whitelist.txt` and `modlist.txt` files in search_filters (or wherever your Sympa `search_filters` path is).
   These must exist as a default for lists that do not have a defined whitelist or modlist.

3. Install the `whitelist.tt2` template into the `web_tt2` directory.
   This is the admin pages for the whitelist and modlist.
   It goes into your `web_tt2` customisation directory.

4. Update `nav.tt2` on your system.
   This is where you add the new Whitelist and Modlist menu items.

   Add `[% PROCESS whitelist/admin.tt2 %]` after the `[% IF conf.use_blacklist != 'none' %]` block.

5. Update `search.tt2` and `review.tt2` on your system.
   These add the Whitelist and Modlist buttons to the subscribers review page.

   Add `[% PROCESS whitelist/links.tt2 %]` after the `[% IF conf.use_blacklist != 'none' %]` block.

6. Update `admin.tt2` on your system.
   This adds the white/modlist options to the list admin page.
   This is optional but recommended.

   Add `[% PROCESS whitelist/admin.tt2 %]` after the `[% IF conf.use_blacklist != 'none' %]` block.

7. Copy `fr` directory to your your `web_tt2` customisation directory.
   If you already have a `fr` directory in it, copy its content to your `fr` directory.

8. Copy `include.send.header` into your `scenari` directory.
   This activates the Whitelist and Modlist on all lists, though until you define some entries, all lists will get the default empty files you set up in step 2.

9. Restart the Sympa daemons, and restart your web server.
   This will pick up the changes.

10. TEST!
    Choose a list and verify that the Whitelist and Modlist tabs appear in the admin page.
    Try adding an entry to the whitelist and verify that it works and produces no errors.
    Make sure the tabs appear for Whitelist and Modlist in the web interface for list owners and admins.

Make sure file ownerships are correct.

## Translations

Create a folder named after the language code you want to add translations to and translate those files.
`fr` directory is a good example.
