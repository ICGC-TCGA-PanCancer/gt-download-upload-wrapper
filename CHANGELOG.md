# 2.0.11

* added `$ktimeout` to upload, this is the `-k` parameter from gtupload
* added `$max_children`, `$rate_limit_mbytes`, `$ktimeout` to download. These correspond to the following gtdownload params:
    * --max-children <gtdownload_default>
    * --rate-limit <gtdownload_default>
    * -k <minutes_of_inactivity_to_abort_recommend_less_than_timeout_if_you_want_this_to_be_used>
* Previously the values were hard coded to: 4, 200, and 60 respectively for the above, if you want to match the old behavior you must specify these values otherwise the defaults for gtdownload will be used, see [here](https://cghub.ucsc.edu/docs/user/CGHubUserGuide.pdf).
