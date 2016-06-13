#!/bin/bash

# Safety First!
set -euo pipefail

USAGE="./run-builder.sh node-name s3://your-bucket"
NODE_INPUT=$1
BUCKET_NAME=$2
RVM_BUILDER_FOLDER=`dirname "$0"`
salt_params="cwd=/home/$USER"

if [ -z "${NODE_INPUT}" ] || [ -z "${BUCKET_NAME}" ]; then
    echo "Usage: $USAGE"
    exit 1
fi

# If the user passed in an IP, we need to use the -S flag
if [[ "$NODE_INPUT" =~ ^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  salt_target="-S ${NODE_INPUT}"
# If the user passed a node name, no need to do anything special
else
  salt_target="${NODE_INPUT}"
fi

echo "Copying over scripts needed to setup vm, rvm, and install ruby..."
scp $RVM_BUILDER_FOLDER/builder-scripts/*.sh $NODE_INPUT:~/

echo "Setting up instance..."
sudo salt $salt_target cmd.run $salt_params "./setup-vm.sh"
echo "Installing rvm..."
sudo salt $salt_target cmd.run $salt_params "./install-rvm.sh $USER"

echo "************"
echo "Building ruby binaries. Please note, this may take a long time."
echo "************"
for ruby_ver in "2.2.1" "2.2.2" "2.2.3" "2.3.0" "2.3.1"
do
    echo "Building ruby version: $ruby_ver"
    sudo salt $salt_target cmd.run $salt_params "./install-ruby.sh $ruby_ver"
done

echo "************"
echo "Done building binaries!!!"
echo "************"
# Copy built binaries to machine script is running on
scp -r $NODE_INPUT:~/binaries .

# Uploads binaries to S3
s3cmd put --recursive binaries $BUCKET_NAME
