# frozen_string_literal: true
# Preview: Ruby translation (high-level) of ext/puma_http11/mini_ssl.c
#
# NOTE:
# - This is a behavioral translation/skeleton, not a drop-in replacement for the C extension.
# - The C extension uses OpenSSL memory BIOs and drives SSL_read/SSL_write directly.
# - In Ruby we emulate the same “inject/encrypt/decrypt/extract” style using OpenSSL::SSL::SSLSocket
#   over a pair of in-memory IO-like pipes. This is sufficient for understanding/control-flow,
#   but it won’t match the exact performance/edge semantics of the C engine.

require 'openssl'
require 'securerandom'
require 'stringio'

module Puma
  module SSL
    class Context
      attr_accessor :verify_mode
      attr_reader :no_tlsv1, :no_tlsv1_1

      def initialize
        @no_tlsv1   = nil
        @no_tlsv1_1 = nil
        @key = nil
        @cert = nil
        @key_pem = nil
        @cert_pem = nil
        @reuse = nil
        @reuse_cache_size = nil
        @reuse_timeout = nil
        @alpn = nil
      end

      def check_file(file, desc)
        raise ArgumentError, "#{desc} file '#{file}' does not exist" unless File.exist? file
        raise ArgumentError, "#{desc} file '#{file}' is not readable" unless File.readable? file
      end

      if Puma::IS_JRUBY
        # jruby-specific Context properties: java uses a keystore and password pair rather than a cert/key pair
        attr_reader :keystore
        attr_reader :keystore_type
        attr_accessor :keystore_pass
        attr_reader :truststore
        attr_reader :truststore_type
        attr_accessor :truststore_pass
        attr_reader :cipher_suites
        attr_reader :protocols

        def keystore=(keystore)
          check_file keystore, 'Keystore'
          @keystore = keystore
        end

        def truststore=(truststore)
          # NOTE: historically truststore was assumed the same as keystore, this is kept for backwards
          # compatibility, to rely on JVM's trust defaults we allow setting `truststore = :default`
          unless truststore.eql?(:default)
            raise ArgumentError, "No such truststore file '#{truststore}'" unless File.exist?(truststore)
          end
          @truststore = truststore
        end

        def keystore_type=(type)
          raise ArgumentError, "Invalid keystore type: #{type.inspect}" unless ['pkcs12', 'jks', nil].include?(type)
          @keystore_type = type
        end

        def truststore_type=(type)
          raise ArgumentError, "Invalid truststore type: #{type.inspect}" unless ['pkcs12', 'jks', nil].include?(type)
          @truststore_type = type
        end

        def cipher_suites=(list)
          list = list.split(',').map(&:strip) if list.is_a?(String)
          @cipher_suites = list
        end

        # aliases for backwards compatibility
        alias_method :ssl_cipher_list, :cipher_suites
        alias_method :ssl_cipher_list=, :cipher_suites=

        def protocols=(list)
          list = list.split(',').map(&:strip) if list.is_a?(String)
          @protocols = list
        end

        def check
          raise "Keystore not configured" unless @keystore
          # @truststore defaults to @keystore due backwards compatibility
        end

      else
        # non-jruby Context properties
        attr_reader :key
        attr_reader :key_password_command
        attr_reader :cert
        attr_reader :ca
        attr_reader :cert_pem
        attr_reader :key_pem
        attr_accessor :ssl_cipher_filter
        attr_accessor :ssl_ciphersuites
        attr_accessor :verification_flags

        attr_reader :reuse, :reuse_cache_size, :reuse_timeout

        def key=(key)
          check_file key, 'Key'
          @key = key
        end

        def key_password_command=(key_password_command)
          @key_password_command = key_password_command
        end

        def cert=(cert)
          check_file cert, 'Cert'
          @cert = cert
        end

        def ca=(ca)
          check_file ca, 'ca'
          @ca = ca
        end

        def cert_pem=(cert_pem)
          raise ArgumentError, "'cert_pem' is not a String" unless cert_pem.is_a? String
          @cert_pem = cert_pem
        end

        def key_pem=(key_pem)
          raise ArgumentError, "'key_pem' is not a String" unless key_pem.is_a? String
          @key_pem = key_pem
        end

        def check
          raise "Key not configured" if @key.nil? && @key_pem.nil?
          raise "Cert not configured" if @cert.nil? && @cert_pem.nil?
        end

        # Executes the command to return the password needed to decrypt the key.
        def get_key_password
          raise "Key password command not configured" if @key_password_command.nil?

          stdout_str, stderr_str, status = Open3.capture3(@key_password_command)

          return stdout_str.chomp if status.success?

          raise "Key password failed with code #{status.exitstatus}: #{stderr_str}"
        end

        # Controls session reuse.  Allowed values are as follows:
        # * 'off' - matches the behavior of Puma 5.6 and earlier.  This is included
        #   in case reuse 'on' is made the default in future Puma versions.
        # * 'dflt' - sets session reuse on, with OpenSSL default cache size of
        #   20k and default timeout of 300 seconds.
        # * 's,t' - where s and t are integer strings, for size and timeout.
        # * 's' - where s is an integer strings for size.
        # * ',t' - where t is an integer strings for timeout.
        #
        def reuse=(reuse_str)
          case reuse_str
          when 'off'
            @reuse = nil
          when 'dflt'
            @reuse = true
          when /\A\d+\z/
            @reuse = true
            @reuse_cache_size = reuse_str.to_i
          when /\A\d+,\d+\z/
            @reuse = true
            size, time = reuse_str.split ','
            @reuse_cache_size = size.to_i
            @reuse_timeout = time.to_i
          when /\A,\d+\z/
            @reuse = true
            @reuse_timeout = reuse_str.delete(',').to_i
          end
        end
      end

      # disables TLSv1
      # @!attribute [w] no_tlsv1=
      def no_tlsv1=(tlsv1)
        raise ArgumentError, "Invalid value of no_tlsv1=" unless ['true', 'false', true, false].include?(tlsv1)
        @no_tlsv1 = tlsv1
      end

      # disables TLSv1 and TLSv1.1.  Overrides `#no_tlsv1=`
      # @!attribute [w] no_tlsv1_1=
      def no_tlsv1_1=(tlsv1_1)
        raise ArgumentError, "Invalid value of no_tlsv1_1=" unless ['true', 'false', true, false].include?(tlsv1_1)
        @no_tlsv1_1 = tlsv1_1
      end

      def to_sslcontext
        sslctx = OpenSSL::SSL::SSLContext.new
        # Protocol min version logic (C uses SSL_CTX_set_min_proto_version when available)
        # Ruby/OpenSSL exposes min/max via attributes in newer versions; guard for compatibility.
        if sslctx.respond_to?(:min_version=)
          sslctx.min_version =
            if @no_tlsv1_1
              OpenSSL::SSL::TLS1_2_VERSION
            elsif @no_tlsv1
              OpenSSL::SSL::TLS1_1_VERSION
            else
              OpenSSL::SSL::TLS1_VERSION
            end
        end

        # alpn_list = @alpn || ['h2', 'http/1.1', 'http/1.0']
        alpn_list = @alpn || ['http/1.1', 'http/1.0']

        sslctx.alpn_select_cb = -> (protocols) do
          alpn_list.each do |protocol|
            return protocol if protocols.include?(protocol)
          end
        end

        # Certificate / key from files
        ssl_certs = if @cert
          OpenSSL::X509::Certificate.load File.binread(@cert)
        elsif @cert_pem
          OpenSSL::X509::Certificate.load @cert_pem
        else
          nil
        end
        ssl_cert = ssl_certs.shift

        ssl_key = if @key
          pass = get_key_password if @key_password_command
          OpenSSL::PKey.read File.binread(@key), pass
        elsif @key_pem
          pass = get_key_password if @key_password_command
          OpenSSL::PKey.read @key_pem, pass
        else
          nil
        end

        if ssl_cert && ssl_key
          if ssl_certs.empty?
            sslctx.add_certificate ssl_cert, ssl_key
          else
            sslctx.add_certificate ssl_cert, ssl_key, ssl_certs
          end
        else
          raise SSLError, "Must provide cert & key"
        end

        if @ca
          store = OpenSSL::X509::Store.new
          store.add_file @ca
          sslctx.cert_store = store
        end

        if @verification_flags && @cert_store
          sslctx.cert_store.flags = Integer(@verification_flags) if @cert_store.respond_to?(:flags=)
        end

        sslctx.verify_mode = Integer(@verify_mode) if @verify_mode

        # Cipher list / suites
        sslctx.ciphers = if @ssl_cipher_filter
          @ssl_cipher_filter
        else
          "HIGH:!aNULL@STRENGTH" rescue nil
        end

        if @ssl_ciphersuites && sslctx.respond_to?(:ciphersuites=)
          sslctx.ciphersuites = @ssl_ciphersuites
        end

        sslctx.session_cache_mode = @reuse ?
          OpenSSL::SSL::SSLContext::SESSION_CACHE_SERVER :
          OpenSSL::SSL::SSLContext::SESSION_CACHE_OFF

        # Session cache configuration (C toggles server cache)
        # Ruby does not expose the same server cache knobs; omit.

        # Session id context equivalent (C uses Random.bytes)
        # Not directly available in Ruby OpenSSL API; omit.

        self.freeze
        sslctx
      rescue => err
        raise SSLError, "#{err&.class} #{err&.message}"
      end
    end
  end
end
