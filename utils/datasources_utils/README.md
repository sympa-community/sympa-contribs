# Sympa datasource tester

Usage : ./datasource [-h] [-v] [-q] [-c list_config_file_path] [-i source_index|-a] [-d lists_dir] [-l list_name] [-r robots_conf] [(advanced options)]

	-h : this help
	-v : verbose mode, outputs all found data
	-q : quiet mode, outputs nothing, only set return code depending on success of operation

	-c : list config file path, set to - if config given through stdin (in this case you might want to also give -l and -d)
	-i : index of datasource to test (given in datasources list), will list all datasources without it
	-a : test all datasources

	-d : sympa lists directory, not needed if list config file under it given through -c
	-l : list name (full, like list@domain), not needed if list config file given through -c
	-r : robots config path (defaults to ../etc/ relative to -d, only needed if testing remote symap list inclusion using robot certificate

## Advanced options

	--db-dsn : Sympa database DSN, only used when testing local list inclusion
	--db-user : Sympa database user, only used when testing local list inclusion
	--db-password : Sympa database password, only used when testing local list inclusion

## Requirements (depending on used datasources types)
	php-pdo and related drivers
	php-curl
