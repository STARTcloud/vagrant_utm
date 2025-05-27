# frozen_string_literal: true

require "vagrant/util/scoped_hash_override"

module VagrantPlugins
  module Utm
    module Util
      # This module contains the code to compile network configurations from config.
      module CompileNetworks
        include Vagrant::Util::ScopedHashOverride

        # This method compiles the network configurations into network models.
        # @param [Vagrant::Config::V2::Root] config The Vagrant configuration
        # @return [Array<Hash>] Array of network configuration hashes
        def compile_networks(config)
          networks = []
          adapter_index = 2  # Start at index 2 (Adapter 3 in UTM UI)

          config.vm.networks.each do |type, options|
            # Skip forwarded ports as they're handled separately
            next if type == :forwarded_port

            # Get UTM-specific options
            options = scoped_hash_override(options, :utm)

            case type
            when :private_network
              networks << compile_private_network(adapter_index, options)
            when :public_network
              networks << compile_public_network(adapter_index, options)
            end

            adapter_index += 1
          end

          networks
        end

        private

        # Compile private network configuration
        # @param [Integer] adapter_index The adapter index (0-based)
        # @param [Hash] options Network options
        # @return [Hash] Network configuration hash
        def compile_private_network(adapter_index, options)
          config = {
            adapter: adapter_index,
            type: :private_network,
            mode: determine_private_network_mode(options)
          }

          # Handle static IP configuration
          if options[:ip]
            config[:ip] = options[:ip]
            config[:netmask] = options[:netmask] || "255.255.255.0"
            config[:dhcp] = false
          else
            config[:dhcp] = true
          end

          # Handle additional options
          config[:bridge] = options[:bridge] if options[:bridge]
          config[:mac] = options[:mac] if options[:mac]

          config
        end

        # Compile public network configuration  
        # @param [Integer] adapter_index The adapter index (0-based)
        # @param [Hash] options Network options
        # @return [Hash] Network configuration hash
        def compile_public_network(adapter_index, options)
          config = {
            adapter: adapter_index,
            type: :public_network,
            mode: :bridged
          }

          # Handle bridge selection
          config[:bridge] = options[:bridge] if options[:bridge]
          config[:mac] = options[:mac] if options[:mac]

          # Public networks are typically DHCP by default
          if options[:ip]
            config[:ip] = options[:ip]
            config[:netmask] = options[:netmask] || "255.255.255.0"
            config[:dhcp] = false
          else
            config[:dhcp] = true
          end

          config
        end

        # Determine the appropriate network mode for private networks
        # @param [Hash] options Network options
        # @return [Symbol] Network mode (:host_only, :internal)
        def determine_private_network_mode(options)
          # If a specific bridge is requested, it's likely host-only
          return :host_only if options[:bridge]
          
          # If type is explicitly set to dhcp, use host-only
          return :host_only if options[:type] == "dhcp"
          
          # Default to host-only for private networks
          :host_only
        end
      end
    end
  end
end
