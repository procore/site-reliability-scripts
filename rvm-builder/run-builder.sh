#!/bin/bash

USAGE="./run-builder.sh node-name s3://your-bucket"
NODE_NAME=$1
BUCKET_NAME=$2

RVM_BUILDER_FOLDER=`dirname "$0"`

salt_parms="cwd=/home/$USER"

if [ -z "${NODE_NAME}" ] || [ -z "${BUCKET_NAME}" ]; then
    echo "Usage: $USAGE"
    exit 1
fi

echo "Copying over scripts needed to setup vm, rvm, and install ruby..."
scp $RVM_BUILDER_FOLDER/builder-scripts/*.sh $NODE_NAME:~/

echo "Setting up instance..."
sudo salt $NODE_NAME cmd.run $salt_parms "./setup-vm.sh"
echo "Installing rvm..."
sudo salt $NODE_NAME cmd.run $salt_parms "./install-rvm.sh $USER"

echo "************"
echo "Building ruby binaries. Please note, this may take a long time."
echo "************"
for ruby_ver in "2.2.1" "2.2.2" "2.2.3" "2.3.0"
do
    echo "Building ruby version: $ruby_ver"
    sudo salt $NODE_NAME cmd.run $salt_parms "./install-ruby.sh $ruby_ver"
done

echo "************"
echo "Done building binaries!!!"
echo "************"
# Copy built binaries to machine script is running on
scp -r $NODE_NAME:~/binaries .

# Uploads binaries to S3
s3cmd put --recursive binaries $BUCKET_NAME
