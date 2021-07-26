#!/bin/bash

# run from Puma directory
#
# Runs one set of clients with loops and connections as given, then runs a second set
# with the two flipped.  Useful for seeing how Puma behaves when overloaded with
# client requests
#
# example - runs 30k requests, first with 20 client threads, then with 50 client threads
#
# benchmarks/local/overload.sh -l20 -c50 -r30 -d0.01 -s tcp -w4 -t5:5
#

source benchmarks/local/base.sh

printf "\n"

bundle exec ruby -Ilib bin/puma -q -b $bind $puma_args --control-url=tcp://$HOST:$CTRL --control-token=test test/rackup/ci_string.ru &
sleep 5s

printf "\n════════════════════════════════════════════════════════════════════════════ String Body\n"
printf "%7d     1kB Body   ── curl test\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 1' $curl_str)
printf "%7d    10kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 10' $curl_str)
printf "%7d   100kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 100' $curl_str)
printf "%7d  2050kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 2050' $curl_str)

printf "\n──────────────────────────────────────────────────────────────────────────── Overload Stats\n"
ruby benchmarks/local/overload.rb -t$threads -w$workers -c$connections -r$req_per_client -s$skt_type $optional_args

printf "\n"
bundle exec ruby -Ilib bin/pumactl -C tcp://$HOST:$CTRL -T test stop
sleep 3
printf "\n"
