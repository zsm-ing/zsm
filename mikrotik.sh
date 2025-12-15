# China IP List Updater v3.0 (RouterOS Compatible)
# Fixes all known syntax errors
# Supports RouterOS v6.45+ (recommended v7.x+)

# ============= Configuration =============
:local listNameV4 "CN"
:local listNameV6 "CN"
:local ipv4Source "https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt"
:local ipv6Source "https://raw.githubusercontent.com/ChanthMiao/China-IPv6-List/release/cn6.txt"
:local maxEntriesPerRun 80
# =========================================

# Main function
:local updateChinaIPList do={
    :log info "Starting China IP list update..."
    
    # Create temp files
    :local ipv4File ("ipv4_" . [/system identity get name] . ".tmp")
    :local ipv6File ("ipv6_" . [/system identity get name] . ".tmp")
    
    # Download IPv4 list
    :log info "Downloading IPv4 list..."
    /tool fetch url=$ipv4Source dst-path=$ipv4File
    
    # Download IPv6 list
    :log info "Downloading IPv6 list..."
    /tool fetch url=$ipv6Source dst-path=$ipv6File
    
    # Process IPv4
    :log info "Processing IPv4 addresses..."
    /ip firewall address-list remove [find list=$listNameV4]
    :delay 2s;
    :local ipv4Content [/file get $ipv4File contents]
    :local ipv4Lines [:toarray $ipv4Content]
    :local ipv4Count 0
    
    :foreach line in=$ipv4Lines do={
        :if ([:len $line] > 7 && [:pick $line 0 1] != "#") do={
            /ip firewall address-list add address=$line list=$listNameV4
            :set ipv4Count ($ipv4Count + 1)
            :if ($ipv4Count % $maxEntriesPerRun = 0) do={
                :log info ("Processed $ipv4Count IPv4 entries")
                :delay 0.5s
            }
        }
    }
    :log info ("IPv4 done: $ipv4Count entries")
    
    # Process IPv6 (RouterOS v7+ required)
    :log info "Processing IPv6 addresses..."
    /ipv6 firewall address-list remove [find list=$listNameV6]
    :delay 2s;
    :local ipv6Content [/file get $ipv6File contents]
    :local ipv6Lines [:toarray $ipv6Content]
    :local ipv6Count 0
    
    :foreach line in=$ipv6Lines do={
        :if ([:len $line] > 7 && [:pick $line 0 1] != "#") do={
            /ipv6 firewall address-list add address=$line list=$listNameV6
            :set ipv6Count ($ipv6Count + 1)
            :if ($ipv6Count % $maxEntriesPerRun = 0) do={
                :log info ("Processed $ipv6Count IPv6 entries")
                :delay 0.5s
            }
        }
    }
    :log info ("IPv6 done: $ipv6Count entries")
    
    # Cleanup
    /file remove [find name=$ipv4File]
    /file remove [find name=$ipv6File]
    
    :log info "China IP lists updated successfully!"
    :log info "IPv4: $ipv4Count, IPv6: $ipv6Count"
}

# Execute with error handling
:do {
    updateChinaIPList
} on-error={
    :log error "Update failed: $error"
}
