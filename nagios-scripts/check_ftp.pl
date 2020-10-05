#!/usr/bin/perl -w 
# 
# Version 0.0.2
# # fixed some bugs when using strict
# Version 0.0.1
# # initial version

use Net::FTP;
use Getopt::Long qw(:config no_ignore_case);

my $hostname = 'devx-ftp001';
my $username = 'anonymous';
my $password = 'username@domain.com';
my $port = '21';
my $directory = '/';
my $file = '';
my $verbose = '0';
my $passive = '0';
my $timeout = "30";
my $version = "0.0.2";

sub help ();

my $options_okay = GetOptions (
  'hostname|H=s'	=> \$hostname,
  'username|u=s'	=> \$username,
  'password|p=s'	=> \$password,
  'port|P=s'		=> \$port,
  'directory=s'		=> \$directory,
  'file=s'		=> \$file,
  'verbose=i'		=> \$verbose,
  'version'		=> \$version,
  'help|h'		=> sub {help}
);

# creating connection
my $ftp = Net::FTP->new("$hostname", Debug => $verbose, Port => $port, Timeout => $timeout, Passive => $passive ) or die "ERROR: Cannot conect to $hostname\n";
 # print "ERROR: Cannot connect to $hostname, exiting...\n";
  #exit 2;
if (!$ftp->login("$username","$password")) { 
  print "ERROR: Sever says: ", $ftp->message;
  exit 2;
}
if ($file eq "") {
  if (!$ftp->ls("$directory")) { 
    print "WARNING: server says: " , $ftp->message;
    exit 1;
  } else  {
    print $ftp->message;
  }
} else {
  if (!$ftp->ls("$file")) { 
    print "WARNING: server says: " , $ftp->message;
    exit 1;
  } else {
    if (!$ftp->get("$file","/tmp/check_ftp")) {
      print "WARNING: server says: " , $ftp->message;
    } else {
      my @message = $ftp->message;
      chomp @message;
      print "OK: ", "$message[0] $message[1]\n";
      exit 0;
    }
  }
}
$ftp->quit;

sub help () {
        print "Copyright (c) 2005 Joost Veldkamp, nagios at darth dot xs4all dot nl
This plugin checks a ftp server, logins supported. The check downloads a file and returns
OK when the download succeeded.

-H, --hostname=HOST
   Name or IP address of host to check
-u, --username=username
   FTP username
-p --password=password
   FTP Password
-P --port=INTEGER
   TCP port of the FTP server (default 21)
-d --directory=PATH
   Directory on the remote FTP server
-f --file=FILENAME
   Filename of the file on the remote FTP server
-v --verbose=INT
   Print verbose stuff when performing the check, default 0, other for debugging.
-h --help
   Print this message.
-v --version
   Print version number.
";
exit 0;
}

