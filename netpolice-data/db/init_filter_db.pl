#!/usr/bin/perl -w

use strict;
use Getopt::Std;
use DBI;

my $options = {};
getopts ('hvcwd:sp:', $options);
if ($options->{h} || !$ARGV [0]) {
	$0 =~ m|([^/]+)$|;
	print <<EOF;
Usage is: $1 [-h] [-v] [-c] [-w] [-d directory] [-s] [-p passwd] DSN [dbuser [dbpass]]
where
	-h	print this message
	-v	print SQL statements
	-c	check only, don't create database
	-w	don't create database if any warnings
	-d	directory where configuration files resides
	-s	create schema only
	-p	set root password for WEB inteface (default root)
EOF
	exit;
}

my $engine = (DBI->parse_dsn ($ARGV [0])) [1];
if (!open SCHEMA,  $options->{d} ? "$options->{d}/$engine.schema" : "$engine.schema") {
	print STDERR "Can't find schema file for engine '$engine'\n";
	exit (1);
}
my $cmd = [];
while (<SCHEMA>) {
	chomp;
	push @$cmd, $_;
}
close SCHEMA;

my $dbh = DBI->connect (@ARGV);
if (!$dbh) {
	print STDERR "Error opening database '$ARGV[0]': ", DBI->errstr, "\n";
	exit (1);
}
push @$cmd, "INSERT INTO admins (aname, passwd, type) VALUES ('root', " . $dbh->quote ($options->{p} || 'root') . ", 'g')";

if ($options->{s}) {
	init_db ($cmd);
	exit (0);
}

my $keywords = [qw(parent whitelist blacklist reject redirect exactmatch)];

my ($roles, $users, $ngeneric) = ([], []);

if (!parse_roles ($roles, $options->{d} ? "$options->{d}/generic_roles" : 'generic_roles', ['accept', @$keywords])) {
	print STDERR "Fatal error parsing generic_roles file\n";
	exit (1);
}

$ngeneric = @$roles;
if (!$ngeneric) {
	print STDERR "No generic roles defined\n";
	exit (1);
}

if (!parse_roles ($roles, $options->{d} ? "$options->{d}/custom_roles": 'custom_roles', $keywords)) {
	print STDERR "Fatal error parsing custom_roles file\n";
	exit (1);
}

my ($name2id, $id);
for (@$roles) {
	$name2id->{$_->{rname}} = ++$id;
	next if $id <= $ngeneric;
	if (!exists $_->{parent} || !@{$_->{parent}}) {
		print STDERR "No parent(s) for custom role '$_->{rname}' defined\n";
		exit (1);
	}
}

if (!parse_users ($users, $options->{d} ? "$options->{d}/users" : 'users')) {
	print STDERR "Fatal error parsing users file\n";
	exit (1);
}

for (@$roles) {
	$id = $name2id->{$_->{rname}};
	push @$cmd, "INSERT INTO roles VALUES ($id, " . $dbh->quote ($_->{rname}) . ", '" . ($id <= $ngeneric ? 'g' : 'c') . "');";

	for (@{$_->{whitelist}}) {
		my $stars = /\*/g;
		$stars = 0 if !$stars;
#		if ($stars) {
			s/([?.+|\[\](){}])/\\$1/g;
			s/\*/\.*/g;
#		}
		push @$cmd, "INSERT INTO lists (rolid, url, stars, action) VALUES ($id, " . $dbh->quote ("^$_\$") . ", $stars, 0);";
	}

	for (@{$_->{blacklist}}) {
		my $stars = /\*/g;
		$stars = 0 if !$stars;
#		if ($stars) {
			s/([?.+|\[\](){}])/\\$1/g;
			s/\*/\.*/g;
#		}
		push @$cmd, "INSERT INTO lists (rolid, url, stars, action) VALUES ($id, " . $dbh->quote ("^$_\$") . ", $stars, 1);";
	}

	for (@{$_->{accept}}) {
		push @$cmd, "INSERT INTO perms (rolid, cat, action) VALUES ($id, $_, 0);";
	}

	for (@{$_->{reject}}) {
		push @$cmd, "INSERT INTO perms (rolid, cat, action) VALUES ($id, $_, 1);";
	}

	for (@{$_->{redirect}}) {
		push @$cmd, "INSERT INTO perms (rolid, cat, action) VALUES ($id, $_, 2);";
	}

	push @$cmd, "INSERT INTO hierarchy (parent, child) VALUES ($id, $id);";

	for (@{$_->{parent}}) {
		push @$cmd, "INSERT INTO hierarchy (parent, child) VALUES ($name2id->{$_}, $id)";
	}
}

for (@$users) {
	push @$cmd, "INSERT INTO users (uname, addr, mask, rolid) VALUES (" . $dbh->quote ($_->{uname}) . ", $_->{addr}, $_->{mask}, $name2id->{$_->{rname}});";
}

init_db ($cmd);

sub init_db {
	my ($cmd) = @_;
	for ('BEGIN;', @$cmd, 'COMMIT;') {
		print "$_\n" if $options->{v};
		if (!$options->{c} && !$dbh->do ($_)) {
			print STDERR "Error executing '$_': ", $dbh->errstr, "\n";
			exit (1);
		}
	}
	$dbh->disconnect;
}

sub parse_users {
	my ($users, $file) = @_;

	if (!open FILE, $file) {
		print STDERR "Can't open $file file: $!\n";
		return undef;
	}

	my $line;
	while (<FILE>) {
		++$line;
		chop;
		s/#.*//;
		next if /^\s*$/;
		my ($uname, $rname, $addr, $mask) = split ' ';
		if ($uname !~ /^(.+?)?@((\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(\/(\d{1,2}))?)?$/) {
			print STDERR "File '$file', line $line: Invalid user specification\n";
			return undef;
		}
		$uname = $1 ? $1 : '';
		if (!$2) {
#			$addr = "0.0.0.0";
#			$mask = 0;
			$addr = $mask = 0;
		} else {
#			$addr = "$3.$4.$5.$6";
#			$mask = $7 ? $8 : 32;
			$addr = ((($3 << 8) + $4 << 8) + $5 << 8) + $6;
			$mask = $7 && $8 < 32 ? ~0 << 32 - $8 & 0xffffffff : 0xffffffff;
			$addr &= $mask;
		}
		if (!$rname || !grep $rname eq $_->{rname}, @$roles) {
			print STDERR "File '$file', line $line: Role '$rname' doesn't exists\n";
			return undef;
		}
		push @$users, {uname => $uname, addr => $addr, mask => $mask, rname => $rname};
	}
	return $users;
}

sub parse_roles {
	my ($roles, $file, $keywords) = @_;
	my ($role, $line, $exactmatch);

	if (!open FILE, $file) {
		print STDERR "Can't open $file file: $!\n";
		return undef;
	}

	while (<FILE>) {
		++$line;
		s/#.*//;
		next if /^\s+$/;
		if (/^role\s+(\w+)/) {
			push @$roles, $role if $role;
			if (grep $1 eq $_, map $_->{rname}, @$roles) {
				print STDERR "File $file, line $line: Role '$1' alreay exists\n";
				return undef;
			}
			$role = {rname => $1};
		} elsif (!$role) {
			print STDERR "File $file, line $line:  Ignore statement outside role declaration\n";
			return undef if $options->{w};
		} else {
			my ($keyword, @args) = split ' ';
			if (!grep $keyword eq $_, @$keywords) {
				print STDERR "File $file, line $line: Invalid or illegal keyword '$keyword'\n";
				return undef if $options->{w};
			} elsif (!@args) {
				print STDERR "File $file, line $line: No arguments for keyword '$keyword'\n";
				return undef if $options->{w};
			} elsif ($keyword eq 'parent') {
				my @badargs;
				for my $rname (@args) {
					push @badargs, $rname if !grep $rname eq $_->{rname}, @$roles;
				}
				if (@badargs) {
					print STDERR "File $file, line $line: Roles @badargs not exists\n";
					return undef;
				}
			} elsif (grep $keyword eq $_, qw(accept reject redirect)) {
				my @badargs = grep !/^\d+$/, @args;
				if (@badargs) {
					print STDERR "File $file, line $line: Invalid categories numbers @badargs\n";
					return undef;
				}
			} elsif (grep $keyword eq $_, qw(whitelist blacklist)) {
				my @badargs;
				for (@args) {
					if (!m<^\w+://([^/]+\.)?\w+\.\w+($|/)>) {
						push @badargs, $_;
					} elsif (!$exactmatch) {
						$_ .= '*';
					} elsif (!length $2) {
						$_ .= '/';
					}
				}
				if (@badargs) {
					print STDERR "File $file, line $line: Invalid urls @badargs\n";
					return undef;
				}
			} elsif ($keyword eq 'exactmatch') {
				if (grep $args [0] eq $_, qw(on true 1)) {
					$exactmatch = 1;
				} elsif (grep $args [0] eq $_, qw(off false 1)) {
					$exactmatch = 0;
				} else {
					print STDERR "File $file, line $line: Invalid arguments for keyword '$keyword'\n";
					return undef if $options->{w};
				}
				@args = [];
			}
			push @{$role->{$keyword}}, @args if @args;
		}
	}
	push @$roles, $role if $role;
	return $roles;
}
