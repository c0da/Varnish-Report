#!/usr/bin/perl
#
# varnishreport.pl
#
# Analyzes the contents of a log generated by varnishncsa and build statistics usage of cache
#
# http://github.com/djinns/Varnish-Report
#
# Copyright (C) 2011 djinns@chninkel.net
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

#------------------------------------------------
# LIBS
use warnings;
use strict;
use Getopt::Long;
use DateTime;
use Text::ASCIITable;
use ProgressBar::Stack;
use URI;

#------------------------------------------------
# PARAMS

# META
my $version="0.2.5";

# Options
my ($o_help,$o_fullstats,$o_progress,$o_fulluri)=0;
my ($i,$t,$o_logfile);
my $o_top=10;
my $csv; my $o_csv="none";

# Timestamp date
my ($timestamp_start,$timestamp_stop,$totalrequest,$totalbytes,$duration)=0;
my %mon2num = qw(jan 1 feb 2 mar 3 apr 4 may 5 jun 6 jul 7 aug 8 sep 9 oct 10 nov 11 dec 12);

# Clients
my (%h_client,%h_client_bytes,%h_client_hit,%h_client_miss)=();

# Cache status
my (%h_status,%h_status_bytes)=();
my ($hit,$hit_bytes,$miss,$miss_bytes)=0;

# HTTP Method
my (%h_method,%h_method_bytes,%h_method_hit,%h_method_miss)=();
my ($method,$vhost,$uri,$proto);

# MIME
my (%h_mime,%h_mime_bytes,%h_mime_hit,%h_mime_miss)=();

# HTTP CODE
my (%h_httpcode,%h_httpcode_bytes,%h_httpcode_hit,%h_httpcode_miss,%h_httpcode_404,%h_httpcode_404_bytes,%h_httpcode_500,%h_httpcode_500_bytes)=();

# URI
my (%h_uri,%h_uri_bytes,%h_uri_cbytes,%h_uri_hit,%h_uri_miss,%h_vhost,%h_vhost_bytes,%h_vhost_miss,%h_vhost_hit)=();

# Parent
my (%h_parent,%h_parent_bytes)=();

#------------------------------------------------
# Functions

#----------------
# check_options
#
# Check options from the command line
#
sub check_options {
	Getopt::Long::Configure ("bundling");
	GetOptions(
		'l:s'	=> \$o_logfile,		'logfile:s'		=> \$o_logfile,
		't:s'	=> \$o_top,			'top:s'			=> \$o_top,
		'f'		=> \$o_fullstats,	'fullstats'		=> \$o_fullstats,
		'p'		=> \$o_progress,	'progressbar'	=> \$o_progress,
		'u'		=> \$o_fulluri,		'fulluri'		=> \$o_fulluri,
		'c:s'	=> \$o_csv,			'csv:s'			=> \$o_csv,
		'h'		=> \$o_help,		'help'			=> \$o_help
	);

    if (!defined($o_logfile)||($o_help)) {
		usage();
		exit;
	}

	if($o_csv !~ "none") {
		open($csv,'>',$o_csv) or die "ERROR: can't open csv file ($!)\n\n";
	}
}

#----------------
# usage()
#
# Show usage of the script
#
sub usage {
	print <<"EOT";
Usage of $0

Required parameters:
	-l,--logfile /path/to/access/log\t: path to the log file
	
Optional parameters:
	-f,--fullstats\t: print extra statitics. Default none
	-t,--top\t: number of lines for of extra statitics. Default 10
	-u,--fulluri\t: use full uri (URI+query string) in the full statistics mode. Default none
	-p,--progress\t: print progress bar. Default none

	-c,--csv /path/to/file.csv\t: save to csv file

	-h,--help\t: print this menu

	Report bugs or ask for new options: https://github.com/DjinnS/Varnish-Report

EOT
}

#----------------
# parsing()
#
# Parsing access log file and build hashes tables for statistics
#
sub parsing {
	my ($varnish,$client,$date,$status,$size,$request,$referer,$uagent,$mime);
	
	# real date
	my ($year,$month,$day,$hour,$min,$sec);

	open(my $fd,"<",$o_logfile) or die "Can't accesslog file: $!";

	# get size for progress bar
	my $filesize = -s $o_logfile;

	# progressbar
	if($o_progress) { init_progress; }

	my $bytesread=0;
	my $totalread=0;

	while (<$fd>) {

		$bytesread += (length($_));
		$totalread = sprintf("%.2f",($bytesread*100)/$filesize);

		($varnish,$client,$date,$status,$size,$request,$referer,$uagent,$mime) = /(\[.*-.*\])\s(\d+\.\d+\.\d+\.\d+)\s(\[.*\])\s(.*)\s(.*)\s(\".*\")\s(\".*\")\s(.*)\s\((.*)\)/; 

		# fix for size=0
		if($size =~ /-/) { $size=0; }

		# make real date
		$_ = $date;

		($day,$month,$year,$hour,$min,$sec) = /\[(.*)\/(.*)\/(.*):(.*):(.*):(.*)\s.*\]/;

		$date = DateTime->new(
			year	=> $year,
			month	=> $mon2num{lc substr($month,0,3)},
			day		=> $day,
			hour	=> $hour,
			minute	=> $min,
			second	=> $sec
		);

		# if the regexp match
		if($client) {
			$totalrequest += 1;
			$totalbytes += $size;

			# Date and timestamp
			$timestamp_stop=$date->epoch();
			$timestamp_start = ($timestamp_start==0) ? $date->epoch() : $timestamp_start;

			# HTTP Method / vhost / URI / proto
			$request =~ tr/"//d;
			$_ = $request;
			($method,$uri,$proto) = /(.*)\s(http.*)\s(.*)/;

			$uri = URI->new($uri);

			$h_method{$method} 			= ($h_method{$method})			? $h_method{$method}+1 : 1;
			$h_method_bytes{$method}	= ($h_method_bytes{$method})	? $h_method_bytes{$method}+$size : $size;

			# URI & Vhost
			$h_vhost{$uri->host} 		= ($h_vhost{$uri->host}) 		? $h_vhost{$uri->host}+1 : 1;
			$h_vhost_bytes{$uri->host}	= ($h_vhost_bytes{$uri->host})	? $h_vhost_bytes{$uri->host}+$size : $size;

			if($o_fullstats) {
				if($o_fulluri) {
					$h_uri{$uri->path_query}		= ($h_uri{$uri->path_query})		? $h_uri{$uri->path_query}+1 : 1;
					$h_uri_bytes{$uri->path_query}	= ($h_uri_bytes{$uri->path_query})	? $h_uri_bytes{$uri->path_query}+$size : $size;
				} else {
					$h_uri{$uri->path}			= ($h_uri{$uri->path})			? $h_uri{$uri->path}+1 : 1;
					$h_uri_bytes{$uri->path}	= ($h_uri_bytes{$uri->path})	? $h_uri_bytes{$uri->path}+$size : $size;
				}
			}

			# bytes by mime type
			if($o_fulluri) {
				$h_uri_cbytes{$uri->path_query} = ($h_uri_cbytes{$uri->path_query}) ? $h_uri_cbytes{$uri->path_query} : $size;
			} else {
				$h_uri_cbytes{$uri->path} = ($h_uri_cbytes{$uri->path}) ? $h_uri_cbytes{$uri->path} : $size;
			}

			# HTTP CODE
			$h_httpcode{$status}		= ($h_httpcode{$status})		? $h_httpcode{$status}+1 : 1;
			$h_httpcode_bytes{$status}	= ($h_httpcode_bytes{$status})	? $h_httpcode_bytes{$status}+$size : $size;

			if($status =~ /404/ && $o_fullstats) {
				if($o_fulluri) {
					$h_httpcode_404{$uri->path_query}		= ($h_httpcode_404{$uri->path_query})		? $h_httpcode_404{$uri->path_query}+1 : 1;
					$h_httpcode_404_bytes{$uri->path_query}	= ($h_httpcode_404_bytes{$uri->path_query})	? $h_httpcode_404_bytes{$uri->path_query}+$size : $size;
				} else {
					$h_httpcode_404{$uri->path}			= ($h_httpcode_404{$uri->path})			? $h_httpcode_404{$uri->path}+1 : 1;
					$h_httpcode_404_bytes{$uri->path}	= ($h_httpcode_404_bytes{$uri->path})	? $h_httpcode_404_bytes{$uri->path}+$size : $size;
				}
			}
			if($status =~ /500/ && $o_fullstats) {
				if($o_fulluri) {
					$h_httpcode_500{$uri->path_query}		= ($h_httpcode_500{$uri->path_query})		? $h_httpcode_500{$uri->path_query}+1 : 1;
					$h_httpcode_500_bytes{$uri->path_query}	= ($h_httpcode_500_bytes{$uri->path_query})	? $h_httpcode_500_bytes{$uri->path_query}+$size : $size;
				} else {
					$h_httpcode_500{$uri->path}			= ($h_httpcode_500{$uri->path})			? $h_httpcode_500{$uri->path}+1 : 1;
					$h_httpcode_500_bytes{$uri->path}	= ($h_httpcode_500_bytes{$uri->path})	? $h_httpcode_500_bytes{$uri->path}+$size : $size;
				}
			}

			# Mime stats
			$h_mime{$mime}			= ($h_mime{$mime})			? $h_mime{$mime}+1 : 1;
			$h_mime_bytes{$mime}	= ($h_mime_bytes{$mime})	? $h_mime_bytes{$mime}+$size : $size;

			# Client
			if($o_fullstats) {
				$h_client{$client}			= ($h_client{$client})			? $h_client{$client}+1 : 1;
				$h_client_bytes{$client}	= ($h_client_bytes{$client})	? $h_client_bytes{$client}+$size : $size;
			}

			# HIT & MISS
			if($varnish =~ /hit/) {
				$hit++; 
				$hit_bytes += $size;

				$h_vhost_hit{$uri->host}     = ($h_vhost_hit{$uri->host})     ? $h_vhost_hit{$uri->host}+1     : 1;
				$h_method_hit{$method}       = ($h_method_hit{$method})       ? $h_method_hit{$method}+1       : 1;
				$h_httpcode_hit{$status}     = ($h_httpcode_hit{$status})     ? $h_httpcode_hit{$status}+1     : 1;
				$h_mime_hit{$mime}           = ($h_mime_hit{$mime})           ? $h_mime_hit{$mime}+1           : 1;
				if($o_fullstats) {
					if($o_fulluri) {
						$h_uri_hit{$uri->path_query} = ($h_uri_hit{$uri->path_query}) ? $h_uri_hit{$uri->path_query}+1 : 1;
					} else {
						$h_uri_hit{$uri->path} = ($h_uri_hit{$uri->path}) ? $h_uri_hit{$uri->path}+1 : 1;
					}
					$h_client_hit{$client}       = ($h_client_hit{$client})       ? $h_client_hit{$client}+1       : 1;
				}
			} else {
				$miss += 1;
				$miss_bytes += $size;

				$h_vhost_miss{$uri->host}     = ($h_vhost_miss{$uri->host})     ? $h_vhost_miss{$uri->host}+1     : 1;
				$h_method_miss{$method}       = ($h_method_miss{$method})       ? $h_method_miss{$method}+1       : 1;
				$h_httpcode_miss{$status}     = ($h_httpcode_miss{$status})     ? $h_httpcode_miss{$status}+1     : 1;
				$h_mime_miss{$mime}           = ($h_mime_miss{$mime})           ? $h_mime_miss{$mime}+1           : 1;
				if($o_fullstats) {
					if($o_fulluri) {
						$h_uri_miss{$uri->path_query} = ($h_uri_miss{$uri->path_query}) ? $h_uri_miss{$uri->path_query}+1 : 1;
					} else {
						$h_uri_miss{$uri->path} = ($h_uri_miss{$uri->path}) ? $h_uri_miss{$uri->path}+1 : 1;
					}
					$h_client_miss{$client}       = ($h_client_miss{$client})       ? $h_client_miss{$client}+1       : 1;
				}
			}
		}

		if($o_progress) { update_progress($totalread, "Processing file ".$o_logfile." ..."); }
	}

	close($fd);

	return ($timestamp_stop-$timestamp_start);
}


#------------------------------------------------
# MAIN

print "\nVarnish Report - $version\n\n";

check_options();

$duration=parsing();

printf "\n\nLog start: %20s\nLog end  : %20s\n\n",scalar(localtime($timestamp_start)),scalar(localtime($timestamp_stop));

if(defined($csv)) {
	print $csv "Varnish Report - $version;\n";
	print $csv ";\n";
	print $csv "Log start;%20s;Log end;%20s;\n",scalar(localtime($timestamp_start)),scalar(localtime($timestamp_stop));
	print $csv ";\n";
}

# Summary stats
$t = Text::ASCIITable->new({ headingText => 'Summary'},'outputWidth',80);
$t->setCols(' Data',' Value','Rate ');
$t->addRow("Request",$totalrequest,sprintf("%10.2f",$totalrequest/$duration)." req/s");
$t->addRow("Bytes",$totalbytes,sprintf("%10.2f",$totalbytes/$duration/1024/1024)." MB/s");
$t->addRow("Hit",$hit,sprintf("%10.2f",$hit/$duration)." hit/s");
$t->addRow("Miss",$miss,sprintf("%10.2f",$miss/$duration)." hit/s");
print "$t\n";

if(defined($csv)) {
	print $csv "Summary;\n";
	print $csv "Date;Value;Rate;\n";
	print $csv "Request;$totalrequest;".sprintf("%.2f",$totalrequest/$duration)." req/s;\n";
	print $csv "Bytes;$totalbytes;".sprintf("%.2f",$totalbytes/$duration/1024/1024)." MB/s;\n";
	print $csv "Hit;$hit;".sprintf("%.2f",$hit/$duration)." hit/s;\n";
	print $csv "Miss;$miss;".sprintf("%.2f",$miss/$duration)." hit/s;\n";
	print $csv ";\n";
}

# Cache stats
$t = Text::ASCIITable->new({ headingText => 'Varnish cache stats' },'outputWidth',80);
$t->setCols('Status','Hit','Size (Mb)','req/s','Rate (%)');
$t->addRow("HIT",$hit,sprintf("%.2f",$hit_bytes/1024/1024),sprintf("%.2f",$hit/$duration),sprintf("%.2f",($hit*100)/$totalrequest));
$t->addRow("MISS",$miss,sprintf("%.2f",$miss_bytes/1024/1024),sprintf("%.2f",$miss/$duration),sprintf("%.2f",($miss*100)/$totalrequest));
print "$t\n";

if($csv) {
	print $csv "Varnish cache stats;\n";
	print $csv "Status;Hit;Size (Mb);req/s;Rate (%);\n";
	print $csv "HIT;$hit;".sprintf("%.2f",$hit_bytes/1024/1024).";".sprintf("%.2f",$hit/$duration).";".sprintf("%.2f",($hit*100)/$totalrequest).";\n";
	print $csv "MISS;$miss;".sprintf("%.2f",$miss_bytes/1024/1024).";".sprintf("%.2f",$miss/$duration).";".sprintf("%.2f",($miss*100)/$totalrequest).";\n";
	print $csv ";\n";
}

# HTTP CODE STATS
$t = Text::ASCIITable->new({ headingText => 'HTTP status code' },'outputWidth',80);
$t->setCols('HTTP Code','Hit','Size (Mb)','req/s','Rate (%)','hit (%)','miss (%)');

if($csv) {
	print $csv "HTTP status code;\n";
	print $csv "HTTP Code;Hit;Size (Mb);req/s;Rate (%);hit (%);miss (%);\n";
}

foreach my $k (sort {$h_httpcode{$b} <=> $h_httpcode{$a}} keys(%h_httpcode) ) {
	$t->addRow($k,
		$h_httpcode{$k},
		sprintf("%.2f",$h_httpcode_bytes{$k}/1024/1024),
		sprintf("%.2f",$h_httpcode{$k}/$duration),
		sprintf("%.2f",($h_httpcode{$k}*100)/$totalrequest),
		sprintf("%.2f",((($h_httpcode_hit{$k}) ? $h_httpcode_hit{$k} : 0)*100)/$h_httpcode{$k}),
		sprintf("%.2f",((($h_httpcode_miss{$k})? $h_httpcode_miss{$k}: 0)*100)/$h_httpcode{$k}));

	if($csv) {
		print $csv "$k;$h_httpcode{$k};".sprintf("%.2f",$h_httpcode_bytes{$k}/1024/1024).";".sprintf("%.2f",$h_httpcode{$k}/$duration).";".sprintf("%.2f",($h_httpcode{$k}*100)/$totalrequest).";".sprintf("%.2f",((($h_httpcode_hit{$k}) ? $h_httpcode_hit{$k} : 0)*100)/$h_httpcode{$k}).";".sprintf("%.2f",((($h_httpcode_miss{$k})? $h_httpcode_miss{$k}: 0)*100)/$h_httpcode{$k}).";\n";
	}
}
print "$t\n";

if($csv) {
	print $csv ";\n";
}

# HTTP METHOD STATS
$t = Text::ASCIITable->new({ headingText => 'HTTP Request method' },'outputWidth',80);
$t->setCols('HTTP Method','Hit','Size (Mb)','req/s','Rate (%)','hit (%)','miss (%)');

if($csv) {
	print $csv "HTTP Request method;\n";
	print $csv "HTTP Method;Hit;Size (Mb);req/s;Rate (%);hit (%);miss (%);\n";
}

foreach my $k (sort {$h_method{$b} <=> $h_method{$a}} keys(%h_method) ) {
	$t->addRow($k,
		$h_method{$k},
		sprintf("%.2f",$h_method_bytes{$k}/1024/1024),
		sprintf("%.2f",$h_method{$k}/$duration),
		sprintf("%.2f",($h_method{$k}*100)/$totalrequest),
		sprintf("%.2f",((($h_method_hit{$k}) ? $h_method_hit{$k} : 0)*100)/$h_method{$k}),
		sprintf("%.2f",((($h_method_miss{$k})? $h_method_miss{$k}: 0)*100)/$h_method{$k}));

	if($csv) {
		print $csv "$k;$h_method{$k};".sprintf("%.2f",$h_method_bytes{$k}/1024/1024).";".sprintf("%.2f",$h_method{$k}/$duration).";".sprintf("%.2f",($h_method{$k}*100)/$totalrequest).";".sprintf("%.2f",((($h_method_hit{$k}) ? $h_method_hit{$k} : 0)*100)/$h_method{$k}).";".sprintf("%.2f",((($h_method_miss{$k})? $h_method_miss{$k}: 0)*100)/$h_method{$k}).";\n";
	}
}
print "$t\n";

if($csv) {
	print $csv ";\n";
}

# MIME STATS
$t = Text::ASCIITable->new({ headingText => 'MIME STATS' },'outputWidth',80);
$t->setCols('MIME','Hit','Size (Mb)','req/s','Rate (%)','hit (%)','miss (%)');

foreach my $k (sort {$h_mime{$b} <=> $h_mime{$a}} keys(%h_mime)) {
    $t->addRow($k,
        $h_mime{$k},
        sprintf("%.2f",$h_mime_bytes{$k}/1024/1024),
        sprintf("%.2f",$h_mime{$k}/$duration),
        sprintf("%.2f",($h_mime{$k}*100)/$totalrequest),
        sprintf("%.2f",((($h_mime_hit{$k}) ? $h_mime_hit{$k} : 0)*100)/$h_mime{$k}),
        sprintf("%.2f",((($h_mime_miss{$k})? $h_mime_miss{$k}: 0)*100)/$h_mime{$k}));

	if($csv) {
		print $csv "$k;$h_mime{$k};".sprintf("%.2f",$h_mime_bytes{$k}/1024/1024).";".sprintf("%.2f",$h_mime{$k}/$duration).";".sprintf("%.2f",($h_mime{$k}*100)/$totalrequest).";".sprintf("%.2f",((($h_mime_hit{$k}) ? $h_mime_hit{$k} : 0)*100)/$h_mime{$k}).";".sprintf("%.2f",((($h_mime_miss{$k})? $h_mime_miss{$k}: 0)*100)/$h_mime{$k}).";\n";
	}
}
print "$t\n";

if($csv) {
	print $csv ";\n";
}

# HTTP VHOST STATS
$t = Text::ASCIITable->new({ headingText => 'VHOST' },'outputWidth',80);
$t->setCols('VHOST','Hit','Size (Mb)','req/s','Rate (%)','hit (%)','miss (%)');

if($csv) {
	print $csv "VHOST;\n";
	print $csv "VHOST;Hit;Size (Mb);req/s;Rate (%);hit (%);miss (%);\n";
}

foreach my $k (sort {$h_vhost{$b} <=> $h_vhost{$a}} keys(%h_vhost) ) {
    $t->addRow($k,
        $h_vhost{$k},
        sprintf("%.2f",$h_vhost_bytes{$k}/1024/1024),
        sprintf("%.2f",$h_vhost{$k}/$duration),
        sprintf("%.2f",($h_vhost{$k}*100)/$totalrequest),
        sprintf("%.2f",((($h_vhost_hit{$k}) ? $h_vhost_hit{$k} : 0)*100)/$h_vhost{$k}),
        sprintf("%.2f",((($h_vhost_miss{$k})? $h_vhost_miss{$k}: 0)*100)/$h_vhost{$k}));

	if($csv) {
		print $csv "$k;$h_vhost{$k};".sprintf("%.2f",$h_vhost_bytes{$k}/1024/1024).";".sprintf("%.2f",$h_vhost{$k}/$duration).";".sprintf("%.2f",($h_vhost{$k}*100)/$totalrequest).";".sprintf("%.2f",((($h_vhost_hit{$k}) ? $h_vhost_hit{$k} : 0)*100)/$h_vhost{$k}).";".sprintf("%.2f",((($h_vhost_miss{$k})? $h_vhost_miss{$k}: 0)*100)/$h_vhost{$k}).";\n";
	}
}
print "$t\n";

if($csv) {
	print $csv ";\n";
}

if($o_fullstats) {

	# TOP CLIENT
	$t = Text::ASCIITable->new({ headingText => 'TOP '.$o_top.' clients' },'outputWidth',80);
	$t->setCols('Client','Hit','Size (Mb)','req/s','Rate (%)','hit (%)','miss (%)');

	if($csv) {
		print $csv "TOP $o_top clients;\n";
		print $csv "Client;Hit;Size (Mb);req/s;Rate (%);hit (%);miss (%);\n";
	}

	$i=0;
	foreach my $k (sort {$h_client{$b} <=> $h_client{$a}} keys(%h_client) ) {

	    $t->addRow($k,
    	    $h_client{$k},
	        sprintf("%.2f",$h_client_bytes{$k}/1024/1024),
	        sprintf("%.2f",$h_client{$k}/$duration),
	        sprintf("%.2f",($h_client{$k}*100)/$totalrequest),
	        sprintf("%.2f",((($h_client_hit{$k}) ? $h_client_hit{$k} : 0)*100)/$h_client{$k}),
	        sprintf("%.2f",((($h_client_miss{$k})? $h_client_miss{$k}: 0)*100)/$h_client{$k}));

		last if($i++>$o_top);

		if($csv) {
			print $csv "$k;$h_client{$k};".sprintf("%.2f",$h_client_bytes{$k}/1024/1024).";".sprintf("%.2f",$h_client{$k}/$duration).";".sprintf("%.2f",($h_client{$k}*100)/$totalrequest).";".sprintf("%.2f",((($h_client_hit{$k}) ? $h_client_hit{$k} : 0)*100)/$h_client{$k}).";".sprintf("%.2f",((($h_client_miss{$k})? $h_client_miss{$k}: 0)*100)/$h_client{$k}).";\n";
		}
	}

	print "$t\n";

	if($csv) {
		print $csv ";\n";
	}

	# TOP URL
    $t = Text::ASCIITable->new({ headingText => 'TOP '.$o_top.' URI' },'outputWidth',80);
    $t->setCols('URI','Hit','Size (Mb)','req/s','Rate (%)','hit (%)','miss (%)');

	$i=0;
	foreach my $k (sort {$h_uri{$b} <=> $h_uri{$a}} keys(%h_uri) ) {

		$t->addRow((length($k)>80) ? substr($k,0,37)."[...]".substr($k,length($k)-38,length($k)) : $k,
            $h_uri{$k},
            sprintf("%.2f",$h_uri_bytes{$k}/1024/1024),
            sprintf("%.2f",$h_uri{$k}/$duration),
            sprintf("%.2f",($h_uri{$k}*100)/$totalrequest),
            sprintf("%.2f",((($h_uri_hit{$k}) ? $h_uri_hit{$k} : 0)*100)/$h_uri{$k}),
            sprintf("%.2f",((($h_uri_miss{$k})? $h_uri_miss{$k}: 0)*100)/$h_uri{$k}));

		last if($i++>$o_top);

		if($csv) {
			print $csv "$k;$h_uri{$k};".sprintf("%.2f",$h_uri_bytes{$k}/1024/1024).";".sprintf("%.2f",$h_uri{$k}/$duration).";".sprintf("%.2f",($h_uri{$k}*100)/$totalrequest).";".sprintf("%.2f",((($h_uri_hit{$k}) ? $h_uri_hit{$k} : 0)*100)/$h_uri{$k}).";".sprintf("%.2f",((($h_uri_miss{$k})? $h_uri_miss{$k}: 0)*100)/$h_uri{$k}).";\n";
		}
    }
    print "$t\n";

	if($csv) {
		print $csv ";\n";
	}

	# TOP HIT URI
    $t = Text::ASCIITable->new({ headingText => 'TOP '.$o_top.' HIT URI' },'outputWidth',80);
    $t->setCols('Hit URI','Hit','Size (Mb)','req/s','Rate (%)','hit (%)');

	if($csv) {
		print $csv "TOP $o_top HIT URI;\n";
		print $csv "Hit URI;Hit;Size (Mb);req/s;Rate (%);hit (%);\n";
	}

    $i=0;
	foreach my $k (sort {$h_uri_hit{$b} <=> $h_uri_hit{$a}} keys(%h_uri_hit) ) {

        $t->addRow((length($k)>80) ? substr($k,0,37)."[...]".substr($k,length($k)-38,length($k)) : $k,
            $h_uri_hit{$k},
            sprintf("%.2f",$h_uri_bytes{$k}/1024/1024),
            sprintf("%.2f",$h_uri_hit{$k}/$duration),
            sprintf("%.2f",($h_uri_hit{$k}*100)/$totalrequest),
            sprintf("%.2f",((($h_uri_hit{$k}) ? $h_uri_hit{$k} : 0)*100)/$h_uri{$k}));

		last if($i++>$o_top);

		print $csv "$k;$h_uri_hit{$k};".sprintf("%.2f",$h_uri_bytes{$k}/1024/1024).";".sprintf("%.2f",$h_uri_hit{$k}/$duration).";".sprintf("%.2f",($h_uri_hit{$k}*100)/$totalrequest).";".sprintf("%.2f",((($h_uri_hit{$k}) ? $h_uri_hit{$k} : 0)*100)/$h_uri{$k}).";\n";
    }
    print "$t\n";

	if($csv) {
		print $csv ";\n";
	}

	# TOP MISS URI
    $t = Text::ASCIITable->new({ headingText => 'TOP '.$o_top.' MISS URI' },'outputWidth',80);
    $t->setCols('Miss URI','Hit','Size (Mb)','req/s','Rate (%)','miss (%)');

	if($csv) {
		print $csv "TOP $o_top MISS URI;\n";
		print $csv "Miss URI;Hit;Size (Mb);req/s;Rate (%);miss (%);\n";
	}

    $i=0;
	foreach my $k (sort {$h_uri_miss{$b} <=> $h_uri_miss{$a}} keys(%h_uri_miss) ) {

        $t->addRow((length($k)>80) ? substr($k,0,37)."[...]".substr($k,length($k)-38,length($k)) : $k,
            $h_uri_miss{$k},
            sprintf("%.2f",$h_uri_bytes{$k}/1024/1024),
            sprintf("%.2f",$h_uri_miss{$k}/$duration),
            sprintf("%.2f",($h_uri_miss{$k}*100)/$totalrequest),
            sprintf("%.2f",((($h_uri_miss{$k}) ? $h_uri_miss{$k} : 0)*100)/$h_uri{$k}));

		last if($i++>$o_top);

		if($csv) {
			print $csv "$k;$h_uri_miss{$k};".sprintf("%.2f",$h_uri_bytes{$k}/1024/1024).";".sprintf("%.2f",$h_uri_miss{$k}/$duration).";".sprintf("%.2f",($h_uri_miss{$k}*100)/$totalrequest).";".sprintf("%.2f",((($h_uri_miss{$k}) ? $h_uri_miss{$k} : 0)*100)/$h_uri{$k}).";\n";
		}
    }
    print "$t\n";

   	if($csv) {
		print $csv ";\n";
	}

	# TOP 404
    $t = Text::ASCIITable->new({ headingText => 'TOP '.$o_top.' 404' },'outputWidth',80);
    $t->setCols('404 URI','Hit','Size (Mb)','req/s','Rate (%)');

	if($csv) {
		print $csv "TOP $o_top 404;\n";
		print $csv "404 URI;Hit;Size (Mb);req/s;Rate (%);\n";
	}

    $i=0;
	foreach my $k (sort {$h_httpcode_404{$b} <=> $h_httpcode_404{$a}} keys(%h_httpcode_404) ) {

        $t->addRow((length($k)>80) ? substr($k,0,37)."[...]".substr($k,length($k)-38,length($k)) : $k,
            $h_httpcode_404{$k},
            sprintf("%.2f",$h_httpcode_404_bytes{$k}/1024/1024),
            sprintf("%.2f",$h_httpcode_404{$k}/$duration),
            sprintf("%.2f",($h_httpcode_404{$k}*100)/$totalrequest));

		last if($i++>$o_top);

		if($csv) {
			print $csv "$k;$h_httpcode_404{$k};".sprintf("%.2f",$h_httpcode_404_bytes{$k}/1024/1024).";".sprintf("%.2f",$h_httpcode_404{$k}/$duration).";".sprintf("%.2f",($h_httpcode_404{$k}*100)/$totalrequest).";\n";
		}
    }
    print "$t\n";

	if($csv) {
		print $csv ";\n";
	}

    # TOP 500
    $t = Text::ASCIITable->new({ headingText => 'TOP '.$o_top.' 500' },'outputWidth',80);
    $t->setCols('500 URI','Hit','Size (Mb)','req/s','Rate (%)');

	if($csv) {
		print $csv "TOP $o_top 500;\n";
		print $csv "500 URI;Hit;Size (Mb);req/s;Rate (%);\n";
	}

    $i=0;
	foreach my $k (sort {$h_httpcode_500{$b} <=> $h_httpcode_500{$a}} keys(%h_httpcode_500) ) {

        $t->addRow((length($k)>80) ? substr($k,0,37)."[...]".substr($k,length($k)-38,length($k)) : $k,
            $h_httpcode_500{$k},
            sprintf("%.2f",$h_httpcode_500_bytes{$k}/1024/1024),
            sprintf("%.2f",$h_httpcode_500{$k}/$duration),
            sprintf("%.2f",($h_httpcode_500{$k}*100)/$totalrequest));

		last if($i++>$o_top);

		if($csv) {
			print $csv "$k;$h_httpcode_500{$k};".sprintf("%.2f",$h_httpcode_500_bytes{$k}/1024/1024).";".sprintf("%.2f",$h_httpcode_500{$k}/$duration).";".sprintf("%.2f",($h_httpcode_500{$k}*100)/$totalrequest).";\n";
		}
    }
    print "$t\n";

	if($csv) {
		print $csv ";\n";
	}
}

if($csv) { close($csv); }

