#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

# Function to show help
fn_show_help() {
    print_cyan "Usage: qlabvmctl delete-disk [OPTIONS]
Options:
  -d, --disks <list>   Comma-separated list of disk files to delete from detached storage
  -h, --help           Show this help message

Examples:
  qlabvmctl delete-disk                         # Interactive mode - select disks
  qlabvmctl delete-disk -d disk1.qcow2,disk2.qcow2  # Delete specific disks

WARNING:
  This permanently deletes disk files from detached storage.
  Deleted disks cannot be recovered!
"
}

# Parse arguments
disks_arg=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            fn_show_help
            exit 0
            ;;
        -d|--disks)
            if [[ -z "$2" || "$2" == -* ]]; then
                print_error "Option -d/--disks requires a value."
                exit 1
            fi
            disks_arg="$2"
            shift 2
            ;;
        -*)
            print_error "Unknown option: $1"
            fn_show_help
            exit 1
            ;;
        *)
            print_error "Unexpected argument: $1"
            print_info "This command does not take positional arguments."
            fn_show_help
            exit 1
            ;;
    esac
done

DETACHED_DIR="/kvm-hub/detached-data-disks"

# Check detached disks directory
if [[ ! -d "$DETACHED_DIR" ]]; then
    print_error "Detached disks directory does not exist: $DETACHED_DIR"
    print_info "No detached disks available to delete."
    exit 1
fi

# Get list of available detached disks
print_info "Scanning detached disks..."
declare -a AVAILABLE_DISKS
while IFS= read -r disk_file; do
    AVAILABLE_DISKS+=("$(basename "$disk_file")")
done < <(sudo find "$DETACHED_DIR" -maxdepth 1 -type f -name "*.qcow2" 2>/dev/null)

if [[ ${#AVAILABLE_DISKS[@]} -eq 0 ]]; then
    print_warning "No detached disks found in $DETACHED_DIR"
    exit 0
fi

# Get disks to delete (from argument or prompt)
declare -a DISKS_TO_DELETE

if [[ -n "$disks_arg" ]]; then
    # Parse comma-separated disk list
    IFS=',' read -ra DISKS_TO_DELETE <<< "$disks_arg"
    
    # Validate each disk
    for disk in "${DISKS_TO_DELETE[@]}"; do
        # Remove whitespace
        disk=$(echo "$disk" | xargs)
        
        # Check if disk exists in detached directory
        if [[ ! -f "$DETACHED_DIR/$disk" ]]; then
            print_error "Disk $disk not found in detached storage: $DETACHED_DIR"
            exit 1
        fi
    done
    print_info "Using specified disks: ${DISKS_TO_DELETE[*]}"
else
    # Interactive mode - show available disks
    print_notify "Available detached disks:"
    for i in "${!AVAILABLE_DISKS[@]}"; do
        disk="${AVAILABLE_DISKS[$i]}"
        disk_path="$DETACHED_DIR/$disk"
        if [[ -f "$disk_path" ]]; then
            disk_size=$(du -h "$disk_path" | awk '{print $1}')
            echo "  $((i+1))) $disk ($disk_size)"
        else
            echo "  $((i+1))) $disk"
        fi
    done
    echo "  q) Quit"
    
    print_info "Enter disk numbers to delete (space-separated, e.g., '1 3' or 'all' for all disks):"
    read -rp "Selection: " selection
    
    if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
        print_info "Quitting without any action."
        exit 0
    fi
    
    if [[ "$selection" == "all" || "$selection" == "ALL" ]]; then
        DISKS_TO_DELETE=("${AVAILABLE_DISKS[@]}")
        print_info "Selected all disks: ${DISKS_TO_DELETE[*]}"
    else
        # Parse space-separated numbers
        for num in $selection; do
            if [[ ! "$num" =~ ^[0-9]+$ ]]; then
                print_error "Invalid selection: $num"
                exit 1
            fi
            idx=$((num - 1))
            if (( idx < 0 || idx >= ${#AVAILABLE_DISKS[@]} )); then
                print_error "Invalid disk number: $num"
                exit 1
            fi
            DISKS_TO_DELETE+=("${AVAILABLE_DISKS[$idx]}")
        done
        print_info "Selected disks: ${DISKS_TO_DELETE[*]}"
    fi
fi

# Confirm deletion
print_warning "WARNING: The following disk(s) will be PERMANENTLY DELETED:"
for disk in "${DISKS_TO_DELETE[@]}"; do
    disk_path="$DETACHED_DIR/$disk"
    if [[ -f "$disk_path" ]]; then
        disk_size=$(du -h "$disk_path" | awk '{print $1}')
        echo "  - $disk ($disk_size) at $disk_path"
    else
        echo "  - $disk at $disk_path"
    fi
done

print_error "This action CANNOT be undone!"
read -rp "Type 'DELETE' in uppercase to confirm permanent deletion: " confirm
if [[ "$confirm" != "DELETE" ]]; then
    print_info "Operation cancelled."
    exit 0
fi

# Delete disks
deleted_count=0
for disk in "${DISKS_TO_DELETE[@]}"; do
    disk_path="$DETACHED_DIR/$disk"
    
    print_task "Deleting $disk..." nskip
    if error_msg=$(sudo rm -f "$disk_path" 2>&1); then
        print_task_done
        ((deleted_count++))
    else
        print_task_fail
        print_error "$error_msg"
        continue
    fi
done

if [[ $deleted_count -eq 0 ]]; then
    print_error "Failed to delete any disks."
    exit 1
fi

print_success "Permanently deleted $deleted_count disk(s) from detached storage."
print_info "Deleted disks cannot be recovered."
