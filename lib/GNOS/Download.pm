package GNOS::Download;

use warnings;
use strict;

use feature qw(say);
use autodie;
use Carp qw( croak );

use constant {
    MILLISECONDS_IN_AN_HOUR => 3600000,
};

#############################################################################################
# DESCRIPTION                                                                               #
#############################################################################################
#  This module is wraps the gtdownload script and retries the downloads if it freezes up.   #
#############################################################################################
# USAGE: run_download($class, $pem, $url, $file, $max_attempts, $timeout_minutes);          #
#        Where the command is the full gtdownlaod command                                   #
#############################################################################################

# TODO: add min rate

sub run_download {
    my ($class, $pem, $url, $file, $max_attempts, $timeout_minutes, $max_children, $rate_limit_mbytes, $ktimeout) = @_;

    $max_attempts //= 30;
    $timeout_minutes //= 60;
    my $max_children_txt = "";
    if ($max_children > 0) {
      $max_children_txt = "--max-children $max_children";
    }
    my $rate_limit_mbytes_txt = "";
    if ($rate_limit_mbytes > 0) {
      $rate_limit_mbytes_txt = "--rate-limit $rate_limit_mbytes";
    }
    my $ktimeout_txt = "";
    if ($ktimeout > 0) {
      $ktimeout_txt = "-k $ktimeout";
    }

    my $timeout_milliseconds = ($timeout_minutes / 60) * MILLISECONDS_IN_AN_HOUR;
    say "TIMEOUT: $timeout_minutes minutes ( $timeout_milliseconds milliseconds )";

    my ($log_filepath, $time_stamp, $pid, $random_int);
    my $attempt = 0;
    do {
        my @now = localtime();
        $time_stamp = sprintf("%04d-%02d-%02d-%02d-%02d-%02d",
                                 $now[5]+1900, $now[4]+1, $now[3],
                                 $now[2],      $now[1],   $now[0]);

        $random_int = int(rand(1000));
        $log_filepath = "gtdownload-$time_stamp-$random_int.log";
        say "STARTING DOWNLOAD WITH LOG FILE $log_filepath ATTEMPT ".++$attempt." OUT OF $max_attempts";

        `gtdownload -l $log_filepath $max_children_txt $rate_limit_mbytes_txt -c $pem -v $url $ktimeout_txt </dev/null >/dev/null 2>&1 &`;

        sleep 10; # to give gtdownload a chance to make the log files.

        if ( read_output($log_filepath, $timeout_milliseconds) ) {
            say "KILLING PROCESS";
            `sudo pkill -f 'gtdownload -l $log_filepath'`;
        }
        sleep 10; # to make sure that the file has been created.
    } while ( ($attempt < $max_attempts) and ( not (-e $file) ) );

    return 0 if ( (-e $file) and (say "DOWNLOADED FILE $file AFTER $attempt ATTEMPTS") );

    say "FAILED TO DOWNLOAD FILE: $file AFTER $attempt ATTEMPTS";
    return 1;
}

sub read_output {
    my ($log_filepath, $timeout) = @_;

# needs to be param
my $min_rate = 0;

    my $start_time = time;
    my $time_last_downloading = 0;
    my $last_reported_percent = 0;
    my $last_reported_rate = 0;

    my ($size, $percent, $rate, $rate_units);
    $rate_units = "M";
    my (@lines, $output, $process);
    sleep (20); # to wait for gtdownload to create the log file

    while( $output = `tail -n 20 $log_filepath` ) {
        sleep 10;

        ($size , $percent, $rate, $rate_units) = (0,0,0,"M");

        # Gets last occurance of the progress line in the 20 lines from the tail command
        @lines = split "\n", $output;
        foreach my $line (@lines) {
            if (my @captured = $line =~  m/Status:\s*(\d+.\d+|\d+|\s*)\s*[M|G]B\s*downloaded\s*\((\d+.\d+|\d+|\s)%\s*complete\)\s*current rate:\s+(\d+.\d+|\d+| )\s+([M|K|G])B\/s/g) {
                ($size, $percent, $rate, $rate_units) = @captured;
                if ($rate_units eq "K") { $rate = $rate / 1024; }
                if ($rate_units eq "G") { $rate = $rate * 1024; }
            }
        }

        $percent = $last_reported_percent unless( defined $percent);
        $rate = $last_reported_rate unless( defined $rate);

        my $md5sum = ($output =~ m/Download resumed, validating checksums for existing data/g)? 1: 0;

        $process = `ps aux | grep 'gtdownload -l $log_filepath'`;
        return 0 if ($process !~ m/children/ && $percent >= 100); # This checks to see if the gtdownload process is still running. Does not say if completed correctly

        #return 0 if ($percent > 100); # this is an edge case where for some reason the percentage continues increasing beyond 100%

        # LEFT OFF WITH: need to check the rate here... if < threshold for > retries then kill the job
        # need to properly parse the... need to make this check optional

        if ( ( $percent > $last_reported_percent && $rate > $min_rate ) || $md5sum) {  # Checks to see if the download is making progress.
            $time_last_downloading = time;
            say "UPDATING LAST DOWNLOAD TIME: $time_last_downloading";
            say "  REPORTED PERCENT DOWNLOADED - LAST: $last_reported_percent CURRENT: $percent" if ($percent > $last_reported_percent);
            say "  IS MD5Sum State: $md5sum" if ($md5sum);
        }
        elsif ((($time_last_downloading != 0) and ( (time - $time_last_downloading) > $timeout) )
                 or ( ($percent == 0) and ( (time - $start_time) > (3 * $timeout)) )) { # this check is to see the download has not been working for too long
                # This should trigger if gtdownload stops being able to download for a certain amount of time
                #     or if it never starts downloading - giving time for the md5 check
            say "BASED ON OUTPUT DOWNLOAD IS NEEDING TO BE RESTARTED";
            return 1;
        }

        $last_reported_percent = $percent;
    }

    return 1;
}

1;
