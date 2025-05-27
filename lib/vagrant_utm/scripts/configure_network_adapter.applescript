# Usage: osascript configure_network_adapter.applescript UUID adapter_index network_type mac_address device_type [netdev_options]
# Example: osascript configure_network_adapter.applescript 12345678-1234-1234-1234-123456789012 2 bridged 00:11:22:33:44:55 e1000 "ifname=en0"
on run argv
    set vmID to item 1 of argv
    set adapterIndex to item 2 of argv
    set networkType to item 3 of argv
    set macAddress to item 4 of argv
    set deviceType to item 5 of argv
    
    -- Get optional netdev options if provided
    set netdevOptions to ""
    if (count of argv) >= 6 then
        set netdevOptions to item 6 of argv
        if netdevOptions is not "" then
            set netdevOptions to "," & netdevOptions
        end if
    end if
    
    tell application "UTM"
        set vm to virtual machine id vmID
        
        -- Get current configuration
        set config to configuration of vm
        
        -- Get existing QEMU arguments
        set qemuArgs to qemu additional arguments of config
        
        -- Create a unique ID for this network adapter
        set netID to "net" & adapterIndex
        
        -- Create netdev argument based on network type
        set netdevArg to {}
        if networkType is "bridged" then
            set netdevArg to {argument string:"-netdev vmnet-bridged,id=" & netID & netdevOptions}
        else if networkType is "host" then
            set netdevArg to {argument string:"-netdev vmnet-host,id=" & netID & netdevOptions}
        else
            -- Default to shared network
            set netdevArg to {argument string:"-netdev vmnet-shared,id=" & netID & netdevOptions}
        end if
        
        -- Create device argument with MAC address using the provided device type
        set deviceArg to {argument string:"-device " & deviceType & ",mac=" & macAddress & ",netdev=" & netID}
        
        -- Log the arguments we're adding for debugging
        log "Adding netdev: " & (argument string of netdevArg)
        log "Adding device: " & (argument string of deviceArg)
        
        -- Add the new arguments to the existing arguments
        -- The netdev must be added before the device that references it
        set qemu additional arguments of config to qemuArgs & netdevArg & deviceArg
        
        -- Update the VM configuration
        update configuration of vm with config
        
        return "Network interface added successfully with ID: " & netID & " of type: " & networkType & " and MAC: " & macAddress
    end tell
end run
