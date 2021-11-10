BEGIN { 
body = 0;
multipart=0;
separator="";
}
/^$/ {
	if (body==0) body=1;
	else if (multipart==1) {
		print gensub("^--","", "", separator);
		exit;	
		}
}
/^Content-Type:/ {
	if (body==1) multipart=1;
}
{
	if (body==1) {
	  	if($0~"^--.*$") separator=$0;
		else if (separator=="") separator=$0;
		}

}

