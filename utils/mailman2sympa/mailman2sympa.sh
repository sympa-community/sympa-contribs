#!/bin/sh

# USAGE: ./mailman2sympa [list_name...]

. conf/mailman2sympa.conf

[ ! -d $WDIR ]		&& mkdir -p $WDIR
[ ! -d $EXPL ]		&& mkdir -p $EXPL
[ ! -d $WDIR/lists ]	&& mkdir $WDIR/lists
[ ! -d $WDIR/csv ]	&& mkdir $WDIR/csv

[ $# = 0 ] && set `ls -1 $MAILMAN_VAR/lists/ | sed 's=/==g'`
echo "$@" | tr '[:upper:]' '[:lower:]' > $WDIR/mailman-lists

echo
echo Picking up configuration of mailman lists

for f in `cat $WDIR/mailman-lists` ; do
	if [ -s $MAILMAN_VAR/lists/$f/config.pck ]; then
		mmdb=$MAILMAN_VAR/lists/$f/config.pck
	elif [ -s $MAILMAN_VAR/lists/$f/config.db ]; then
		mmdb=$MAILMAN_VAR/lists/$f/config.db
	else
		echo "Warning list $f not found - skipping"
		sed -i -e "/^$f\$/d" $WDIR/mailman-lists
		continue
	fi
	./scripts/mm2s_unpickle.py "$mmdb" > $WDIR/lists/$f
done

echo
echo Creating configuration files for Sympa lists

echo -n "" > $WDIR/aliases-sympa
echo -n "" > $WDIR/csv/import_admins.csv
echo -n "" > $WDIR/csv/import_users.csv
echo -n "" > $WDIR/csv/import_subscribers.csv

for l in `cat $WDIR/mailman-lists` ; do

	host_name=$(jq -r .host_name < $WDIR/lists/$l)
	if [ -n "$host_name" -a "$DOMAIN" != "$host_name" ]; then
	    echo "Skipping $l - domain doesn't match"
	    continue
	fi

	[ ! -d $EXPL/$l ] && mkdir $EXPL/$l
	
	./scripts/mm2s_config < $WDIR/lists/$l > $WDIR/$l.config
	./scripts/mm2s_aliases $l >> $WDIR/aliases-sympa
	./scripts/mm2s_admins < $WDIR/lists/$l >> $WDIR/csv/import_admins.csv
	./scripts/mm2s_users < $WDIR/lists/$l >> $WDIR/csv/import_users.tmp
	# mailman users are created per list so filter out duplicated emails
	# of course only one password will be used after but it's better than nothing
	sort $WDIR/csv/import_users.tmp |sort -u -k1,1 -t';' > $WDIR/csv/import_users.csv
	./scripts/mm2s_subscribers < $WDIR/lists/$l >> $WDIR/csv/import_subscribers.csv
	./scripts/mm2s_blacklist < $WDIR/lists/$l > $WDIR/$l.blacklist
	if jq -er .info < $WDIR/lists/$l >/dev/null; then
		info=$(jq -r .info < $WDIR/lists/$l)
		[ -n "$info" ] && printf '%s\n' "$info" > $WDIR/$l.info
	fi

	if [ -f $EXPL/$l/config ] ; then
		echo "Skipping $l - config already exists"
	else
		mv $WDIR/$l.config $EXPL/$l/config
		[ -s $WDIR/$l.info ] && mv $WDIR/$l.info $EXPL/$l/info
	fi

	if [ -s $WDIR/$l.blacklist ] ; then
		[ ! -d $EXPL/$l/search_filters ] && mkdir $EXPL/$l/search_filters
		mv $WDIR/$l.blacklist $EXPL/$l/search_filters/blacklist.txt
	else
		rm $WDIR/$l.blacklist
	fi
done

echo
echo Giving lists configuration to $USER
chown -R ${USER}:${GROUP} $EXPL

if [ $CONVERT_ARCHIVE = "yes" ] ; then
	echo
	echo Converting Archives
	for l in `cat $WDIR/mailman-lists` ; do
		./scripts/getmailmanarchive $l
	done
	echo "To regenerate web archive as listmaster go to 'Sympa Admin' and under 'Archive' is options to regenerate html"
fi

echo
echo Cleaning temporary files...

rm -rf $WDIR/lists/

echo 
echo -n "Do you want to import users/subscribers/admins from CSV into the sympa database? [y/n]: "
read IMPORT

if [ "$IMPORT" == "y" ]; then
	./loadsubscribers.sh
fi

echo
echo Done.
echo
