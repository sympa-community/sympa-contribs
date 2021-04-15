# Publisher

## Definition

This custom scenario condition allows the definition of users permitted to send
messages to a list without being owner/editor/member of it. Is is usefull for
enviroments where you have users that should be allowed to send to many lists
but he/she does not want to subscribe to them, e.g the president of a company.

This custom scenario condition is a response to my Feature Request [#669](https://github.com/sympa-community/sympa/issues/669).

## Installation
1. In the main sympa configurariton path, e.g. '/etc/sympa', create a folder called 'custom_conditions'.
2. Put publisher.pm file in this folder.
3. Put the configuration file, i.e. `publisher.conf`, in the main sympa configuration folder, e.g. `/etc/sympa`.
4. Add entries to the configuration file followind the format specified there.
5. Copy the send scenario files to the location where custom scenario file should be stored, e.g. `/etc/sympa/scenari`. See the [documentation](https://sympa-community.github.io/manual/customize/basics-scenarios.html) for all the information
6. Modify your send scenario files to include lines like these in the correct order:
```
CustomCondition::publisher([listname],[sender],)   smtp,dkim ->   request_auth
CustomCondition::publisher([listname],[sender],)   smime,md5 ->   do_it
```
7. The final `do_it` action can be changed to `editorkey` if you want the posts from the allowed user to be moderated by the editors of the list.
8. Check that all the files and folders mentioned in this readme file are readable by the system user executing sympa.
9. Restart sympa and apache services.

## Flaws
- These services should be restarted every time the configuration file is changed.
- The name of the list defined in the configuration file should not include the domain name.
- The configuration file does not support wildcards.
- I have only tested this custom scenario condition in sympa 6.2.16 under Debian Stretch.

## Final note
Feel free to modify this code to your wish and, please, contribute your changes, corrections and improvements.

## License
MIT, (c) 2019 Luis A. Martínez. See the [LICENSE file](LICENSE) for details.