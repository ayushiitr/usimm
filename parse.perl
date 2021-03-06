#!/usr/bin/perl -w

#-----------------------------------------------------------
# Description:
# ------------
# This script parses the files mentioned in the runsim script 
# and creates a csv with all the relevant information of all 
# the simulations
# 
# Inputs:
# -------
# 1) gen_csv.pl takes the name of the USIMM runscript as the only argument
# 2) The outputs produced by the runscript should be in the output/ 
#    directory
# 3) The output files must follow the following naming convention
#      <two letter abbv of benchmark>-...-<>-<num channels>_<whatever>
# 4) Usage: > cd <usimm_dir>
#           > ./gen_csv.pl -runscript <run script>
# 
# Outputs:
# --------
# output/stats.csv
# Final Metric numbers are also printed on Stdout
#
# Other Notes:
# ------------
# 1) Make sure all your single thread bcmks have "$single_thread_time"
#    (The times in this gen_csv.pl script represent single thread behavior 
#    with an FCFS scheduler, and will be the ones used for the MSC)
# 2) $mt includes the programs excluded from the fairness calculations

#-----------------------------------------------------------
use strict;

my %single_thread_time;

# Benchmark Naming convention
# $single_thread_time{<benchmark><Num Channels>}

$single_thread_time{bl1}=318150748;
$single_thread_time{bo1}=293623201;
$single_thread_time{ca1}=465074385;
$single_thread_time{fa1}=404645160;
$single_thread_time{fe1}=379065129;
$single_thread_time{fr1}=305902869;
$single_thread_time{ra1}=319983309;
$single_thread_time{st1}=320441340;
$single_thread_time{vi1}=325420205;
$single_thread_time{x21}=332000385;
$single_thread_time{c11}=372897100;
$single_thread_time{c21}=442948245;
$single_thread_time{fl1}=468052997;
$single_thread_time{sw1}=474243253;


$single_thread_time{c31}=354524613;
$single_thread_time{c41}=316208876;
$single_thread_time{c51}=265660108;
$single_thread_time{fd1}=464442704;
$single_thread_time{fp1}=251305652;
$single_thread_time{ge1}=389291761;
$single_thread_time{hm1}=296911657;
$single_thread_time{lb1}=608302501;
$single_thread_time{le1}=395169481;
$single_thread_time{li1}=611499664;
$single_thread_time{mc1}=614688361;
$single_thread_time{mu1}=628855245;
$single_thread_time{s21}=351731072;
$single_thread_time{ti1}=672025103;



$single_thread_time{bl4}=187992840;
$single_thread_time{bo4}=167672553;
$single_thread_time{ca4}=300787617;
$single_thread_time{fa4}=210337888;
$single_thread_time{fe4}=232711401;
$single_thread_time{fr4}=174316754;
$single_thread_time{ra4}=186816805;
$single_thread_time{st4}=188074168;
$single_thread_time{vi4}=192811301;
$single_thread_time{x24}=197657337;
$single_thread_time{c14}=244419708;
$single_thread_time{c24}=303069945;
$single_thread_time{fl4}=275488665;
$single_thread_time{sw4}=276348929;


$single_thread_time{c34}=218593453;
$single_thread_time{c44}=190803829;
$single_thread_time{c54}=154061128;
$single_thread_time{fd4}=267090041;
$single_thread_time{fp4}=125928705;
$single_thread_time{ge4}=225046893;
$single_thread_time{hm4}=217980413;
$single_thread_time{lb4}=319465145;
$single_thread_time{le4}=390428605;
$single_thread_time{li4}=364135428;
$single_thread_time{mc4}=383824086;
$single_thread_time{mu4}=443990865;
$single_thread_time{s24}=195015969;
$single_thread_time{ti4}=462633387;




# Multi threaded benchmarks  and single programmed workloads are being excluded
# from the fairness calculations.
# Slowdown cannot be calculated for these
my %mt;
$mt{MTc} =1;
$mt{c2} =1;
$mt{MTf} =1;
#$mt{MTf4} =1;

#-----------------------------------------------------------
#Get Options 
use Getopt::Long;
my  ($ret, $help);
my $runscript;

$ret = Getopt::Long::GetOptions (

        "runscript|runsim:s"        => \$runscript,
        "help|h:s"          => \$help
        ) ;



if( !(defined $runscript)) {
    print STDERR "Warning: USIMM runscript not specified. Using the default ./runsim\n";
    $runscript= "runsim";
    print STDERR "Usage: $0 -runscript <run script>\n\n";
}

if (defined $help) {
    print STDERR "Usage: $0 -runscript <run script>\n\n";
    exit;
}
#-----------------------------------------------------------
# Check if the script is being run in the correct directory
if (! -d "./output") {
    die ("ERROR: ./output does not exis.. Exiting");
}

# Check if the runcript exists in the location specified by the user
if (! -e "$runscript") {
    die ("ERROR: $runscript does not exis.. Exiting");
}

#-----------------------------------------------------------
# Parse the runscript to get the names of all the output files
# The runscript is assumed to be a shell script where the output
# is dumped using the ">" operatior
# All files generated by the ">" operator in the runscript will be
# assumed to be valid usimm outputs

open (RUNSIM_FH, "<$runscript") or die "Error: Can't open $runscript\n";

# This variable keeps track of the max number of programs in each workload
# This is needed to align the columns in the .csv
my $max_progs=0;

my $line;

#This variable will have all the filenames that will parsed as valid USIMM 
#outputs
my @outputs;

while (<RUNSIM_FH>) {
    chomp;
    $line=$_;
    if ($line=~/>/) {
        chomp;
        $line=~s/.*>\s*//;
        $line=~s/.*output.*\///;
        $line=~s/.*\///;
        $line=~s/&//;
        $line=~s/\s+.*//;
        $line=~s/"//g;
        @outputs[scalar @outputs] = $line;

        my @benchmarks=  split (/-/,$line);
        my $file_len = scalar @benchmarks -1;
        $max_progs= $file_len if ($max_progs < $file_len);
    }
}
close RUNSIM_FH;

#-----------------------------------------------------------

my $progs=0;
my $sum_time=0;


#my @outputs = ( "c2-1", "c1-c1-1", "bl-bl-fr-fr-1", "c2-4", "st-st-st-st-1", "c1-c1-4", "fa-fa-fe-fe-1", "c1-c1-c2-c2-1", "bl-bl-fr-fr-4", "st-st-st-st-4", "c1-c1-c2-c2-4", "fa-fa-fe-fe-4", "MTc-1", "MTc-4", "fl-sw-c2-c2-1", "fl-sw-c2-c2-4", "fl-fl-sw-sw-c2-c2-fe-fe-4", "fl-fl-sw-sw-c2-c2-fe-fe-bl-bl-fr-fr-c1-c1-st-st-4" );


# This is the file where the output will be writted to in the output directory
my $out_file = "stats.csv";

print "INFO: Writing output to output/$out_file\n";
open (OUT_FH, ">output/$out_file") or die "Error: Can't open output/$out_file\n";

print OUT_FH "Workload, Sum of Execution Time,Execution Time,Execution Time,Execution Time,Execution Time,Execution Time,Execution Time,Execution Time,Execution Time,Execution Time,Execution Time,Execution Time,Execution Time,Execution Time,Execution Time,Execution Time,Execution Time,,Max SlowDown, MinSlowDown, SlowDown, SlowDown, SlowDown, SlowDown, SlowDown, SlowDown, SlowDown, SlowDown, SlowDown, SlowDown, SlowDown, SlowDown, SlowDown, SlowDown, SlowDown, SlowDown...\n";

my $infile;
my %bcmk;
my %time;
my %slowdown;
my %max_slowdown;
my %min_slowdown;
my $total_execution_time=0;
my $pfp_total_execution_time=0;
my %edp;
my $total_edp=0;
my $i;

# Start reading USIMM output files
foreach $infile (@outputs) {
    print "INFO: Openeing file output/$infile ";
    open (IN_FH, "<output/$infile") or die "Error: Can't open output/$infile ";

#Core Num
    my $n=0;
    my $file_name;

    $infile =~s/_.*//;
    $file_name = $infile;
    $file_name =~s/-(\d+).*//;
    my $current_channel= $1;
    my @bcmks= split ("-", $file_name);

    while  (<IN_FH>) {
        chomp;
        $line= $_;



        if ($line =~/^Done: Core/) {
#time {inFile} {core}
            $time{$infile}{$n} = $line;
            $time{$infile}{$n} =~s/.* //;


            $total_execution_time += $time{$infile}{$n};
            $pfp_total_execution_time += $time{$infile}{$n} if (!exists $mt{$file_name});

            $bcmk{$infile}{$n} = $bcmks[$n];

# If filename exists in the $mt hash, then it is multi-threaded and will not have a 
# single threaded exec time
            if (!exists $mt{$file_name}) {
                my $single_thread_key= "$bcmks[$n]"."$current_channel";
                if (exists $single_thread_time{$single_thread_key}) {
                    $slowdown{$infile}{$n} = $time{$infile}{$n}/$single_thread_time{$single_thread_key};
                } else {
                    die "ERROR: single_thread_time{$single_thread_key} does not exist n=$n file_name=$file_name ... Exiting";
                }   
            } else {
# SLowdown is marked negative to mark invalid               
# This condition is checked each time $slowdown is used
                $slowdown{$infile}{$n} = -1;
            }

# Find max slowdown
            if (! exists $max_slowdown{$infile}) {
                if ($slowdown{$infile}{$n} > 0) {
                    $max_slowdown{$infile} = $slowdown{$infile}{$n};
                } else {
                    $max_slowdown{$infile} = 0;
                }
            } elsif ($max_slowdown{$infile} < $slowdown{$infile}{$n} ){
                $max_slowdown{$infile} = $slowdown{$infile}{$n};
            }

            if (! exists $min_slowdown{$infile}) {
                if ($slowdown{$infile}{$n} > 0) {
                    $min_slowdown{$infile} = $slowdown{$infile}{$n};
                } else {
                    $min_slowdown{$infile} = 0;
                }
            } elsif ($min_slowdown{$infile} > $slowdown{$infile}{$n} ){
                $min_slowdown{$infile} = $slowdown{$infile}{$n};
            }

            $n++;

        } elsif ($line =~/Energy Delay product \(EDP\) = (\S+) J.s/) {
            $edp{$infile} = $1;
            $total_edp += $1;
        }
    }

    #print " - MAX SLOWDOWN: $max_slowdown{$infile} , MIN SLOWDOWN: $min_slowdown{$infile}\n";

    close IN_FH;
}



my $n=0;
my $total_max_slowdown=0;
my $l_slowdown=0;
my $avg_max_slowdown;

my $workload;
my $core;
my $num_non_mt_workload=0;


$n=0;
# The completion time of MultiThreaded workloads is not considered while
# calculating the PFP metrics

foreach  $workload (sort keys %slowdown) {
    $n++;
    my $threads= $workload;

    printf "THREADS= $threads\n";


    $threads=~s/-\d+$//;
    if ( ! exists $mt{$threads}) {
        $num_non_mt_workload++ ;
    }
    $total_max_slowdown+=$max_slowdown{$workload} ;
}
$avg_max_slowdown = $total_max_slowdown/$n;
my $pfp_avg_max_slowdown =  $total_max_slowdown/$num_non_mt_workload;

my $pfp = $pfp_total_execution_time * $pfp_avg_max_slowdown;

#Start Generating the csv file:
foreach  $workload (sort keys %time) {
    $progs=0;
    $sum_time=0;
    print OUT_FH "$workload";

    foreach $core (sort {$a<=> $b} keys %{$time{$workload}}){
        $sum_time += $time{$workload}{$core};
    }
    print OUT_FH ",$sum_time";

    foreach $core (sort {$a<=> $b} keys %{$time{$workload}}){
        print OUT_FH ",$time{$workload}{$core}";
        $progs++;
    }
    for ($i=$progs; $i<= $max_progs; $i++) {
        print OUT_FH ",";
    }

    print OUT_FH ",$max_slowdown{$workload}";
    print OUT_FH ",$min_slowdown{$workload}";
    $progs=0;
    foreach $core (sort {$a<=> $b} keys %{$time{$workload}}){
        if ($slowdown{$workload}{$core} > 0) {
            print OUT_FH ",$slowdown{$workload}{$core}";
        } else {
            print OUT_FH ",";
        }
        $progs++;
    }
    for ($i=$progs; $i<= $max_progs; $i++) {
        print OUT_FH ",";
    }
    print OUT_FH "\n";

}

print OUT_FH "\n\nTotal Exection Time, $total_execution_time\n";
print OUT_FH "PFP Avg Max Slowdown, $pfp_avg_max_slowdown\n";
print OUT_FH "PFP, $pfp\n\n\n";

#Print the EDP stats into the CSV

print OUT_FH "Work Load, EDP\n";
foreach  $workload (sort keys %edp) {
    print OUT_FH "$workload, $edp{$workload}\n";
}
print OUT_FH "Total, $total_edp\n";

print "#----------------------------------------------\n";
print "Total_execution_time     = $total_execution_time\n";
print "PFP Total_execution_time = $pfp_total_execution_time\n";
print "PFP                      = $pfp\n";
print "PFP Average Max Slowdown = $pfp_avg_max_slowdown\n";
print "Total EDP                = $total_edp\n";
print "#----------------------------------------------\n";


close OUT_FH;

