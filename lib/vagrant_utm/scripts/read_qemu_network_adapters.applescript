on run argv
    set vmID to item 1 of argv
    
    log "Script started with VM ID: " & vmID
    
    try
        tell application "UTM"
            log "Connected to UTM application"
            set vm to virtual machine id vmID
            log "Found VM with ID: " & vmID
            set config to configuration of vm
            log "Got VM configuration"
            set qemuArgs to qemu additional arguments of config
            log "Got QEMU args, count: " & (count of qemuArgs)
            
            repeat with i from 1 to count of qemuArgs
                set anArg to item i of qemuArgs
                set argString to argument string of anArg
                log "Arg " & i & ": " & argString
                
                -- Check for netdev arguments
                if argString starts with "-netdev" then
                    -- Extract the netdev ID from the argument
                    -- Format: -netdev vmnet-bridged,id=net2,ifname=en0
                    set AppleScript's text item delimiters to ","
                    set argParts to text items of argString
                    repeat with part in argParts
                        if part starts with "id=" then
                            set netdevID to text 4 thru -1 of part
                            log "netdev:" & netdevID
                            exit repeat
                        end if
                    end repeat
                    set AppleScript's text item delimiters to ""
                end if
                
                -- Check for device arguments
                if argString starts with "-device" and argString contains "netdev=" then
                    -- Extract the netdev reference from the device argument
                    -- Format: -device virtio-net-pci,mac=XX:XX:XX:XX:XX:XX,netdev=net2
                    set AppleScript's text item delimiters to ","
                    set argParts to text items of argString
                    repeat with part in argParts
                        if part starts with "netdev=" then
                            set netdevRef to text 8 thru -1 of part
                            log "device:" & netdevRef
                            exit repeat
                        end if
                    end repeat
                    set AppleScript's text item delimiters to ""
                end if
            end repeat
            
            log "Script completed successfully"
        end tell
    on error errMsg
        log "Error in script: " & errMsg
    end try
end run
