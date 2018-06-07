# sqlite2mysql

Attempts to convert a sqlite sympa DB to mysql sympa DB.

## Usage: 

* extract mysql database structure
* CREATE DATABASE and USER in mysql
* dump sqlite into dump.sqlite: `sqlite3 /path/to/your/sqlite3/sympa/sympa .dump > dump.sqlite`
* convert dump: `cat dump.sqlite | perl sqlite2mysql.pl > dump.mysql`
* push dump into mysql: `mysql -u sympa -p sympa < dump.perl`
* for Debian users: `dpkg-reconfigure sympa`, don't forget to reconf database,
  you can ignore errors as database already exists

Working sympa structure for sympa 6.1.11~dfsg-5 on debian wheezy is in the
sample directory.

## Known bugs

* only tested with sympa 6.1.11~dfsg-5 on debian wheezy
* have to add a `robot_exclusion` field to `exclusion_table`: 

    robot_exclusion   varchar(80) NOT NULL,

* have to add `list_table` schema:

    CREATE TABLE list_table (
         creation_email_list    varchar(100) default NULL,
         creation_epoch_list    int(11),
         editors_list   text,
         name_list      varchar(50) NOT NULL,
         owners_list    text,
         path_list      text,
         robot_list     varchar(80) NOT NULL,
         status_list    varchar(15) default NULL,
         subject_list   text,
         topics_list    varchar(255) default NULL,
         web_archive_list       int,
         PRIMARY KEY (name_list, robot_list)
    ) ENGINE=MyISAM DEFAULT CHARSET=utf8;


