#!/bin/bash

# Set variables
REPO_PATH="/etc/bind/blocklists" # Path to your Git repository
DOMAIN_TO_TEST="xxx.com" # Domain to test the blocklist effectiveness
LOG_FILE="/var/log/named/blocklist_error.log" # Temporary log file for errors

# Change directory to the repository
cd "$REPO_PATH" || { echo "Failed to change directory. Exiting..."; exit 1; }

# Pull the latest changes from the Git repository
git reset --hard HEAD
git clean -f -d
git pull origin main # Change 'main' if your branch name is different

# Function to check for DNS resolution
check_dns_resolution() {
    IP=$(kdig +short @"$(hostname)" "$DOMAIN_TO_TEST" A)
    if [[ -z "$IP" ]]; then
        echo "Blocklist is working. No IP returned for $DOMAIN_TO_TEST."
        return 0 # Success
    else
        echo "Blocklist failed. IP returned for $DOMAIN_TO_TEST: $IP" | tee -a "$LOG_FILE"
        return 1 # Failure
    fi
}

# Calculate total number of commits
TOTAL_COMMITS=$(git rev-list --count HEAD)

# Attempt to reconfigure and rollback on failure
while [ $TOTAL_COMMITS -gt 1 ]; do
    # Attempt to reconfigure BIND
    rndc reconfig 2>> "$LOG_FILE"
    if [ $? -eq 0 ]; then
        # Check if the blocklist is effective
        if check_dns_resolution; then
            echo "Configuration and blocklist are effective."
            [[ -s "$LOG_FILE" ]] && mv "$LOG_FILE" "$REPO_PATH" # Move log file to the repository root directory
            exit 0
        fi
    else
        echo "rndc reconfig failed, error logged. Rolling back to the previous commit..." | tee -a "$LOG_FILE"   
    fi
    git reset --hard HEAD~1
    ((TOTAL_COMMITS--))
done

echo "Reached the initial commit or failed to reconfigure successfully. Manual investigation required. Logs are in $LOG_FILE."
