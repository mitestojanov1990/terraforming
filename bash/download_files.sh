#!/bin/bash

sudo apt-get install -y sshpass
# Create backups directory if it doesn't exist
mkdir -p ~/backups
cd ~/backups

# Connect to the FTP server and download all .zip files
sshpass -p 'thepass' sftp -oBatchMode=no -b - awesome@awesome.ftp <<EOF
mget *.zip
bye
EOF
