#!/bin/bash

# run from Puma directory
#
# Runs clients against an array body, a chunked body, and a string body.
# Each set of runs is done with 1, 10, and 100 kB bodies.  300 requests are
# also sent that return a 2050 kB body, which is juts over 2 mB.
#
# example
# benchmarks/local/array_chunked_string.sh -l10 -c100 -r10 -s tcp -t5:5 -w2
#

source benchmarks/local/base.sh

# run from Puma directory

printf "\n"

bundle exec ruby -Ilib bin/puma -q -b $bind $puma_args --control-url=tcp://$HOST:$CTRL --control-token=test test/rackup/ci_array.ru &
sleep 5s
printf "\n══════════════════════════════════════════════════════════════════════════   Array Body\n"
printf "%7d     1kB Body   ── curl test\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 1' $curl_str)
printf "%7d    10kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 10' $curl_str)
printf "%7d   100kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 100' $curl_str)
printf "%7d  2050kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 2050' $curl_str)

# show headers
# curl -kvo /dev/null -H 'Len: 1' $curl_str

printf "\n────────────────────────────────────────────────────────────────────────────   1kB Body\n"
ruby benchmarks/local/client_times.rb -l$loops -c$connections -r$req_per_client -s$skt_type -b1

printf "\n────────────────────────────────────────────────────────────────────────────  10kB Body\n"
ruby benchmarks/local/client_times.rb -l$loops -c$connections -r$req_per_client -s$skt_type -b10

printf "\n──────────────────────────────────────────────────────────────────────────── 100kB Body\n"
ruby benchmarks/local/client_times.rb -l$loops -c$connections -r$req_per_client -s$skt_type -b100

printf "\n─────────────────────────────────────────────────────────────────────────── 2050kB Body\n"
ruby benchmarks/local/client_times.rb -l10 -c15 -r2 -s$skt_type -b2050

printf "\n"
bundle exec ruby -Ilib bin/pumactl -C tcp://$HOST:$CTRL -T test stop
sleep 3s

printf "\n\n"

bundle exec ruby -Ilib bin/puma -q -b $bind $puma_args --control-url=tcp://$HOST:$CTRL --control-token=test test/rackup/ci_chunked.ru &
sleep 5s

printf "\n══════════════════════════════════════════════════════════════════════════ Chunked Body\n"
printf "%7d     1kB Body   ── curl test\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 1' $curl_str)
printf "%7d    10kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 10' $curl_str)
printf "%7d   100kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 100' $curl_str)
printf "%7d  2050kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 2050' $curl_str)

# show headers
# curl -kvo /dev/null -H 'Len: 1' $curl_str

printf "\n────────────────────────────────────────────────────────────────────────────   1kB Body\n"
ruby benchmarks/local/client_times.rb -l$loops -c$connections -r$req_per_client -s$skt_type -b1

printf "\n────────────────────────────────────────────────────────────────────────────  10kB Body\n"
ruby benchmarks/local/client_times.rb -l$loops -c$connections -r$req_per_client -s$skt_type -b10

printf "\n──────────────────────────────────────────────────────────────────────────── 100kB Body\n"
ruby benchmarks/local/client_times.rb -l$loops -c$connections -r$req_per_client -s$skt_type -b100

printf "\n─────────────────────────────────────────────────────────────────────────── 2050kB Body\n"
ruby benchmarks/local/client_times.rb -l10 -c15 -r2 -s$skt_type -b2050

printf "\n"
bundle exec ruby -Ilib bin/pumactl -C tcp://$HOST:$CTRL -T test stop
sleep 3s

printf "\n\n"

bundle exec ruby -Ilib bin/puma -q -b $bind $puma_args --control-url=tcp://$HOST:$CTRL --control-token=test test/rackup/ci_string.ru &
sleep 5s

printf "\n═══════════════════════════════════════════════════════════════════════════ String Body\n"
printf "%7d     1kB Body   ── curl test\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 1' $curl_str)
printf "%7d    10kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 10' $curl_str)
printf "%7d   100kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 100' $curl_str)
printf "%7d  2050kB Body\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Len: 2050' $curl_str)

printf "\n────────────────────────────────────────────────────────────────────────────   1kB Body\n"
ruby benchmarks/local/client_times.rb -l$loops -c$connections -r$req_per_client -s$skt_type -b1

printf "\n────────────────────────────────────────────────────────────────────────────  10kB Body\n"
ruby benchmarks/local/client_times.rb -l$loops -c$connections -r$req_per_client -s$skt_type -b10

printf "\n──────────────────────────────────────────────────────────────────────────── 100kB Body\n"
ruby benchmarks/local/client_times.rb -l$loops -c$connections -r$req_per_client -s$skt_type -b100

printf "\n─────────────────────────────────────────────────────────────────────────── 2050kB Body\n"
ruby benchmarks/local/client_times.rb -l10 -c15 -r2 -s$skt_type -b2050

printf "\n"
bundle exec ruby -Ilib bin/pumactl -C tcp://$HOST:$CTRL -T test stop
sleep 3
printf "\n"
