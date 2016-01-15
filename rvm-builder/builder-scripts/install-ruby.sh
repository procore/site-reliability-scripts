#!/usr/bin/env bash
export PATH="/usr/local/rvm/bin:$PATH"

RUBY_VER=$1

echo "Uninstalling ruby ver $RUBY_VER"
sudo rvm uninstall --gems $RUBY_VER
echo "Installing ruby ver $RUBY_VER"
sudo rvm install --movable $RUBY_VER --autolibs=4
echo "Preparing..."
sudo rvm prepare --path $RUBY_VER
