#!/usr/local/bin/perl -w
use strict;
use IO::Socket;

my($sock, $server_host, $msg, $PORTNO);

$PORTNO  = 15555;
$server_host = '188.x.x.x';



$sock = IO::Socket::INET->new(Proto     => 'udp',
                              PeerPort  => $PORTNO,
                              PeerAddr  => $server_host)
    or die "Creating socket: $!\n";


while (<>){
$sock->send($_)
}
