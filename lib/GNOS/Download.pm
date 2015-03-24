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
# USAGE: run_upload($command, $file, $retries, $cooldown_min, $timeout_min);                #
#        Where the command is the full gtdownlaod command                                   #
#############################################################################################

sub run_download {
    my ($class, $pem, $url, $file, $max_attempts, $cooldown_min, $timeout_min) = @_;

    $max_attempts //= 30;
    $timeout_min //= 60;
    $cooldown_min //= 1;


    my $timeout_mili = ($timeout_min / 60) * MILLISECONDS_IN_AN_HOUR;
    my $cooldown_sec = $cooldown_min * 60;

    say "TIMEOUT: min $timeout_min milli $timeout_mili";



    my ($command, $log_filepath, $time_stamp);
 
    my $attempt = 0;
    do {
        my @now = localtime();
        $time_stamp = sprintf("%04d-%02d-%02d-%02d-%02d-%02d", 
                                 $now[5]+1900, $now[4]+1, $now[3],
                                 $now[2],      $now[1],   $now[0]);

        $log_filepath = "gtdownload-$time_stamp.log"; 
        $command = "gtdownload --max-children 4 --rate-limit 200 -c $pem -vv -d $url -l $log_filepath -k 60";
        say "STARTING DOWNLOAD WITH LOGFILE $log_filepath ATTEMPT ".++$attempt." OUT OF $max_attempts";

        `$command`;

        if ( read_output($log_filepath, $timeout_min) ) {
            say "Killing process";
            die;
        }

        sleep (10); # to make sure that the file has been created. 
    } while ( ($attempt < $max_attempts) and ( not (-e $file) ) );
    
    return 0 if ( (-e $file) and (say "OUTPUT FILE $file EXISTS AFTER $attempt ATTEMPTS") );
    
    say "FAILED TO DOWNLOAD FILE: $file AFTER $attempt ATTEMPTS";
    return 1;
    
}


sub read_output {
    my ($output_log, $timeout) = @_;

    my $start_time = time;
    my $time_last_downloading = 0;
    my $last_reported_size = 0;

    open my $in, '<', $output_log;

    while(<$in>) {

        # just print the output for debugging reasons
        print "$_";

        # these will be defined if the program is actively downloading
        my ($size, $percent, $rate) = $_ =~ m/^Status:\s*(\d+.\d+|\d+|\s*)\s*[M|G]B\s*downloaded\s*\((\d+.\d+|\d+|\s)%\s*complete\)\s*current rate:\s+(\d+.\d+|\d+| )\s+MB\/s/g;

	# override, let's use percent for size because it's always increasing whereas the units of the size change and this will interfere with the > $last_reported_size
	$size = $percent;

        # test to see if the thread is md5sum'ing after an earlier failure
        # this actually doesn't produce new lines, it's all on one line but you
        # need to check since the md5sum can take hours and this would cause a timeout
        # and a kill when the next download line appears since it could be well past
        # the timeout limit
        my $md5sum = ($_ =~ m/^Download resumed, validating checksums for existing data/g)? 1: 0;
        
        if ((defined($size) &&  defined($last_reported_size) && $size > $last_reported_size) || $md5sum) {
            $time_last_downloading = time;
            say "UPDATING LAST DOWNLOAD TIME: $time_last_downloading";
            if (defined($last_reported_size) && defined($size)) { say "  LAST REPORTED SIZE $last_reported_size SIZE: $size"; }
            if (defined($md5sum)) { say "  IS MD5Sum State: $md5sum"; }
        }
        elsif ((($time_last_downloading != 0) and ( (time - $time_last_downloading) > $timeout) )
                 or ( ($size == 0) and ( (time - $start_time) > (3 * $timeout)) )) {
            say 'ERROR: Killing Thread - Timed out '.time;
            exit;
        }
        $last_reported_size = $size;
    }
}

1;
