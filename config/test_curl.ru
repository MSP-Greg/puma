if ::Puma::IS_JRUBY
  ssl_bind 'localhost', 47447, {
    keystore: '/mnt/c/Greg/GitHub/puma/examples/puma/client_certs/keystore.jks',
    keystore_pass: 'jruby_puma',
    verify_mode: 'force_peer'
  }
else
  ssl_bind 'localhost', 47447, {
    cert: '/mnt/c/Greg/GitHub/puma/examples/puma/client_certs/server.crt',
    key:  '/mnt/c/Greg/GitHub/puma/examples/puma/client_certs/server.key',
    ca:   '/mnt/c/Greg/GitHub/puma/examples/puma/client_certs/ca.crt',
    verify_mode: 'force_peer'
  }
end

threads 1, 1

app { |_| [200, { 'Content-Type' => 'text/plain' }, ["HELLO", ' ', "THERE"]] }
