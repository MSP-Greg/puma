on_booted do
  puts "second on_booted called"
  pid = Process.pid
  Process.kill :TERM, pid
  begin
    Process.wait2 pid
  rescue Errno::ECHILD
  end
end
