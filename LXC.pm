package LXC;

use warnings;

$host     = "localhost";
$port     = 34838;

$version  = "1.4.2";
$prefx    = "LXC";
$system   = "$^O";
$traceid  = ">>> $prefx >>>";
$rlprompt = "LXC>";
$dest     = "";
$userid   = "";
$passwd   = "";
$keyword  = "";
$command  = "";
$nodeid   = "        ";
$maxfrag  = 2097120;
$seqno    = 0;
$timeout  = 0;
$trace    = 0;
$help     = 0;
$batch    = 0;
$quiet    = 0;
$cmdpref  = 0;
$cmmds    = 0;
$readline = 0;

warn ("System identified as $system.");
if ($system eq "darwin") {$homedir = "$ENV{HOME}"} 
elsif ($system eq "linux") {$homedir = "$ENV{HOME}"}
else                    {$homedir = "$ENV{USERPROFILE}"}

($seconds, $minutes, $hour, $day, $month, $year) = localtime();

$strtdate = sprintf("%4d-%02d-%02d", $year + 1900, $month + 1, $day);
$strttime = sprintf("%02d:%02d:%02d", $hour, $minutes, $seconds);

$workdir  = "$homedir";
$keyfile  = "$homedir/.keyword.lxc";
$histfile = "$homedir/.history.lxc";
$histsize = 256;


if ($ENV{LXCHOST}) {$host   = $ENV{LXCHOST}};
if ($ENV{LXCPORT}) {$port   = $ENV{LXCPORT}};
if ($ENV{LXCUSER}) {$userid = $ENV{LXCUSER}};
if ($ENV{LXCPASS}) {$passwd = $ENV{LXCPASS}};


use Getopt::Long;

Getopt::Long::Configure(gnu_getopt, require_order);

GetOptions( "c|command=s"   =>\$command,
	    "d|directory=s" =>\$workdir,
	    "h|host=s"      =>\$host,
	    "p|port=i"      =>\$port,
	    "u|userid=s"    =>\$userid,
	    "P|password=s"  =>\$passwd,
	    "T|timeout=i"   =>\$timeout,
	    "t|trace"       =>\$trace,
	    "help|?"        =>\$help
	  ) or exit 4;

unless ($timeout >= 0 && $timeout <= 60) {
   die "Invalid TIMEOUT value. Must be between 0 and 60\n";
}

unless (-d $workdir) {
   die "Working directory $workdir does not exist\n";
}


use Term::ReadLine;

$history  = new Term::ReadLine "LXC history";
%features = %{$history->Features};
$history -> ornaments(0);

if ($features{stiflehistory}) {$history->stifle_history($histsize)}
if ($features{readHistory} && $features{writeHistory}) {
   $readline = 1;
   if (-f $histfile) {$history->ReadHistory($histfile) or
      warn "Error opening history file. $!\n     ";
   }
} elsif ($system eq "linux") {warn "History file not supported by ", $history->ReadLine, "\n"}


if ($trace) {
   print "$traceid      LXC server is $host, port is $port\n";
   print "$traceid Sys  $system\n";
   print "$traceid Host $host\n";
   print "$traceid Port $port\n";
   print "$traceid User $userid\n";
   print "$traceid Pswd $passwd\n";
   print "$traceid Time $timeout\n";
   print "$traceid Help $help\n";
   print "$traceid Wdir $workdir\n";
   print "$traceid Cmnd $command\n";
   print "$traceid Parm @ARGV\n";
}
 
if (defined $ARGV[0]) {
   if ($command) {$command .= "\#@ARGV"}
   else {$command = "@ARGV"}
}

if ($command ne "") {$batch = 1};

if ($help) {
   print "Usage: lxc [OPTIONS] [command]\n";
   print "       Run LXC commands\n";
   print "   -t, --trace      Set trace option. Default is OFF\n";
   print "   -T, --timeout    Timeout value in seconds. Must be between 0 and 60\n";
   print "   -d, --directory  Work directory for file transfers. Default is home directory\n";
   print "   -h, --host       Server host address. Default is local host\n";
   print "   -p, --port       Server port. Default is 34838\n";
   print "   -u, --userid     UserID\n";
   print "   -P, --password   User's password\n";
   print "   -c, --command    Command to run. Default is none. Interactive use\n";
   exit;
}


use Socket;

if ($system eq "linux") {$recv_flags = Socket::MSG_WAITALL}
else                    {$recv_flags = 0}

$iaddr = inet_aton($host) or die "Host not found or invalid: $host.\n     ";
$paddr = sockaddr_in($port, $iaddr);
$proto = getprotobyname('tcp');

socket(SOCKID, PF_INET, SOCK_STREAM, $proto) or die "Error in Socket function socket. $!\n     ";

if($timeout) {
   $timeo = pack("LL", $timeout, 0);
   if(!setsockopt(SOCKID, SOL_SOCKET, SO_SNDTIMEO, $timeo)) {
      $timeout = pack("QQ", $timeout, 0);
      setsockopt(SOCKID, SOL_SOCKET, SO_SNDTIMEO, $timeout) or warn
		"Error setting Socket timeout. $!\n";
   }
}

connect(SOCKID, $paddr) or die "Error in Socket function connect. $!\n     ";

if ($command eq "") {
   print "$prefx $nodeid Ready;\n";
   while ($command ne "QUIT") {
      $command = $history->readline($rlprompt);

      if (substr($command, 0, 1) eq "`") {
	 $command = substr($command, 1);
	 system("$command");
	 print "$prefx $nodeid Ready;\n";
	 next;
      }
      check();
      if ($command eq "\0") {next}
      if ($command =~ /^\s*\(/) {put("$command")}
      else {put("$dest $command")}
      receive();
      process();
   }
} else {
   if ($command =~ /^\s*(\(.*?\))/) {$dest = $1}
   login();
   $quiet = 1;
   put("$dest LOGIN $userid $passwd $keyword");
   receive();
   process();
   $quiet = 0;
   $cmmds = 0;
   @command = split("#", $command);
   while (@command != 0) {
      $command = shift(@command);
      if ($command =~ /^\s*\(/) {put("$command")}
      else {put("$dest $command")}
      receive();
      process();
   }
}

$lxc_rc = $hdr_rc;

put("QUIT");
receive();

close (SOCKID);

if ($readline) {
   $history->WriteHistory($histfile) or warn "Error writing history file. $!\n     ";
}

exit $lxc_rc;



sub abbrev {
   ($key, $abb, $min) = @_;
   (uc($key) =~ /^\U$abb/) and (length($abb) >= $min);
}


sub geti {
   $prompt = "@_";
   print "$prompt";

   eval("use Term::ReadKey");

   unless ($@) {
      eval("ReadMode 'noecho'");
      chomp($result = <STDIN>);
      eval("ReadMode 'restore'");
   } else {
      system('stty','-echo');
      chomp($result = <STDIN>);
      system('stty','echo');
   }
   return $result;
}


sub login {
   @date = localtime();
   $date = sprintf("%4d-%02d-%02d", $date[5] + 1900, $date[4] + 1, $date[3]);

   $recuser = "";

   if ($userid ne "" && $passwd ne "") {return}

   if (-f $keyfile) {
      if (open(KEYFILE, "<$keyfile")) {
	 $record = <KEYFILE>;
	 ($recdate, $recuser, $keyword) = split(" ", $record);
	 if ($date ne $recdate) {$keyword = ""}
	 if ($userid eq "") {$userid = $recuser}
	 close(KEYFILE);
      }
   }

   if ($keyword eq "" || $userid ne $recuser) {
      if ($userid eq "") {
	 if ($system eq "linux") {
	    $userid = `whoami`;
	    chomp($userid);
	 } else {$userid = "$ENV{USERNAME}"}
	 print "Enter userid \[$userid\]\n";
	 $newid = <STDIN>;
	 chomp($newid);
	 if ($newid ne "") {$userid = $newid}
      }
      $passwd = geti("Enter password for $userid\n");
      if (open(KEYFILE, ">$keyfile")) {
	 $keyword = substr(int(rand(99999999999)) . int(rand(99999999999)), 1, 16);
	 print KEYFILE "$date $userid $keyword\n";
	 chmod(0600, $keyfile);
	 close(KEYFILE);
     }
   }
}


sub put {
   $block = "@_";
   $seqno++;
   $cmmds++;
   send(SOCKID, " $prefx $seqno $block", 0) or die "Error in Socket function send. $!\n     ";
   if ($trace) {print "$traceid Send $prefx $seqno $block\n"}
}


sub receive {
   defined(recv(SOCKID, $header, 48, $recv_flags)) or die
	  "Error in Socket function recv. $!\n     ";

   ($hdr_key, $hdr_rc, $hdr_bytes, $hdr_lines, $hdr_sysid, $hdr_task, $hdr_sskey, $hdr_tskey,
	      $hdr_flag, $hdr_cmd) = unpack("A3 A5 A8 A8 a8 A8 A A A A", $header);

   if ($header ne "") {
       $nodeid = $hdr_sysid;
      if ($hdr_bytes > 0) {
	 defined(recv(SOCKID, $block, $hdr_bytes, $recv_flags)) or die
		"Error in Socket function recv. $!\n     ";
      } else {$block = ""}

      if ($trace) {
	 print "$traceid Recv $header\n";
	 if (length($block) > 0) {print "$traceid Recv ", substr($block, 0, 47), "\n"};
      }
   }
}


sub reply {
   ($code, $key, $sskey, $tskey, $block) = @_;

   if ($code < 0) {
      $code = "-" . substr("0000" . substr($code, 2), -4);
   } else {$code = substr("0000$code", -5)}

   if ($hdr_flag < 2) {$segment = 0}

   my $bytes = substr("       " . length($block), -8);
   my $lines = substr("       " . ($segment = $segment + 1), -8);
   my $sysid = substr("$hdr_sysid      ", 0, 8);
   my $task  = substr("       $hdr_task", -8);

   $header = pack("a3 a5 a8 a8 a8 a8 a a a a a4", $key, $code, $bytes, $lines,
	     $sysid, $task, $sskey, $tskey, $hdr_flag, $hdr_cmd, "    ");

   send(SOCKID, "$header$block", 0) or die "Error in Socket function send. $!\n     ";

   if ($trace) {
      print "$traceid Send $header\n";
      if (length($block) > 0) {print "$traceid Send ", substr($block, 0, 47), "\n"}
   }
}


sub process {
   use File::Spec;

   $bytes = 0;
   $lines = 0;

   while ($cmmds > 0) {
      unless ($hdr_flag =~ /[01234]/) {
	 print "unsupported header flag: $hdr_sskey-$hdr_tskey-$hdr_flag\n";
	 exit 8;
      }

      if ($hdr_key eq "LXC") {
	 if ($cmdpref) {
	    $block = "$prefx $nodeid $block";
	    $block =~ s/\n/\n$prefx $nodeid /g;
	    $nodeid = "        ";
	 }
	 $bytes = $bytes + $hdr_bytes;
	 $lines = $lines + $hdr_lines;
	 if ($hdr_lines > 0 && ! $quiet) {print "$block\n"}
	 $cmmds--;
	 if ($cmmds == 0) {
	    if (! $batch) {
	       print "$prefx $nodeid Ready; rc($hdr_rc) bytes($bytes) lines($lines)\n"
	    }
	    $cmdpref = 0;
	    return;
	 }
      } elsif ($hdr_key eq "LXD") {
	 $bytes = $bytes + $hdr_bytes;
	 $lines = $lines + $hdr_lines;
	 if ($cmdpref) {
	    $block = "$prefx $nodeid $block";
	    $block =~ s/\n/\n$prefx $nodeid /g;
	    $nodeid = "        ";
	 }
	 print "$block\n";
	 if ($hdr_tskey eq "N") {
	 } elsif ($hdr_tskey eq "P") {
	    $resp = <STDIN>;
	    chomp($resp);
	    reply(0, "$hdr_key", "?", "P", "$resp");
	 } elsif ($hdr_tskey eq "I") {
	    $resp = geti("");
	    reply(0, "$hdr_key", "?", "I", "$resp")
	 } else {
	      print "Unsuported header subkey: $hdr_key-$hdr_tskey\n";
	      exit 8;
	 }
      } elsif ($hdr_key eq "LXR") {
	 if ($hdr_sskey eq "K") {
	    ($file_name, $file_type) = split(" ", $block);
	    $fileid = File::Spec->catfile($workdir, "$file_name.$file_type");
	    if (-f $fileid) {
	       $file_header = header("$fileid");
	       reply(0, $hdr_key, $hdr_sskey, $hdr_tskey, $file_header);
	    } else {reply(28, $hdr_key, $hdr_sskey, $hdr_tskey, "")}
	 } elsif ($hdr_sskey eq "C" || $hdr_sskey eq "I") {
	    ($file_name, $file_type) = split(" ", $block);
	    $fileid = File::Spec->catfile($workdir, "$file_name.$file_type");
	    if (-f $fileid) {
	       if ($hdr_flag eq 0) {
		  $file_header = header("$fileid");
		  if ($file_size > $maxfrag && $hdr_sskey eq "I") {
		     $file_left = $file_size;
		     $hdr_flag = 1;
		  }
	       } elsif ($file_left > $maxfrag) {
		  $hdr_flag = 2;
	       } else {$hdr_flag = 3}
	       $file_block = block("$fileid");
	       reply(0, $hdr_key, $hdr_sskey, $hdr_tskey, "$file_header$file_block");
	       if ($hdr_flag != 0) {
		  $file_left = $file_left - $maxfrag;
	       }
	    } else {reply(28, $hdr_key, $hdr_sskey, $hdr_tskey, "")}
	 } else {
	    print "Unsupported header subkey: $hdr_key-$hdr_sskey\n";
	    exit 8;
	 }
      } elsif ($hdr_key eq "LXS") {
	 if ($hdr_tskey eq "A") {
	    $file_header = substr($block, 0, 79);
	    $file_block = substr($block, 80);
	    @file_header = split(" ", $file_header);
	    ($file_name, $file_type, $file_date, $file_time) = @file_header[0, 1, 7, 8];
	    $fileid = File::Spec->catfile($workdir, "$file_name.$file_type");
	    if (open(LXSFILE, ">>$fileid")) {
	       if ($hdr_sskey eq "I") {
		  binmode LXSFILE;
		  print LXSFILE $file_block;
	       } else {print LXSFILE "\n$file_block"}
	       close(LXSFILE);
	    } else {
      	       print "Error creating $fileid. $!\n";
	       reply(32, $hdr_key, $hdr_sskey, $hdr_tskey, "");
	    }


	    reply(0, $hdr_key, $hdr_sskey, $hdr_tskey, "");
	 } elsif ($hdr_tskey eq "B") {

	    $file_header = substr($block, 0, 79);
	    $file_block = substr($block, 80);
	    @file_header = split(" ", $file_header);
	    ($file_name, $file_type, $file_date, $file_time) = @file_header[0, 1, 7, 8];
	    $fileid = File::Spec->catfile($workdir, "$file_name.$file_type");
	    open(LXSFILE, "| less -r");
	    print LXSFILE $file_block;
	    close(LXSFILE);
	    reply(0, $hdr_key, $hdr_sskey, $hdr_tskey, "");
	 } elsif ($hdr_tskey eq "C") {
	    $bytes = $bytes + $hdr_bytes;
	    $lines = $lines + $hdr_lines;

	    if ($cmdpref) {
	       $block = "$prefx $nodeid $block";
	       $block =~ s/\n/\n$prefx $nodeid /g;
	       $nodeid = "        ";
	    }

	    print "$block\n";
	    reply(0, $hdr_key, $hdr_sskey, $hdr_tskey, "");
	 } elsif ($hdr_tskey eq "P") {
	    print "CMS packed files not supported\n";
	    reply(32, $hdr_key, $hdr_sskey, $hdr_tskey, "");
	 } elsif ($hdr_tskey eq "R") {
	    $file_header = substr($block, 0, 79);
	    $file_block = substr($block, 80);
	    @file_header = split(" ", $file_header);
	    ($file_name, $file_type, $file_date, $file_time) = @file_header[0, 1, 7, 8];
	    $fileid = File::Spec->catfile($workdir, "$file_name.$file_type");

	    if ($hdr_flag =~ /[01]/) {
	       if (open(LXSFILE, ">$fileid")) {
		  chmod(0600, $fileid);
		  if ($hdr_sskey eq "I") {binmode LXSFILE}
		  print LXSFILE $file_block;
		  if ($hdr_flag =~ /[03]/) {
		     close(LXSFILE);
		     if (length($file_date) == 10 && length($file_time) == 8) {
			$stamp = substr($file_date, 0, 4);
			$stamp .= substr($file_date, 5, 2);
			$stamp .= substr($file_date, 8, 2);
			$stamp .= substr($file_time, 0, 2);
			$stamp .= substr($file_time, 3, 2) . ".";
			$stamp .= substr($file_time, 6, 2);
			if ($system eq "linux") {system("touch -t $stamp $fileid")}
		     }
		  }
	          reply(0, $hdr_key, $hdr_sskey, $hdr_tskey, "");
	       } else {
      	          print "Error creating $fileid. $!\n";
	          reply(32, $hdr_key, $hdr_sskey, $hdr_tskey, "");
	       }
	    }
	 } else {
	    print "Unsuported header subkey: $hdr_key-$hdr_tskey\n";
	    exit 8;
	 }
      } elsif ($hdr_key eq "LXM") {
	 $cmmds = $cmmds + $hdr_rc - 1;
	 $cmdpref = 1;
      } else {
	 print "unsupported header key: $hdr_key\n";
	 exit 8;
      }
      receive();
      if ($header eq "") {last}
   }
}


sub header {
   $id = "@_";

   ($seconds, $minutes, $hour, $day, $month, $year) = localtime();

   $file_date = sprintf("%4d-%02d-%02d", $year + 1900, $month + 1, $day);
   $file_time = sprintf("%02d:%02d:%02d", $hour, $minutes, $seconds);
   $file_size = (stat($id))[7];

   $fn = substr("$file_name       ", 0, 8);
   $ft = substr("$file_type       ", 0, 8);
   $fs = substr("         $file_size", -10);

   $file_header = "$fn $ft A1 V          1 $fs          1 $file_date $file_time     ";
   return $file_header;
}


sub block {
   $id = "@_";
   if ($hdr_flag == 0 || $hdr_flag == 1) {
      open(BLKFILE, "<$id") or return "";
      if ($hdr_sskey eq "I") {binmode BLKFILE}
   }
   if ($hdr_flag == 0) {$fileread = $file_size} else {$fileread = $maxfrag}
   read(BLKFILE, $file_block, $fileread);
   if ($hdr_flag == 0 || $hdr_flag == 3) {close(BLKFILE)}
   return $file_block;
}

sub check {
   if ($command eq "") {return}
   @words = split(" ", $command);
   $cmd = $words[0];
   if ($cmd =~ /\W/) {return}
   shift(@words);

   if (abbrev("Quit", $cmd, 1) ||
       abbrev("Exit", $cmd, 3) ||
       abbrev("End",  $cmd, 3) ||
       abbrev("Bye",  $cmd, 3)) {
      if ($#words < 0) {$command = "QUIT"}
   } elsif (abbrev("LOGin", $cmd, 3)) {
      ($dst, $usr) = @words[0, 1];
      if (defined($dst) && $dst ne "") {$dest = "( $dst )"}
      if (defined($usr) && $usr ne "") {$userid = "$usr"}
      login();
      $command = "LOGIN $userid $passwd $keyword";
      $passwd = "";
   } elsif (abbrev("WDirectory", $cmd, 2)) {
      $command = "\0";
      $nodeid  = "        ";
      $tempdir = "@words";
      if ($tempdir eq "") {
	 print "Current working directory is $workdir\n";
      } elsif (-d $tempdir) {
      $workdir = $tempdir;
      print "Working directory updated\n";
      } else {print "Working directory not updated. $tempdir does not exist\n"}
      print "$prefx $nodeid Ready; rc(00000) bytes(0) lines(0)\n"
   } elsif (abbrev("TArget", $cmd, 2)) {
      $command = "\0";
      $nodeid = "        ";
      $dst = "@words";
      if ($dst eq "") {$dest = "";
      } else          {$dest = "( $dst )"}
      print "$prefx $nodeid Ready; rc(00000) bytes(0) lines(0)\n";
   } elsif (abbrev("TRace", $cmd, 2)) {
      $command = "\0";
      $nodeid = "        ";
      $trace = ($trace == 0);
      if ($trace) {print "Trace is now ON\n"
      } else           {print "Trace is now OFF\n"}
      print "$prefx $nodeid Ready; rc(00000) bytes(0) lines(0)\n";
   } elsif (abbrev("Version", $cmd, 1)) 	{
      print "LXC Perl client version $version. Started on $strtdate at $strttime\n";
   }
}
1;
