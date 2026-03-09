# frozen_string_literal: true

begin
  require 'io/wait' unless Puma::HAS_NATIVE_IO_WAIT
rescue LoadError
end

require 'openssl'
require 'open3'

module Puma
  module SSL
    class SSLError < StandardError; end

    OPENSSL_VERSION = OpenSSL::OPENSSL_VERSION
    OPENSSL_LIBRARY_VERSION = OpenSSL::OPENSSL_LIBRARY_VERSION if defined?(OpenSSL::OPENSSL_LIBRARY_VERSION)
    OPENSSL_NO_SSL3   = true  # Ruby/OpenSSL has long disabled SSLv3 in most builds
    OPENSSL_NO_TLS1   = false
    OPENSSL_NO_TLS1_1 = false

    VERIFY_NONE = 0
    VERIFY_PEER = 1
    VERIFY_FAIL_IF_NO_PEER_CERT = 2

    # https://github.com/openssl/openssl/blob/master/include/openssl/x509_vfy.h.in
    # /* Certificate verify flags */
    VERIFICATION_FLAGS = {
      "USE_CHECK_TIME"       => 0x2,
      "CRL_CHECK"            => 0x4,
      "CRL_CHECK_ALL"        => 0x8,
      "IGNORE_CRITICAL"      => 0x10,
      "X509_STRICT"          => 0x20,
      "ALLOW_PROXY_CERTS"    => 0x40,
      "POLICY_CHECK"         => 0x80,
      "EXPLICIT_POLICY"      => 0x100,
      "INHIBIT_ANY"          => 0x200,
      "INHIBIT_MAP"          => 0x400,
      "NOTIFY_POLICY"        => 0x800,
      "EXTENDED_CRL_SUPPORT" => 0x1000,
      "USE_DELTAS"           => 0x2000,
      "CHECK_SS_SIGNATURE"   => 0x4000,
      "TRUSTED_FIRST"        => 0x8000,
      "SUITEB_128_LOS_ONLY"  => 0x10000,
      "SUITEB_192_LOS"       => 0x20000,
      "SUITEB_128_LOS"       => 0x30000,
      "PARTIAL_CHAIN"        => 0x80000,
      "NO_ALT_CHAINS"        => 0x100000,
      "NO_CHECK_TIME"        => 0x200000,
      "OCSP_RESP_CHECK"      => 0x400000,
      "OCSP_RESP_CHECK_ALL"  => 0x800000
    }.freeze

    # Define constant at runtime, as it's easy to determine at built time,
    # but Puma could (it shouldn't) be loaded with an older OpenSSL version
    # @version 5.0.0
    HAS_TLS1_3 = IS_JRUBY ||
        ((OPENSSL_VERSION[/ \d+\.\d+\.\d+/].split('.').map(&:to_i) <=> [1,1,1]) != -1 &&
         (OPENSSL_LIBRARY_VERSION[/ \d+\.\d+\.\d+/].split('.').map(&:to_i) <=> [1,1,1]) !=-1)

    if IS_JRUBY
      OPENSSL_NO_SSL3 = false
      OPENSSL_NO_TLS1 = false
    end
  end
end
