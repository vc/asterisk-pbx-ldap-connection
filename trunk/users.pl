#!/usr/bin/perl
# users.pl v1.1
#
# Script to generate asterisk 'users.conf' file from Active Directory (LADP) on users which contains 'phone' attribute
# 
# Using:
# 1. Print users to STDOUT:
# users.pl 
#
# 2. Print users to file:
# users.pl users_custom.conf

use strict;
use warnings;
use Net::LDAP;
use Lingua::Translit;

######################
### BEGIN SETTINGS ###
######################
my $debug = 0;
my $warning = 0;

# name of Domain
my $AD="domain";

# Domain name in format AD
# for example  mydomain.ru
my $ADDC="DC=domain";

# user in Active directory
# example: "CN=asterisk,CN=Users,$ADDC"
my $ADUserBind="CN=asterisk,CN=Users,$ADDC";
my $ADpass="p@s$w0rd";

# base search tree
# example "OU=Users,$ADDC"
my $ADUsersSearchBase="OU=Organisation,$ADDC";

# Field in active directory where telephone number, display name, phone stored
# "telephonenumber", "displayname", "mail"
my $ADfieldTelephone="telephonenumber";
my $ADfieldFullName="displayname";
my $ADfieldMail="mail";
my $ADfieldUser="samaccountname";

# You need to create a dialplan in your asterisk server;
my $dialplan="office";

# default settings
my $user_static = 
"context = $dialplan
call-limit = 100
type = friend
registersip = no
host = dynamic
callgroup = 1
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
#######################
### END OF SETTINGS ###
#######################

my $ldap;

# get array DNS names of AD controllers
my $dig = "dig -t srv _ldap._tcp.$AD" . '| grep -v "^;\|^$" | grep SRV | awk "{print \$8}"';
my @adControllers = `$dig`;
# try connect to AD controllers
foreach my $controller (@adControllers){
	$controller =~ s/\n//;
	#INITIALIZING
	$ldap = Net::LDAP->new ( $controller ) or next;
	print STDERR "Connected to AD controller: $controller\n" if $debug > 0;
	last;
}
die "$@" unless $ldap; 

my $mesg = $ldap->bind ( dn=>$ADUserBind, password =>$ADpass);

#PROCESSING - Displaying SEARCH Results
# Accessing the data as if in a structure
#  i.e. Using the "as_struct"  method
my $ldapUsers = LDAPsearch ( 
	$ADUsersSearchBase, 
	"$ADfieldTelephone=*",  
	[ $ADfieldFullName, $ADfieldTelephone, $ADfieldMail, $ADfieldUser ]
)->as_struct;

# translit RUS module.
# GOST 7.79 RUS, reversible, GOST 7.79:2000 (table B), Cyrillic to Latin, Russian
my $tr = new Lingua::Translit("GOST 7.79 RUS");

my %hashPhones = ();
my $phones = \%hashPhones;

my @out;

while ( my ($distinguishedName, $attrs) = each(%$ldapUsers) ) {
	# if not exist phone or name - skipping
	my $attrPhone = $attrs->{ "$ADfieldTelephone" } || next;	
	my $attrUser = $attrs->{ "$ADfieldUser" } || next;
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
	push (@out,  
		"[@$attrPhone]\n"
		. "fullname = $encName\n"
		. "email = @$attrMail\n"
		. "username = @$attrUser\n"
		#. "mailbox = @$attrPhone\n"
		. "cid_number = @$attrPhone\n"
		. "vmsecret = $phsecret\n"
		. "secret = $phsecret\n"	
		. "transfer = yes\n"	
		. "$user_static\n"
	);
}	# End of that DN

# print to file
if (@ARGV){
	open FILE, "> $ARGV[0]" or die "Error create file '$ARGV[0]': $!";
	print STDOUT "Printing to file '$ARGV[0]'";
	print FILE @out;	
	close FILE;
	print STDOUT " ...done!\n";
}
# print to STDOUT
else{
	print @out;
}

exit 0;

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
}