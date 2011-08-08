#!/usr/bin/perl
use strict;
use warnings;
use Net::LDAP;
use Lingua::Translit;

######################
### BEGIN SETTINGS ###
######################
my $debug = 0;
my $warning = 1;

# name of Domain
my $AD="mydomain";

# Domain name in format AD
# for example  mydomain.ru
my $ADDC="DC=mydomain";

# user in Active directory
# example: "CN=asterisk,CN=Users,$ADDC"
my $ADUserBind="CN=asterisk,CN=Users,$ADDC";
my $ADpass="p@s$w0rd";

# base search Groups tree example "OU=Users,$ADDC"
my $ADGroupsSearchBase = "OU=asterisk,OU=Groups,OU=eKassir,$ADDC";
# base search Users tree example "OU=Users,$ADDC"
my $ADUsersSearchBase = "OU=eKassir,$ADDC";

# Field in active directory where telephone number, display name, phone stored ...
# "telephonenumber", "displayname", "mail", ...
my $ADfieldTelephone = "telephonenumber";
my $ADfieldMember = "member";
my $ADfieldMemberOf = "memberof";
my $ADfieldInfo = "info";
my $ADfieldDescription = "description";
my $ADfieldMail = "mail";
#######################
### END OF SETTINGS ###
#######################

my $ldap;

# get array DNS names of AD controllers
my @adControllers = `dig -t srv _ldap._tcp.$AD | grep -v '^;\\|^\$' | grep SRV | awk '{print \$8}'`;
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
my $ldapGroups = LDAPsearch ( 
	$ADGroupsSearchBase, 
	"$ADfieldDescription=*",  
	[ $ADfieldMember, $ADfieldDescription ]
)->as_struct;

# translit RUS module.
# GOST 7.79 RUS, reversible, GOST 7.79:2000 (table B), Cyrillic to Latin, Russian
my $tr = new Lingua::Translit("GOST 7.79 RUS");

my $hash = ();

# process each group in $ADGroupsSearchBase with phone
while ( my ($distinguishedName, $groupAttrs) = each(%$ldapGroups) ) {
	print STDERR "Processing GROUP: [$distinguishedName]\n" if $debug > 1;
	my $attrMembers = $groupAttrs->{ $ADfieldMember } or next;
	my $desc = $groupAttrs->{ $ADfieldDescription } or next;
	my $groupNumber = "@$desc";
	
	print STDERR "MEMBERS: @$attrMembers\nDESC: $groupNumber  (Count=$#$attrMembers+1)" if $debug > 1;
	
	# process members in current group
	foreach my $member (@$attrMembers) {				
		my $ldapMember = LDAPsearch(
			$ADUsersSearchBase, 
			"$ADfieldTelephone=*", 
			[ $ADfieldTelephone ]
		) -> as_struct;
		
		my $memberAttrs = $ldapMember->{$member};
		my $memberPhone = $memberAttrs->{$ADfieldTelephone}[0] or next;		
		
		print STDERR "\nMEMBER: $member" if $debug > 1;
		print STDERR "\tPHONE:$memberPhone" if $debug > 1;		
		
		if ($hash -> {$groupNumber}){
			my $a = $hash -> {$groupNumber};
			push @$a, $memberPhone;
		} else {			
			$hash -> {$groupNumber} = [$memberPhone];
		}
	}
	print STDERR "\n\n" if $debug > 1;	
}	# End of that groups in $ADGroupsSearchBase

while ( my ($groupPhone, $userPhones) = each (%$hash) ) {	
	print STDERR "GROUP: $groupPhone\t PHONES: @$userPhones\n" if $debug > 1;
	#foreach my $userPhone (@$userPhones)	{
	print "exten => $groupPhone,1,Dial(sip/" . join('&sip/', @$userPhones) . ")\n";	
}

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
	#print STDERR "\nServer error: " . $mesg->server_error if $debug;
}