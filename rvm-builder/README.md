# rvm-builder

### Required Software

* salt - Remote execution
* s3cmd - Uploads binaries

### How-To

1. First, create the server you want to use to build your rubies.
1. Next, make sure you have a bucket created to store your built binaries
1. Run `./run-builder.sh server_ip s3://bucket_name`
1. Destroy your server and do any other clean up needed.
