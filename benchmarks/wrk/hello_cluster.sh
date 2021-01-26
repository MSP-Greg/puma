# You are encouraged to use @ioquatix's wrk fork, located here: https://github.com/ioquatix/wrk

bundle exec bin/puma -t 5:5 -w 2 -b tcp://127.0.0.1:40010 test/rackup/hello.ru &
PID1=$!
sleep 5
wrk -t4 -c8 -d 30 --latency http://127.0.0.1:40010
sleep 1
kill $PID1
