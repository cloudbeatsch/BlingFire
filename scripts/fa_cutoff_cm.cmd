@perl -Sx %0 %*
@goto :eof
#!perl

use File::Temp qw/ :mktemp  /;



sub usage {

print <<EOM;

Usage: fa_cutoff_cm [OPTIONS] < input.utf8 > output.utf8

This program reads an input which is a tab separated fields followed by
the integer count and makes a cut-off based on the cumulative probability 
mass of P(f_n|f_1,f_2,...,f_{n-1}), the probability is summed in the rank
order (from more to less frequent). The probability is calculated as follows:

 P(f_n|f_1,f_2,...,f_{n-1}) == N(f_1,f_2,...,f_n) / N(f_1,f_2,...,f_{n-1})


  --cutoff=P - probability mass cutoff (1.0 by default)

  --verbose - adds cumulative probability mass as an extra field to the output

EOM

}


$cutoff = 1.1;
$verbose = 0;

while (0 < 1 + $#ARGV) {

    if("--help" eq $ARGV [0]) {

        usage ();
        exit (0);

    } elsif ($ARGV [0] =~ /^--cutoff=(.+)/) {

        $cutoff = 0.0 + $1;

    } elsif ($ARGV [0] eq "--verbose") {

        $verbose = 1;

    } elsif ($ARGV [0] =~ /^-.*/) {

        print STDERR "ERROR: Unknown parameter $$ARGV[0], see fa_count2prob --help";
        exit (1);

    } else {

        last;
    }
    shift @ARGV;
}


# Step1
#
# Input:
#   f1\tf2\t...f{n-1}\tfn\tc
#
# Output:
#   f1\tf2\t...f{n-1}\t\tc1
#   f1\tf2\t...f{n-1}\tfn\tc2
#

$proc1 = <<'EOF';

$prev_cx = "";
$prev_c = 0;

while(<>) {

    s/[\r\n]+$//;
    s/^\xEF\xBB\xBF//;

    # [(context)\t](target)\t(count)
    m/^(.+\t)?([^\t]+)\t([0-9]+)$/;

    if (0 >= $3 || "" eq $2) {
      print STDERR "ERROR: Invalid input line: \"$_\"";
      exit (1);
    }

    print "$1$2\t$3\n";

    if($1 ne $prev_cx) {

      if(0 != $prev_c) {
          print "$prev_cx\t$prev_c\n";
      }

      $prev_cx = $1;
      $prev_c = $3;

    } else {

      $prev_c += $3;

    }
}

if(0 != $prev_c) {
    print "$prev_cx\t$prev_c\n";
}

EOF

($fh, $tmp1) = mkstemp ("fa_count2prob_XXXXXXXX");
print $fh $proc1;
close $fh;


# Step2
#
# Input:
#   f1\tf2\t...f{n-1}\t\tc1
#   f1\tf2\t...f{n-1}\tfn\tc2
#
# Output:
#   f1\tf2\t...f{n-1}\tc2\tfn\tp2
#

$proc2 = <<'EOF';

$count = 0;

while(<>) {

    s/[\r\n]+$//;

    m/^(.+\t)?([^\t]*)\t([0-9]+)$/;

    if("" eq $2) {

        $count = $3;

    } else {

        if(0 == $count) {
            print STDERR "ERROR: Internal error, the sequence is not sorted.";
            exit (1);
        }

        $f = (0.0 + $3) / (0.0 + $count) ;

        print $1 . sprintf("%12i", $3) . "\t" . $2 . "\t" . sprintf("%.12e", $f) . "\n";
    }
}

EOF

($fh, $tmp2) = mkstemp ("fa_count2prob_XXXXXXXX");
print $fh $proc2;
close $fh;



# Step3
#
# Iutput sorted by counts:
#   f1\tf2\t...f{n-1}\tc2\tfn\tp2
#
# Output if cumulative probability is less than the cutoff
#   f1\tf2\t...f{n-1}\tfn\tp2
#

$proc3 = <<'EOF';

$prev_context = "\t\t\t";

$cutoff = 0.0 + $ARGV [0];
shift @ARGV;

$verbose = 0 + $ARGV [0];
shift @ARGV;

$summ_prob = 0.0;

while(<>) {

    s/[\r\n]+$//;

    m/^(.+\t)?[ ]*([0-9]+)\t([^\t]*)\t([^\t]+)$/;

    $context = $1;
    $count = $2;
    $fn = $3;
    $p = $4;

    if($prev_context ne $context) {
      $summ_prob = 0.0;
      $prev_context = $context;
    }

    $summ_prob += $p ;

    if($summ_prob <= $cutoff) {

       print "$context$fn\t" . $count;

       if(1 == $verbose) {
         print "\t" . sprintf("%.12e", $p) ;
       }
       print "\n" ;
    }
}

EOF

($fh, $tmp3) = mkstemp ("fa_count2prob_XXXXXXXX");
print $fh $proc3;
close $fh;



$ENV{"LC_ALL"} = "C";

$command = "fa_sortbytes -m | perl $tmp1 | fa_sortbytes -m | perl $tmp2 | tee q | sort -r | perl $tmp3 $cutoff $verbose | ";

open INPUT, $command ;

while(<INPUT>) {
    print $_ ;
}
close INPUT ;


#
# delete temporary files
#

END {
    if ($tmp1 && -e $tmp1) {
        unlink ($tmp1);
    }
    if ($tmp2 && -e $tmp2) {
        unlink ($tmp2);
    }
    if ($tmp3 && -e $tmp3) {
        unlink ($tmp3);
    }
}
