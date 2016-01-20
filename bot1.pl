use Net::IRC;

$server = 'zgen201m.z.bne.stg.ibm';
$channel = '#bodsz-cloning';
$botnick = 'bodszbot-beta';
#$password = 'lnx4ever';
$botadmin = 'viccross';

$irc = new Net::IRC;

$conn = $irc->newconn(Nick => $botnick,
	Server => $server, Port => 6667);

$conn->add_global_handler('376', \&on_connect);
$conn->add_global_handler('disconnect', \&on_disconnect);
$conn->add_global_handler('kick', \&on_kick);
$conn->add_global_handler('msg', \&on_msg);

$irc->start;

sub on_connect {
	$self = shift;
#	$self->privmsg('nickserv', "identify $password");
	$self->join($channel);
	$self->privmsg($channel, "Lo! I'm just a silent bot.");
}

sub on_disconnect {
	$self = shift;
	$self->connect();
}

sub on_kick {
	$self = shift;
	$self->join($channel);
	$self->privmsg($channel, "Please don't kick me!");
}

sub on_msg {
	$self = shift;
	$self->privmsg($botadmin, `uptime`);
}

