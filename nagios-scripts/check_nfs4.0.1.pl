#!/usr/bin/perl -w
#
# check_nfs4.pl
#
# Monitor NFSv4 servers (and clients)
#
# Usage:
#-------
# Use this plugin with NRPE:
#  - on the server config:
#       check_command check_nrpe!check_nfs4
#  - on the monitored host config:
#       command[check_nfs4]=/usr/local/bin/check_nfs4.pl [-s][-i]
#
# Performance data:
#------------------
# The performance data can be displayed in NagiosGraph with the following conf:
#    /perfdata:nfsd_cpu=(\d+)% nfsd_used_threads=(\d+)% io_read=(\d+)% io_write=(\d+)%/
#    and push @s, [ NFS4,
#               [ nfsd_cpu,             GAUGE, $1 ],
#               [ nfsd_used_threads,    GAUGE, $2 ],
#               [ io_read,              GAUGE, $3 ],
#               [ io_write,             GAUGE, $4 ] ];
#
#
# Released under GPL
# Copyright (c) 2005 Frederic Jolly
# Version 0.1
#

use strict;
use File::Basename;
use lib "/usr/local/nagios/libexec";
use utils qw($TIMEOUT %ERRORS &print_revision &support);
use vars qw($PROGNAME);

sub exit_error($$);
sub print_help();
sub print_usage();

#
# Configure here:
#----------------
#  - the timeout (in second) after which a mounts is considered as not responding
#  - the list of the logfiles you want to check
#  - the warning string you want to grep from the log files
my ($hang_timeout, @logfiles, $pblog);
$hang_timeout = 3;
@logfiles = ('/tmp/messages');
$pblog = ("(rpc.mountd: refused mount|NFSD: Failure|NFSD: error)");


$PROGNAME = 'check_nfs4';

my ($opt_V, $opt_H, $client, $opt_S, $verbose, $state, $status, $perfs);

$opt_V = $opt_H = $client = $opt_S = '';
$verbose = 0;
$state = 'OK';
$status = '';
$perfs = '|';

$ENV{'BASH_ENV'}='';
$ENV{'ENV'}='';
$ENV{'PATH'}='';
$ENV{'LC_ALL'}='C';

# Get the options
use Getopt::Long;
Getopt::Long::Configure('bundling');
GetOptions(
	   'V'  => \$opt_V,     'version'  => \$opt_V,
	   'h'  => \$opt_H,     'help'     => \$opt_H,
	   'i'  => \$client,    'client'   => \$client,
	   's'  => \$opt_S,     'sec'      => \$opt_S,
	   'v+'  => \$verbose,  'verbose+' => \$verbose
	   );

# -h|--help displays help
if ($opt_H) {
    print_help();
    exit $ERRORS{'OK'};
}

# -V|--version displays version number
if ($opt_V) {
    print_revision($PROGNAME,'$Revision: 0.1 $ '); 
    exit $ERRORS{'OK'};
}


# Get CPU perfs
if (!$client) {
    my ($cpu, @nfsd);
    $cpu=0;
    @nfsd = `/bin/ps --no-heading -C nfsd -o %cpu`;
    if ($?) { exit_error('UNKNOWN', "cannot find the command: '/bin/ps' or unknown options\n"); }
    map { $cpu += $_ } @nfsd;
    $perfs = $perfs . "nfsd_cpu=$cpu% ";
    if ($verbose) {
	$status = $status . "nfsd cpu = $cpu% ; ";
    }
}


#check the number of effective processes nfsd used
if (!$client) {
    my (@th_nfsd, $nb_th, $percent_used_th);
    open(RPC_NFSD, '/proc/net/rpc/nfsd') ||
	exit_error('UNKNOWN', "cannot read the file: '/proc/net/rpc/nfsd'\n");
    while (my $line = <RPC_NFSD>) {
	if ($line =~ /^th/) { @th_nfsd = split(' ', $line); }
    }
    close RPC_NFSD;
    $nb_th = $th_nfsd[1];
    if ($verbose) {
	$status = $status . "nfsd threads = $nb_th ; ";
    }
    $percent_used_th = 0;
    splice(@th_nfsd, 0, 3);
    map { if ($_ != 0) { $percent_used_th++ }} @th_nfsd;
    $percent_used_th *= 10;
    $status = $status . "nfsd used threads <= $percent_used_th% ; ";
    $perfs = $perfs . "nfsd_used_threads=$percent_used_th%";
}


# Get tranfer rates
if (!$client) {
    my (@iostat);
    @iostat = `/usr/sbin/nfsstat -ns`;
    if ($?) { exit_error('UNKNOWN', "cannot find the command: '/usr/sbin/nfsstat'\n"); }
    chomp @iostat;
    if ($iostat[12] =~ /[ ]*(\d+)% [^ ]+[ ]*(\d+)%/) {
	$perfs = $perfs . " io_read=$1% io_write=$2%";
    }
}


# Check if the daemons are running
my ($nfsd_d, $idmapd_d, $mountd_d, $svcgssd_d, $gssd_d, $process, $daelist);
$nfsd_d = $idmapd_d = $mountd_d = $svcgssd_d, $gssd_d = 0;
$daelist = '';
$process = `/bin/ps aux`;
if ($?) { exit_error('UNKNOWN', "cannot find the command: '/bin/ps'\n"); }
if ($process =~ /nfsd\]\n/) { $nfsd_d = 1; }
if ($process =~ /rpc.idmapd/) { $idmapd_d = 1; }
if ($process =~ /rpc.mountd\n/) { $mountd_d = 1; }
if ($process =~ /rpc.svcgssd\n/) { $svcgssd_d = 1; }
if ($process =~ /rpc.gssd\n/) { $gssd_d = 1; }
if (!$idmapd_d) { $daelist = $daelist . ' idmapd'; } 
if (!$client) {
    if (!$nfsd_d) { $daelist = $daelist . ' nfsd'; }
    if (!$mountd_d) { $daelist = $daelist . ' mountd'; }
    if ($opt_S && !$svcgssd_d) { $daelist = $daelist . ' svcgssd'; }
} else {
    if ($opt_S && !$gssd_d) { $daelist = $daelist . ' gssd'; }
}
if ($daelist ne '') {
    $state = 'CRITICAL';
    if ($daelist =~ / [^ ]+ /) { $status = $status . "daemons$daelist are not running ; "; }
    else { $status = $status . "daemon$daelist is not running ; ";}
}

# Check rpc errors
my (@nfsstat, @nfsstat_er, $rpc_error);
$rpc_error = 0;
if ($client) { @nfsstat = `/usr/sbin/nfsstat -rc`; }
else         { @nfsstat = `/usr/sbin/nfsstat -rs`; }
if ($?) { exit_error('UNKNOWN', "cannot find the command '/usr/sbin/nfsstat'\n"); }
chomp @nfsstat;
$nfsstat[2] =~ s/[ ]+/ /g;
@nfsstat_er = split(' ', $nfsstat[2]);
if ($client) {
    if ($nfsstat_er[1] != 0) { 
	$rpc_error = 1;
	if ($verbose) { $status = $status . "Client retrans = $nfsstat_er[1] ; "; }
    }
    if ($nfsstat_er[2] != 0) {
	$rpc_error = 1;
	if ($verbose) { $status = $status . "Client authrefrsh = $nfsstat_er[2] ; "; }
    }
} else {
    if ($nfsstat_er[1] != 0) {
	$rpc_error = 1;
	if ($verbose) { $status = $status . "Server badcalls = $nfsstat_er[1] ; "; }
    }
    if ($nfsstat_er[2] != 0) { 
	$rpc_error = 1;
	if ($verbose) { $status = $status . "Server badauth = $nfsstat_er[2] ; "; }
    }
    if ($nfsstat_er[3] != 0) {
	$rpc_error = 1;
	if ($verbose) { $status = $status . "Server badclnt = $nfsstat_er[3] ; "; }
    }
}
if ($rpc_error) { 
    $state = 'WARNING' unless $state eq 'CRITICAL';
    if (!$verbose) { $status = $status . "RPC errors ; "; }
}


# Detect if a mount points hangs
my (@mounts, @nfs4_mounts);
@mounts = `/bin/mount`;
if ($?) { exit_error('UNKNOWN', "cannot find the command '/bin/mount'\n"); }
@nfs4_mounts = grep { /type nfs4/ ? s/.*on ([^ ]*) type nfs4.*/$1/ : () } @mounts;
chomp @nfs4_mounts;
foreach my $dir (@nfs4_mounts) {
    eval {
        local $SIG{ALRM} = sub { die 'TIMEOUT\n' };
        alarm $hang_timeout;
	opendir(DIR,$dir);
	readdir(DIR);
	closedir(DIR);
        alarm 0;
    };
    if ($@) {
	$state = 'CRITICAL';
	$status = $status . "; The mounted directory $dir is not responding ; ";
    }
}


# Check the logfiles
# (an offset is used and stored to prevent from returning twice the same error)
foreach my $logfile (@logfiles) {
    if (! -f $logfile) { exit_error('UNKNOWN', "cannot find file $logfile\n"); }
    my ($log_error, $offsetfile, $inode, $offset, $ino, $size);
    $log_error = 0;
    $offsetfile = '/tmp/.' . basename($logfile) . '.offset';
    $inode = $offset = 0;
    unless (open(LOGFILE, $logfile)) { exit_error('UNKNOWN', "file $logfile can not be read\n"); }
    if (open(OFFSET, $offsetfile)) {
        $_ = <OFFSET>;
	chomp $_;
	$inode = $_;
	$_ = <OFFSET>;
	chomp $_;
	$offset = $_;
	close OFFSET;
    }
    unless ((undef,$ino,undef,undef,undef,undef,undef,$size) = stat $logfile) {
        exit_error('UNKNOWN', "cannot get $logfile file size\n");
    }
    if ($inode != $ino || $offset > $size) { $offset = 0; }
    seek(LOGFILE, $offset, 0);
    while (my $logline = <LOGFILE>) {
	chomp $logline;
	if ($logline =~ /$pblog/) {
	    $log_error = 1;
	    if ($verbose) { $status = $status . "\nLOG error: $logline ; "; }
	}
    }
    if ($log_error) {
	unless ($state eq 'CRITICAL') { $state = 'WARNING'; }
	if (!$verbose) { $status = $status . "LOG errors ; "; }
    }
    $size = tell LOGFILE;
    close LOGFILE;
    unless (open(OFFSET, ">$offsetfile")) { exit_error('UNKNOWN', "file $offsetfile cannot be created\n"); }
    print OFFSET "$ino\n$size\n";
    close OFFSET;
}


exit_error($state, $status);

#
# subroutines
#
sub exit_error ($$) {
    my $the_state = shift;
    my $the_line = shift;
    chomp $the_line;
    if ($the_line =~ / $/) { chop($the_line); }
    if ($the_line =~ /;$/) { chop($the_line); }
    print "$the_state: $the_line$perfs \n";
    exit $ERRORS{$the_state};
}

sub print_help () {
    print_revision($PROGNAME, '$Revision: 0.1 $ ');
    print "Copyright (c) 2005 Frédéric Jolly\n\n";
    print "NFSv4 plugin for Nagios\n";
    print_usage();
    print "\n";
    print "   [-v]                 Verbose\n";
    print "   [-i | --client]      Monitor an NFSv4 client\n";
    print "   [-s | --sec]         Check also security features\n";
    print "\n";
    print "$PROGNAME monitors on an NFSv4 server (or on an NFSv4 client) the following NFSv4 features:\n";
    print "  - check if the daemons (server-side, client-side, security) are running\n";
    print "  - check if there are rpc errors\n";
    print "  - detect if a mounting point hangs\n";
    print "  - check the percentage of CPU taken by nfsd\n";
    print "  - check the number of effective used nfsd processes\n";
    print "  - grep some problematic strings from logs\n";
    print "\n";
    print "$PROGNAME returns also performance data:\n";
    print "  - the percentage of CPU taken by nfsd\n";
    print "  - the number of effective used nfsd processes\n";
    print "  - the transfer rates\n";
    print "\n";
    support();
}

sub print_usage () {
    	print "Usage: \n";
	print " $PROGNAME [-v] [-i | --client] [-s | --sec]\n";
	print " $PROGNAME [-h | --help]\n";
	print " $PROGNAME [-V | --version]\n";
}
