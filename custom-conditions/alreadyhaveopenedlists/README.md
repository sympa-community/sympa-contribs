# Already have opened lists

This custom scenario condition checks if the sender already owns more than X opened lists.

X is configurable in the scenario, if you omit it, its default value is 2.

## How to use it?

Put `alreadyhaveopenedlists.pm` in `custom_conditions` folder of `$SYSCONDIR` (usually `/home/sympa/etc/custom_conditions/`).
See the [documentation](https://www.sympa.org/manual/customize/custom-scenario-conditions.md) for details or other options.

Here’s a modified `create_list.public_listmaster` scenario, asking for the user to already own 3 opened lists to bypass list moderation:

```
title.gettext anybody by validation by listmaster required

is_listmaster([sender])   md5,smime -> do_it
CustomCondition::alreadyhaveopenedlists([sender], [domain], 3) smtp,md5,smime -> do_it
true()                    smtp,md5,smime -> listmaster,notify
```

## Why use it?

On a public instance, you may want to moderate lists asked by new users, but let users who already have asked lists for legit purpose to open lists without being moderated.

## Warning

Custom scenario conditions are cached by Sympa for one hour.
Don’t be confused if the user still does not pass the condition after you opened his/her pending lists.

## License

MIT, (c) 2019 Framasoft. See the [LICENSE file](LICENSE) for details.
