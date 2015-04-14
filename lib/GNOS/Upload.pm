package GNOS::Upload;

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
#  This module is wraps the gtupload script and retries the uploads if it freezes up.       #
#############################################################################################
# USAGE: run_upload($sub_path, $key, $max_attempts, $timeout_minutes);                      #
#        Where the command is the full gtuplaod command                                     #
#############################################################################################

sub run_upload {
    my ($class, $sub_path, $key, $max_attempts, $timeout_minutes) = @_;

    $max_attempts //= 30;
    $timeout_minutes //= 60;

    my $timeout_milliseconds = ($timeout_minutes / 60) * MILLISECONDS_IN_AN_HOUR;
    say "TIMEOUT: $timeout_minutes minutes ( $timeout_milliseconds milliseconds )";

    my ($log_filepath, $time_stamp, $pid, $read_output, $command);
    my $attempt = 0;
    do {
        my @now = localtime();
        $time_stamp = sprintf("%04d-%02d-%02d-%02d-%02d-%02d",
                                 $now[5]+1900, $now[4]+1, $now[3],
                                 $now[2],      $now[1],   $now[0]);

        # BUG: Adam, you are already in this directory, $sub_path does not exist!
        #$log_filepath = "$sub_path/gtupload-$time_stamp.log";
        $log_filepath = "gtupload-$time_stamp.log";

        say "STARTING UPLOAD WITH LOG FILE $log_filepath ATTEMPT ".++$attempt." OUT OF $max_attempts";

        my $upload_cmd = "cd $sub_path; gtupload -l $log_filepath -v -c $key -u ./manifest.xml";

        say "UPLOAD COMMAND: $upload_cmd\n";

        `$upload_cmd </dev/null >/dev/null 2>&1 &`;

        sleep 30;

        $read_output = read_output($sub_path, $log_filepath, $timeout_milliseconds);
        if ($read_output == 1 ) {
            say "KILLING PROCESS";
            `pkill -f gtupload -l $log_filepath`;  # need to have log_filepath included so that it doesn't kill other gt_upload process
        }

    } while ( ($attempt < $max_attempts) and ( $read_output ) );

    return 0 if ( ($read_output == 0) and (say "UPLOADED FILE AFTER $attempt ATTEMPTS") );

    say "FAILED TO UPLOAD FILE AFTER $attempt ATTEMPTS";
    return 1;

}

sub read_output {
    my ($sub_path, $log_filepath, $timeout) = @_;

    my $start_time = time;
    my $time_last_uploading = 0;
    my $last_reported_percent = 0;

    my (@lines, $process, $output);

    say "DIR: ".`pwd`." LOG: ".`ls -lth $sub_path/$log_filepath`."\n";

    my ($uploaded, $percent, $rate);
    while(  $output = `tail -n 20 $sub_path/$log_filepath`  ) {
        sleep(10);
        ($uploaded , $percent, $rate) = (0,0,0);

        # Gets last occurance of the progress line in the 20 lines from the tail command
        @lines = split "\n", $output;
        foreach my $line (@lines) {
            if (my @captured = $line =~ m/Status:\s+(\d+.\d+|\d+| )\s+[M|G]B\suploaded\s*\((\d+.\d+|\d+| )%\s*complete\)\s*current\s*rate:\s*(\d+.\d+|\d+| )\s*[M|k]B\/s/g ) {
                ($uploaded, $percent, $rate) = @captured;
            }
        }

        $percent = $last_reported_percent unless( defined $percent);

        $process = `ps aux | grep 'gtupload -l $log_filepath'`; #check to see if the command that we are monitoring has completed. 
        return 0 unless ($process =~ m/manifest/); # This checks to see if the gtupload process is still running. Does not say if completed correctly

        if ($percent > $last_reported_percent) {
            $time_last_uploading = time;
            say "  UPLOADING TIME: $time_last_uploading";
            say "  REPORTED PERCENT UPLOADED - LAST: $last_reported_percent CURRENT: $percent";
        }
        elsif ((($time_last_uploading != 0) and ( (time - $time_last_uploading) > $timeout) )
                 or ( ($percent == 0) and ( (time - $start_time) > (3 * $timeout)) )) {
                # This should trigger if gtupload stops being able to upload for a certain amount of time
                #     or if it never starts uploading
            say "BASED ON OUTPUT UPLOAD IS NEEDING TO BE RESTARTED";
            return 1;
        }

        $last_reported_percent = $percent;
    }

    return 1;
}

1;
