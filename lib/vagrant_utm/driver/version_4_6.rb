# frozen_string_literal: true

require File.expand_path("version_4_5", __dir__)

module VagrantPlugins
  module Utm
    module Driver
      # Driver for UTM 4.6.x
      class Version_4_6 < Version_4_5 # rubocop:disable Naming/ClassAndModuleCamelCase
        def initialize(uuid)
          super

          @logger = Log4r::Logger.new("vagrant::provider::utm::version_4_6")
        end

        # Implement clear_shared_folders
        def clear_shared_folders
          # Get the list of shared folders
          shared_folders = read_shared_folders
          # Get the args to remove the shared folders
          script_path = @script_path.join("read_shared_folders_args.js")
          cmd = ["osascript", script_path.to_s, @uuid, "--ids", shared_folders.join(",")]
          output = execute_shell(*cmd)
          result = JSON.parse(output)
          return unless result["status"]

          # Flatten the list of args and build the command
          sf_args = result["result"].flatten
          return unless sf_args.any?

          command = ["remove_qemu_additional_args.applescript", @uuid, "--args", *sf_args]
          execute_osa_script(command)
        end

        def import(utm)
          utm = Vagrant::Util::Platform.windows_path(utm)

          vm_id = nil

          command = ["import_vm.applescript", utm]
          output = execute_osa_script(command)

          @logger.debug("Import output: #{output}")

          # Check if we got the VM ID
          if output =~ /virtual machine id ([A-F0-9-]+)/
            vm_id = ::Regexp.last_match(1) # Capture the VM ID
          end

          vm_id
        end

        def export(path)
          @logger.debug("Exporting UTM file to: #{path}")
          command = ["export_vm.applescript", @uuid, path]
          execute_osa_script(command)
        end

        def read_shared_folders
          @logger.debug("Reading shared folders")
          script_path = @script_path.join("read_shared_folders.js")
          cmd = ["osascript", script_path.to_s, @uuid]
          output = execute_shell(*cmd)
          result = JSON.parse(output)
          return unless result["status"]

          # Return the list of shared folders names(id)
          result["result"]
        end

        def share_folders(folders)
          # sync folder cleanup will call clear_shared_folders
          # This is just a precaution, to make sure we don't
          # have duplicate shared folders
          shared_folders = read_shared_folders
          @logger.debug("Shared folders: #{shared_folders}")
          @logger.debug("Sharing folders: #{folders}")

          folders.each do |folder|
            # Skip if the folder is already shared
            next if shared_folders.include?(folder[:name])

            args = ["--id", folder[:name],
                    "--dir", folder[:hostpath]]
            command = ["add_folder_share.applescript", @uuid, *args]
            execute_osa_script(command)
          end
        end

        def unshare_folders(folders)
          @logger.debug("Unsharing folder: #{folder[:name]}")
          # Get the args to remove the shared folders
          script_path = @script_path.join("read_shared_folders_args.js")
          cmd = ["osascript", script_path.to_s, @uuid, "--ids", folders.join(",")]
          output = execute_shell(*cmd)
          result = JSON.parse(output)
          return unless result["status"]

          # Flatten the list of args and build the command
          sf_args = result["result"].flatten
          return unless sf_args.any?

          command = ["remove_qemu_additional_args.applescript", @uuid, "--args", *sf_args]
          execute_osa_script(command)
        end

        def read_qemu_network_adapters
          @logger.debug("Reading existing QEMU network adapters")
          command = ["read_qemu_network_adapters.applescript", @uuid]
          output = execute_osa_script(command)
          
          @logger.debug("Raw AppleScript output: #{output.inspect}")
          
          adapters = {}
          output.split("\n").each do |line|
            line = line.strip
            @logger.debug("Processing line: #{line.inspect}")
            
            if line.start_with?("netdev:")
              net_id = line.split(":")[1]
              @logger.debug("Found netdev: #{net_id}")
              adapters[net_id] = { netdev: true }
            elsif line.start_with?("device:")
              net_id = line.split(":")[1]
              @logger.debug("Found device: #{net_id}")
              adapters[net_id] ||= {}
              adapters[net_id][:device] = true
            end
          end
          
          @logger.debug("Found QEMU network adapters: #{adapters}")
          adapters
        end

        def clear_additional_network_adapters
          @logger.info("Clearing additional network adapters (preserving base adapters 0,1)")
          
          # Get all existing QEMU network adapters
          existing_adapters = read_qemu_network_adapters
          
          # Find adapters to remove (anything except net0 and net1)
          adapters_to_remove = existing_adapters.keys.reject { |net_id| ["net0", "net1"].include?(net_id) }
          
          if adapters_to_remove.empty?
            @logger.info("No additional network adapters to remove")
            return
          end
          
          @logger.info("Removing additional network adapters: #{adapters_to_remove.join(', ')}")
          
          # Get the raw output to find the exact QEMU arguments
          command = ["read_qemu_network_adapters.applescript", @uuid]
          output = execute_osa_script(command)
          
          # Parse the output to find exact QEMU arguments that contain our net IDs
          args_to_remove = []
          output.split("\n").each do |line|
            line = line.strip
            # Look for lines that show the actual QEMU arguments (format: "Arg X: -netdev ...")
            if line.match(/^Arg \d+: (.+)$/)
              arg_content = $1
              # Check if this argument contains any of our net IDs to remove
              adapters_to_remove.each do |net_id|
                if arg_content.include?(net_id)
                  args_to_remove << arg_content
                  @logger.debug("Found argument to remove: #{arg_content}")
                end
              end
            end
          end
          
          # Remove the arguments using the existing script
          unless args_to_remove.empty?
            @logger.info("Removing #{args_to_remove.length} QEMU arguments")
            command = ["remove_qemu_additional_args.applescript", @uuid, "--args"] + args_to_remove
            output = execute_osa_script(command)
            @logger.debug("Remove network adapters output: #{output}")
          end
          
          @logger.info("Finished clearing additional network adapters")
        end

        def add_network_adapter(adapter_index, network_type, network_config)
          @logger.info("Adding network adapter #{adapter_index} of type #{network_type}")
          
          # Create a unique ID for this network adapter
          net_id = "net#{adapter_index}"
          
          # Check if this adapter already exists
          existing_adapters = read_qemu_network_adapters
          if existing_adapters[net_id] && existing_adapters[net_id][:netdev] && existing_adapters[net_id][:device]
            @logger.info("Network adapter #{net_id} already exists, skipping")
            return
          end
          
          # Convert network type to UTM's network mode
          utm_mode = case network_type
                     when :host_only
                       "host"
                     when :bridged
                       "bridged" 
                     when :internal
                       "host"  # UTM doesn't have a separate internal mode
                     else
                       "shared"  # Default to shared/NAT
                     end

          # Get MAC address from config or generate a random one
          # Handle "auto" value by generating a random MAC address
          mac_address = if network_config[:mac].nil? || network_config[:mac] == "auto"
                          random_mac_address
                        else
                          network_config[:mac]
                        end
          
          # Prepare additional netdev options
          netdev_options = ""
          
          # For bridged networks, we need to specify the interface name
          if network_type == :bridged
            # Use the bridge parameter if specified, otherwise default to en0
            bridge = network_config[:bridge] || "en0"
            netdev_options = ",ifname=#{bridge}"
          end
          
          # Get device type from config or use appropriate default based on network type
          device_type = network_config[:device_type]
          if device_type.nil?
            device_type = (network_type == :bridged) ? "virtio-net-pci" : "e1000"
          end
          
          # Build the QEMU arguments
          netdev_arg = "-netdev vmnet-#{utm_mode},id=#{net_id}#{netdev_options}"
          device_arg = "-device #{device_type},mac=#{mac_address},netdev=#{net_id}"
          
          @logger.debug("Adding netdev: #{netdev_arg}")
          @logger.debug("Adding device: #{device_arg}")
          
          # Use the existing add_qemu_additional_args script to add both arguments
          command = ["add_qemu_additional_args.applescript", @uuid, "--args", netdev_arg, device_arg]
          output = execute_osa_script(command)
          @logger.debug("AppleScript output: #{output}")
        end

        def ensure_network_adapter_exists(adapter_index, network_type)
          @logger.info("Ensuring network adapter #{adapter_index} (#{network_type}) exists")
          
          # Create a unique ID for this network adapter
          net_id = "net#{adapter_index}"
          
          # Check if this adapter already exists in QEMU args
          existing_adapters = read_qemu_network_adapters
          if existing_adapters[net_id] && existing_adapters[net_id][:netdev] && existing_adapters[net_id][:device]
            @logger.info("Base network adapter #{net_id} already exists, skipping")
            return
          end
          
          # Also check UTM native network interfaces as fallback
          interfaces = read_network_interfaces
          if interfaces[adapter_index]
            @logger.debug("Adapter #{adapter_index} already exists as #{interfaces[adapter_index][:type]}")
            return
          end

          # Convert network type to UTM's network mode
          utm_mode = case network_type
                     when :shared
                       "shared"
                     when :emulated
                       "emulated"
                     when :host_only
                       "host"
                     when :bridged
                       "bridged"
                     else
                       "shared"  # Default to shared/NAT
                     end

          # Generate a random MAC address for the new adapter
          # Note: ensure_network_adapter_exists always generates random MAC since no config is passed
          mac_address = random_mac_address
          
          # Prepare additional netdev options
          netdev_options = ""
          
          # For bridged networks, we need to specify the interface name
          if network_type == :bridged
            # Use a default bridge interface for ensure_network_adapter_exists
            default_bridge = "en0"
            netdev_options = ",ifname=#{default_bridge}"
          end
          
          # Get appropriate device type based on network type
          device_type = (network_type == :bridged) ? "virtio-net-pci" : "e1000"
         
          # Create a unique ID for this network adapter
          net_id = "net#{adapter_index}"
          
          # Build the QEMU arguments
          netdev_arg = "-netdev vmnet-#{utm_mode},id=#{net_id}#{netdev_options}"
          device_arg = "-device #{device_type},mac=#{mac_address},netdev=#{net_id}"
          
          # Use the existing add_qemu_additional_args script to add both arguments
          command = ["add_qemu_additional_args.applescript", @uuid, "--args", netdev_arg, device_arg]
          output = execute_osa_script(command)
        end
      end
    end
  end
end
