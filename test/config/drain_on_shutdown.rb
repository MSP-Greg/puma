drain_on_shutdown

app do |env|
  [200, {}, ['Hello']]
end

lowlevel_error_handler do |err|
  STDOUT.puts err
  STDOUT.puts err.backtrace
  [500, {}, ["error page"]]
end
