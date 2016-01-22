#!/usr/bin/perl
#
# gridbot.pl
# Your grid management bot with the lot.
# This is $Revision$

use strict;
use warnings;
use Switch;
use POE qw(Component::IRC);
use POE qw(Component::JobQueue);
use Net::Twitter::Lite::WithAPIv1_1;
use Try::Tiny;

my ($revision) = '$Revision$' =~ /\$Revision: (.+) \$/;
my $pidfile  = '/var/run/gridbot.pid';
my $nickname = 'testBot';
my $password = 'gridBotTObDIRG';
my $ircname  = 'Management of the Cloning Grid';
my $server   = 'zgn2c001.z.mel.stg.ibm';

my $gueststatus = {};
my @channels = ('#bodsz-cloning');

my $TWITTER_CONSUMER_KEY = "u8cGtaZRPH9ROZUf0HZgEOtS7";
my $TWITTER_CONSUMER_SECRET = "WPDYSSvzhwN0kpW3r2JOVGbMJMOn0XhRd6eU9MAOm5a2mxfNr9";
my $TWITTER_ACCESS_TOKEN = "401858482-IQbMcYFnWMrulJNFOcTfJLxW0M4jKAvBofVy8Fi0";
my $TWITTER_ACCESS_SECRET = "TZQXTPZWsvQlnd19sm8PaADUjw57NFeEuXR5OzFxm9Wbs";

my @grpsufx = ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F');
my @racksufx = ('1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F');

my $gridcount = 0;
my $gridpcnt = 0;
my $avgproc = 0;
my $paging = 0;
my $topicint = 60;
my $dirmBot = 'no';
my $maindelay = 2;
my $cattledelay = 0;

# Daemonise, maximum warp, engage
use POSIX;
#POSIX::setsid or die "setsid: $!";
#my $pid = fork ();
#if ($pid < 0) {
#    die "fork: $!";
#} elsif ($pid) {
#    open PIDFILE, ">$pidfile" or die "can't open $pidfile: $!\n";
#    print PIDFILE $pid;
#    close PIDFILE;
#    exit 0;
#}
#chdir "/";
#umask 0;
#foreach (0 .. (POSIX::sysconf (&POSIX::_SC_OPEN_MAX) || 1024))
#    { POSIX::close $_ }
#open (STDIN, "</dev/null");
#open (STDOUT, ">/dev/null");
#open (STDERR, ">&STDOUT");

# We create a new PoCo-IRC object
my $irc = POE::Component::IRC->spawn(
   nick => $nickname,
   ircname => $ircname,
   server  => $server,
   flood => 1,
) or die "Oh noooo! $!";

POE::Session->create(
    package_states => [
        main => [ qw(_default _start irc_001 irc_public irc_msg irc_join irc_part irc_quit irc_ctcp_action irc_dcc_request irc_dcc_get irc_dcc_done) ],
    ],
    heap => { irc => $irc },
);

POE::Component::JobQueue->spawn
  ( Alias       => 'command',
    WorkerLimit => 1,
    Worker      => \&pop_cmd,
    Passive     => {},
  );

POE::Component::JobQueue->spawn
  ( Alias       => 'vmcp',
    WorkerLimit => 1,
    Worker      => \&pop_vmcp,
    Passive     => {},
  );

POE::Component::JobQueue->spawn
  ( Alias       => 'smapi',
    WorkerLimit => 1,
    Worker      => \&pop_smapi,
    Passive     => {},
  );

POE::Component::JobQueue->spawn
  ( Alias       => 'cattle',
    WorkerLimit => 1,
    Worker      => \&pop_cattle,
    Passive     => {},
  );
  
POE::Component::JobQueue->spawn
  ( Alias       => 'action',
    WorkerLimit => 1,
    Worker      => \&pop_action,
    Passive     => {},
  );

POE::Session->create(
    inline_states   => {
        _start      => \&update_stats,
        topic_stats => \&topic_stats,
    },
);

$poe_kernel->run();

sub _start {
    my $heap = $_[HEAP];

    # retrieve our component's object from the heap where we stashed it
    my $irc = $heap->{irc};

    $irc->yield( register => 'all' );
    $irc->yield( connect => { } );
    return;
}

sub irc_001 {
    my $sender = $_[SENDER];

    # Since this is an irc_* event, we can get the component's object by
    # accessing the heap of the sender. Then we register and connect to the
    # specified server.
    my $irc = $sender->get_heap();

    print "Connected to ", $irc->server_name(), "\n";

    # we join our channels
    $irc->yield( privmsg => 'nickserv', "identify $password" );
    $irc->yield( join => $_ ) for @channels;
    return;
}

sub irc_public {
    my ($sender, $who, $where, $what) = @_[SENDER, ARG0 .. ARG2];
    my $nick = ( split /!/, $who )[0];
    my $channel = $where->[0];

    if ( my ($actual) = $what =~ /^$nickname[,:]* (.+)/ ) {
        &process($nick,$channel,$actual,'pub');
    }
    return;
}

sub irc_msg {
    my ($sender, $who, $where, $what) = @_[SENDER, ARG0 .. ARG2];
    my $nick = ( split /!/, $who )[0];

    &process($nick,$channels[0],$what,'priv');
    return;
}

sub process {
    my ($nick,$channel,$what,$pubpriv) = @_;
    if ( my ($rot13) = $what =~ /^rot13 (.+)/ ) {
        $rot13 =~ tr[a-zA-Z][n-za-mN-ZA-M];
        $irc->yield( privmsg => $channel => "$nick: $rot13" );
    }
    # show usage info
    if ( $what =~ /^usage/ ) {
        my $dest = ( $pubpriv eq 'priv' ) ? $nick : $channel;
        $irc->yield( privmsg => $dest => "gridBot beta0.2-r$revision usage:");
        $irc->yield( privmsg => $dest => "status             : Tells you about the grid");
        $irc->yield( privmsg => $dest => "gueststat [guest]  : Tells you about a specific clone");
        $irc->yield( privmsg => $dest => "grpstat [C R G]    : Tells you about a group");
        $irc->yield( privmsg => $dest => "guestset [gst] [s] : Sets status for a specific clone");
        $irc->yield( privmsg => $dest => "startcage [C]      : Starts a cage C=cage");
        $irc->yield( privmsg => $dest => "startrack [C R]    : Starts a rack C=cage, R=rack");
        $irc->yield( privmsg => $dest => "startgrp [C R G]   : Starts a group C=cage, R=rack, G=group");
        $irc->yield( privmsg => $dest => "stopcage [C]       : Stops a cage C=cage");
        $irc->yield( privmsg => $dest => "stoprack [C R]     : Stops a rack C=cage, R=rack");
        $irc->yield( privmsg => $dest => "stopgrp [C R G]    : Stops a group C=cage, R=rack, G=group");
        $irc->yield( privmsg => $dest => "botstat            : Tells you about my processing");
        $irc->yield( privmsg => $dest => "tweetstats #[hash] : Tweet grid stats, add a whimsical hashtag");
        $irc->yield( privmsg => $dest => "vmcp [command]     : Issue a CP command");
        $irc->yield( privmsg => $dest => "smapi [command]    : Issue a SMAPI command");
    }
    # Issue a CP command
    if ( my ($cpcommand) = $what =~ /^vmcp (.+)/ ) {
        $cpcommand =~ tr[a-z][A-Z];
        $irc->yield( privmsg => $channel => "Issuing $cpcommand for $nick" );
        $poe_kernel->post('vmcp', 'enqueue', '', "$cpcommand", "$nick", "irc");
#       my @cpresult = `vmcp $cpcommand`;
#	my $rc = $?;
#	foreach (@cpresult) {
#          $irc->yield( privmsg => $channel => "$_" );
#	}
#	if ( $rc > 0 ) {
#          $irc->yield( ctcp => $channel => "ACTION saw exit status of $rc on that command $nick" );
#	}
    }
    # Issue a SMAPI command
    if ( my ($smapicommand) = $what =~ /^smapi (.+)/ ) {
#        $smapicommand =~ tr[a-z][A-Z];
        $irc->yield( privmsg => $channel => "Issuing SMAPI $smapicommand for $nick" );
        $poe_kernel->post('smapi', 'enqueue', '', "$smapicommand", "$nick", "irc");
    }
    # Get a guest status
    if ( my ($guest) = $what =~ /^gueststat (.+)/ ) {
        my $dest = ( $pubpriv eq 'priv' ) ? $nick : $channel;
        $guest =~ tr[a-z][A-Z];
        $irc->yield( privmsg => $channel => "Finding status of $guest for $nick" );
        my $status = ( !defined $gueststatus->{ $guest } ) ? "unknown" : $gueststatus->{ $guest };
        $irc->yield( privmsg => $dest =>  "Clone $guest is $status");
    }
    # Get a group status
    if ( my ($cage, $rack, $group) = $what =~ /^grpstat (.) (.) (.)/ ) {
        my $dest = ( $pubpriv eq 'priv' ) ? $nick : $channel;
        $irc->yield( privmsg => $channel => "Finding status of cage $cage, rack $rack, group $group for $nick" );
        my $status = "";
        foreach my $x (@grpsufx) {
        	switch ( $gueststatus->{ "GN2C$cage$rack$group$x" } ) {
        		case "active"       { $status = $status . "a " }
        		case "activating"   { $status = $status . "A " }
        		case "deactivating" { $status = $status . "D " }
        		case "down"         { $status = $status . "d " }
        		case "recycling"    { $status = $status . "R " }
        		case "deactivate"   { $status = $status . "K " }
        		case "activate"     { $status = $status . "S " }
        		else                { $status = $status . "u " }
        	}
        }
        $irc->yield( privmsg => $dest =>  "GN2C$cage$rack$group" . "x status as follows:");
        $irc->yield( privmsg => $dest =>  "0 1 2 3 4 5 6 7 8 9 A B C D E F");
        $irc->yield( privmsg => $dest => $status );
    }
    # Set a guest status
    if ( my ($guest, $status) = $what =~ /^guestset (.+) (.+)/ ) {
        my $dest = ( $pubpriv eq 'priv' ) ? $nick : $channel;
        $guest =~ tr[a-z][A-Z];
        $irc->yield( privmsg => $channel => "Setting status of $guest to $status for $nick" );
        $gueststatus->{ $guest } = $status;
        $irc->yield( privmsg => $dest =>  "Clone $guest is now set to $status");
    }
    # Tweet the grid status
    if ( my ($tweethashtag) = $what =~ /^tweetstats (.+)/ ) {
        my $time = strftime "%a %e %H:%M", localtime();
        try { &tweet("Grid status at $time: $gridcount guests active, avg CPU $avgproc%, Paging $paging/sec.","$tweethashtag"); }
	catch { $irc->yield( ctcp => $channels[0] => "ACTION just tried to tweet and it failed: $_." ); };
    }
    # start a group of servers
    if ( my ($cage, $rack, $group) = $what =~ /^startgrp (.) (.) (.)$/ ) {
        $irc->yield( privmsg => $channel => "$nick asked me to start cage $cage, rack $rack, group $group");
	    $irc->yield( ctcp => $channel => "ACTION puts that in the queue");
	    &startgrp($nick,$cage,$rack,$group);
    }
    # stop a group of servers
    if ( my ($cage, $rack, $group) = $what =~ /^stopgrp (.) (.) (.)$/ ) {
        $irc->yield( privmsg => $channel => "$nick asked me to stop cage $cage, rack $rack, group $group");
	    $irc->yield( ctcp => $channel => "ACTION puts that in the queue");
	    &stopgrp($nick,$cage,$rack,$group);
    }
    # start a rack of servers
    if ( my ($cage, $rack) = $what =~ /^startrack (.) (.)$/ ) {
        $irc->yield( privmsg => $channel => "$nick asked me to start cage $cage, rack $rack");
	    $irc->yield( ctcp => $channel => "ACTION puts that in the queue");
	    &startrack($nick,$cage,$rack);
    }
    # stop a rack of servers
    if ( my ($cage, $rack) = $what =~ /^stoprack (.) (.)$/ ) {
        $irc->yield( privmsg => $channel => "$nick asked me to stop cage $cage, rack $rack");
	    $irc->yield( ctcp => $channel => "ACTION puts that in the queue");
	    &stoprack($nick,$cage,$rack);
    }
    # make a group of servers
    if ( my ($cage, $rack, $group) = $what =~ /^makegrp (.) (.) (.)$/ ) {
        $irc->yield( privmsg => $channel => "$nick asked me to create cage $cage, rack $rack, group $group");
        $irc->yield( ctcp => $channel => "ACTION puts that in the queue");
        &makegrp($nick,$cage,$rack,$group);
    }
    # drop a group of servers
    if ( my ($cage, $rack, $group) = $what =~ /^dropgrp (.) (.) (.)$/ ) {
        $irc->yield( privmsg => $channel => "$nick asked me to remove cage $cage, rack $rack, group $group");
        $irc->yield( ctcp => $channel => "ACTION puts that in the queue");
        &dropgrp($nick,$cage,$rack,$group);
    }
    # get the grid status
    if ( $what =~ /^status/ ) {
        my $dest = ( $pubpriv eq 'priv' ) ? $nick : $channel;
        $irc->yield( privmsg => $dest => "Status of the cloning grid:");
	    $irc->yield( privmsg => $dest => "Number of active grid guests: $gridcount");
	    $irc->yield( privmsg => $dest => "AvgProc: $avgproc% Paging: $paging");
	    $irc->yield( privmsg => $dest => "Current command delay: $maindelay sec");
#	    $irc->yield( privmsg => $dest => "Is dirmBot logged on: $dirmBot");
    }
    # get the bot status
    if ( $what =~ /^botstat/ ) {
        my $dest = ( $pubpriv eq 'priv' ) ? $nick : $channel;
        $irc->yield( privmsg => $dest => "I'm super, thanks for asking!");
        $irc->yield( ctcp => $dest => "ACTION has a little squee at being noticed and appreciated");
    }
    return;
}

sub irc_join {
    my ($sender, $who, $where) = @_[SENDER, ARG0 .. ARG1];
    my $nick = ( split /!/, $who )[0];
    if ( $nick eq $nickname ) { return; }
    my $channel = $where;
    if ( $nick eq 'dirmBot' ) {
        $irc->yield( privmsg => $channel => "M'coll dirmBot is online, DirMaint command functions available");
	$dirmBot = 'yes';
    } else {
        $irc->yield( privmsg => $channel => "Welcome to $channel, $nick, from your friendly gridBot");
        $irc->yield( privmsg => $channel => "You can get help on usage by typing 'usage'");
        $irc->yield( privmsg => $channel => "To avoid cluttering the channel most dialog will be via PRIVMSG.");
    }
    return;
}

sub irc_part {
    my ($sender, $who, $where, $why) = @_[SENDER, ARG0 .. ARG2];
    my $nick = ( split /!/, $who )[0];
    my $channel = $where;
    if ( $nick eq 'dirmBot' ) {
        $irc->yield( privmsg => $channel => "M'coll dirmBot just left, DirMaint command functions not available");
	$dirmBot = 'no';
    }
    return;
}

sub irc_quit {
    my ($sender, $who, $why) = @_[SENDER, ARG0 .. ARG1];
    my $nick = ( split /!/, $who )[0];
    if ( $nick eq 'dirmBot' ) {
        $irc->yield( privmsg => $channels[0] => "M'coll dirmBot just quit, DirMaint command functions not available");
	$dirmBot = 'no';
    }
    return;
}

sub irc_ctcp_action {
    my ($sender, $who, $where, $what) = @_[SENDER, ARG0 .. ARG2];
    my $nick = ( split /!/, $who )[0];
    if ( $nick eq $nickname ) { return; }
    my $channel = $where->[0];

    $irc->yield( privmsg => $channel => "More power to ya, $nick!");
    return;
}

sub irc_dcc_request {
    my ($sender, $who, $which, $port, $cookie, $what, $size, $ipaddr) = @_[SENDER, ARG0 .. ARG6];
    my $nick = ( split /!/, $who )[0];
    if ( $nick eq $nickname ) { return; }

    $irc->yield( privmsg => $nick => "Trying DCC with $nick, file $what ($size bytes)");
    $irc->yield( dcc_accept => $cookie );
    return;
}

sub irc_dcc_get {
    return;
}

sub irc_dcc_done {
    my ($sender, $wheelid, $who, $type, $port, $what, $size, $ipaddr) = @_[SENDER, ARG0 .. ARG7];
    my $nick = ( split /!/, $who )[0];

    $irc->yield( privmsg => $nick => "DCC with $nick completed, received $what ($size bytes)");
    return;
}

# We registered for all events, this will produce some debug info.
sub _default {
    my ($event, $args) = @_[ARG0 .. $#_];
    my @output = ( "$event: " );

    for my $arg (@$args) {
        if ( ref $arg eq 'ARRAY' ) {
            push( @output, '[' . join(', ', @$arg ) . ']' );
        }
        else {
            push ( @output, "'$arg'" );
        }
    }
    print join ' ', @output, "\n";
    return;
}

###
# Grid-specific functions
#

sub startgrp {
    my ($nick, $cage, $rack, $group) = @_;

    foreach my $x (@grpsufx) {
      $poe_kernel->post('command', 'enqueue', '', "XAUTOLOG GN2C$cage$rack$group$x", "$nick");
#      $irc->yield( privmsg => @channels[0] => "XAUTOLOG GN2C$cage$rack$group$x");
    }
    return;
}

sub startrack {
    my ($nick, $cage, $rack) = @_;

    foreach my $x (@racksufx) {
        &startgrp($nick, $cage, $rack, $x);
    }
}

sub stopgrp {
    my ($nick, $cage, $rack, $group) = @_;

    foreach my $x (@grpsufx) {
      $poe_kernel->post('command', 'enqueue', '', "SIGNAL SHUTDOWN GN2C$cage$rack$group$x WITHIN 30", "$nick");
    }
    return;
}

sub stoprack {
    my ($nick, $cage, $rack) = @_;

    foreach my $x (@racksufx) {
        &stopgrp($nick, $cage, $rack, $x);
    }
}

sub makegrp {
    my ($nick, $cage, $rack, $group) = @_;

    $poe_kernel->post('dirmBot', 'enqueue', \&dirm_cmd, "MAKEGRP $cage $rack $group", "$nick");
#    foreach my $x (@grpsufx) {
#      $poe_kernel->post('command', 'enqueue', '', "XAUTOLOG GN2C$cage$rack$group$x", "$nick", 3);
#    }
    return;
}

sub dropgrp {
    my ($nick, $cage, $rack, $group) = @_;

    $poe_kernel->post('dirmBot', 'enqueue', \&dirm_cmd, "DROPGRP $cage $rack $group", "$nick");
#    foreach my $x (@grpsufx) {
#      $poe_kernel->post('command', 'enqueue', '', "XAUTOLOG GN2C$cage$rack$group$x", "$nick", 3);
#    }
    return;
}

sub pop_cmd {
    my ($postback, $cmdline, $nick) = @_;

    POE::Session->create (
      inline_states => {
        _start      => \&run_cmd,
        cmd_clr     => \&cmd_clr,
      },
      args => [ "$cmdline", "$nick" ],
    );
    return;
}

sub cmd_clr {
    return;
}

sub run_cmd {
    my ($cmdline, $nick) = @_[ARG0 .. ARG1];
#    $irc->yield( privmsg => $nick => "Issuing $cmdline");
#    $irc->yield( privmsg => $channel => "Issuing $cmdline for $nick" );
    $poe_kernel->post('vmcp', 'enqueue', '', "$cmdline", "$nick", "irc");
    $poe_kernel->delay(cmd_clr => $maindelay);
    return;
}

sub pop_vmcp {
    my ($postback, $cmdline, $nick, $disp ) = @_;

    POE::Session->create (
      inline_states => {
        _start      => \&run_vmcp,
#	cmd_clr     => \&cmd_clr,
      },
      args => [ "$cmdline", "$nick", "$disp" ],
    );
    return;
}

sub run_vmcp {
    my ($cmdline, $nick, $disp) = @_[ARG0 .. ARG2];
#    $irc->yield( privmsg => $nick => "Issuing $cmdline");
#    $irc->yield( privmsg => $channel => "Issuing $cmdline for $nick" );

    if ($disp eq "gridcount") {
        local $/ = ' ';
        my @cpresult = `vmcp --buffer=512k $cmdline`;

        foreach (@cpresult) { s/DSC\n//g; }
        foreach (@cpresult) { s/-L.{4}\n//g; }

        @cpresult = grep { $_ =~ /^GN2C/ } @cpresult;
        $gridpcnt = $gridcount;
        $gridcount = scalar @cpresult;
        scan_guest_status(@cpresult);
    } elsif ($disp eq "indicate") {
#        local $/ = ' ';
        my @cpresult = `vmcp $cmdline`;

        ($avgproc) = $cpresult[0] =~ /AVGPROC-0*(.+)%/;
        ($paging) = $cpresult[2] =~ /PAGING-(.+)\/SEC/;
        $maindelay = int(($avgproc/100)*3) + int($paging/1000)**2 + int($gridcount/500) + 2;

    } elsif ($disp eq "irc") {  
        my @cpresult = `vmcp $cmdline`;
        my $rc = $?;
        if ( $nick ne "" ) {
        	foreach (@cpresult) {
            	$irc->yield( privmsg => $nick => "$_" );
        	}
        	if ( $rc > 0 ) {
            	$irc->yield( ctcp => $nick => "ACTION saw exit status of $rc on that command" );
        	}
        }
    }
    return;
}

sub pop_smapi {
    my ($postback, $cmdline, $nick, $disp ) = @_;

    POE::Session->create (
      inline_states => {
        _start      => \&run_smapi,
#	cmd_clr     => \&cmd_clr,
      },
      args => [ "$cmdline", "$nick", "$disp" ],
    );
    return;
}

sub run_smapi {
    my ($cmdline, $nick, $disp) = @_[ARG0 .. ARG2];
    my $smapicmd = "";

# SMAPI commands here...  :)
# Rather than expecting full smcli command strings to come in via IRC,
# we'll code smarts here and parse 'sensible' SMAPI commands into
# smcli command strings.  Just like we do in the main command process loop.
# Not much to do really, because we'll handle only a few specific API calls.

    if ( my ($smapicommand) = $cmdline =~ /^iqd (.+)/ ) {
        $smapicmd = "smcli iqd -T $1 -H IUCV";
    } elsif ( ($smapicommand) = $cmdline =~ /^iacq (.+)/ ) {
        $smapicmd = "smcli iacq -T $1 -H IUCV";
    }

    $irc->yield( privmsg => $nick => "$smapicmd" );

    if ( $smapicmd ne "" ) {
        my @smapiresult = `$smapicmd`;
	@smapiresult = grep /\S/, @smapiresult;
        my $rc = $?;
        foreach (@smapiresult) {
            $irc->yield( privmsg => $nick => "$_" );
        }
        if ( $rc > 0 ) {
            $irc->yield( ctcp => $nick => "ACTION saw exit status of $rc on that command" );
        }
    }
    return;
}

sub update_stats {
    $poe_kernel->post('vmcp', 'enqueue', '', "Q N", "", "gridcount");
    $poe_kernel->post('vmcp', 'enqueue', '', "IND", "", "indicate");
    $poe_kernel->post('action', 'enqueue', '');

    $poe_kernel->delay(topic_stats => 5);

    return;
}

sub topic_stats {
    my $time = strftime "%a %e %H:%M" , localtime();
    if ($gridcount != $gridpcnt) {
        $irc->yield( topic => $channels[0] => "Status change: at $time, $gridcount guests active, avg CPU $avgproc%, Paging $paging/sec.");
	$topicint = 0;
    } elsif ($topicint == 60) {
        &compactmem();
        $irc->yield( topic => $channels[0] => "Grid status at $time: $gridcount guests active, avg CPU $avgproc%, Paging $paging/sec.");
        try { tweet("Grid status at $time: $gridcount guests active, avg CPU $avgproc%, Paging $paging/sec.",""); }
	catch { $irc->yield( ctcp => $channels[0] => "ACTION just tried to tweet and it failed." ); };
	$topicint = 0;
    }
    $topicint += 1;

    $poe_kernel->delay(_start => 55);

    return;
}

sub pop_dirmBot {
    my ($postback, $cmdline, $nick ) = @_;

    POE::Session->create (
      inline_states => {
        _start      => \&init_dirmBot,
	dirm_cmd    => \&dirm_cmd, 
      },
      args => [ "$cmdline", "$nick" ],
    );
    return;
}

sub init_dirmBot {
    my ($cmdline, $nick) = @_[ARG0 .. ARG1];
    if ($dirmBot eq "no") {
        $poe_kernel->post('vmcp', 'enqueue', '', "XAUTOLOG DIRMBOT", "$nick", "irc");
	$poe_kernel->delay(dirm_cmd => 5 => $cmdline, $nick);
    } else {
        $poe_kernel->delay(dirm_cmd => 1 => $cmdline, $nick);
    }
    return;
}

sub dirm_cmd {
    my ($cmdline, $nick) = @_[ARG0 .. ARG1];
#    my ($cmdline, $nick) = @_;
    $irc->yield( privmsg => 'dirmBot' => "$cmdline $nick");
    return;
}

sub pop_cattle {
    my ($postback, $nick) = @_;
    
    POE::Session->create (
    inline_states => {
        _start        => \&run_cattle,
        cattle_pause  => \&cattle_pause,
    },
    args => [ $nick ],
    );
    return;
}

sub run_cattle {
    my ($nick) = $_[ARG0];
    #    $irc->yield( privmsg => $nick => "Issuing $cmdline");
    #    $irc->yield( privmsg => $channel => "Issuing $cmdline for $nick" );

    my $digit1 = rand(2) + 1;
    my $digit2 = rand(4) + 1;
    my $digit3 = rand(2) + 1;
    my $digit4 = rand(10);
    my $tgtname = "gn2c$digit1$digit2$digit3$digit4";
    $irc->yield( privmsg => $nick => "running workload on $tgtname");
    system ( 'expect -c "spawn ssh -o \"PubkeyAuthentication no\" -o \"StrictHostKeyChecking no\" root@$tgtname dd if=/dev/urandom of=/dev/null bs=1024 count=25600" -f /root/ssh.expect &' );
    if ($cattledelay > 0) {
        $poe_kernel->delay(cattle_pause => $cattledelay => $nick);
    }
    return;
}

sub cattle_pause {
    my ($nick) = $_[ARG0];
    $poe_kernel->post('cattle', 'enqueue', '$nick');
    return;
}

sub compactmem {
    open PROCFILE, ">/proc/sys/vm/compact_memory" or die "can't open /proc/sys/vm/compact_memory: $!\n";
    print PROCFILE "1";
    close PROCFILE;
    return;
}

sub tweet {
    my ($text, $hashtag) = @_;

    die 'tweet requires text as an argument' unless $text;

    unless ($TWITTER_CONSUMER_KEY
         && $TWITTER_CONSUMER_SECRET
         && $TWITTER_ACCESS_TOKEN
         && $TWITTER_ACCESS_SECRET) {
        die 'Required Twitter Env vars are not all defined';
    }

    # build tweet, max 140 chars
    my $tweet;

    if (length("$text $hashtag") < 130) {
        $tweet = "$text $hashtag";
    } elsif (length($text) < 130) {
        $tweet = "$text";
    } else {
    # shorten text
        $tweet = substr($text, 0, 126) . "... ";
    }

    try {
        my $twitter = Net::Twitter::Lite::WithAPIv1_1->new(
                        access_token_secret => $TWITTER_ACCESS_SECRET,
                        consumer_secret     => $TWITTER_CONSUMER_SECRET,
                        access_token        => $TWITTER_ACCESS_TOKEN,
                        consumer_key        => $TWITTER_CONSUMER_KEY,
                        user_agent          => 'gridBot',
                        ssl => 1,
                      );
        $twitter->update($tweet);
    }
    catch {
        die join(' ', "Error tweeting $text $hashtag",
                      $_->code, $_->message, $_->error);
    };
    return;
}

sub scan_guest_status {
	my @guestlist = @_;
	
	foreach my $guest (@guestlist) {
		$guest =~ s/^\s+|\s+$//g;
		if (!defined $gueststatus->{"$guest"}) {
			$gueststatus->{"$guest"} = 'logged on';
			`ping -c1 $guest`;
			if ($? == 0 ) {
				$gueststatus->{"$guest"} = 'active';
			}
		}
	}
	return;
}

sub pop_action {
    my ($postback) = @_;

    POE::Session->create (
      inline_states => {
        _start      => \&action_guest_status,
#	cmd_clr     => \&cmd_clr,
      },
      args => [ ],
    );
    return;
}

sub action_guest_status {
	for my $guest ( keys %$gueststatus ) {
		my $status = $gueststatus->{ $guest };
		switch ($status) {
			case "active" {
				`ping -c1 $guest`;
				if ($? != 0) {
					$gueststatus->{ $guest }='recycling';
					$poe_kernel->post('command', 'enqueue', '', "SIGNAL SHUTDOWN $guest WITHIN 30", "");
					print "$guest problem ping, set to recycle.\n";
				}
			}
			case "activating" {
				print "$guest is $status: ";
				`ping -c1 $guest`;
				if ($? == 0) {
					$gueststatus->{ $guest }='active';
					print "marking active\n";
				} else { print "\n"; }
			}
			case "deactivating" {
				print "$guest is $status: ";
				my $cmdout = `smcli isq -T $guest -H IUCV`;
				$cmdout =~ s/^\s+|\s+$//g;
				if ("$cmdout" ne "$guest") {
					$gueststatus->{ $guest }='down';
					print "marking as down.\n";
				} else { print "\n"; }
			}
			case "activate" {
				print "$guest is $status: ";
				$poe_kernel->post('command', 'enqueue', '', "XAUTOLOG $guest", "");
				$gueststatus->{$guest}='activating';
				print "issued command, marking as activating.\n";
			}	 
			case "deactivate" {
				print "$guest is $status: ";
				$poe_kernel->post('command', 'enqueue', '', "SIGNAL SHUTDOWN $guest WITHIN 30", "");
				$gueststatus->{$guest}='deactivating';
				print "issued command, marking as deactivating.\n";
			}
			case "recycling" {
				print "$guest is $status: ";
				# is it down yet?
				my $cmdout = `smcli isq -T $guest -H IUCV`;
				$cmdout =~ s/^\s+|\s+$//g;
				if ("$cmdout" ne "$guest") {
					$gueststatus->{ $guest }='activating';
					$poe_kernel->post('command', 'enqueue', '', "XAUTOLOG $guest", "");
					print "came down, restarted, marked as activating.\n"
				} else { print "still waiting to come down.\n"};
			}
			else {
				print "$guest: unknown status $status.\n";
			}
		}
	}
	return;
}

#### #!/usr/bin/perl

#use strict;
#use warnings;
#
#sub count_grid {
#    local $/ = ' ';
#    my @stuff = `vmcp q n`;
#
#    foreach (@stuff) { s/DSC\n//g; }
#    foreach (@stuff) { s/-L.{4}\n//g; }
#
#    @stuff = grep { $_ =~ /^GN2C/ } @stuff;
#
#    foreach my $name (@stuff) {
#      print "$name\n"
#    }
#
#    return scalar @stuff;
#}

