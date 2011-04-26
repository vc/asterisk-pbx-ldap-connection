#!/usr/bin/perl
use strict;
use warnings;
use Net::LDAP;
use Lingua::Translit;

my $debug = 0;
my $warning = 0;

#name or IP of Domain controller
my $ADcontroller="dc";

#Domain name in format AD
#for example  mydomain.ru
my $ADDC="DC=mydomain, DC=ru";

# BIND user in Active directory
# example: "CN=asterisk,CN=Users,$ADDC"
my $ADUserBind="CN=asterisk,CN=Users,$ADDC";
my $ADpass="p@s$w0rd";

# base search tree
# example "OU=Users,$ADDC"
my $ADUsersSearchBase="OU=MyOrganisation,$ADDC";

#Field in active directory where telephone number, display name, phone stored
# "telephonenumber", "displayname", "mail"
my $ADfieldTelephone="telephonenumber";
my $ADfieldFullName="displayname";
my $ADfieldMail="mail";

#You need to create a dialplan in your asterisk server;
my $dialplan="office";

# default settings
my $user_static = 
"context = $dialplan
call-limit = 100
type = friend
registersip = no
host = dynamic
callgroup = 1
hasvoicemail = yes
threewaycalling = no
hasdirectory = no
callwaiting = no
hasmanager = no
hasagent = no
hassip = yes
hasiax = yes
nat=yes
qualify=yes
dtmfmode = rfc2833
insecure = no
pickupgroup = 1
autoprov = no
label =
macaddress =
linenumber = 1
LINEKEYS = 1
callcounter = yes
disallow = all
allow = ulaw,alaw,iLBC,h263,h263p
";

#INITIALIZING
my $ldap = Net::LDAP->new ( $ADcontroller ) or die "$@";

#BINDING
my $mesg = $ldap->bind ( dn=>$ADUserBind, password =>$ADpass);

#PROCESSING - Displaying SEARCH Results
# Accessing the data as if in a structure
#  i.e. Using the "as_struct"  method
my $ldapUsers = LDAPsearch ( 
	$ADUsersSearchBase, 
	"$ADfieldTelephone=*",  
	[ $ADfieldFullName, $ADfieldTelephone, $ADfieldMail ]
)->as_struct;

# translit RUS module.
# GOST 7.79 RUS, reversible, GOST 7.79:2000 (table B), Cyrillic to Latin, Russian
my $tr = new Lingua::Translit("GOST 7.79 RUS");

my %hashPhones = ();
my $phones = \%hashPhones;

while ( my ($distinguishedName, $attrs) = each(%$ldapUsers) ) {
#	print $_, "\n";
	# if not exist phone or name - skipping
	my $attrPhone = $attrs->{ "$ADfieldTelephone" } || next;	
	my $attrName = $attrs->{ "$ADfieldFullName" } || next;	
	my $encName = $tr->translit("@$attrName");	
	my $attrMail = $attrs->{ "$ADfieldMail" } || [""];
	
	# check for duplicates phone number
	if ( $phones -> {"@$attrPhone"} ){
		my $currUser = "@$attrName";
		my $existUser = $phones -> {"@$attrPhone"};
		print STDERR "@$attrPhone alredy exist! Exist:'$existUser' Current:'$currUser'... skipping - '[@$attrPhone] $currUser'\n" if $warning;
		next;
	} else {			
		$phones -> {"@$attrPhone"} = "@$attrName";
	}
	
	# password for SID = (telephonenumber without first digit) + 1
	# example: phone=6232 pass=233
	#$phsecret =sprintf("%03d",( substr("@$attrVal",1,100)+1));
	my $phsecret = "@$attrPhone";
	print "[@$attrPhone]\n";
	
	print "fullname = $encName\n";
	print "email = @$attrMail\n";
	print "username = @$attrPhone\n";	
	#print "mailbox = @$attrPhone\n";
	print "cid_number = @$attrPhone\n";
	print "vmsecret = $phsecret\n";
	print "secret = $phsecret\n";
	
	print "transfer = yes\n";
	
	print "$user_static\n";	
}	# End of that DN

#OPERATION - Generating a SEARCH 
#$base, $searchString, $attrsArray
sub LDAPsearch
{
	my ($base, $searchString, $attrs) = @_;
	my $ret = $ldap->search ( base    => $base,
             	              scope   => "sub",
            		          filter  => $searchString,
                    	      attrs   => $attrs
                        	);
	LDAPerror("LDAPsearch", $ret) && die if( $ret->code );
	return $ret;
}

sub LDAPerror
{
	my ($from, $mesg) = @_;
	my $err = "[$from] - error" 
		."\nCode: " . $mesg->code
		."\nError: " . $mesg->error . " (" . $mesg->error_name . ")"
		."\nDescripton: " . $mesg->error_desc . ". " . $mesg->error_text;
	print STDERR $err if $warning;
	#print "\nServer error: " . $mesg->server_error if $debug;
}