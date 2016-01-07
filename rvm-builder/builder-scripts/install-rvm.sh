#!/usr/bin/env bash
home_user=$1
installer_options=( --auto-dotfiles --path /usr/local/rvm )

curl -L https://get.rvm.io | bash -s -- "${installer_options[@]}"

rm -rf /usr/local/rvm/user/*
/usr/local/rvm/bin/rvm gemset globalcache enable

for type in archives repos gems/cache
do
  if
    [[ -d /home/$home_user/rvm-${type//\//-} ]]
  then
    mkdir -p /usr/local/rvm/${type%/*} &&
    rm -rf /usr/local/rvm/${type} &&
    ln -s /home/$home_user/rvm-${type//\//-}/ /usr/local/rvm/${type}
  else
    echo "rvm-${type} missing, shared ${type} disabled" >&2
  fi
done
