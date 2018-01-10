#!/usr/bin/env perl
#If your copy of perl is not in /usr/bin, please adjust the line above.
#
# Copyright (C) Academie de Nantes 2002
# Author: Guy PARESSANT
# mailto:rpm-sympa@ac-nantes.fr
#
# (C) 2017-2018 Academie de Grenoble - thomasvo@ac-grenoble.fr
#
# D'apres le programme listaccountsympad de Stephane URBANOVSKI <s.urbanovski@ac-nancy-metz.fr>
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
use strict;
use warnings;
use utf8;
use feature qw(say);
use open ":encoding(utf8)";
use Encode;
use Data::Dumper;
use Net::SMTP;
use Net::LDAP;
use Config::Simple;
use Fcntl ':flock';

##########################################
### Chemin du fichier de configuration ###
##########################################
#my $contribsympaconf = "/appli/sympa/sympaV6.2.12/sympa/conf/contribsympa.conf";
#my $contribsympaconf = "/appli/sympa/sympaV6.2.12/sympa/conf/contribsympa.conf";
my $contribsympaconf = "/home/tvo/contribsympa.conf";
 
##########################
### Variables globales ###
##########################
my $nomprog = 'sympa2ldap';
my $VERSION = "$nomprog, v6.00 2018/01/03";
my $debog   = 0;
my $parconf = {}; # hashref qui contiendra tous les parametres du fichier de configuration
my $paramo  = ""; # Nom des parametres obligatoires manquants

######################################
### parametre en ligne de commande ###
######################################
my ($pa) = @ARGV;
if (defined($pa)) {
    if ($pa !~ /^-d/) {
        print "Usage :\n'$0 [-h] [-d[n]]'\n
-h     : Print this help and exit
-d[n]] : Set $0 in debug mode : keep it attached to the terminal
         n=1 is quiet(default), 6 is most verbose\n";
         exit(0);
     } else {
         $debog = 1;
         if ($pa =~ /^-d\s*(\d+)/) {
             $debog = $1;
         }
         print "Debug mode $debog\n";
     }
 }

###############################################
### Lecture des parametres de configuration ###
###############################################
my $conf = new Config::Simple($contribsympaconf);
my $config = $conf->vars();

#############
### Suite ###
#############
my ($academie, $acad, @domaine, $H, $P, $B, $D, $W, $sympahome, @sympaexpl,
    $usersympa, $groupsympa,
    @listemailhost, @http_host, @ListesURL, $mailadmin, $defScanInterval,
    $errScanInterval, $verifInterval, $mailsympa, $flagFile, $aliasFile,
    $altFile, $debutpara, $ListesDN, $subOupublic, $subOuadmin, $visipublic,
    $testseul, $codageUTF8, @sympaSuffixe);
 
$academie         = instconf('academie'        , ''                                  , 'nom academie dans le domaine');
$acad             = 'ac-'.$academie;
$domaine[0]       = instconf('domaine'         , "$acad.fr"                          , '');
$H                = instconf('ldapHost'        , ''                                  , "nom de l'annuaire LDAP de donnees MAITRE");
$P                = instconf('ldapPort'        , '389'                               , '');
$B                = instconf('ldapBase'        , ""                                  , "branche annuaire pour l'academie");
$D                = instconf('ldapDN'          , ''                                  , 'dn du Directory Manager');
$W                = instconf('ldapPwd'         , ''                                  , 'password');
$sympahome        = instconf('sympahome'       , ''                                  , 'Directory home de sympa');
$usersympa        = instconf('sympauser'       , 'sympa'                             , '');
$groupsympa       = instconf('sympagroup'      , 'sympa'                             , '');
$sympaexpl[0]     = instconf('sympaexpl'       , ''                                  , 'Directory de stockage des listes sur sympa');
$mailadmin        = instconf('mailadmin'       , ''                                  , "Destinataire du mail d'erreur");
$defScanInterval  = instconf('scanIntDefault'  , '60'                                , '');
$errScanInterval  = instconf('scanIntError'    , '600'                               , '');
$verifInterval    = instconf('scanIntNormal'   , '90000'                             , '');
$mailsympa        = instconf('sympamail'       , 'sympa'                             , '');
$flagFile         = instconf('flagFile'        , "$sympahome/$nomprog.flag"          , '');
$aliasFile        = instconf('aliasFile'       , '/etc/postfix/sympa.aliases'        , '');
$altFile          = instconf('altFile'         , '/etc/postfix/sympa.alternates'     , '');
$listemailhost[0] = instconf('listsMailHost'   , ''                                  , 'Mailhost des listes : nom du serveur sympa');
$http_host[0]     = instconf('listsHttpHost'   , $domaine[0]                         , 'Nom du serveur apache sympa');
$ListesURL[0]     = instconf('listsURL'        , 'http://'.$http_host[0].'/wws'      , '');
$ListesDN         = instconf('listsBase'       , "ou=$acad,ou=education,o=gouv,c=fr" , '');
$subOupublic      = instconf('listsSubOupublic', 'ou=public'                         , 'Sub-ou branche mails principaux');
$subOuadmin       = instconf('listsSubOuadmin' , 'ou=sympa'                          , 'Sub-ou branche aliases de mails');
$visipublic       = instconf('listsvisipublic' , '^(noconceal|intranet)$'            , '');
$testseul         = instconf('testseul'        , '1'                                 , '');
$codageUTF8       = instconf('codageUTF8'      , '0'                                 , '');
@sympaSuffixe     = split(/,/,
                    instconf('sympaSuffixe'    , '-request,-owner,-unsubscribe,-editor,-subscribe', 'Suffixes des listes utilises par sympa'));

                #print Dumper($config);
                #exit();

###############################
### Gestion demon / verrous ###
###############################
my $pidfile = "/var/run/$nomprog.pid";

if (not $debog) {
    # Passe la tache en arriere plan
    if (($_ = fork) != 0) {
        print( "Starting server, pid $_");
        exit(0);
    }

    ## Create and write the pidfile
    open my $lock, '>>', $pidfile or die "Could not open $pidfile : $!";
    flock($lock, LOCK_EX) or die "Could not lock $pidfile : $!";
    print $lock "$$\n";
}

## Set the GroupID & UserID for the process
$( = $) = (getgrnam($groupsympa))[2];
$< = $> = (getpwnam($usersympa))[2];

# Recupere la demande d'interruption pour arreter proprement
$SIG{'TERM'} = 'sigterm';

#########################
## Variables utilisees ##
#########################

my $filtre = '';      # Filtre des requetes LDAP
my $ldap;             # Objet Net::LDAP (connection ldap RO)
my $ldapw;            # Objet Net::LDAP (connection ldap RW)
my $mesg;             # Objet Net::LDAP::Message (resultat du ldapsearch)
my $entree;           # Objet Net::LDAP::Entry (entree ldap lue)
my $result;           # Objet Net::LDAP::Message (resultat d'une operation LDAP)
my $resultw;          # Objet Net::LDAP::Message (resultat d'une operation LDAP)
my ($dn, $cn, $mail); # Attributs correspondants
my $tempo = '';       # Variable temporaire
my $temp = '';        # Variable temporaire
my $temp2 = '';       # Variable temporaire
my $end = 0;          # Flag de sortie de la boucle infinie
my $scanInterval = 30; # Intervalle de test des modif dans sympa
my $subject = '';     # Sujet de la liste dans sympa
my $status = '';      # Etat de la liste dans sympa
my $info = '';        # Info sur la liste dans sympa
my $suffix = '';      # Prend toutes les valeurs de @sympaSuffixe

my $i = 0;
my @mailMsg = ();     # Le contenu du message envoye a l'administrateur sympa
my @realAliases = (); # Contenu du fichier des alias : les adresses sympa
my $realAlias = '';   # Une des valeurs de @realAliases (partie gauche du mail)
my $realdomain = '';  # Le domaine d'une des valeurs de @realAliases
my %ldapIndex = ();   # Hash qui contient les entrees LDAP des listes sympa
my @attrs = ();       # Liste des attributs retourne par la requete LDAP
my %attrs = ();       # Hash des valeurs des attributs d'une nouvelle entree
my $subOu = '';       # Branche ou doit etre la liste (normale ou=listes ou cachee ou=sympa)
my ($cndn, $suboudn, $basedn); # pour isoler le cn,... dans le dn d'une entree
my $cmdflag;          # Commande de detection d'un changement
my @listesmodifiees;  # Resultat de $cmdflag
my $lastverif = 0;    # Date/heure de la derniere verification quotidienne
my $faireverif = 0;   # Flag de declenchement de la verification quotidienne
my $aliasprinc = 0;   # Flag pour indiquer un alias principal (et nom du type liste-owner)
my $nomliste;         # Nom d'une des listes modifiees
my %maa;              # Hash des "mail alternate address"
                      # format cle : "liste"  val : tableau des "alt@domaine"
my @mailalt;          # Tableau temporaire pour verifier que les adresses "alt" sont libres
my $command;          # commande shell
my $robotconf;        # fichier de conf d'un robot supplementaire (robot.conf)
my $robot;            # Nom du robot supplementaire actuel
my $flagfaireverif;   # indicateur de chgt dans au moins un des robots
my ($r,$nbrobots);    # index et index max de robots
my $listeinconnue;    # = 1 si la liste modifiee n'est trouvee dans aucun robot
my $altinconnu;       # = 1 si le mail alternate n'est trouve dans aucun robot
my $robotinconnu;     # = 1 si le robot n'est pas trouve dans le debut de ligne alias
my $ligalt;           # ligne du fichier des alternates
#100305
my @listemailhost2;   # Nom du mailhost sans le domaine pour l'attribut mailroutingaddress

#100305
$_ = index($listemailhost[0], $domaine[0]); # la position du domaine dans listemailhost
# $_ = -1 si non trouve : 0 si domaine = listmailhost
if (($_ != -1) and ($_ != 0)) { # on retire le domaine et le point avant
    $listemailhost2[0] = substr($listemailhost[0], 0, $_-1);
} else { # sinon, on ne garde que le debut, avant le premier "."
    if ($listemailhost[0] =~ /^([^\.]*)\./) {
        $listemailhost2[0] = $1;
    } else { # Il n'y a pas de point ? on prend tout !
        $listemailhost2[0] = $listemailhost[0];
    }
}

# Valeurs initiales de l'entree LDAP d'une liste sympa
my $initentree = {
    #100305  'objectclass' => ["top", "groupofuniquenames", "mailgroup",
    'objectclass' => ['top', 'inetLocalMailRecipient', 'inetMailGroup', 'groupofuniquenames',
                      'mailgroup', 'mailgroupmanagement', 'groupofurls', 'educationnationale'],
    'diffusion'   => '1',
    #ajout100305 (2 lignes)
    'maildeliveryoption'  => 'members',
    'inetmailgroupstatus' => 'active'};

# Liste d'alias qui ne doivent pas etre supprimes lors de la synchronisation :
my @aliasAConserver = ('listmaster', $mailsympa, 'bounce+*', "$mailsympa-owner", "$mailsympa-request");

# Sous arborescence de l'annuaire utilisee pour stocker la liste :
my %subOu;
$subOu{'public'} = $subOupublic; # Listes accessibles publiquement
$subOu{'admin'}  = $subOuadmin;  # Listes administratives cachees

# Init des parametres des robots supplementaires
# trouver les robots :
$command="cd $sympahome/etc; find . -name robot.conf";
# 0 le robot ppal, 1..n pour les robots supplementaires
$r=1;

for (`$command`) {
    # ./robot1.ac-nantes.fr/robot.conf
    s/\.\///; s/\/.*$//;
    chomp;
    $robot=$_;
    $domaine[$r]=$robot;
    $sympaexpl[$r] = $sympaexpl[0]."/$robot"; 
    # Fichier de configuration du robot
    $robotconf = "$sympahome/etc/$robot/robot.conf";
    open my $botconf, '<', $robotconf or die "Impossible de lire le fichier de conf ($robotconf) : $!";
    while (my $confline = <$botconf>) {
        chomp($confline);
        # on zappe les commentaires
        next if ($confline =~ m/^\s*#/);
        if (/^\s*([\w\_]+)\s+([^\s+]+)\s*$/) {
            # http_host  listes-testrobot1.ac-nantes.fr
            $parconf->{"$robot.$1"} = $2;
        }
    }
    close $botconf;

    # pour les robots suppl, on peut simplifier : mailhost=domaine
    $listemailhost[$r] = $domaine[$r];
    $http_host[$r] = &instconf("$robot.http_host", $domaine[$r], '');
    # attention a la valeur par defaut : /sympa pour sympa V6.2.., /wws avant
    $ListesURL[$r] = &instconf("$robot.wwsympa_url", "http://$listemailhost[$r]/sympa", '');

    if ($paramo ne '') { 
        &mailMsg("Il manque un parametre obligatoire !!!!\n$paramo\n");
        die;
    }
    $_ = index($listemailhost[$r], $domaine[$r]); # la position du domaine dans listemailhost
    # $_ = -1 si non trouve : 0 si domaine = listmailhost
    if (($_ != -1) and ($_ != 0)) { # on retire le domaine et le point avant
        $listemailhost2[$r] = substr($listemailhost[$r], 0, $_-1);
    } else { # sinon, on ne garde que le debut, avant le premier "."
        if ( $listemailhost[$r] =~ /^([^\.]*)\./ ) {
            $listemailhost2[$r] = $1;
        } else { # Il n'y a pas de point ? on prend tout !
            $listemailhost2[$r] = $listemailhost[$r];
        }
    }
    $r++;  
}

#########################
## Programme principal ##
#########################

# Debut de la boucle infinie
$end = 0;
$scanInterval = $defScanInterval;
$faireverif = 1; # On commence par tout verifier
$nbrobots=$#domaine + 1;

if ($debog) {
    # 0 le robot ppal, 1..n pour les robots supplementaires
    for ($r = 1; $r < $nbrobots; $r++) {
        print "$r : domaine $domaine[$r]\n";
        print "   : sympaexpl $sympaexpl[$r]\n";
        print "   : listemailhost $listemailhost[$r]\n";
        print "   : http_host $http_host[$r]\n";
        print "   : ListesURL $ListesURL[$r]\n";
    }
}

# Si on se positionne sur le robot ppal, on voit les repert des autres robots
$cmdflag = "cd $sympahome;find ".$sympaexpl[0]." -name 'config' -newer $flagFile";

while (not $end) {
    @listesmodifiees = (); # Pour ne pas recommencer aussitot
    until (($end) or (@listesmodifiees) or ($faireverif)) {
        sleep($scanInterval);
        push (@listesmodifiees, `$cmdflag`);
        if ((time() - $lastverif) > $verifInterval) {
            $faireverif = 1;
        }
    }
    if (&cnxldap) {
        if ($faireverif) {
            $faireverif = 0;
            $lastverif = time();
            # a l'heure de la derniere modif
            system("touch $flagFile");
            &verifquot();
        } elsif ( @listesmodifiees ) {
            # a l'heure de la derniere modif
            system("touch $flagFile");
            &modiflist();
        }
        $ldap->unbind;
        $ldapw->unbind;
    }
    %maa = ();
    @realAliases = ();
    %ldapIndex = ();
}

# Sortie du programme
if (not $debog) {
    unlink($pidfile);
}
exit(0);


###################
## Sous-routines ##
###################

sub cnxldap {
    # On se connecte a l'annuaire
    if (not ($ldap = Net::LDAP->new($H, port => $P, async => 1))) {
        &mailMsg("Probleme de connection RO a la base LDAP : $@");
        $scanInterval = $errScanInterval;
        return 0;
    }
    $result = $ldap->bind(dn => $D, password => $W);
    if ($result->code) {
        &mailMsg("Impossible de se logger dans l'annuaire RO: ".$result->code." $@");
        $scanInterval = $errScanInterval;
        $ldap->unbind;
        return 0;
    }
    if (not ($ldapw = Net::LDAP->new($H, port => $P))) {
        &mailMsg("Probleme de connection RW a la base LDAP : $@");
        $scanInterval = $errScanInterval;
        return 0;
    }
    $resultw = $ldapw->bind(dn => $D, password => $W);
    if ($resultw->code) {
        &mailMsg("Impossible de se logger dans l'annuaire RW : ".$resultw->code." $@");
        $scanInterval = $errScanInterval;
        $ldapw->unbind;
        return 0;
    }
    return 1;
}

sub modiflist {
    say 'modiflist()' if ($debog);
    &mailMsg("Detection d'un changement dans les listes :");
    &lirealt;
    foreach my $modlist (@listesmodifiees) {
        say "Liste modifiee : $modlist" if ($debog > 3);
        # robot ppal :
        # /appli/sympa/sympaV6.2.12/sympa/list_data/testsympa2ldap/config
        # robot suppl :
        # /appli/sympa/sympaV6.2.12/sympa/list_data/robot1.ac-nantes.fr/testrobot1d/config
        chomp($modlist);
        $listeinconnue = 1;
        for ($r = 1; $r < $nbrobots; $r++) {
            if ($modlist =~ /\/([^\/]+)\/([^\/]+)\/config$/) {
                if ((($r == 0) and ($1 eq 'list_data')) or ($1 eq $domaine[$r])) { 
                    # c'est bien le robot concerne
                    $listeinconnue = 0;
                    $nomliste = $2;
                    $filtre = "(&(objectclass=groupofuniquenames)(mailhost=$listemailhost[$r])";
                    $filtre.= '(|';
                    foreach my $suffix ('', @sympaSuffixe) {
                        $filtre .= "(mail=$nomliste$suffix\@$domaine[$r])";
                    }
                    $filtre.= '))';
                    if (&lireannuaire($filtre)) {
                        $realAlias = $nomliste;
                        &verifalias();
                        if ($status =~ /pending|closed/i) {
                            # La liste est fermee : on efface les entrees annuaire
                            foreach my $tempo ('', @sympaSuffixe) {
                                $realAlias = $nomliste.$tempo;
                                if (defined($ldapIndex{$realAlias})) {
                                    $dn = ${$ldapIndex{$realAlias}->{dn}}[0];
                                    # Efface l'entree de la liste
                                    &supentree($dn, $realAlias, "liste $status");
                                }
                            }
                        } else {
                            $subOu = $subOu{'public'}; # Pour la liste principale
                            say "$subOu pour $realAlias" if ($debog > 5);
                            if (not defined($ldapIndex{$realAlias})) {
                                # L'entree principale n'existe pas (ou plus) : on ajoute dans l'annuaire
                                &ajoutentree();
                            }
                            # idem pour les entrees secondaires
                            $subOu = $subOu{'admin'}; # Alias secondaire a cacher
                            $subject = '';
                            $status = '';
                            foreach my $tempo (@sympaSuffixe) {
                                $realAlias = $nomliste.$tempo;
                                if (not defined($ldapIndex{$realAlias})) {
                                    # L'entree n'existe pas : on ajoute dans l'annuaire
                                    say "$subOu pour $realAlias" if ($debog > 5);
                                    &ajoutentree();
                                }
                            }
                        }
                    }
                    # Pas de resultat dans l'annuaire, on abandonne
                }
            } else {
                &mailMsg("Anomalie pour $modlist\nImpossible d'isoler le nom de liste\n");
            }
        }
        if ($listeinconnue) {
            &mailMsg("Anomalie pour $modlist\nImpossible de trouver le robot de laliste\n");
        }
    }
    # On envoie le mail
    &sendMailMsg();
}

sub verifquot {
    say 'verifquot()' if ($debog);
    &mailMsg('Verification quotidienne sympa / ldap :');
    # Lecture du fichier d'alias de Sympa :
    &lirealt;
    if (&lirealias()) {
        # Lecture des entrees annuaire de Sympa :
        for ($r = 1; $r < $nbrobots; $r++) {
            $filtre = "(&(objectclass=groupofuniquenames)(mailhost=$listemailhost[$r]))";
            if (&lireannuaire($filtre)) {
                #       foreach $realAlias (@realAliases) 
                # ATTENTION : la ligne precedente ne transmet pas la bonne valeur aux sous-routines
                # Pour valoriser $realAlias dans les sub, il faut passer par tempo :
                foreach my $ra (@realAliases) {
                    if ($ra =~ /([\w\d\-\.]+)\@([\w\d\-\.]+)/) {
                        $realAlias = $1;
                        $realdomain=$2;
                        if ($realdomain eq $domaine[$r]) {
                            # cela concerne le robot actuel
                            # Trouver le cn, la branche et verifier l'entree si elle existe
                            &verifalias();
                            if (not defined($ldapIndex{$realAlias})) {
                                # L'entree n'existe pas (ou plus) : on ajoute dans l'annuaire
                                &ajoutentree();
                            } else {
                                # On ne garde que les entrees qui doivent etre supprimees de l'annuaire
                                delete($ldapIndex{$realAlias});
                            }
                        }
                    } else {
                        &mailMsg("Impossible de trouver le domaine pour l'alias : $tempo");
                    }
                }
                # On supprime les listes a conserver dans le hash des alias a supprimer :
                foreach my $ac (@aliasAConserver) {
                    if (defined($ldapIndex{$ac})) {
                        delete ($ldapIndex{$ac});
                    }
                }
            }
            # On supprime les listes qui ne sont pas dans le fichier des alias
            foreach my $k (keys %ldapIndex) {
                $dn = ${$ldapIndex{$k}->{dn}}[0];
                # Efface l'entree de la liste
                &supentree($dn, $k, 'alias absent');
            }
        }
    }
    # On envoie le mail
    &sendMailMsg();
}

sub lirealt {
    say 'lirealt()' if ($debog);
    %maa = ();
    my $altfile;
    if (not open $altfile, '<', $altFile) {
        &mailMsg("Pb lecture fichier des alternates sympa $altFile : $!");
        $scanInterval = $errScanInterval; #on ralentit le scan
        return 0;
    }
    while (my $ligalt = <$altfile>) {
        chomp($ligalt);
        $altinconnu = 1;
        for ($r = 1; $r < $nbrobots; $r++) {
            if ($ligalt =~ /^\s*([\w\d\-\.]+)\:.+queue\s+([\w\d\-\.]+)\@$domaine[$r]\"\s*$/) {
                $altinconnu = 0;
                push(@{$maa{$2}}, $1.'@'.$domaine[$r]);
            } elsif ((/^\s*$/) || (/^\s*#/)) {
                # Passe les commentaires ou les lignes vides
            }
        }
        if ($altinconnu) {
            &mailMsg("Alternate rejete : $_");
        }
    }
    close $altfile;
    if ($debog > 3) {
        for (keys(%maa)) {
            print "$_ : ";
            print join('; ', @{$maa{$_}})."\n";
        }
    }
    return 1;
}

sub lirealias {
    say 'lirealias()' if ($debog);
    @realAliases = ();
    my $aliasesfile;
    if (not open $aliasesfile, '<', $aliasFile) {
        &mailMsg("Pb lecture fichier des alias sympa $aliasFile : $!");
        $scanInterval = $errScanInterval; #on ralentit le scan
        return 0;
    }
    while (<$aliasesfile>) {
        # robot ppal "sympa6.ac-nantes.fr" :
        # testsympa2ldap: "| /appli/sympa/sympaV6.2.12/sympa/bin/queue testsympa2ldap@sympa6.ac-nantes.fr"
        # testsympa2ldap-request: "| /appli/sympa/sympaV6.2.12/sympa/bin/queue testsympa2ldap-request@sympa6.ac-nantes.fr"
        # robot supplementaire "robot1.ac-nantes.fr" :
        # robot1.ac-nantes.fr-testrobot1a: "| /appli/sympa/sympaV6.2.12/sympa/bin/queue testrobot1a@robot1.ac-nantes.fr"
        # robot1.ac-nantes.fr-testrobot1a-request: "| /appli/sympa/sympaV6.2.12/sympa/bin/queue testrobot1a-request@robot1.ac-nantes.fr"
        if (/^\s*([\w\d\-\.]+)\:/ or /^\s*([\w\d\-\.]+)\+/) {
            # le debut de la ligne d'alias
            $temp = $1;
            if (/\@([\w\d\-\.]+)"$/) {
                # et le domaine a la fin de la ligne
                $temp2 = $1;
                if (index($temp, $temp2.'-') == 0) {
                    # c'est un alias de robot suppl
                    # tronquer le debut pour avoir la partie gauche du mail
                    $temp = substr($temp, length($temp2)+1);
                }
                push(@realAliases, "$temp\@$temp2");
            } else {
                # c'est une ligne du type :
                #  syndicat.XXX-sympa-owner: postmaster
                # dans ce cas le domaine est deduit du debut de la ligne
                $robotinconnu = 1;
                for ($r = 1; $r < $nbrobots; $r++) {
                    if (index($temp, $domaine[$r].'-') == 0) {
                        # c'est un alias de robot suppl
                        $robotinconnu = 0;
                        $temp2 = $domaine[$r];
                        # tronquer le debut pour avoir la partie gauche du mail
                        $temp = substr($temp, length($temp2)+1);
                    }
                }
                if ($robotinconnu) {
                    # alors c'est un alias du robot ppal
                    $temp2 = $domaine[0];
                    # pas besoin de tronquer
                }
                push(@realAliases, "$temp\@$temp2");
            }
        } elsif ((/^\s*$/) or (/^\s*#/)) {
            # Passe les commentaires ou les lignes vides
        } else {
            &mailMsg("Alias rejete : $_");
        }
    }
    close $aliasesfile;
    return 1;
}

sub lireannuaire {
    my $f = shift; # filtre en argument
    #my ($f) = @_; # filtre de recherche
    say "lireannuaire($f)" if ($debog);
    #my %listinfo; # contient l'entree LDAP en hash (listinfo{"dn"} pour avoir le dn)
    #                ne pas l'initialiser ici, mais plutot dans la boucle...
    # Lecture des listes enregistrees dans l'annuaire
    #100305  @attrs = qw(cn mail description mailalternateaddress);
    @attrs = qw(objectclass mailroutingaddress maildeliveryoption inetmailgroupstatus cn mail description mailalternateaddress);
    $mesg = $ldap->search (
        base => $B,
        filter => $f,
        attrs => [@attrs] );
    %ldapIndex = ();
    while (my $entree = $mesg->shift_entry) {
        my $listinfo = {};
        $listinfo->{'dn'} = [$entree->dn];
        foreach my $a (@attrs) {
            if ($entree->exists($a)) {
                my @tab_val = $entree->get_value($a);
                $listinfo->{$a} = [@tab_val];
            }
        }
        # On recherche le "vrai" nom de la liste dans le mail de l'entree
        if ($entree->exists('mail')) {
            if ($entree->get_value('mail') =~ m/\@/) {
                my $mailaddr = $`;
                $ldapIndex{$mailaddr} = $listinfo;
            } else {
                &mailMsg("Pb de mail sur l'entree " . $listinfo->{"dn"});
            }
        } else {
            &mailMsg("Pas de mail sur l'entree " . $listinfo->{"dn"});
        }
    }
    return 1;
}

sub verifalias {
    say "verifalias() - $realAlias" if ($debog > 3);
    # conf de la liste, info de la liste
    my ($fconf, $finfo) = ('', '');
    # variables de la liste
    my ($subject, $status, $info) = ('', '', '');
    # info du ldap
    my ($description, $maildeliveryoption, $inetmailgroupstatus, $mailroutingaddress)
        = ('', '', '', '');
    my @objectclass;
    # alternate addresses
    my ($sympaalts, $dsalts);
    # ligne du fichier de conf
    my $lig = '';
    # pour la verif des attributs inetLocalMailRecipient et inetMailGroup
    my ($t1, $t2);
    # Recherche du type d'alias : principal ou secondaire?
    $subOu = $subOu{'public'};
    foreach my $suffix (@sympaSuffixe) {
        if ($realAlias =~ /($suffix)$/) {
            $subOu = $subOu{'admin'}; # Alias secondaire a cacher
        }
    }
    # En dur les alias sympa, listmaster et bounce preconises a l'install (y compris pour les robots)
    # si ces alias sont modifies, l'erreur n'est pas bloquante 
    if (($subOu eq $subOu{'public'}) and ($realAlias !~ /^sympa$|^listmaster$|^bounce$/)) {
        $aliasprinc = 1; # On a l'alias principal d'une liste
    } else {
        $aliasprinc = 0; # C'est un alias secondaire ( -owner,...)
    }
    if ($aliasprinc) {
        say 'Visibilite liste '.$sympaexpl[$r]." -> $realAlias" if ($debog > 4);
        # Regarder si la liste est cachee ou pas
        $fconf = "$sympaexpl[$r]/$realAlias/config";
        open my $listconf, '<', $fconf or die "Could not open list configuration ($fconf): $!";
        $subOu = $subOu{'admin'}; # Cachee par defaut pour securite
        $debutpara=1;
        while ($lig = <$listconf>) {
            chomp($lig);
            if ($debutpara) {
                if ($lig =~ /^\s*visibility\s*/) {
                    # liste visible
                    $subOu = $subOu{'public'} if ($' =~ /$visipublic/);
                }
                # sujet de la liste
                $subject = &mef2($') if ($lig =~ /^\s*subject\s*/);
                # etat de la liste
                $status = $' if ($lig =~ /^\s*status\s*/);
            }
            if ($lig =~ /^\s*$/) {
                # debut de paragraphe du fichier de conf
                $debutpara=1;
            } else {
                # ou pas
                $debutpara=0;
            }
        }
        close $listconf;
        $finfo = "$sympaexpl[$r]/$realAlias/info";
        if (open my $listinfofile, '<', $finfo) {
            while ($lig = <$listinfofile>) {
                $info .= $lig;
            }
            close $listinfofile;
            $info = &mef2($info);
        }
    }
    if (defined($ldapIndex{$realAlias})) {
        # L'entree de la liste existe dans l'annuaire
        $dn = ${$ldapIndex{$realAlias}->{dn}}[0];
        @objectclass = @{$ldapIndex{$realAlias}->{objectclass}};
        if (defined($ldapIndex{$realAlias}->{description})) {
            $description = ${$ldapIndex{$realAlias}->{description}}[0];
        }
        #100305
        if (defined($ldapIndex{$realAlias}->{maildeliveryoption})) {
            $maildeliveryoption = ${$ldapIndex{$realAlias}->{maildeliveryoption}}[0];
        }
        if (defined($ldapIndex{$realAlias}->{inetmailgroupstatus})) {
            $inetmailgroupstatus = ${$ldapIndex{$realAlias}->{inetmailgroupstatus}}[0];
        }
        if (defined($ldapIndex{$realAlias}->{mailroutingaddress})) {
            $mailroutingaddress = ${$ldapIndex{$realAlias}->{mailroutingaddress}}[0];
        }
        ($cndn, $suboudn, $basedn) = split(/,/,$dn,3);
        # L'entree de la liste est dans la bonne branche ?
        if ($suboudn ne $subOu) {
            # Efface l'entree de la liste car elle n'est pas bien placee
            if (&supentree($dn, $realAlias, 'changement type')) {
                # Pour recreer l'entree de la liste, on simule son absence
                delete ($ldapIndex{$realAlias});
            }
        } else {
            # l'entree est au bon endroit
            if ($aliasprinc) {
                # Le cn dans l'annuaire est bien le subject sur sympa ?
                if (($cndn ne "cn=$subject") and ($cndn ne "cn=$subject -$realAlias $domaine[$r]-")) {
                    # Modifie le cn de l'entree de la liste
                    $_ = &modcnentree($dn, $realAlias, 'changement cn');
                    if (($_ ne '') and ($_ ne '0') and ($_ ne '1')) {
                        # Le dn a change !
                        $dn = 'cn='.$_.','.$suboudn.','.$basedn;
                    }
                }
                # OK le cn est bien le subject sur sympa
                # La description dans l'annuaire est bien l'info ?
                if ($description ne $info) {
                    # Modifie la description de l'entree de la liste
                    &modentree($dn, 'description', 'changement description', $info);
                }
            }
            #100305
            # Les nouveaux attributs "messaging 5" sont-ils corrects ?
            ($t1, $t2) = (1, 1);
            foreach my $o (@objectclass) {
                $t1 = 0 if ($o =~ m/^inetLocalMailRecipient$/i);
                $t2 = 0 if ($o =~ m/^inetMailGroup$/i);
            }
            if ($t1) {
                # Modifie l'attribut correspondant de l'entree de la liste
                &modaddentree($dn, 'objectclass', 'changement objectclass inetLocalMailRecipient', 'inetLocalMailRecipient');
            }
            if ($t2) {
                # Modifie l'attribut correspondant de l'entree de la liste
                &modaddentree($dn, 'objectclass', 'changement objectclass inetMailGroup', 'inetMailGroup');
            }
            if ($maildeliveryoption ne 'members') {
                # Modifie l'attribut correspondant de l'entree de la liste
                &modentree($dn, 'maildeliveryoption', 'changement maildeliveryoption', 'members');
            }
            if ($inetmailgroupstatus ne 'active') {
                # Modifie l'attribut correspondant de l'entree de la liste
                &modentree($dn, 'inetmailgroupstatus', 'changement inetmailgroupstatus', 'active');
            }
            if ($mailroutingaddress ne "$realAlias\@$listemailhost2[$r]") {
                # Modifie l'attribut correspondant de l'entree de la liste
                &modentree($dn, 'mailroutingaddress', 'changement mailroutingaddress', "$realAlias\@$listemailhost2[$r]");
            }
            if ($aliasprinc) {
                # Les "mail alternate address" correspondent bien ?
                $sympaalts = "pas d'alts";
                $dsalts = "pas d'alts";
                if (defined($maa{$realAlias})) {
                    # il y a au - 1 alt. sur sympa
                    $sympaalts = join("\\", sort(@{$maa{$realAlias}}));
                    if ($sympaalts eq '') {
                        # bug si fichier des alts vide ???
                        $sympaalts = "pas d'alts";
                    }
                }
                if (defined($ldapIndex{$realAlias}->{'mailalternateaddress'})) {
                    # il y a au moins 1 mailalternateaddress sur l'entree annuaire
                    $dsalts = join("\\", sort(@{$ldapIndex{$realAlias}->{'mailalternateaddress'}}));
                }
                if ($sympaalts ne $dsalts) {
                    # Remplace les mailalternateaddress de l'entree de la liste
                    @mailalt = ();
                    # on ne prend que les alts valides
                    for (@{$maa{$realAlias}}) {
                        if (not &mailused($_) or ((index($dsalts, $_) != -1) and (&mailused($_) == 1))) {
                            # l'adresse n'est pas utilisee, ou elle est deja sur l'entree
                            push(@mailalt, $_);
                        } else {
                            &mailMsg("Echec ajout pour $realAlias mail alternate $_ : deja utilise.");
                        }
                    }
                    $sympaalts = "pas d'alts valides dans sympa";
                    if (@mailalt) {
                        # on ne prend que les alts valides
                        $sympaalts = join("\\", sort(@mailalt));
                    }
                    # L'entree est-elle reellement desynchronisee ?
                    if ($sympaalts ne $dsalts) { 
                        &modentree($dn, 'mailalternateaddress', 'changement alternate(s)', @mailalt);
                    }
                    # sinon il n'y a rien a changer en fait
                }
            }
        }
        # L'entree annuaire n'est pas encore creee, on ne verifie rien
    }
    return 1;
}

sub ajoutentree {
    say 'ajoutentree()' if ($debog);
    $mail = "$realAlias\@$domaine[$r]";
    if (&mailused($mail)) {
        &mailMsg("Ajout de la liste $realAlias (type $subOu , cn:$cn)\n");
        &mailMsg("Echec de l'ajout : L'adresse $realAlias est deja utilisee... ($subject)");
        return 0;
    }
    $cn = $realAlias; # pour les alias secondaire ( -owner,...), sinon le subject
    $cn = $subject if ($subject ne '');
    $i = 0; # on essaie le cn, puis le cn + " -$realAlias-"
    @attrs = qw(cn);
    while ($i < 2) {
        $mesg = $ldap->search(base   => $B,
                              filter => "(cn=$cn)",
                              attrs  => [@attrs]);
        last if ($mesg->count < 1);
        $cn.= " -$realAlias $domaine[$r]-";
        $i++;
    }
    if ($i >= 2) {
        &mailMsg("Ajout de la liste $realAlias (type $subOu , cn:$cn)\n");
        &mailMsg("Echec de l'ajout : Le cn (nom) '$cn' est deja utilise... ($subject)");
        return 0;
    }
    $dn = "cn=$cn,$subOu,$ListesDN";
    my $attrs = {};
    while (my ($a, $v) = each %{$initentree}) {
        $attrs->{$a} = $v;
    }
    $attrs->{'cn'} = $cn;
    $attrs->{'mail'} = $mail;
    $attrs->{'labeleduri'} = $ListesURL[$r] . "/info/$realAlias";
    $attrs->{'description'} = $info;
    $attrs->{'ou'} = [$subOu, $acad, 'education'];
    $attrs->{'mailhost'} = $listemailhost[$r];
    $attrs->{'mailroutingaddress'} = "$realAlias\@$listemailhost2[$r]";
    @mailalt = ();
    for (@{$maa{$realAlias}}) {
        if (&mailused($_)) {
            &mailMsg("Ajout de la liste $realAlias (type $subOu , cn:$cn)\n");
            &mailMsg("Echec ajout adresse alternate $_ : deja utilisee...");
        } else {
            push(@mailalt, $_);
        }
    }
    if (@mailalt) {
        $attrs->{'mailalternateaddress'} = [ @mailalt ];
    }
    say 'ajout au ldap de '.$dn.Dumper($attrs) if ($debog > 5);
    if ($testseul) {
        &mailMsg("Ajout de la liste $realAlias (type $subOu , cn:$cn) test seulement...\n");
        return 1;
    }
    $resultw = $ldapw->add (dn => $dn, attrs => [%{$attrs}] );
    if ($resultw->code) {
        &mailMsg("Ajout de la liste $realAlias (type $subOu , cn:$cn)\nErreur : $@\n".$resultw->code);
        return 0;
    } else {
        &mailMsg("Ajout de $realAlias reussi ! (type $subOu , cn:$cn)");
        $scanInterval = $defScanInterval;
        return 1;
    }
}

sub modcnentree {
    my ($dn2, $liste, $commentaire) = @_; # dn, cn de la liste, commentaire pour message
    say "modcnentree($dn2, $liste, $commentaire)" if ($debog);
    my $cn2;
    my ($cndn2, $suboudn2, $basedn2) = split(/,/,$dn2,3);
    $cndn2 =~ s/^cn=//;
    if (($suboudn2 ne $subOu{'public'}) and ($suboudn2 ne $subOu{'admin'})) {
        &mailMsg("L'entree n'est pas dans une branche liste.\nPas de modification ($commentaire) de $liste ($dn2)\nCorrigez l'entree manuellement SVP!");
        return 0;
    }
    if ($testseul) {
        &mailMsg("Modification ($commentaire) de $liste ($dn2)\nTest seulement...\n");
        return 1;
    }
    $cn2 = $liste;
    if ($subject ne '') { $cn2 = $subject }
    $i = 0; # on essaie le cn, puis le cn + " -$realAlias-"
    @attrs = qw(cn);
    while ($i < 2) {
        $mesg = $ldap->search(base   => $B,
                              filter => "(cn=$cn2)",
                              attrs  => [@attrs]);
        last if ($mesg->count < 1);
        $cn2.= " -$liste $domaine[$r]-";
        $i++;
    }
    if ($i >= 2) {
        &mailMsg("Modification ($commentaire) de $liste ($dn2) : Nouveau cn : $cn2");
        &mailMsg("Echec de la modification : Le cn (nom) '$cn2' est deja utilise... ($subject)");
        return 0;
    }
    $resultw = $ldapw->moddn($dn2, newrdn =>"cn=$cn2", deleteoldrdn => 1);
    if (not $resultw->code) {
        &mailMsg("Modification ($commentaire) de $liste ($dn2) reussi ! Nouveau cn : $cn2");
        $scanInterval = $defScanInterval;
        return $cn2;
    } else {
        &mailMsg("Modification ($commentaire) de $liste ($dn2)\nErreur : $@ ".$resultw->code);
        return '';
    }
}

sub modentree {
    my ($dn2, $att, $commentaire, @vals) = @_;
    # dn, attribut, commentaire pour message, nouvelle(s) valeur(s)
    say "modentree($dn2, $att, $commentaire, @vals)" if ($debog);
    my ($cndn2, $suboudn2, $basedn2) = split(/,/,$dn2,3);
    $cndn2 =~ s/^cn=//;
    if (($suboudn2 ne $subOu{'public'}) and ($suboudn2 ne $subOu{'admin'})) {
        &mailMsg("L'entree n'est pas dans une branche liste.\n".
                 "Pas de modification ($commentaire) de $dn2\n".
                 "Corrigez l'entree manuellement SVP!");
        return 0;
    }
    if ($testseul) {
        &mailMsg("Modification ($commentaire) de '$cndn2'\nTest seulement...\n");
        return 1;
    }
    my $attrsmod = ();
    $attrsmod->{$att} = [ @vals ];
    $resultw = $ldapw->modify($dn2, replace => $attrsmod);
    if (not $resultw->code) {
        &mailMsg("Modification ($commentaire) de '$cndn2' reussi ! $att : ".join(' ', @vals));
        $scanInterval = $defScanInterval;
        return 1;
    } else {
        &mailMsg("Modification ($commentaire) de '$cndn2'\nErreur : $@ ".$resultw->code);
        return 0;
    }
}

sub modaddentree {
    my ($dn2, $att, $commentaire, @vals) = @_;
    # dn, attribut, commentaire pour message, nouvelle(s) valeur(s)
    say "modaddentree($dn2, $att, $commentaire, @vals)" if ($debog);
    my ($cndn2, $suboudn2, $basedn2) = split(/,/,$dn2,3);
    $cndn2 =~ s/^cn=//;
    if (($suboudn2 ne $subOu{'public'}) and ($suboudn2 ne $subOu{'admin'})) {
        &mailMsg("L'entree n'est pas dans une branche liste.\n".
                 "Pas de modification ($commentaire) de $dn2\n".
                 "Corrigez l'entree manuellement SVP!");
        return 0;
    }
    if ($testseul) {
        &mailMsg("Modification add ($commentaire) de '$cndn2'\nTest seulement...\n");
        return 1;
    }
    my $attrsmod = {};
    $attrsmod->{$att} = [@vals];
    $resultw = $ldapw->modify($dn2, add => $attrsmod);
    if (not $resultw->code) {
        &mailMsg("Modification add ($commentaire) de '$cndn2' reussi ! $att : ".join(' ', @vals));
        $scanInterval = $defScanInterval;
        return 1;
    } else {
        &mailMsg("Modification add ($commentaire) de '$cndn2'\nErreur : $@ ".$resultw->code);
        return 0;
    }
}

sub mailused {
    my ($a) = @_; # adresse mail qui doit etre cherchee dans l'annuaire
    say "mailused($a)" if ($debog);
    @attrs = qw(dn);
    $mesg = $ldap->search (
        base   => $B,
        filter => "(|(mail=$a)(mailalternateaddress=$a)(mailequivalentaddress=$a))",
        attrs  => [@attrs] );
    return $mesg->count;
}

sub supentree {
    my ($dn2, $liste, $commentaire) = @_; # dn, nom de la liste, commentaire pour message
    say "supentree($dn2, $liste, $commentaire)" if ($debog);
    my ($cndn2, $suboudn2, $basedn2) = split(/,/,$dn2,3);
    if (($suboudn2 ne $subOu{'public'}) and ($suboudn2 ne $subOu{'admin'})) {
        &mailMsg("L'entree n'est pas dans une branche liste.\n".
                 "Pas de suppression ($commentaire) de $liste ($dn2)\n".
                 "Corrigez l'entree manuellement SVP!");
        return 0;
    }
    if ($testseul) {
        &mailMsg("Suppression ($commentaire) de $liste ($dn2)\nTest seulement...\n");
        return 1;
    }
    $resultw =  $ldapw->delete($dn2);
    if (not $resultw->code) {
        &mailMsg("Suppression ($commentaire) de $liste ($dn2) reussi !");
        $scanInterval = $defScanInterval;
        return 1;
    } else {
        &mailMsg("Suppression ($commentaire) de $liste ($dn2)\nErreur : $@ ".$resultw->code);
        return 0;
    }
}

sub mailMsg {
    my ($msg) = @_;
    say "mailMsg($msg)" if ($debog);
    push (@mailMsg, $msg);
}

sub sendMailMsg {
    say 'sendMailMsg()' if ($debog);
    if (@mailMsg < 2) {
        @mailMsg = ();
        return 0;
    }
    my $smtp = Net::SMTP->new('localhost');
    $smtp->mail("root\@$listemailhost[0]");
    $smtp->to($mailadmin);
    $smtp->data();
    $smtp->datasend("To: $mailadmin\n");
    $smtp->datasend("Subject: [SYMPA-Annuaire] Rapport d'activite\n");
    $smtp->datasend("\n");
    $smtp->datasend(&ConvDate(time)." Programme : $VERSION\n");
    $smtp->datasend("Synchronisation des entrees dans l'annuaire pour les listes sympa.\n\n");
    $smtp->datasend(join("\n", @mailMsg));
    $smtp->dataend();
    $smtp->quit;
    @mailMsg = ();
    return 1;
}

sub ConvDate {
    # Retourne la date et l'heure dans un format lisible
    my ($tps) = @_;
    say "ConvDate($tps)" if ($debog > 5);
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($tps);
    $year+= 1900;
    $mon++;
    $min = "0$min" if ($min < 10);
    $hour = "0$hour" if ($hour < 10);
    $mday = "0$mday" if ($mday < 10);
    $mon = "0$mon" if ($mon < 10);
    return "Le $mday/$mon/$year a $hour"."h$min";
}

sub mef2 {
    # Mise en forme d'une chaine : elimination des accents,
    #  caracteres autorises a..zA..Z0..9 . - et espace,
    #  sinon on remplace par -
    my ($chaine) = @_;
    say "mef2($chaine)" if ($debog > 5);
    if ($codageUTF8) {
        # Chaine codee en UTF8, on traduit en iso8859 pour eliminer les accents
        $_ = encode('iso-8859-1', decode('utf8', $chaine));
        $chaine = $_;
    }
    # ATTENTION la ligne suivante contient des accents codes en iso8859, ne pas la modifier !!!
    $chaine =~ tr/àâäéèêëîïôöùûüç/aaaeeeeiioouuuc/; # les accents
    $chaine =~  s/[^a-zA-Z0-9 .-]/-/g; # les caract. speciaux (tout le reste plutot)
    $chaine =~  s/\s+$//; # les espaces a la fin
    return $chaine;
}

sub sigterm {
    say 'SIGTERM' if ($debog);
    &mailMsg('Signal TERM recu, on termine la tache courante');
    $end = 1;
}

sub instconf {
    ### retourne le parametre du fichier de conf ou la valeur par defaut ou undef
    my ($nomp, $valdef, $comment) = @_;
    say "instconf($nomp, $valdef, $comment)" if ($debog > 5);
    if (not defined $config->{'default.'.$nomp}) {
        # si pas de valeur pour nomp dans le fichier de conf
        if (not defined $valdef or $valdef eq '') {
            # si pas de valeur par defaut
            $paramo .= "$nomp : $comment\n";
            say "Ajout de $nomp aux parametres manquants" if ($debog > 5);
            return;
        }
        say 'Valeur par defaut!!!' if ($debog > 5);
        return $valdef;
    }
    say "$nomp a pour valeur ".$config->{'default.'.$nomp} if ($debog > 5);
    return $config->{'default.'.$nomp};
}

__END__

