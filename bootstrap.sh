#!/bin/bash

# Enable logging for debugging
exec > /var/log/user_data.log 2>&1
set -x

# Variables
TMP=/tmp
HOST=$(hostname)
HASHCAT_DIR=/usr/local/hashcat
HASHCAT=$HASHCAT_DIR/hashcat.bin
BACKUP_DIR=/mnt/hashcat

# Update and install required packages
sudo apt-get update && sudo apt-get install -y \
    jq \
    wget \
    p7zip-full \
    tmux \
    awscli \
    software-properties-common

# Add and update NVIDIA drivers repository
sudo add-apt-repository -y ppa:graphics-drivers/ppa
sudo apt-get update

# Clean up package system
sudo apt-get --fix-broken install -y
sudo apt-get install -f -y
sudo apt-get autoremove -y

# Download and setup Hashcat
cd $TMP || exit
curl -s https://api.github.com/repos/hashcat/hashcat/releases/latest | \
    jq -r '.assets[] | select(.name|endswith(".7z")) | .browser_download_url' | wget -i -
7zr x hashcat*.7z
rm -f hashcat*.7z
mv -f /tmp/hashcat* $HASHCAT_DIR
chmod -R 755 $HASHCAT_DIR

# Verify NVIDIA GPU
if ! nvidia-smi >> /var/log/nvidia-gpu-check.log 2>&1; then
    echo "Error: NVIDIA GPU not detected or drivers not installed properly." | tee -a /var/log/user_data.log
    exit 1
fi

# Create backup directory and restore previous session files
mkdir -p $BACKUP_DIR
if [ -e $BACKUP_DIR ]; then
    for file in hashcat.restore hashcat.potfile hashcat.dictstat2 hashcat.log; do
        cp -f $BACKUP_DIR/$file $HASHCAT_DIR/$file 2>/dev/null || true
    done
fi

# Create hashcat example runner script
cat > /tmp/run_hashcat.sh << 'EOF'
#!/bin/bash

cd /usr/local/hashcat || exit 1

# Make example scripts executable
chmod +x example*.sh

# Run examples in sequence
for script in example0.sh example400.sh example500.sh; do
    echo "Starting $script at $(date)"
    ./$script
    result=$?
    
    if [ $result -eq 0 ]; then
        echo "$script completed successfully at $(date)"
    else
        echo "$script failed with exit code $result at $(date)"
        exit 1
    fi
    
    # Brief pause between examples
    sleep 5
done

echo "All examples completed successfully at $(date)"
EOF

chmod +x /tmp/run_hashcat.sh

# Start tmux session and run examples
session="hashcat"
tmux new-session -d -s $session || true
tmux rename-window -t $session:0 'hashcat' || true
tmux send-keys -t $session:0 "/tmp/run_hashcat.sh" Enter

# Monitor and backup
while true; do
    if ! pgrep -x "hashcat.bin" > /dev/null; then
        echo "Hashcat finished, saving results..." | tee -a /var/log/user_data.log
        
        # Backup final results
        for file in hashcat.restore hashcat.potfile hashcat.dictstat2 hashcat.log; do
            cp -f $HASHCAT_DIR/$file $BACKUP_DIR/$file 2>/dev/null || true
        done
        
        # Shutdown system
        # shutdown -h now
    fi
    sleep 60
done
