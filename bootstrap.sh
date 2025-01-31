#!/bin/bash

# Enable logging for debugging
exec > /var/log/user_data.log 2>&1
set -x

# Variables
HASHCAT=/usr/local/hashcat/hashcat.bin
WORDLIST=/mnt/wordlists/xsukax-Wordlist-All.txt
RULES=/usr/local/hashcat/rules/best64.rule
HASHES=/mnt/hashes/
TMP=/tmp/
HOST=`/bin/hostname`

# Update package list
sudo apt-get update && sudo apt-get install -y jq wget p7zip-full tmux awscli

# Install necessary dependencies and NVIDIA driver
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y ppa:graphics-drivers/ppa
sudo apt-get update
# sudo apt-get install -y nvidia-driver-460 nvidia-cuda-toolkit-11.0

# Clean up any broken packages and fix dependencies
sudo apt-get --fix-broken install
sudo apt-get install -f
sudo apt-get autoremove

# Reboot to apply NVIDIA driver changes
# echo "Rebooting to apply NVIDIA driver changes..."
# sudo reboot
# sleep 60

# Download and extract Hashcat
cd $TMP
curl -s https://api.github.com/repos/hashcat/hashcat/releases/latest | jq -r '.assets[] | select(.name|endswith(".7z")) | .browser_download_url' | wget -i -
7zr x hashcat*.7z
rm -f hashcat*.7z
mv -f /tmp/hashcat* /usr/local/hashcat

# Ensure hashcat directory is accessible
chmod -R 755 /usr/local/hashcat

# Verify NVIDIA GPU
nvidia-smi >> /var/log/nvidia-gpu-check.log 2>&1
if [[ $? -ne 0 ]]; then
  echo "Error: NVIDIA GPU not detected or drivers not installed properly." | tee -a /var/log/user_data.log
  exit 1
fi

# Restore previous session if exists
if [ -e /mnt/hashcat ]; then
  cp -f /mnt/hashcat/hashcat.restore /usr/local/hashcat/hashcat.restore 
  cp -f /mnt/hashcat/hashcat.potfile /usr/local/hashcat/hashcat.potfile
  cp -f /mnt/hashcat/hashcat.dictstat2 /usr/local/hashcat/hashcat.dictstat2
  cp -f /mnt/hashcat/hashcat.log /usr/local/hashcat/hashcat.log
fi

# Check if hashcat is working
# $HASHCAT -I >> $HASHES/hashcat-info-$HOST.log 2>&1
# if [[ $? -ne 0 ]]; then
#   echo "Error: Hashcat failed initialization" | tee -a /var/log/user_data.log
#   exit 1
# fi

# Ensure hash list and type exist
if [ ! -f /mnt/hashes/crackme.type ]; then
  echo "Error: Hash type file not found!" | tee -a /var/log/user_data.log
  exit 1
fi

HASHTYPE=$(cat /mnt/hashes/crackme.type)

# Start Hashcat in a tmux session
session="hashcat"
tmux new-session -d -s $session
window=0
tmux rename-window -t $session:$window 'hashcat'
tmux send-keys -t $session:$window "$HASHCAT -o crackme.cracked -a 0 -m $HASHTYPE crackme $WORDLIST -r $RULES -w 4" C-m

# Check if Hashcat is running
sleep 10
if ! pgrep -x "hashcat.bin" > /dev/null; then
  echo "Error: Hashcat did not start properly" | tee -a /var/log/user_data.log
  exit 1
fi

# Monitor Hashcat process
while true; do
  if ! pgrep -x "hashcat.bin" > /dev/null; then
    echo "Hashcat finished, saving results..." | tee -a /var/log/user_data.log
    cp -f /usr/local/hashcat/hashcat.restore /mnt/hashcat/hashcat.restore
    cp -f /usr/local/hashcat/hashcat.potfile /mnt/hashcat/hashcat.potfile
    cp -f /usr/local/hashcat/hashcat.dictstat2 /mnt/hashcat/hashcat.dictstat2
    cp -f /usr/local/hashcat/hashcat.log /mnt/hashcat/hashcat.log
    shutdown -h now
  fi
  sleep 60
done