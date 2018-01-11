#!/usr/bin/env perl
#===============================================================================
#
#         FILE: sympatoldap.pl
#
#        USAGE: ./sympatoldap.pl  
#
#  DESCRIPTION: Push sympa lists entries in a LDAP Directory
#
# REQUIREMENTS: ---
#       AUTHOR: Thomas vO
# ORGANIZATION: DSI Rectorat — Académie de Grenoble
#      VERSION: 0.1
#      LICENSE: 3-Clause BSD (https://opensource.org/licenses/BSD-3-Clause)
#    COPYRIGHT: Copyright (c) 2018, Thomas vO
#      CREATED: 01/04/2018 11:07:21 AM
#  INSPIRATION: d'après listaccountsympad de Stephane URBANOVSKI (académie de Nancy-Metz)
#               et sympa2ldap.pl de Guy PARESSANT (académie de Nantes)
#===============================================================================

use strict;
use warnings;
use utf8;
use feature qw(say);
use open ":encoding(utf8)";
use Encode;
use Data::Dumper;
use DateTime;
use Net::SMTP;
use Net::LDAP;
use Config::Simple;
use Fcntl ':flock';

##########################################
### Chemin du fichier de configuration ###
##########################################
#my $confile = "/appli/sympa/sympaV6.2.12/sympa/conf/contribsympa.conf";
my $confile = "sympatoldap.conf";

#################################
### Autres variables globales ###
#################################
my $nomprog = 'sympatoldap';
my $VERSION = "$nomprog, v1.00 2018/01/04";
my $debug   = 0;
my $err     = 0;
my $attrs   = ['objectClass', 'cn', 'description', 'inetMailGroupStatus', 'mail',
    'owner', 'mailEquivalentAddress', 'mailAlternateAddress', 'mailHost',
    'mgmanHidden', 'mgrpRFC822MailMember'];
my $classes = ['top', 'inetMailGroup', 'groupOfUniqueNames',
    'inetLocalMailRecipient', 'inetMailGroupManagement'];
my @textMail = ();
# structure reprenant toutes les données :
my $lists   = {};
# on a donc une structure qui ressemble à : 
# $lists->{robot}->{config file => '',
#                   …[autres paramètres du robot]
#                   lists => { nom_liste => { objectClass => [],
#                                             …[autres attributs LDAP]
#                                             subject => ''
#                                             …[autres paramètres config]
#                                           }}}

#######################################
### Paramètres en ligne de commande ###
#######################################
my ($cla) = @ARGV;
if (defined($cla)) {
    # si on a des arguments
    if ($cla !~ /^-d/) {
        # si ces arguments ne matchent pas '-d'
        say "Usage :\n'$0 [-h] [-d[n]]'";
        say '-h    : Print this help and exit';
        say "-d[n] : Set $0 in debug mode : keep it attached to the terminal";
        say '        n=1 is quiet(default), 6 is most verbose';
        exit(0);
    } else {
        # sinon, on fixe le niveau de debug pour la suite
        $debug = 1;
        if ($cla =~ /^-d\s*(\d+)/) {
            $debug = $1;
        }
        say "Debug mode $debug";
    }
}

####################################
### Lecture du fichier de config ###
####################################
my $cfg = new Config::Simple($confile);
my $conf = $cfg->vars();
# on se retrouve avec une structure { section.param => valeur }

########################################
### Gestion du daemon et des verrous ###
########################################
my $pidfile = $conf->{'main.pidfile'};
if (not $debug) {
    # pas de debug, on passe la tache en arrière plan
    if (($_ = fork) != 0) {
        print( "Starting server, pid $_");
        exit(0);
    }
    # création du fichier de lock, et écriture du pid
    open my $lock, '>>', $pidfile or die "Could not open $pidfile : $!";
    flock($lock, LOCK_EX) or die "Could not lock $pidfile : $!";
    print $lock "$$\n";
    # on met les permissions du user et du groupe aux process/fichiers
    $( = $) = (getgrnam($conf->{'sympa.group'}))[2];
    $< = $> = (getpwnam($conf->{'sympa.user'}))[2];
    # récupère la demande d'interruption pour arrêter proprement
    $SIG{'TERM'} = 'sigterm';
}

###########################
### Programme principal ###
###########################
# si debug > 5, on dumpe la conf
say Dumper($conf) if ($debug >= 6);

# on va chercher la config des robots
$err = get_robot_list();
test_err($err);

# liste des listes à modifier
my @modiflists;
# variable globale de temps de scan
my $scanInt = $conf->{'scan.default'};
# commande qui permettra de voir si des listes ont été modifiées
my $getlistnewerthanflag = 'find '.$conf->{'sympa.expl'}.' -type f -name "config" -newer '.$conf->{'main.flagfile'};

# boucle infinie
my $end = 0;
my ($lastcheck, $recheck) = (0, 1);
while (not $end) {
    say "Next check in $scanInt seconds" if ($debug >= 2);
    until (($end) or (@modiflists) or ($recheck)) {
        # tant que on a pas la fin, ou un recheck, ou des listes modifiées
        # on attend scanInt, on vérifie si des listes ont changé, on met
        # à jour recheck
        sleep($scanInt);
        push(@modiflists, `$getlistnewerthanflag`);
        say "@modiflists" if ($debug >= 2);
        if ((time() - $lastcheck) > $scanInt) {
            $recheck = 1;
        }
        say "ScanInt: $scanInt - Recheck: $recheck" if ($debug >= 6);
    }
    if (connect_ldap()) {
        if ($recheck) {
            # remise à zéro du recheck
            $recheck = 0;
            # heure de la dernière modif
            $lastcheck = time();
            # on lance le check quotidien
            $err = daily_check();
            # 1 => trop de listes avec le même cn dans le ldap
            if ($err == 1) {
                say "Too much lists with same cn in LDAP Directory, giving up!" if ($debug);
                # next évite au flagfile de se faire `touch`er
                next; 
            }
            # on touche le flagfile
            system("touch ".$conf->{'main.flagfile'});
        } elsif ( @modiflists ) {
            # il y a des listes modifiees
            $err = lists_modification(@modiflists);
            if ($err == 1) {
                say "Too much lists with same cn in LDAP Directory, giving up!" if ($debug);
                # next évite au flagfile de se faire `touch`er
                next; 
            }
            # on touche le flagfile
            system("touch ".$conf->{'main.flagfile'});
        }
    }
}

# fin du programme
if (not $debug) {
    unlink $pidfile;
}
exit(0);

##################
### Procédures ###
##################
sub test_err {
    # sortie en retournant le code d'erreur
    my $e = shift;
    if ($e) {
        say "Erreur numéro $e";
        exit($e);
    }
}

sub get_robot_list {
    # on recupere la liste des robots sur le serveur et on boucle sur chaque robot
    my $getrobotlist = 'find '.$conf->{'sympa.home'}.' -name robot.conf';
    say "Looking for list robot configuration files" if ($debug >= 2);
    for my $r (`$getrobotlist`) {
        chomp($r);
        $r =~ s/^($conf->{'sympa.home'}\/(.*?)\/robot.conf)$/$2/;
        $lists->{$r} = {
            confile => $1,
            lists  => {},
        };
        say "Found config file for $r" if ($debug >= 3);
        open my $botconf, '<', $lists->{$r}->{'confile'} or die "Cannot read config file for $r: $!";
        # on ouvre le fichier de conf du robot et on le parse
        while (my $confline = <$botconf>) {
            chomp($confline);
            # on zappe les commentaires
            next if ($confline =~ m/^\s*#/);
            if ($confline =~ m/^\s*([^\s]+)\s+([^\s]+)\s*$/) {
                # param valeur
                $lists->{$r}->{$1} = $2;
                say "Robot $r, parameter $1 has value $2" if ($debug >= 5);
            }
        }
        close $botconf;
        if ($conf->{'lists.mainrobot'} eq $r) {
            # c'est le robot "principal" du serveur
            $lists->{$r}->{'primary'} = 1;
        } else {
            # sinon, on met primary à 0
            $lists->{$r}->{'primary'} = 0;
        }
        if ($conf->{'lists.aliases'} eq $r) {
            # il faut créer des aliases en 'main.domaine'
            $lists->{$r}->{'createAliases'} = 1;
        } else {
            # sinon, on ne crée pas d'aliases
            $lists->{$r}->{'createAliases'} = 0;
        }
        say Dumper($lists->{$r}) if ($debug >= 6);
    }
    return 0;
}

sub connect_ldap {
    # on se connecte à l'annuaire pour voir s'il répond
    my $ldap = Net::LDAP->new($conf->{'ldap.host'}, port => $conf->{'ldap.port'});
    my $result = $ldap->bind(dn => $conf->{'ldap.binddn'}, password => $conf->{'ldap.bindpwd'});
    if ($result->code()) {
        say 'Cannot connect to LDAP server: '.$result->code if ($debug);
        mail_msg('Cannot login to LDAP server: '.$result->code);
        $scanInt = $conf->{'scan.error'};
        $ldap->unbind;
        return 0;
    }
    $ldap->unbind;
    return 1;
}

sub mail_msg {
    my $msg = shift;
    push(@textMail, $msg);
}

sub sendMail {
    # si $textMail n'a rien, on zappe
    if (@textMail < 1) {
        @textMail = ();
        return 0;
    }
    say 'Sending mail report' if ($debug);
    # sinon, on construit le mail
    my $d = DateTime->now();
    my $h = `hostname`;
    chomp($h);
    my $smtp = Net::SMTP->new('localhost');
    $smtp->mail('root@'.`hostname`);
    $smtp->to($conf->{'main.report'});
    $smtp->data();
    $smtp->datasend('To: '.$conf->{'main.report'}."\n");
    $smtp->datasend("Subject: [$nomprog] Report for $nomprog on $h (".$d->ymd.")\n");
    $smtp->datasend("\n");
    $smtp->datasend("This is $VERSION\n");
    $smtp->datasend("Running on $h, the ".$d->ymd().' at '.$d->hms()."\n");
    $smtp->datasend("Synchronizing LDAP entries for sympa lists:\n\n");
    $smtp->datasend(join("\n", @textMail));
    $smtp->dataend();
    $smtp->quit;
    @textMail = ();
    return 1;
}

sub daily_check {
    say "Daily_check" if ($debug);
    mail_msg('Daily checking of sympa/ldap mails and aliases:');
    # on fait la liste des robots avec la conf
    get_robot_list();
    # pour chaque robot dans $lists
    while (my ($r, $robot) = each %{$lists}) {
        # récup des listes sur sympa
        say "Getting lists configuration for $r" if ($debug >= 3);
        mail_msg("Getting lists configuration for $r");
        get_lists_for_robot($r);
        # pour chaque liste
        while (my ($l, $list) = each %{$lists->{$r}->{'lists'}}) {
            my $n = get_listinfo_from_ldap($r, $l);
            if ($n == 0) {
                # liste inexistante, on la crée (avec les aliases)
                # si le statut est ok
                if ($lists->{$r}->{'lists'}->{$l}->{'status'} eq 'open') {
                    create_list_and_aliases($r, $l);
                } else {
                    say 'Status is '.$lists->{$r}->{'lists'}->{$l}->{'status'}.
                        " for list $l ($r), so no creation!" if ($debug);
                    mail_msg('Status is '.$lists->{$r}->{'lists'}->{$l}->{'status'}.
                        " for list $l ($r), so no creation!");
                }
            } elsif ($n == 1) {
                # liste existante, à modifier ?
                test_modify_list_or_aliases($r, $l);
            } elsif ($n == 2) {
                # plusieurs listes avec ce cn -> erreur
                say "Too much cn for list $l (robot $r)!" if ($debug);
                mail_msg("Too much cn for list $l (robot $r)!");
                return 1; 
            } else {
                # TODO: problèm de connexion au LDAP
            }
        }
        # TODO: il faut maintenant checker chaque liste LDAP ayant $r pour
        # mailHost pour vérifier qu'elle existe dans sympa
    }
    # envoi du mail de CR
    sendMail();
    return 0;
}

sub get_lists_for_robot {
    my $r = shift;
    say "Get lists for robot $r" if ($debug);
    my $getlistslist = 'find '.$conf->{'sympa.expl'}.'/'.$r.' -type f -name "config"';
    # sur le serveur, on va chercher les différentes listes du robot
    for my $l (`$getlistslist`) {
        chomp($l);
        $l =~s/^($conf->{'sympa.expl'}\/$r\/(.*?)\/config)$/$2/;
        $lists->{$r}->{'lists'}->{$l} = { confile => $1};
        say "Found config file for $l" if ($debug >= 3);
        open my $listconf, '<', $lists->{$r}->{'lists'}->{$l}->{'confile'} 
            or die "Cannot read config file for $l ($r): $!";
        my $flagown = 0;
        my @owners = ();
        while (my $confline = <$listconf>) {
            chomp($confline);
            next if ($confline =~ m/^\s*#/);
            # on récupère ensuite les items de config suivants :
            # owner, subject, visibility, status
            if ($flagown and $confline =~ m/^email (.*)$/) {
                push(@owners, $1);
                $flagown = 0;
                next;
            }
            if ($confline =~ m/^subject (.*)$/) {
                $lists->{$r}->{'lists'}->{$l}->{'subject'} = $1;
            } elsif ($confline =~ m/^status (\w+)$/) {
                $lists->{$r}->{'lists'}->{$l}->{'status'} = $1;
            } elsif ($confline =~ m/^visibility (\w+)$/) {
                $lists->{$r}->{'lists'}->{$l}->{'visibility'} = $1;
            } elsif ($confline =~ m/^owner/) {
                $flagown = 1;
                next;
            }
        }
        $lists->{$r}->{'lists'}->{$l}->{'owners'} = \@owners;
        close $listconf;
        say Dumper($lists->{$r}->{'lists'}->{$l}) if ($debug >= 6);
    }
}

sub get_listinfo_from_ldap {
    my ($r, $list) = @_;
    say "Getting LDAP data for $list ($r)" if ($debug);
    my $ldap = Net::LDAP->new($conf->{'ldap.host'}, port => $conf->{'ldap.port'});
    $ldap->bind(dn => $conf->{'ldap.binddn'}, password => $conf->{'ldap.bindpwd'});
    # on cherche la liste dans le ldap
    my $msg = $ldap->search(
        base   => $conf->{'ldap.base'},
        filter => "(&(cn=$list)(objectClass=inetMailGroupManagement))",
        attrs  => $attrs );
    $msg->code() and return 5;
    $ldap->unbind;
    if ($msg->entries == 0) {
        # il n'y en a pas, on renvoie 0
        say "No list $list in LDAP directory!" if ($debug);
        return 0;
    } elsif ($msg->entries == 1) {
        # il y en a une, on récupère les données et on renvoie 1
        foreach my $li ($msg->entries) {
            my $l = $li->dn();
            $l =~ s/^cn=(.*?),$conf->{'lists.public'}$/$1/;
            $lists->{$r}->{'lists'}->{$l}->{'dn'} = $li->dn;
            say 'List found: '.$li->dn if ($debug >= 2);
            foreach my $a (@{$attrs}) {
                if ($li->exists($a)) {
                    $lists->{$r}->{'lists'}->{$l}->{$a} = $li->get_value($a, asref => 1);
                }
            }
            # tout est basé sur mgrpRFC822MailMember, s'il n'est pas là, c'est bizarre
            if (not $li->exists('mgrpRFC822mailmember')) {
                mail_msg('Mail problem for '.$li->dn);
                say 'Mail problem for '.$li->dn if ($debug);
            } elsif ($li->get_value('mgrpRFC822mailmember') !~ m/^.*?\@$r$/) {
                say 'Mail problem for '.$l.': strange redirector!' if ($debug);
            }
        }
        return 1;
    } else {
        # il y en a plus, c'est étrange
        say "Too much lists found for $list" if ($debug);
        return 2;
    }
}

sub create_list_and_aliases {
    my ($r, $l) = @_;
    say "Create list $l and its aliases ($r) in LDAP" if ($debug);
    mail_msg("Create list $l and its aliases ($r) in LDAP");
    # création liste principale dans 'lists.public'
    my $ldap = Net::LDAP->new($conf->{'ldap.host'}, port => $conf->{'ldap.port'});
    $ldap->bind(dn => $conf->{'ldap.binddn'}, password => $conf->{'ldap.bindpwd'});
    my $dn = 'cn='.$l.','.$conf->{'lists.public'};
    # liste cachée par défaut
    my $hid = 'true';
    # liste visible si 'lists.pubvisi'
    $hid = 'false' if ($lists->{$r}->{'lists'}->{$l}->{'visibility'} =~ $conf->{'lists.pubvisi'});
    my $mail = $l.'@'.$r;
    $mail = $l.'@'.$conf->{'main.domaine'} if ($conf->{'lists.aliases'} eq $r);
    my $attributes = {
        objectClass           => $classes,
        cn                    => $l,
        description           => $lists->{$r}->{'lists'}->{$l}->{'subject'},
        mail                  => $mail,
        mgmanHidden           => $hid,
        owner                 => $lists->{$r}->{'lists'}->{$l}->{'owners'},
        inetMailGroupStatus   => 'active',
        mgrpRFC822MailMember  => $l.'@'.$r,
        mailHost              => $r};
    $ldap->add($dn, attrs => $attributes) if (not $conf->{'main.test'});
    say "$dn".Dumper($attributes) if ($debug >= 6);
    # création aliases dans 'lists.conceal'
    foreach my $s (split(',', $conf->{'sympa.suffix'})) {
        say "Create alias $l$s ($r) in LDAP" if ($debug >= 3);
        my $adn = 'cn='.$l.$s.','.$conf->{'lists.conceal'};
        my $mail = $l.$s.'@'.$r;
        $mail = $l.$s.'@'.$conf->{'main.domaine'} if ($conf->{'lists.aliases'} eq $r);
        my $aattrs = {
            objectClass           => $classes,
            cn                    => $l.$s,
            description           => "Alias $s pour ".$lists->{$r}->{'lists'}->{$l}->{'subject'},
            mail                  => $mail,
            mgmanHidden           => 'true',
            owner                 => $lists->{$r}->{'lists'}->{$l}->{'owners'},
            inetMailGroupStatus   => 'active',
            mgrpRFC822MailMember  => $l.$s.'@'.$r,
            mailHost              => $r};
        $ldap->add($adn, attrs => $aattrs) if (not $conf->{'main.test'});
        say "$adn".Dumper($aattrs) if ($debug >= 6);
    }
    $ldap->unbind;
}

sub test_modify_list_or_aliases {
    my ($r, $l) = @_;
    say "Test or modify list $l ($r)" if ($debug);
    mail_msg("Test or modify list $l ($r)");
    # vérification fiche liste "principale"
    my $dn = 'cn='.$l.','.$conf->{'lists.public'};
    my $mods = {};
    my ($flagsubject, $flagowner) = (0, 0);
    # comparaison du sujet
    if ($lists->{$r}->{'lists'}->{$l}->{'description'} ne $lists->{$r}->{'lists'}->{$l}->{'subject'}) {
        $mods->{'description'} = $lists->{$r}->{'lists'}->{$l}->{'subject'};
        $flagsubject = 1;
    }
    # comparaison de la visibilité
    if ($lists->{$r}->{'lists'}->{$l}->{'visibility'} =~ $conf->{'lists.pubvisi'}) {
        $mods->{'mgmanHidden'} = 'false' if ($lists->{$r}->{'lists'}->{$l}->{'mgmanHidden'} eq 'true');
    } else {
        $mods->{'mgmanHidden'} = 'true' if ($lists->{$r}->{'lists'}->{$l}->{'mgmanHidden'} eq 'false');
    }
    # comparaison des proprios
    if (join(',', sort(@{$lists->{$r}->{'lists'}->{$l}->{'owner'}})) ne
        join(',', sort(@{$lists->{$r}->{'lists'}->{$l}->{'owners'}}))) {
        $mods->{'owner'} = $lists->{$r}->{'lists'}->{$l}->{'owners'};
        $flagowner = 1;
    }
    say Dumper($mods) if ($debug >= 6);
    my $ldap = Net::LDAP->new($conf->{'ldap.host'}, port => $conf->{'ldap.port'});
    $ldap->bind(dn => $conf->{'ldap.binddn'}, password => $conf->{'ldap.bindpwd'});
    say "Changes for $l ($r), updating LDAP list" if ($debug >= 2);
    $ldap->modify($dn, replace => $mods) if (not $conf->{'main.test'});
    # vérification des aliases
    foreach my $s (split(',', $conf->{'sympa.suffix'})) {
        say "Test or modify aliases for list $l ($r)" if ($debug >= 3);
        my $adn = 'cn='.$l.$s.','.$conf->{'lists.conceal'};
        # est-ce que l'alias de la liste existe ?
        my $exists = search_alias_in_ldap($r, $l.$s);
        if ($exists == 1) {
            # l'alias existe, on le modifie si nécessaire (flags mis sur liste principale)
            say "Modifying alias for list $l ($r) as it exists" if ($debug >= 3);
            my $adn = 'cn='.$l.$s.','.$conf->{'lists.conceal'};
            my $amods = {};
            if ($flagsubject) {
                $amods->{'description'} = "Alias $s pour ".$lists->{$r}->{'lists'}->{$l}->{'subject'};
            }
            if ($flagowner) {
                $amods->{'owner'} = $lists->{$r}->{'lists'}->{$l}->{'owners'};
            }
            if ($flagsubject or $flagowner) {
                say "Changes for subject or owners, updating $adn" if ($debug >= 2);
                $ldap->modify($adn, replace => $amods) if (not $conf->{'main.test'});
            }
        } elsif ($exists == 0) {
            # l'alias n'existe pas, on le crée
            say "Creating alias for list $l ($r) as it doesn't exist" if ($debug >= 3);
            my $mail = $l.$s.'@'.$r;
            $mail = $l.$s.'@'.$conf->{'main.domaine'} if ($conf->{'lists.aliases'} eq $r);
            my $aattrs = {
                objectClass           => $classes,
                cn                    => $l.$s,
                description           => "Alias $s pour ".$lists->{$r}->{'lists'}->{$l}->{'subject'},
                mail                  => $mail,
                mgmanHidden           => 'true',
                owner                 => $lists->{$r}->{'lists'}->{$l}->{'owners'},
                inetMailGroupStatus   => 'active',
                mgrpRFC822MailMember  => $l.$s.'@'.$r,
                mailHost              => $r};
            $ldap->add($adn, attrs => $aattrs) if (not $conf->{'main.test'});
            say "$adn".Dumper($aattrs) if ($debug >= 6);
        } elsif ($exists == 2) {
            # plusieurs fiches ldap renvoyées…
            say "Too much entries in LDAP with cn=$l$s!" if ($debug);
            mail_msg("Too much entries in LDAP with cn=$l$s!");
        } elsif ($exists == 5) {
            # erreur de connexion au ldap
            say "Error while searching cn=$l$s" if ($debug);
            mail_msg("Error while searching cn=$l$s");
        }
    }
    $ldap->unbind;
}

sub search_alias_in_ldap {
    my ($r, $list) = @_;
    say "Getting LDAP data for alias $list ($r)" if ($debug);
    my $ldap = Net::LDAP->new($conf->{'ldap.host'}, port => $conf->{'ldap.port'});
    $ldap->bind(dn => $conf->{'ldap.binddn'}, password => $conf->{'ldap.bindpwd'});
    # on cherche l'alias dans le ldap
    my $msg = $ldap->search(
        base   => $conf->{'ldap.base'},
        filter => "(&(cn=$list)(objectClass=inetMailGroupManagement))",
        scope  => 'subtree',
        attrs  => $attrs );
    $msg->code() and return 5;
    $ldap->unbind;
    if ($msg->entries == 0) {
        # s'il n'y en a pas, on renvoie 0
        say "No list $list in LDAP directory!" if ($debug >= 3);
        return 0;
    } elsif ($msg->entries == 1) {
        # s'il y en a un, on renvoie 1
        say "List $list found in LDAP directory" if ($debug >= 3);
        return 1;
    } else {
        # s'il y en a plus, on renvoie 2
        say "Too much lists found for $list" if ($debug >= 3);
        return 2;
    }
}

sub lists_modification {
    my @lists = @_;
    # @lists contient une liste de fichiers config de listes
    say "Lists modification: \n".join("\n", @lists) if ($debug);
    # Pour chaque liste plus récente que le flag
    foreach my $cf (@lists) {
        # on éclate le chemin pour avoir le robot et la liste
        my $r = $cf;
        $r =~ s#^$conf->{'sympa.expl'}/([^\/]+)/([^\/]+)/config$#$1#;
        my $l = $2;
        # on commence par récupérer la config de la liste
        open my $listconf, '<', $cf or die "Cannot open config file $cf: $!";
        my $flagown = 0;
        my @owners = ();
        while (my $confline = <$listconf>) {
            chomp($confline);
            next if ($confline =~ m/^\s*#/);
            # on récupère ensuite les items de config suivants :
            # owner, subject, visibility, status
            if ($flagown and $confline =~ m/^email (.*)$/) {
                push(@owners, $1);
                $flagown = 0;
                next;
            }
            if ($confline =~ m/^subject (.*)$/) {
                $lists->{$r}->{'lists'}->{$l}->{'subject'} = $1;
            } elsif ($confline =~ m/^status (\w+)$/) {
                $lists->{$r}->{'lists'}->{$l}->{'status'} = $1;
            } elsif ($confline =~ m/^visibility (\w+)$/) {
                $lists->{$r}->{'lists'}->{$l}->{'visibility'} = $1;
            } elsif ($confline =~ m/^owner/) {
                $flagown = 1;
                next;
            }
        }
        $lists->{$r}->{'lists'}->{$l}->{'owners'} = \@owners;
        close $listconf;
        say Dumper($lists->{$r}->{'lists'}->{$l}) if ($debug >= 6);
        # on peut maintenant récupérer les infos du ldap et gérer le cas
        my $n = get_listinfo_from_ldap($r, $l);
        if ($n == 0) {
            # liste inexistante, on la crée (avec les aliases)
            # si le statut est ok
            if ($lists->{$r}->{'lists'}->{$l}->{'status'} eq 'open') {
                create_list_and_aliases($r, $l);
            } else {
                say 'Status is '.$lists->{$r}->{'lists'}->{$l}->{'status'}.
                " for list $l ($r), so no creation!" if ($debug);
                mail_msg('Status is '.$lists->{$r}->{'lists'}->{$l}->{'status'}.
                    " for list $l ($r), so no creation!");
            }
        } elsif ($n == 1) {
            # liste existante, à modifier ?
            test_modify_list_or_aliases($r, $l);
        } elsif ($n == 2) {
            # plusieurs listes avec ce cn -> erreur
            say "Too much cn for list $l (robot $r)!" if ($debug);
            mail_msg("Too much cn for list $l (robot $r)!");
            return 1; 
        } else {
            # TODO: problèm de connexion au LDAP
        }
    }
    return 0;
}

__END__

