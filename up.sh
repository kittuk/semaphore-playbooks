#!/usr/bin/env bash
# System Update Script (upd8)
# Performs full system update, housekeeping, and optional Docker maintenance

# Enable strict error handling
set -Eeuo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'         # Set field separator to newline and tab

# Record start time for elapsed time calculation
start_time=$(date +%s)

# Colors (only if stdout is a TTY)
if [[ -t 1 ]]; then
    RED="$(printf '\033[0;31m')"
    GREEN="$(printf '\033[0;32m')"
    YELLOW="$(printf '\033[0;33m')"
    BOLD="$(printf '\033[1m')"
    NC="$(printf '\033[0m')"
else
    # No colors if output is redirected/piped
    RED=""; GREEN=""; YELLOW=""; BOLD=""; NC=""
fi

# Suppress interactive prompts for apt and needrestart
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Logging helper functions
log() { printf "%s%s%s\n" "$BOLD" "$*" "$NC"; }
ok()  { printf "%s✓ %s%s\n\n" "$GREEN" "$*" "$NC"; }
err() { printf "%s✗ %s%s\n\n" "$RED" "$*" "$NC" >&2; }
warn() { printf "%s⚠ %s%s\n" "$YELLOW" "$*" "$NC"; }

# Prompt user to continue after a failure
ask_continue() {
    local ans
    read -r -p "Last command failed. Continue? (y/N) " ans || true
    [[ "$ans" =~ ^[Yy] ]] || exit 1
}

# Execute a command with logging and error handling
run() {
    local desc="$1"; shift
    log "==> $desc"
    if "$@"; then
        ok "$desc complete"
    else
        err "$desc failed"
        ask_continue
    fi
}

# Display welcome message
greeting() {
    echo
    echo "Hello, ktowning. Let's update this system."
    printf "\e[1;42m %s \e[0m\n\n" "$HOSTNAME"
}

# Perform system package updates
update() {
    run "Update package lists" sudo apt-get -qq update
    run "Full upgrade" sudo apt-get -y dist-upgrade
    ok "System update complete"
}

# Clean up system files and old packages
housekeeping() {
    log "Starting housekeeping tasks..."

    # Remove packages that were automatically installed and are no longer needed
    run "Autoremove unused packages" sudo apt-get -y autoremove --purge
    
    # Clean up obsolete .deb files from cache
    run "Autoclean APT cache" sudo apt-get -y autoclean
    
    # Remove all .deb files from cache
    run "Clean APT cache" sudo apt-get clean

    # Keep only last 7 days of journal logs
    if command -v journalctl >/dev/null 2>&1; then
        run "Vacuum journal logs" sudo journalctl --vacuum-time=7d
    fi

    # Update mlocate/plocate database
    if command -v updatedb >/dev/null 2>&1; then
        run "Update file database" sudo updatedb
    fi

    # Remove old rotated/compressed log files
    run "Remove old compressed logs" sudo find /var/log -type f -name '*.gz' -delete

    # Clean thumbnail cache in user's home directory
    if [[ -d "$HOME/.cache/thumbnails" ]]; then
        run "Clean thumbnail cache" rm -rf "${HOME:?}/.cache/thumbnails/"*
    fi

    # Remove files older than 7 days from temporary directories
    run "Clean /tmp" sudo find /tmp -mindepth 1 -maxdepth 1 -mtime +7 -exec rm -rf {} +
    run "Clean /var/tmp" sudo find /var/tmp -mindepth 1 -maxdepth 1 -mtime +7 -exec rm -rf {} +

    # Remove old kernel versions (keep only the current one)
    if command -v dpkg >/dev/null 2>&1; then
        # Get current kernel version and escape dots for regex
        local current_kernel
        current_kernel="$(uname -r | sed 's/\./\\./g')"
        
        # Find all installed kernel images except the current one
        local old_kernels
        old_kernels=$(dpkg --list 'linux-image-*' 2>/dev/null \
            | awk '/^ii/ && /[0-9]/{print $2}' \
            | grep -E 'linux-image-[0-9]' \
            | grep -v "$current_kernel" || true)
        
        # Purge old kernels if any were found
        if [[ -n "${old_kernels:-}" ]]; then
            # shellcheck disable=SC2086
            run "Purge old kernels" sudo apt-get -y purge $old_kernels
        fi
    fi

    ok "Housekeeping complete"
}

# Check if reboot is required and optionally reboot
check_reboot() {
    echo
    if [[ -f /var/run/reboot-required ]]; then
        warn "Reboot required!"
        
        # Show which packages require a reboot
        if [[ -f /var/run/reboot-required.pkgs ]]; then
            echo "Packages requiring reboot:"
            cat /var/run/reboot-required.pkgs
        fi
        
        # Prompt user to reboot now
        local ans
        read -r -p "Reboot now? (y/N) " ans || true
        if [[ "$ans" =~ ^[Yy] ]]; then
            printf "\e[1;42m Restarting %s \e[0m\n" "$HOSTNAME"
            sleep 2
            sudo reboot
        fi
    else
        ok "No reboot required"
    fi
}

# Perform Docker container and image maintenance
mydocker() {
    # Look for host-specific compose file
    local compose_file="$HOME/docker/docker-compose-$HOSTNAME.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        warn "No docker compose file: $compose_file"
        return 0
    fi
    
    if ! command -v docker >/dev/null 2>&1; then
        warn "docker not installed"
        return 0
    fi

    log "Docker maintenance starting..."
    
    # Ensure all filesystems are mounted (for Docker volumes)
    run "Mount all filesystems" sudo mount -a
    
    # Stop all containers
    run "docker compose down" sudo docker compose --profile all -f "$compose_file" down
    
    sleep 2
    
    # Remove unused images, containers, and volumes
    run "docker system prune" sudo docker system prune -a -f
    
    # Pull latest images
    run "docker compose pull" sudo docker compose --profile all -f "$compose_file" pull
    
    # Start containers with updated images
    run "docker compose up" sudo docker compose --profile all -f "$compose_file" up -d --remove-orphans
    
    # Display Docker disk usage
    log "Docker system usage:"
    sudo docker system df
    
    ok "Docker maintenance complete"
}

# Display summary of update session
print_summary() {
    # Calculate elapsed time
    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "\e[1;42m Update Complete! \e[0m\n"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    # Show elapsed time in seconds and minutes
    printf "\e[1;42m Time Elapsed \e[0m %d seconds (%d min %d sec)\n" \
        "$elapsed" "$((elapsed / 60))" "$((elapsed % 60))"
    
    # Show current date/time
    printf "\e[1;42m Date \e[0m %s\n" "$(date)"
    
    # Show system uptime
    printf "\e[1;42m Uptime \e[0m %s\n" "$(uptime -p 2>/dev/null || uptime)"
    
    # Show memory usage
    printf "\e[1;42m Memory \e[0m\n"
    free -h
    
    # Show network information for default interface
    printf "\e[1;42m Network \e[0m\n"
    local default_if
    default_if="$(ip route show default 2>/dev/null | awk '{print $5; exit}')"
    if [[ -n "${default_if:-}" ]]; then
        ip -f inet -br a show "$default_if"
    else
        ip -f inet -br a
    fi
    echo
}

# Main execution flow
main() {
    greeting
    
    # Step 1: Update system packages
    log "Starting system update..."
    update
    
    # Step 2: Clean up system
    log "Running housekeeping..."
    housekeeping
    
    # Step 3: Run custom cleanup if available
    if [[ -x "$HOME/bin/cleanup.sh" ]]; then
        log "Running custom cleanup script..."
        "$HOME/bin/cleanup.sh" || warn "Custom cleanup script failed"
    fi
    
    # Step 4: Docker maintenance (commented out by default)
    # log "Docker maintenance..."
    # mydocker
    
    # Step 5: Check if reboot is needed
    check_reboot
    
    # Step 6: Display summary
    print_summary
}

# Run main function with all script arguments
main "$@"
