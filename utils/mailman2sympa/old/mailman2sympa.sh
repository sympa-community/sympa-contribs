#!/bin/sh

# USAGE: ./mailman2sympa nom_fichier
# Le fichier contient la liste des listes à migrer

. conf/mailman2sympa.conf

if [ ! -d $WDIR ]; then
	mkdir -p $WDIR
fi

if [ $# = 0 ] ; then
	ls -1 $MAILMAN_VAR/lists/ | sed 's=/==g' | tr '[:upper:]' '[:lower:]'  > $WDIR/mailman-lists
	set $WDIR/mailman-lists
else
	echo "$@" | tr '[:upper:]' '[:lower:]' > $WDIR/mailman-lists
	set $WDIR/mailman-lists
fi

if [ ! -d $EXPL ] ; then
	mkdir $EXPL
	fi

if [ ! -d $WDIR/lists ] ; then
	mkdir $WDIR/lists
	fi
	
if [ ! -d $WDIR/csv ] ; then
	mkdir $WDIR/csv
	fi
echo
echo Picking up configuration of mailman lists

for f in `cat $WDIR/mailman-lists` ; do
	if [ -f $MAILMAN_VAR/lists/$f/config.pck ]; then
	        $MAILMAN_HOME/bin/dumpdb $MAILMAN_VAR/lists/$f/config.pck > $WDIR/lists/$f
	elif [ -f $MAILMAN_VAR/lists/$f/config.db ]; then
	        $MAILMAN_HOME/bin/dumpdb $MAILMAN_VAR/lists/$f/config.db > $WDIR/lists/$f
	else
		echo "Warning list $f not found - skipping"
		sed -i -e "/^$f\$/d" $WDIR/mailman-lists
		continue
	fi
        perl -pe 's/\\([0-3][0-7][0-7])/chr(oct($1))/eg;' $WDIR/lists/$f > $WDIR/lists/$f.perl
        mv -f $WDIR/lists/$f.perl $WDIR/lists/$f
done

echo
echo Creating configuration files for Sympa lists
ALIASES="$WDIR/aliases-sympa"
for l in `cat $WDIR/mailman-lists` ; do
	if [ ! -d $EXPL/$l ] ; then
		mkdir $EXPL/$l
	fi
	echo -n "" > $ALIASES
	echo -n "" > $WDIR/csv/import_admins.csv
	awk -v LIST=$l -v ALIASES=$ALIASES -v PREFIX=$ALIAS_PREFIX -v DOMAIN=$DOMAIN -v SMTPSCRIPTPATH=$SYMPA_SMTPSCRIPTS -v OWNER=$DEFAULT_OWNER -v WDIR=$WDIR -f awk/mailman2sympa.awk $WDIR/lists/$l > $WDIR/$l.config
	if [ -f $EXPL/$l/config ] ; then
		echo "Skipping $l - config already exists"
	else
		mv $WDIR/$l.config $EXPL/$l/config
	fi
done

echo
echo Creating subscribers files

echo -n "" > $WDIR/csv/import_users.csv
echo -n "" > $WDIR/csv/import_subscribers.csv
for  l in `cat $WDIR/mailman-lists` ; do 
	awk -v EXPL=$EXPL -v LIST=$l -v WDIR=$WDIR -v NOMAIL=$TAKE_NOMAIL -v DATE=$DEFAULT_DATE -f awk/subscribers.awk $WDIR/lists/$l
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
