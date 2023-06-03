silence_single_worker_warning

app do |env|
  [200, {"Content-Type" => "text/plain"}, ["Hello World"]]
end
