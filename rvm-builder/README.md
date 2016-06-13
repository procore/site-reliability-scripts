# rvm-builder

### Required Software

* salt - Remote execution
* s3cmd - Uploads binaries

### How-To

1. First, create the server you want to use to build your rubies.
2. Next, make sure you have a bucket created to store your built binaries
3. Run `./run-builder.sh [node_name|server_ip] s3://bucket_name`
4. Destroy your server and do any other clean up needed.
