BEGIN {

}

function GetEmail(s) {
	res=gensub("^{? +('[a-z0-9_]*': [{[] +)?'([^@]*@[^']*)'.*$", "\\2", "g", s);
	#res=gensub("^.*[^a-zA-Z0-9._-]([a-zA-Z0-9._-]*@[a-zA-Z0-9.-]*)[^a-zA-Z0-9.-].*$", "\\1", "g", s);
	if (res !~ ".*@.*") res="";
	return tolower(res);
}

function GetValueN(s) {
	res = gensub("^.*: *([0-9]*)[^0-9]*$", "\\1", "g", s);
	return res;
}

function GetPassword(s) {
	res = gensub("^.*: '(.*)'(},|,)$", "\\1", "g", s);
	return res;
}

function GetUsername(s) {
	res = gensub("^.*: u?'(.*)'(},|,)$", "\\1", "g", s);
	return res;
}

/'digest_members' *: *{/,/} */ {
	digest[GetEmail($0)]=1;
}


/'members' *: *{/,/}/ {
	email=GetEmail($0);
	if (email in options) {
	} else {
		options[email]=0;
	}
}

# Make these non-members with nomail option
/'accept_these_nonmembers' *: *\[/,/\]/ {
	nonmember_email[GetEmail($0)]=1;
}

/'user_options' *: *{/,/} */ {
	options[GetEmail($0)] += GetValueN($0);
}

/'passwords' *: *{/,/}/ {
	passwords[GetEmail($0)] = GetPassword($0);
}

/'usernames' *: *{/,/}/ {
	usernames[GetEmail($0)] = GetUsername($0);
}


END {
	nb_subscribers=0;
	print "" >  EXPL "/" LIST "/subscribers";
	for (email in options) {
		if (email == "") continue;
		opt=options[email];
		visibility="noconceal";
		plain=0;
		ack=0;
		password=passwords[email];
		username=usernames[email];
		if (nonmember_email[email] == 1) {
			# former nonmember that was allowed to post that is now a member
			nonmember_email[email]=0;	
			delete nonmember_email[email];	
		}
		no_metoo=0;
		nomail=0;
		# from /usr/lib64/mailman/Mailman/Defaults.py
		if (opt>=256) {
			# DontReceiveDuplicate - not implemented in sympa
			opt -= 256;
			}
		if (opt>=128) {
			# Moderate - not implemented in sympa
			opt -= 128;
			}
		if (opt>=64) {
			# ReceiveNonmatchingTopics - maybe not implemented in sympa
			opt -= 64;
			}
		if (opt>=32) {
			# SuppressPasswordReminder - not implemented in sympa
			opt -= 32;
			}
		if (opt>=16) {
			visibility="conceal";
			opt -= 16;
			}
		if (opt>=8) {
			# DisableMime # Digesters only
			plain=1;
			opt -= 8;
			}
		if (opt>=4) {
			# AcknowledgePosts
			ack=1;
			opt -= 4;
			}
		if (opt>=2) {
			# DontReceiveOwnPosts
			no_metoo=1;
			opt -= 2;
			}
		if (opt>=1) {
			# DisableDelivery
			nomail=1;
			opt -= 1;
			}
		if (nomail==1 && TAKE_NOMAIL=="no") continue;

		if (nomail==1) {reception="nomail";}
		else if (no_metoo==1) {reception="not_me";}
		else if (digest[email]==1) {
			if (plain) reception="digestplain";
			else reception="digest";
		}
		else {reception="mail";}
		printf("email %s\nvisibility %s\n", email, visibility) >> EXPL "/" LIST "/subscribers";
		if (reception != "mail") {
			printf("reception %s\n", reception)  >> EXPL "/" LIST "/subscribers";
			}
		printf("\n") >> EXPL "/" LIST "/subscribers";
		nb_subscribers += 1;
		printf("%s;%s;%s\n", email, username, password) >> WDIR "/csv/import_users.csv";
		printf("%s;%s;%s;%s;%s;%s\n", LIST, email, username, DATE, visibility, reception) >> WDIR "/csv/import_subscribers.csv";

	}
	for (nmemail in nonmember_email) {
		if (nonmember_email[nmemail] == 1) {
			printf("%s;%s;nonmember;%s;conceal;nomail\n", LIST, nmemail, DATE) >> WDIR "/csv/import_subscribers.csv";
		}
	}
	printf("0 0 0 0 %s", nb_subscribers) >  EXPL "/" LIST "/stats";
}
