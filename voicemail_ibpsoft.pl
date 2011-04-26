#!/usr/bin/perl
use strict;
use warnings;
use Net::LDAP;
use Lingua::Translit;

###### BEGIN USER SETTINGS ######
#name or IP of Domain controller
my $ADcontroller="dc";

#Domain name in format AD
#for example  mydomain.ru
my $ADDC="DC=mydomain, DC=ru";

# user in Active directory
# example: "CN=asterisk,CN=Users,$ADDC"
my $ADUserBind="CN=asterisk,CN=Users,$ADDC";
my $ADpass="p@s$w0rd";

# base search Users tree example "OU=Users,$ADDC"
my $ADUsersSearchBase = "OU=MyOrganisation,$ADDC";

# default email to send voicemail if email user not set
my $defaultEmail = 'asterisk@ekassir.com';

# Field in active directory where telephone number, display name, phone stored ...
# "telephonenumber", "displayname", "mail", ...
my $ADfieldTelephone = "telephonenumber";
my $ADfieldMember = "member";
my $ADfieldMemberOf = "memberof";
my $ADfieldInfo = "info";
my $ADfieldDescription = "description";
my $ADfieldMail = "mail";
my $ADfieldFullName = "name";
# Debug flags
my $debug = 0;
my $warning = 0;
###### END USER SETTINGS ######


#INITIALIZING & BINDING
my $ldap = Net::LDAP->new ( $ADcontroller ) or die "$@";
my $mesg = $ldap->bind ( dn=>$ADUserBind, password =>$ADpass);

#PROCESSING - Displaying SEARCH Results
# Accessing the data as if in a structure i.e. Using the "as_struct"  method
my $ldapUsers = LDAPsearch ( 
	$ADUsersSearchBase, 
	"$ADfieldTelephone=*",  
	[ $ADfieldTelephone, $ADfieldMail, $ADfieldFullName ]
)->as_struct;

my %hashPhones = ();
my $phones = \%hashPhones;

# translit RUS module.
# GOST 7.79 RUS, reversible, GOST 7.79:2000 (table B), Cyrillic to Latin, Russian
#using: $encName = $tr->translit("@$attrName");
my $tr = new Lingua::Translit("GOST 7.79 RUS");

# process each group in $ADGroupsSearchBase with phone
while ( my ($distinguishedName, $userAttrs) = each(%$ldapUsers) ) {
	#print "Processing GROUP: [$distinguishedName]\n" if $debug;
	my $attrTelephone = $userAttrs->{ $ADfieldTelephone	} or next;
	my $attrFullName = $userAttrs->{ $ADfieldFullName} || "";
	my $attrEmail = $userAttrs->{ $ADfieldMail } or next;
	
	# check for duplicates phone number
	if ( $phones -> {"@$attrTelephone"} ){
		my $currUser = "@$attrFullName";
		my $existUser = $phones -> {"@$attrTelephone"};
		print STDERR "@$attrTelephone alredy exist! Exist:'$existUser' Current:'$currUser'... skipping - '[@$attrTelephone] $currUser'\n" if $warning;
		next;
	} else {			
		$phones -> {"@$attrTelephone"} = "@$attrFullName";
	}
	
	my $fullName = $tr->translit("@$attrFullName");
	my $phone = "@$attrTelephone";
	my $mail = "@$attrEmail";
	
	print "USER: $fullName\tPHONE: $phone\tMAIL: $mail\n" if $debug;
	
	print "$phone => $phone, $fullName, $mail\n";
}	# End of that groups in $ADGroupsSearchBase

exit 0;

#OPERATION - Generating a SEARCH
# $base, $searchString, $attrsArray
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