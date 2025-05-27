# frozen_string_literal: true

module VagrantPlugins
  module Utm
    module Action
      # This action configures the networks on the VM.
      class ConfigureNetworks
        include Util::CompileNetworks

        def initialize(app, _env)
          @app = app
        end

        def call(env)
          @env = env

          # Get the networks we're configuring
          networks = compile_networks(env[:machine].config)

          # Ensure base adapters exist regardless of whether we have networks to configure
          ensure_base_adapters_exist
          
          # Only proceed with additional network configuration if there are networks to configure
          unless networks.empty?
            @env[:ui].output(I18n.t("vagrant_utm.actions.vm.configure_networks.configuring"))
            configure_networks(networks)
          end

          @app.call(env)
        end

        private

        def configure_networks(networks)
          driver = @env[:machine].provider.driver

          # Clear any existing additional network adapters to ensure clean state
          # This implements the "clean slate" approach for handling Vagrantfile changes
          driver.clear_additional_network_adapters

          networks.each do |network|
            @env[:ui].detail(I18n.t("vagrant_utm.actions.vm.configure_networks.configuring_adapter",
                                    adapter: network[:adapter] + 1,  # Show as 1-based for user
                                    type: network[:type]))

            # Configure the network adapter in UTM
            case network[:type]
            when :private_network
              configure_private_network(driver, network)
            when :public_network
              configure_public_network(driver, network)
            end
          end
        end

        def configure_private_network(driver, network)
          # Add private network adapter to UTM VM
          driver.add_network_adapter(
            network[:adapter],
            :host_only,
            network
          )
        end

        def configure_public_network(driver, network)
          # Add public network adapter to UTM VM
          driver.add_network_adapter(
            network[:adapter],
            :bridged,
            network
          )
        end

        def ensure_base_adapters_exist
          driver = @env[:machine].provider.driver

          @env[:ui].detail(I18n.t("vagrant_utm.actions.vm.configure_networks.ensuring_base_adapters"))

          # Ensure adapter 0 (shared/NAT) exists - for internet access
          driver.ensure_network_adapter_exists(0, :shared)

          # Ensure adapter 1 (emulated VLAN) exists - for SSH/port forwarding
          driver.ensure_network_adapter_exists(1, :emulated)
        end
      end
    end
  end
end
