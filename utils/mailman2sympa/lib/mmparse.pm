# mmparse.pm
#
#   Parse the output of mailman's dumpdb command.  Returns a hash.
#   Author: John Bazik <jsb at cs.brown.edu>
#
# Copyright 2010 Brown University
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

package mmparse;

use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw(mmparse);

our $debug = 0;

sub mmparse {
   my $mmcfg = shift;
   #
   # skip to the beginning
   #
   $mmcfg =~ /[^{]*/sg;

   my @stk;
   while (1) {
      #
      # single-quoted string
      #
      if ($mmcfg =~ /\G\s*([ur]+)?'([^'\\]*(?:\\.[^'\\]*)*)'/scg) {
         push @stk, defined $2 ? procstr($1, $2) : '';
         warn "STRING->'$1'\n" if $debug;
      }
      #
      # double-quoted string
      #
      elsif ($mmcfg =~ /\G\s*([ur]+)?"([^"\\]*(?:\\.[^"\\]*)*)"/scg) {
         push @stk, defined $2 ? procstr($1, $2) : '';
         warn qq(STRING->"$1"\n) if $debug;
      }
      #
      # pretty-printed reference (just save as a string)
      #
      elsif ($mmcfg =~ /\G\s*<([^>\\]*(?:\\.[^>\\]*)*)>/scg) {
         push @stk, $1;
         warn qq(REF->"$1"\n) if $debug;
      }
      #
      # number
      #
      elsif ($mmcfg =~ /\G\s*(\d+(?:\.\d+)?)/scg) {
         push @stk, $1;
         warn "NUMBER->$1\n" if $debug;
      }
      #
      # a word
      #
      elsif ($mmcfg =~ /\G\s*(\w+)/scg) {
         push @stk, $1;
         warn "WORD->$1\n" if $debug;
      }
      #
      # start of an array or tuple
      #
      elsif ($mmcfg =~ /\G\s*[\[(]/scg) {
         push @stk, undef;
         warn "ARRAY START\n" if $debug;
      }
      #
      # start of a hash
      #
      elsif ($mmcfg =~ /\G\s*\{/scg) {
         push @stk, undef;
         warn "HASH START\n" if $debug;
      }
      #
      # end of an array or tuple
      #
      elsif ($mmcfg =~ /\G\s*[\])]/scg) {
         my @array;
         while (@stk) {
            my $elmt = pop @stk;
            last unless defined $elmt;
            unshift @array, $elmt;
         }
         push @stk, \@array;
         warn "ARRAY END\n" if $debug;
      }
      #
      # end of a hash
      #
      elsif ($mmcfg =~ /\G\s*\}/scg) {
         my %hash;
         while (@stk) {
            my $val = pop @stk;
            last unless defined $val;
            my $key = pop @stk;
            $hash{$key} = $val;
         }
         push @stk, \%hash;
         warn "HASH END\n" if $debug;

         last if @stk == 1;	# done processing
      }
      #
      # skip everything else - comments?
      #
      elsif ($mmcfg =~ /\G([^\w'"\d\[\]{}<>()]+)/scg) {
         warn "SKIP->$1\n" if $debug;
         # skip everything else
      }
      elsif ($mmcfg =~ /\G$/scg) {
         die "parsing failed, stack contains ", scalar(@stk), " elements\n";
      }
   }
   return $stk[0];
}

#
# procstr
#
#  Apply string conversions here.
#
sub procstr {
   my $mode = shift;	# u for unicode, r for raw
   my $string = shift;

   return $string;
}

1;
