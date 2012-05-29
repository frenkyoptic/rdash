#!/usr/local/bin/perl -w
use strict;
use warnings;

use Cache::Memcached::Fast;
use IO::Socket;
use IO::Lambda qw(:all);
use IO::Lambda::Socket qw(:all);
use Getopt::Std;
use POSIX qw/setsid/;

# use -d for demonize

my $PORT=1555;
my $LOCALHOST ='188.x.x.x';
my $CONFIG='./frenko_config';
my $time_to_die=0;
 
my $memd = new Cache::Memcached::Fast({
      servers => [ 
	  { address => 'localhost:11211', weight => 2.5 }],
      connect_timeout => 0.2,
      io_timeout => 0.5,
      close_on_error => 1,
      max_failures => 3,
      failure_timeout => 2,
      ketama_points => 150,
      nowait => 1,
      utf8 => ($^V >= 5.008001 ? 1 : 0),
  });  

my %Regexps=();
load_config(\%Regexps);
  
sub load_config{
	my $re=shift;
	%{$re}=();
	open (F,$CONFIG) || die 'cant open config '.$CONFIG;
	while (<F>){
		next if /^[\s\n]+$/;
		my ($regexp,$key,undef,$rate,$index)=split("\t",$_,5);
		$index=~s/[\n\t\r]//g;
		$$re{$key}{re}=qr($regexp);
		$$re{$key}{index}=$index;
		$$re{$key}{rate}=$rate || 1;
	}
	close (F);
}


sub sendstat{		
	my ($key,$rate,$memd)=@_;
	
	if ($rate==1 || $rate<rand()){

		saver($key,$_,$memd) for (2,300,1200)
		
	}
}

sub saver{
	my ($key,$accur,$memd)=@_;
	
	my $memc=startpoint($accur);
	$key=$key.'_'.$accur.'_'.$memc;
	
	my $ttl=1000;
	if ($accur==300){$ttl=7400}
	elsif($accur==1200){$ttl=87000}
	
	$memd->set($key,1,$ttl) unless $memd->incr($key);
	my $p=$memd->get($key);
	print "$key value: $p\n";
}

sub startpoint{
	my $accur=shift;
	my $t=time();
	my $x=$t % $accur;
	my $memc=$t-$x;
	return $memc;
}

# Returns a lambda that listens on an UDP socket, and spawns
# new lambdas on every datagram.
sub udp_server(&@)
{
    my ($callback, $port, $host) = @_;

    my $server = IO::Socket::INET-> new(
        Proto => 'udp',
        LocalPort => $port,
		LocalHost => $host,
        Blocking => 0,
    );
    return $! unless $server;

    # this lambda will be the server
    return lambda {

        # The two lines below say: on the socket $server, sleep
        # until the socket becomes writable, which means that we've
        # got a connection. On the connected socket then issue a
        # CORE::recv() call with max UDP packet size 64K
        context $server, 65536, 0;
    recv {

        # Address of the client socket, and the datagram
        my ( $addr, $msg) = @_;

        # Re-register the callback and wait again (i.e. same context $server; recv ) call
        again;

        # Instantiate a new lambda with $addr and $msg, and wait
		# /usr/sbin/tcpdump -ni eth1 -A -vv dst port 5151

        # for it to finish. It's not a blocking wait, and again() call
        # above makes sure that if there comes another connection meanwhile,
        # it will be served as well.
        context $callback-> (), $addr, $msg;
        &tail();
    }}
}


sub handle_incoming_connection_udp
{
    lambda {
        my ( $addr, $msg ) = @_;

		if (length($msg)>5){
			if  (substr($msg,0,8) eq 'reconfig'){
				load_config(\%Regexps);
			}
			else {
				foreach my $key(keys %Regexps){
					if (index($msg,$Regexps{$key}{index})>=0){
						if ($Regexps{$key}{index} eq $Regexps{$key}{re}){
							sendstat($key,$Regexps{$key}{rate},$memd);
							last;
						}elsif($msg=~/$Regexps{$key}{re}/){
							sendstat($key,$Regexps{$key}{rate},$memd);
							last;
						}
					}

				}
			
			}
		}
    }
}

sub runserv{
	# fire up the server
	my $server = udp_server { handle_incoming_connection_udp } $PORT,$LOCALHOST;
	die $server unless ref $server;
	$server-> wait;
}

sub signal_handler{
	$time_to_die=1;
}


getopts('d:', my $opts = {});

if (exists $opts->{d}) {
	print "start daemon\n";


	my $pid=fork;
	exit if $pid;
	die 'Couldn\'t fork: '.$! unless defined($pid);
	
	for my $handle (*STDIN, *STDOUT, *STDERR){
		open ($handle, '+<', '/dev/null' ) || die 'Cant\t reopen '.$handle.' to /dev/null: '.$!;
	}
	
	POSIX::setsid() || die 'Can\'t start a new session: '.$!;

	$time_to_die=0;
	
	$SIG{TERM} = $SIG{INT} = $SIG{HUP}= \&signal_handler;
	until ($time_to_die){
		runserv();
	}
	
}
else {
	runserv()
}



