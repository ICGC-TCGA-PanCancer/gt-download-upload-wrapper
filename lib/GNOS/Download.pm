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

sub run_download {
    my ($class, $pem, $url, $file, $max_attempts, $timeout_minutes) = @_;

    $max_attempts //= 30;
    $timeout_minutes //= 60;

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

        `gtdownload -l $log_filepath --max-children 4 --rate-limit 200 -c $pem -v $url -k 60 </dev/null >/dev/null 2>&1 &`;

        sleep 10; # to give gtdownload a chance to make the log files. 

        if ( read_output($log_filepath, $timeout_milliseconds) ) {
            say "KILLING PROCESS";
            `pkill -f 'gtdownload -l $log_filepath'`;
        }
        sleep 10; # to make sure that the file has been created. 
    } while ( ($attempt < $max_attempts) and ( not (-e $file) ) );
    
    return 0 if ( (-e $file) and (say "DOWNLOADED FILE $file AFTER $attempt ATTEMPTS") );
    
    say "FAILED TO DOWNLOAD FILE: $file AFTER $attempt ATTEMPTS";
    return 1;    
}

sub read_output {
    my ($log_filepath, $timeout) = @_;

    my $start_time = time;
    my $time_last_downloading = 0;
    my $last_reported_percent = 0;

    my ($size, $percent, $rate);
    my (@lines, $output, $process);
    sleep (20); # to wait for gtdownload to create the log file

    while( $output = `tail -n 20 $log_filepath` ) {
        sleep 10;

        ($size , $percent, $rate) = (0,0,0);

        # Gets last occurance of the progress line in the 20 lines from the tail command
        @lines = split "\n", $output;
        foreach my $line (@lines) {
            if (my @captured = $output =~  m/^Status:\s*(\d+.\d+|\d+|\s*)\s*[M|G]B\s*downloaded\s*\((\d+.\d+|\d+|\s)%\s*complete\)\s*current rate:\s+(\d+.\d+|\d+| )\s+MB\/s/g) {
                ($size, $percent, $rate) = @captured;
            }
        }

        $percent = $last_reported_percent unless( defined $percent);
        
        my $md5sum = ($output =~ m/Download resumed, validating checksums for existing data/g)? 1: 0;

        $process = `ps aux | grep 'gtdownload -l $log_filepath'`;
        return 0 unless ($process =~ m/children/); # This checks to see if the gtdownload process is still running. Does not say if completed correctly       

        if ( ($percent > $last_reported_percent) || $md5sum) {  # Checks to see if the download is making progress.
            $time_last_downloading = time;
            say "UPDATING LAST DOWNLOAD TIME: $time_last_downloading";
            say "  REPORTED PERCENT DOWNLOADED - LAST: $last_reported_percent CURRENT: $size" if ($percent > $last_reported_percent);
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
