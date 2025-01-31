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
HOST=$(hostname)

# WORDLIST_URL="https://weakpass.com/download/1944/xsukax-Wordlist-All.7z"
# WORDLIST_DIR="/mnt/wordlists"
# WORDLIST_FILE="xsukax-Wordlist-All.txt"

# Update package list
sudo apt-get update && sudo apt-get install -y jq wget p7zip-full tmux awscli

# Install necessary dependencies and NVIDIA driver
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y ppa:graphics-drivers/ppa
sudo apt-get update

# Clean up any broken packages and fix dependencies
sudo apt-get --fix-broken install -y
sudo apt-get install -f -y
sudo apt-get autoremove -y

# Download and extract Hashcat
cd $TMP || exit
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

# Create directories
# sudo mkdir -p $WORDLIST_DIR
# sudo mkdir -p $HASHES
sudo mkdir -p /mnt/hashcat

# Restore previous session if exists
if [ -e /mnt/hashcat ]; then
    cp -f /mnt/hashcat/hashcat.restore /usr/local/hashcat/hashcat.restore 2>/dev/null || true
    cp -f /mnt/hashcat/hashcat.potfile /usr/local/hashcat/hashcat.potfile 2>/dev/null || true
    cp -f /mnt/hashcat/hashcat.dictstat2 /usr/local/hashcat/hashcat.dictstat2 2>/dev/null || true
    cp -f /mnt/hashcat/hashcat.log /usr/local/hashcat/hashcat.log 2>/dev/null || true
fi

# Start Hashcat in a tmux session
session="hashcat"
tmux new-session -d -s $session || true
window=0
tmux rename-window -t $session:$window 'hashcat' || true

# Create a script to run hashcat examples sequentially
cat > /tmp/run_hashcat.sh << 'EOF'
#!/bin/bash

# Change to hashcat directory
cd /usr/local/hashcat || exit 1

# Make example scripts executable
chmod +x example*.sh

# Run examples in sequence
for script in example0.sh example400.sh example500.sh; do
    echo "Running $script..."
    ./$script
    
    # Check if script executed successfully
    if [ $? -eq 0 ]; then
        echo "$script completed successfully"
    else
        echo "$script failed with exit code $?"
        exit 1
    fi
done

echo "All examples completed"
EOF

# Make the script executable
chmod +x /tmp/run_hashcat.sh

# Execute in tmux session
tmux send-keys -t $session:$window "/tmp/run_hashcat.sh" Enter

# Monitor Hashcat process
while true; do
    if ! pgrep -x "hashcat.bin" > /dev/null; then
        echo "Hashcat finished, saving results..." | tee -a /var/log/user_data.log
        cp -f /usr/local/hashcat/hashcat.restore /mnt/hashcat/hashcat.restore 2>/dev/null || true
        cp -f /usr/local/hashcat/hashcat.potfile /mnt/hashcat/hashcat.potfile 2>/dev/null || true
        cp -f /usr/local/hashcat/hashcat.dictstat2 /mnt/hashcat/hashcat.dictstat2 2>/dev/null || true
        cp -f /usr/local/hashcat/hashcat.log /mnt/hashcat/hashcat.log 2>/dev/null || true
        shutdown -h now
    fi
    sleep 60
done
