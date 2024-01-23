BEGIN {
subject = "Mailingliste " LIST;
domain=DOMAIN;
owner_set=0;
subscribe = "auth_notify";
visibility = "conceal";
lang = "de";
anonymous_sender = "";
max_size = 10000000;
footer_type = "append";
private=1;
moderator = "";
owner = OWNER;
reply_to_header = "sender";
custom_subject = "[" LIST "]";
send = "private";
digest = "digest 0 23:0";
archive = 1;
review = "owner";
invite = "closed";
clean_delay_queuemod = 20;
type_archive = "private";
expire_task = "yearly";
spam_protection = "at";
web_archive_spam_protection = "at";
date_epoch = "1042631682";
date = "15 Jan 2003 at 12:54:42";
profile = "privileged";
}

function GetValueS(s) {
	res = gensub(".*: *['\"](.*)['\"] *, *$", "\\1", "g", s);
	return gensub(".351", "é", "%03o",  res);
}

function GetValueN(s) {
	res = gensub("^.*: *([0-9]*)[^0-9]*$", "\\1", "g", s);
	return res;
}

function GetValueL(s) {
	list = gensub(".*: *[[][:space:]*([^]]*)[]].*", "\\1", "g", s);
	gsub("[ ']", "", list);
	return list;
}

function GetEmail(s) {
    res=gensub("^{? +('[a-z0-9_]*': [{[] +)?'([^@]*@[^']*)'.*$", "\\2", "g", s);
    #res=gensub("^.*[^a-zA-Z0-9._-]([a-zA-Z0-9._-]*@[a-zA-Z0-9.-]*)[^a-zA-Z0-9.-].*$", "\\1", "g", s);
    if (res !~ ".*@.*") res="";
    return tolower(res);
}

/'subscribe_policy' *:/	{
	res = GetValueN($0);
	if (res==1) {subscribe = "auth_notify";}
	else if (res==2) {subscribe = "owner";}
	else {subscribe = "owner";}
	}
/'anonymous_list' *:/	{
	res = GetValueN($0);
	if (res!=0) {
		anonymous_sender= LIST "@" domain;
		}
	}
/'description' *:/		{
	subject_value = GetValueS($0);

	if (subject_value) subject = subject_value;
	}
/'max_message_size' *:/	{
	max_size = GetValueN($0) * 1000;
	}
/'member_posting_only' *:/{
	private=GetValueN($0);
	}
/'moderated' *:/	{
	moderated=GetValueN($0);
	}
/'owner' *:.*]/	{ 
	owners =  GetValueL($0);
 	}
/'owner' *:[^]]*$/,/] *,/ {
	owners = owners "," GetEmail($0);
	}
/'moderator' *:[^]]*$/,/] *,/ {
	moderators = moderators "," GetEmail($0);
	}
/'advertised' *:/ {
	if (GetValueN($0)!=0) visibility="noconceal";
	else visibility="conceal";		
	}
/'reply_goes_to_list' *:/ {
	if (GetValueN($0)!=0) reply_to_header="list";
	else reply_to_header="sender";
	 }
/'subject_prefix' *:/	{
	custom_subject=GetValueS($0);
	}
/'archive' *:/  {
	archive = GetValueN($0);
}
/'archive_private' *:/  {
	if (GetValueN($0)!=0) type_archive = "private";
	else type_archive = "public";
}


END  {
	split(owners, array_owners, ",");
	for (i in array_owners) {
		if (array_owners[i]~".*@.*" && !owner_set) {
			printf("creation\ndate_epoch %s\ndate %s\nemail %s\n\n", date_epoch, date, array_owners[i]);
			owner_set = 1;
		}
		printf("%s;owner;%s\n",array_owners[i], LIST) >> WDIR "/csv/import_admins.csv";
	}
	split(moderators, array_moderators, ",");
	for (i in array_moderators) {
		printf("%s;editor;%s\n",array_moderators[i], LIST) >> WDIR "/csv/import_admins.csv";
	}

#	printf("lang %s\n\n", lang);
	printf("topics aful\n\n");
	printf("visibility %s\n\n", visibility);
	printf("user_data_source database\n\n");
	printf("clean_delay_queuemod %s\n\n", clean_delay_queuemod);
	printf("expire_task %s\n\n", expire_task);
	printf("spam_protection %s\n\n", spam_protection);
	printf("web_archive_spam_protection %s\n\n", web_archive_spam_protection);
	printf("%s\n\n", digest);
	if (anonymous_sender != "") printf("anonymous_sender %s\n\n",
					anonymous_sender);
	printf("subject %s\n\n", subject);
	if (custom_subject != "") printf("custom_subject %s\n\n", custom_subject);
	if (private!=0) {
		if (moderator == "") send = "private";
		else send="privateandeditorkey";
		} else {
		if (moderator == "") send = "public";
		else send="editorkey";
		}
	printf("send %s\n\n", send);
	if (archive!=0) {
		printf("archive\nperiod day\naccess %s\n\n", type_archive);
		}
	if (reply_to_header != "") printf("reply_to_header\nvalue %s\napply forced\n\n",
					reply_to_header);
	printf("subscribe %s\n\n", subscribe);
	
	printf("review %s\n\n", review);
	printf("invite %s\n\n", invite);

	printf("footer_type %s\n\n", footer_type);

	printf("max_size %s\n\n", max_size);
	
	for (i in array_owners) { 
		if (array_owners[i]~".*@.*") {
			printf("owner\nemail %s\nprofile %s\n\n", array_owners[i], profile);
			}
		}

	if (moderated!=0) {
		for (i in array_owners) { 
			if (array_owners[i]~".*@.*") {
				printf("editor\nemail %s\n\n", array_owners[i]);
				}
			}
		}
		
	if (archive!=0) {
		printf("web_archive\naccess %s\n\n", type_archive);
		}

	printf("\n# ---------------- %s%s@%s \n", ALIAS_PREFIX, LIST, domain)  >> ALIASES ;
	if (VIRTUAL_ALIASES == "yes") {
		printf(PREFIX "%s%s@%s: \"| %s/queue %s@%s\"\n", ALIAS_PREFIX, LIST, domain, SMTPSCRIPTPATH, LIST, domain) >>  ALIASES ;
		printf(PREFIX "%s%s-request@%s: \"| %s/queue %s-request@%s\"\n", ALIAS_PREFIX, LIST, domain, SMTPSCRIPTPATH, LIST, domain ) >>  ALIASES ;
		printf(PREFIX "%s%s-editor@%s: \"| %s/queue %s-editor@%s\"\n", ALIAS_PREFIX, LIST, domain, SMTPSCRIPTPATH, LIST, domain ) >>  ALIASES ;
		printf(PREFIX "%s%s-owner@%s: \"| %s/bouncequeue %s@%s\"\n", ALIAS_PREFIX,LIST, domain, SMTPSCRIPTPATH, LIST, domain ) >>  ALIASES ;
		printf(PREFIX "%s%s-unsubscribe@%s: \"| %s/queue %s-unsubscribe@%s\"\n", ALIAS_PREFIX,LIST, domain, SMTPSCRIPTPATH, LIST, domain ) >>  ALIASES ;
		printf(PREFIX "# %s%s-subscribe@%s: \"| %s/queue %s-subscribe@%s\"\n\n", ALIAS_PREFIX,LIST, domain, SMTPSCRIPTPATH, LIST, domain ) >>  ALIASES ;
	} else {
		printf(PREFIX "%s%s: \"| %s/queue %s@%s\"\n", ALIAS_PREFIX,LIST, SMTPSCRIPTPATH, LIST, domain) >>  ALIASES ;
		printf(PREFIX "%s%s-request: \"| %s/queue %s-request@%s\"\n", ALIAS_PREFIX,LIST, SMTPSCRIPTPATH, LIST, domain ) >>  ALIASES ;
		printf(PREFIX "%s%s-editor: \"| %s/queue %s-editor@%s\"\n", ALIAS_PREFIX,LIST, SMTPSCRIPTPATH, LIST, domain ) >>  ALIASES ;
		printf(PREFIX "%s%s-owner: \"| %s/bouncequeue %s@%s\"\n", ALIAS_PREFIX,LIST, SMTPSCRIPTPATH, LIST, domain ) >>  ALIASES ;
		printf(PREFIX "%s%s-unsubscribe: \"| %s/queue %s-unsubscribe@%s\"\n", ALIAS_PREFIX,LIST, SMTPSCRIPTPATH, LIST, domain ) >>  ALIASES ;
		printf(PREFIX "# %s%s-subscribe: \"| %s/queue %s-subscribe@%s\"\n\n", ALIAS_PREFIX, LIST, SMTPSCRIPTPATH, LIST, domain ) >>  ALIASES ;
	}
}
