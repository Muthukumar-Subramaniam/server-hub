#!/bin/bash
#
# Migrate existing zone files to new template format
# Preserves all DNS records while updating SOA header
#

set -e

ZONE_DIR="/var/named/dnsbinder-managed-zone-files"
TEMPLATE="/server-hub/named-manage/zone-header.template"
BACKUP_DIR="/var/named/dnsbinder-zone-backups-$(date +%Y%m%d_%H%M%S)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Starting zone file migration...${NC}"

# Create backup directory
echo -e "${YELLOW}Creating backup: ${BACKUP_DIR}${NC}"
mkdir -p "${BACKUP_DIR}"
cp -a "${ZONE_DIR}"/*.db "${BACKUP_DIR}/"
echo -e "${GREEN}✓ Backup completed${NC}"

# Function to migrate a single zone file
migrate_zone_file() {
    local zone_file="$1"
    local zone_name=$(basename "$zone_file" .db)
    
    echo -e "${YELLOW}Processing: ${zone_name}${NC}"
    
    # Check if already migrated (Unix timestamp is 10 digits starting with 1 or 2)
    local current_serial=$(grep ";Serial" "$zone_file" | awk '{print $1}')
    if [[ "$current_serial" =~ ^[12][0-9]{9}$ ]]; then
        echo -e "${GREEN}✓ Already migrated (Serial: ${current_serial})${NC}"
        return 0
    fi
    
    # Extract domain info from zone file
    local dns_host_short=$(grep "^@.*SOA" "$zone_file" | awk '{print $4}' | cut -d'.' -f1)
    local dns_domain=$(grep "^@.*SOA" "$zone_file" | awk '{print $4}' | cut -d'.' -f2- | sed 's/\.$//')
    
    # Generate new serial (Unix timestamp)
    local new_serial=$(date +%s)
    
    # Find where actual DNS records start (after SOA block and NS record)
    # Skip old NS record section and start from A-Records, AAAA-Records, PTR-Records, etc.
    local records_start_line=$(grep -n -E "^;(A|AAAA|PTR|CNAME)-Records" "$zone_file" | head -1 | cut -d':' -f1)
    
    if [ -z "$records_start_line" ]; then
        # Fallback: look for first actual DNS record (A, AAAA, PTR, or CNAME)
        records_start_line=$(grep -n -E "^[^;@].*IN.*(A|AAAA|PTR|CNAME)" "$zone_file" | head -1 | cut -d':' -f1)
    fi
    
    # Create temporary new zone file
    local temp_file="${zone_file}.new"
    
    # Generate new header from template (includes SOA and NS record)
    sed "s/DNS_HOST_SHORT_NAME/${dns_host_short}/g; s/DNS_DOMAIN/${dns_domain}/g; s/0000000000/${new_serial}/g" \
        "${TEMPLATE}" > "${temp_file}"
    
    # Append existing DNS records (skip old SOA header and old NS record - template has new ones)
    if [ -n "$records_start_line" ]; then
        tail -n +${records_start_line} "$zone_file" >> "${temp_file}"
    else
        echo -e "${RED}Warning: Could not detect records in ${zone_name}, skipping${NC}"
        rm -f "${temp_file}"
        return 1
    fi
    
    # Replace old zone file
    mv "${temp_file}" "${zone_file}"
    
    echo -e "${GREEN}✓ Migrated: ${zone_name} (Serial: ${new_serial})${NC}"
}

# Migrate all zone files
migrated_count=0
skipped_count=0

for zone_file in "${ZONE_DIR}"/*.db; do
    if [ -f "$zone_file" ]; then
        # Check if already migrated before calling function
        current_serial=$(grep ";Serial" "$zone_file" | awk '{print $1}')
        if [[ "$current_serial" =~ ^[12][0-9]{9}$ ]]; then
            skipped_count=$((skipped_count + 1))
        else
            migrated_count=$((migrated_count + 1))
        fi
        migrate_zone_file "$zone_file"
    fi
done

echo ""
if [ $migrated_count -gt 0 ]; then
    echo -e "${GREEN}Migration completed: ${migrated_count} zone(s) migrated, ${skipped_count} already up-to-date${NC}"
else
    echo -e "${GREEN}All zones already up-to-date (${skipped_count} zone(s))${NC}"
fi
echo -e "${YELLOW}Backup location: ${BACKUP_DIR}${NC}"
echo ""

# Always validate all zones (whether migrated or not)
echo -e "${YELLOW}Validating all zone files...${NC}"
validation_failed=0

for zone_file in "${ZONE_DIR}"/*.db; do
    zone_name=$(basename "$zone_file" .db)
    
    case "$zone_name" in
        *-forward)
            domain="${zone_name%-forward}"
            if named-checkzone "$domain" "$zone_file" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ Valid: $domain${NC}"
            else
                echo -e "${RED}✗ Invalid: $domain${NC}"
                validation_failed=1
            fi
            ;;
        *-reverse)
            octets=$(echo "$zone_name" | grep -oP "^\d+\.\d+\.\d+" | awk -F. '{print $3"."$2"."$1}')
            if named-checkzone "$octets.in-addr.arpa" "$zone_file" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ Valid: $octets.in-addr.arpa${NC}"
            else
                echo -e "${RED}✗ Invalid: $octets.in-addr.arpa${NC}"
                validation_failed=1
            fi
            ;;
        *-ipv6-reverse)
            ipv6_zone=$(grep "ip6.arpa" /etc/named.conf | grep -v "^#" | cut -d'"' -f2 | head -1)
            if [ -n "$ipv6_zone" ]; then
                if named-checkzone "$ipv6_zone" "$zone_file" >/dev/null 2>&1; then
                    echo -e "${GREEN}✓ Valid: $ipv6_zone${NC}"
                else
                    echo -e "${RED}✗ Invalid: $ipv6_zone${NC}"
                    validation_failed=1
                fi
            fi
            ;;
    esac
done

echo ""

if [ $validation_failed -eq 1 ]; then
    echo -e "${RED}Zone validation failed! Not reloading DNS.${NC}"
    echo -e "${YELLOW}To restore from backup: cp ${BACKUP_DIR}/*.db ${ZONE_DIR}/${NC}"
    exit 1
fi

echo -e "${GREEN}All zones validated successfully!${NC}"
echo ""

# Reload DNS service
echo -e "${YELLOW}Reloading DNS service...${NC}"
if systemctl reload named >/dev/null 2>&1; then
    echo -e "${GREEN}✓ DNS service reloaded successfully${NC}"
else
    echo -e "${RED}✗ Failed to reload DNS service${NC}"
    echo -e "${YELLOW}Restore from backup: cp ${BACKUP_DIR}/*.db ${ZONE_DIR}/${NC}"
    echo -e "${YELLOW}Then: systemctl reload named${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Migration and DNS reload completed successfully!${NC}"
echo ""
