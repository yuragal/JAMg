#!/usr/bin/env perl

=pod

=head1 NAME

 augustus_RNAseq_hints.pl

=head1 USAGE

Create hint files for Augustus using RNASeq/EST. One is junction reads (excellent for introns), the other is RNASeq/EST coverage

 -dir|aug      s  The directory where Augustus is (if augustus is not already in your PATH).
 -bam|in       s  The input BAM file (co-ordinate sorted).
 -genome|fasta s  The genome assembly FASTA file.
 -strandness   i  If RNAseq is directional, provide direction: 0 for unknown (default); or 1 for + strand; -1 for - strand

=cut

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use File::Basename;
use FindBin qw($RealBin);
use lib ("$RealBin/../PerlLib");
$ENV{PATH} .= ":$RealBin";

my ( $samtools_exec, $bedtools_exec ) =
  &check_program( 'samtools', 'bedtools' );
my ($augustus_exec);

#Options
my ( $augustus_dir, $bamfile, $genome, $help );
my $min_score = 10;
my $strandness = int(0);
GetOptions(
	'help'           => \$help,
	'dir|aug:s'      => \$augustus_dir,
	'bam|in:s'       => \$bamfile,
	'genome|fasta:s' => \$genome,
	'min_score:i'   => \$min_score,
        'strandness:i' => \$strandness  
);

pod2usage if $help;
if ($augustus_dir) {
	$augustus_dir = readlink($augustus_dir) if -l $augustus_dir;
	$augustus_exec = $augustus_dir . '/bin/augustus';
}
else {
	$augustus_exec = &check_program('augustus');
	$augustus_dir  = dirname( dirname($augustus_exec) )
	  if $augustus_exec && !$augustus_dir;
}

pod2usage "Cannot find Augustus\n" unless $augustus_exec && -s $augustus_exec;

$ENV{PATH} .= ":$augustus_dir/bin:$augustus_dir/scripts";

pod2usage "Cannot find the BAM or genome FASTA file\n"
  unless $bamfile
	  && -s $bamfile
	  && $genome
	  && ( -s $genome || -s $genome . '.fai');

my $strand;
if (!$strandness || $strandness == 0 ){
	$strand = '.';
}elsif ($strandness > 0){
	$strand = '+';
}elsif ($strandness < 1){
	$strand = '-';
}else{
die;
}



my $genome_idx_cmd = "$samtools_exec $genome";
&process_cmd($genome_idx_cmd) unless -s $genome . '.fai';
die "Cannot index genome $genome\n" unless -s $genome . '.fai';

my $junction_cmd =
"$samtools_exec rmdup -S $bamfile - | $bedtools_exec bamtobed -bed12 | bed12_to_augustus_junction_hints.pl -prio 7 -out $bamfile.junctions.bed | $augustus_dir/scripts/join_mult_hints.pl > $bamfile.junctions.hints";
&process_cmd($junction_cmd) unless -e "$bamfile.junctions.hints.completed";
&touch("$bamfile.junctions.hints.completed");

my $coverage_cmd =
"$bedtools_exec genomecov -split -bg -g $genome.fai -ibam $bamfile >  $bamfile.coverage.bg";
&process_cmd($coverage_cmd) unless -e "$bamfile.coverage.bg.completed";
&touch("$bamfile.coverage.bg.completed");

&bg2hints("$bamfile.coverage.bg") unless -e "$bamfile.coverage.hints.completed";

if (   -e "$bamfile.junctions.hints.completed"
	&& -e "$bamfile.coverage.hints.completed" )
{
 &process_cmd("cat $bamfile.junctions.hints $bamfile.coverage.hints| sort -S 1G -n -k 4,4 | sort -S 1G -s -n -k 5,5 | sort -S 1G -s -n -k 3,3 | sort -S 1G -s -k 1,1 > $bamfile.rnaseq.hints") unless -s "$bamfile.rnaseq.completed";
 &touch("$bamfile.rnaseq.completed");
	print "Done!\n";
}
else {
	die "Something went wrong....\n";
}
###
sub check_program() {
	my @paths;
	foreach my $prog (@_) {
		my $path = `which $prog`;
		pod2usage
		  "Error, path to a required program ($prog) cannot be found\n\n"
		  unless $path =~ /^\//;
		chomp($path);
		$path = readlink($path) if -l $path;
		push( @paths, $path );
	}
	return @paths;
}
###
sub process_cmd {
	my ($cmd) = @_;
	print "CMD: $cmd\n";
	my $ret = system($cmd);
	if ( $ret && $ret != 256 ) {
		die "Error, cmd died with ret $ret\n";
	}
	return $ret;
}

sub bg2hints() {
	my $bg      = shift;
	my $outfile = $bg;
	$outfile =~ s/.bg$/.hints/;
	open( IN,  $bg );
	open( OUT, ">$outfile" );
	while ( my $ln = <IN> ) {
		chomp($ln);
		my @data = split( "\t", $ln );
		next unless $data[3] || $data[3] < $min_score;
		print OUT $data[0]
		  . "\tRNASeq\texonpart\t"
		  . $data[1] . "\t"
		  . $data[2] . "\t"
		  . $data[3]
		  . "\t$strand\t.\tsrc=R;pri=5\n";

	}
	close OUT;
	close IN;
	&touch("$outfile.completed");
	return $outfile;
}

sub touch() {
	my $file = shift;
	system("touch $file");
}
