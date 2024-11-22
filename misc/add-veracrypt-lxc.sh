#!/usr/bin/env bash

# Copyright (c) 2024 kaffolder7
# Author: kaffolder7
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

function header_info {
clear
cat <<"EOF"
 -====+-                 :=------:::::. 
  -==+++-               :===----:::::   
   :+++++=             :=====-::::::    
    .++++++.          ======.           
     .++++++.       .======.            
      .+****+:     .+*****:             
        +*****-   .++####++.            
         =*****= :++++##++++.           
          +#####*++++++=*****+======    
           -######+++-  =******++++++.  
            -*#####+:    =******+++++=. 

EOF
}
header_info
set -e
while true; do
  read -p "This will add VeraCrypt to an existing LXC Container ONLY. Proceed(y/n)?" yn
  case $yn in
  [Yy]*) break ;;
  [Nn]*) exit ;;
  *) echo "Please answer yes or no." ;;
  esac
done
header_info
echo "Loading..."
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}

NODE=$(hostname)
MSG_MAX_LENGTH=0
while read -r line; do
  TAG=$(echo "$line" | awk '{print $1}')
  ITEM=$(echo "$line" | awk '{print substr($0,36)}')
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  CTID_MENU+=("$TAG" "$ITEM " "OFF")
done < <(pct list | awk 'NR>1')

while [ -z "${CTID:+x}" ]; do
  CTID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Containers on $NODE" --radiolist \
    "\nSelect a container to add VeraCrypt to:\n" \
    16 $(($MSG_MAX_LENGTH + 23)) 6 \
    "${CTID_MENU[@]}" 3>&1 1>&2 2>&3) || exit
done

header_info
msg "Installing VeraCrypt..."
pct exec "$CTID" -- bash -c '
PKG_VER="1.26.14"
OS_NAME=$(grep "^NAME=" /etc/os-release | cut -d"=" -f2 | cut -f1 -d" " | sed -e "s/^\"//" -e "s/\"$//")
OS_VER=$(grep "^VERSION_ID=" /etc/os-release | cut -d"=" -f2 | sed -e "s/^\"//" -e "s/\"$//")
case $OS_NAME in
  Ubuntu|Debian)
    ARCH_PKG="amd64.deb"
    ;;
  Fedora|CentOS|openSUSE)
    ARCH_PKG="x86_64.rpm"
    ;;
  *)
    ;;
esac
DEB_PACKAGE_SIGNATURE_URL="https://launchpad.net/veracrypt/trunk/$PKG_VER/+download/veracrypt-console-$PKG_VER-$OS_NAME-$OS_VER-$ARCH_PKG.sig"
DEB_PACKAGE_URL="https://launchpad.net/veracrypt/trunk/$PKG_VER/+download/veracrypt-console-$PKG_VER-$OS_NAME-$OS_VER-$ARCH_PKG"
PGP_PUBLIC_KEY_URL="https://www.idrix.fr/VeraCrypt/VeraCrypt_PGP_public_key.asc"
PGP_PUBLIC_KEY_FINGERPRINT="5069A233D55A0EEB174A5FC3821ACD02680D16DE"
verify_signature() {
  local file=$1 out=
  if out=$(gpg --status-fd 1 --verify "$file" 2>/dev/null) &&
    echo "$out" | grep -qs "^\[GNUPG:\] VALIDSIG $PGP_PUBLIC_KEY_FINGERPRINT "; then
    return 0
  else
    echo "$out" >&2
    return 1
  fi
}
apt-get update &>/dev/null
apt-get install -y gpg libccid libfuse2 libpcsclite1 pcscd &>/dev/null
publicKey="$(basename $PGP_PUBLIC_KEY_URL)"
wget -qO "$publicKey" "$PGP_PUBLIC_KEY_URL"
gpg --show-keys $publicKey &>/dev/null
keyVal="$(gpg --show-keys $publicKey | grep -o -P '[A-Z0-9]{10,}')"
debSig="$(basename $DEB_PACKAGE_SIGNATURE_URL)"
debPkg="$(basename $DEB_PACKAGE_URL)"
if [[ "$keyVal" == "$PGP_PUBLIC_KEY_FINGERPRINT" ]]; then
  gpg --import "$publicKey" &>/dev/null
  rm $publicKey
else
  echo "Public key does not match. Terminating installation."
  exit
fi
wget -qO "$debSig" "$DEB_PACKAGE_SIGNATURE_URL"
wget -qO "$debPkg" "$DEB_PACKAGE_URL"
if verify_signature "$debSig"; then
  dpkg -i ./$debPkg &>/dev/null
else
  echo "Signature verification failed. Terminating installation."
  exit
fi
' || exit
msg "\e[1;32m ✔ Installed VeraCrypt\e[0m"

msg "\e[1;31m Reboot ${CTID} LXC to apply the changes, then run veracrypt -h in the LXC console\e[0m"