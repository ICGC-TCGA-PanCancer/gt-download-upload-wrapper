#!/usr/bin/env bash

perl -I /usr/tmp/seqware-oozie/test/gt-download-upload-wrapper/lib gnos_download_file.pl  --pem /mnt/home/seqware/gnostest.pem --url https://gtrepo-osdc-icgc.annailabs.com/cghub/data/analysis/download/934754d7-3b4f-43f0-81a1-bd9e576c0a3a --file 934754d7-3b4f-43f0-81a1-bd9e576c0a3a/0ad73352cb328d9c568a9dfe7c2e9975.bam --retries 10 --sleep-min 1 --timeout-min 60

