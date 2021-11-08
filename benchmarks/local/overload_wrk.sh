# see comments in bench_overload_wrk.rb

source benchmarks/local/bench_base.sh

if [ "$skt_type" == "unix" ] || [ "$skt_type" == "aunix" ]; then
  printf "\nwrk doesn't support UNIXSockets...\n\n"
  exit
fi

if [ -n "$GITHUB_ACTIONS" ]; then
  printf "##[group]Puma server startup\n\n"
else
  printf "\n"
fi

echo bundle exec bin/puma -q -b $bind $puma_args --control-url=tcp://$HOST:$CTRL --control-token=test $rackup_file
printf "\n"
#exit

bundle exec bin/puma -q -b $bind $puma_args --control-url=tcp://$HOST:$CTRL --control-token=test $rackup_file &
sleep 5s

if [ -n "$GITHUB_ACTIONS" ]; then
  printf "::[endgroup]\n"
else
  printf "\n"
fi

ruby -I./lib benchmarks/local/overload_wrk.rb  $ruby_args -W $wrk_str
wrk_exit=$?

printf "\n"

exit $wrk_exit
