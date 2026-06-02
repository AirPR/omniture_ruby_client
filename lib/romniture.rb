require "romniture/version"
require "romniture/client"
require "romniture/client_factory"
require "romniture/exceptions"
require "romniture/visitorid"
require "romniture/dwresponse"
require "romniture/report_response"
require "rubygems"

require "logger"

begin
	require "rack"
	if defined?(Rack::Utils) && !defined?(Rack::Utils::HeaderHash)
		# HTTPI still references Rack::Utils::HeaderHash, which was removed in Rack 3.
		header_hash_class = Class.new(Hash) do
			def initialize(hash = nil)
				super()
				update(hash) if hash
			end

			def [](key)
				super(normalize_key(key))
			end

			def []=(key, value)
				super(normalize_key(key), value)
			end

			def merge!(other_hash)
				other_hash.each { |k, v| self[k] = v }
				self
			end

			def update(other_hash)
				merge!(other_hash || {})
			end

			private

			def normalize_key(key)
				key.to_s
			end
		end

		Rack::Utils.const_set(:HeaderHash, header_hash_class)
	end
rescue LoadError
	# Rack is an HTTPI transitive dependency; skip shim when unavailable.
end

require "httpi"
require "digest/md5"
require "digest/sha1"
require "base64"
require "json"
require "active_support"
require "active_support/core_ext"

require "curb"
require "stringio"
require 'open-uri'
require 'csv'

module ROmniture
  
end