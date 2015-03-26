gt-download-upload-wrapper
===================

#Description

This tool is used to monitor and make gt-download and upload ore robust. 

To be use primarily with the PanCancer project.

Contained are two modules one for each uploading and downloading


#Usage

##Sample Upload

   GNOS::Upload->run_upload($command_template, $max_attempts, $timeout_minutes);

##Sample Download

   GNOS::Download->run_download($class, $pem, $url, $file, $max_attempts, $timeout_minutes);


We are including the GNOS::Download library by using the -I flag with perl that allows you to specify a path to find the repos. Alterantively you can add the file by adding the line "use lib <lib-path>;" or add the path to the @INC Environment variable.

We are also packaging the taged versions of the repo in OICR's articatory for use with Maven projects. This can be very useful for use with SeqWare workflows. Ask any of the developers on this project to find out where you can get the necessary XML to get the artifact with Maven.

Feel free to use these modules in your own scripts.

Currently they are intended to be used in both the BWA and VCF SeqWare Workflows for the PanCancer Project
