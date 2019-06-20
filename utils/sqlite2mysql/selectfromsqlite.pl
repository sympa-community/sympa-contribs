#!/usr/bin/env perl

### script to help convert sqlite dump to mysql dump for sympa DB
### inspiration from https://blog.bandinelli.net/index.php?post/2014/03/27/sqlite3-to-mysql

use strict;
use warnings;
use utf8;
use feature qw/say/;

my $struct = '/path/to/the/sympa.6.1.11.struct.mysql';
my $flag;

print "SET sql_mode='NO_BACKSLASH_ESCAPES';\n";

while (<>) {
        next if ($_ =~ m/PRAGMA/ or
                 $_ =~ m/BEGIN TRANSACTION/ or
                 $_ =~ m/COMMIT/ or
                 $_ =~ m/DELETE FROM sqlite_sequence/ or
                 $_ =~ m/INSERT INTO "sqlite_sequence"/);
        $_ =~ s/AUTOINCREMENT/AUTO_INCREMENT/g;
        $_ =~ s/DEFAULT 't'/DEFAULT '1'/;
        $_ =~ s/DEFAULT 'f'/DEFAULT '0'/;
        $_ =~ s/,'t'/,'1'/;
        $_ =~ s/,'f'/,'0'/;
        $_=~s/"/`/;$_=~s/"/`/;
        if (not defined $flag) {
                print $_;
                $flag = 'create' if ($_ =~ m/CREATE TABLE/);
                warn "\n$_" if ($_ =~ m/CREATE TABLE/);
        } elsif ($flag eq 'create') {
                if ($_ =~ m/^\);$/) {
                        print ") ENGINE=MyISAM DEFAULT CHARSET=utf8;\n";
                        undef $flag;
                        next;
                }
                my $l = $_;
                if ($l =~ m/KEY/) {
                        print $_;
                } else {
                        $l =~ s/^\s+(\S+).*$/$1/;
                        chomp $l;
                        open my $fh, '<:encoding(UTF-8)', $struct or die;
                        while (my $line = <$fh>) {
                                chomp $line;
                                #warn "---".$l."---\n---".$line."---";
                                if ($line =~ m/(\s|`)$l(\s|`)/ ) {
                                        print "$line\n";
                                        last;
                                }
                        }
                        close $fh;
                }
        }
}


__END__


