require "romniture/client/v2"

module ROmniture
  class ClientFactory
    LEGACY_VERSION_ALIASES = [nil, "legacy", "v1", "1", "1.3", "1.4"].freeze
    V2_VERSION_ALIASES = ["v2", "2", "2.0"].freeze

    def self.build(username, shared_secret, environment, options = {})
      version = normalize_client_version(options[:client_version] || ENV["ROMNITURE_CLIENT_VERSION"])
      sanitized_options = options.dup
      sanitized_options.delete(:client_version)

      if version == :v2
        legacy_base = ROmniture::Client.new(username, shared_secret, environment, sanitized_options)
        return ROmniture::Client::V2.new(legacy_base, sanitized_options)
      end

      ROmniture::Client.new(username, shared_secret, environment, sanitized_options)
    end

    def self.normalize_client_version(client_version)
      normalized = client_version.nil? ? nil : client_version.to_s.strip.downcase

      return :legacy if LEGACY_VERSION_ALIASES.include?(normalized)
      return :v2 if V2_VERSION_ALIASES.include?(normalized)

      raise ArgumentError, "Unknown client version '#{client_version}'. Use one of: legacy, v1, 1.3, 1.4, v2, 2.0"
    end

    private_class_method :normalize_client_version
  end
end