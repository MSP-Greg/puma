# run from Puma directory

# benchmarks/local/curl_ci_select_test.sh

source benchmarks/local/bench_base.sh


StartPuma

# below to check body size of response
printf "\n════════════════════════════════ Checking ci_select.ru - curl response body size test\n"
printf "──────────────────    1kB Body\n"
printf "%7d  array\n"   $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: a1' $curl_str)
printf "%7d  chunked\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: c1' $curl_str)
printf "%7d  string\n"  $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: s1' $curl_str)
printf "%7d  file\n"    $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: i1' $curl_str)

printf "──────────────────   10kB Body\n"
printf "%7d  array\n"   $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: a10' $curl_str)
printf "%7d  chunked\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: c10' $curl_str)
printf "%7d  string\n"  $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: s10' $curl_str)
printf "%7d  file\n"    $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: i10' $curl_str)

printf "──────────────────  100kB Body\n"
printf "%7d  array\n"   $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: a100' $curl_str)
printf "%7d  chunked\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: c100' $curl_str)
printf "%7d  string\n"  $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: s100' $curl_str)
printf "%7d  file\n"    $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: i100' $curl_str)

printf "────────────────── 2050kB Body\n"
printf "%7d  array\n"   $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: a2050' $curl_str)
printf "%7d  chunked\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: c2050' $curl_str)
printf "%7d  string\n"  $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: s2050' $curl_str)
printf "%7d  file\n"    $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: i2050' $curl_str)
printf "\n"

# show headers
# curl -kvo /dev/null -H 'Body-Conf: a10' $curl_str
# curl -kvo /dev/null -H 'Body-Conf: c10' $curl_str
# curl -kvo /dev/null -H 'Body-Conf: s10' $curl_str
# curl -kvo /dev/null -H 'Body-Conf: i10' $curl_str

bundle exec ruby bin/pumactl -C tcp://$HOST:$CTRL -T test stop
sleep 3s

# ────────────────────────────────────────────────────────────────────────────────── ci_array.ru
printf "\n"
bundle exec bin/puma -q -b $bind $puma_args --control-url=tcp://$HOST:$CTRL --control-token=test test/rackup/ci_array.ru &
sleep 6s

# below to check body size of response
  printf "\n════════════════════════════════ Checking ci_array.ru - curl response body size test\n"
  printf "%7d     1 kB\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: 1' $curl_str)
  printf "%7d    10 kB\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: 10' $curl_str)
  printf "%7d   100 kB\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: 100' $curl_str)
  printf "%7d  2050 kB\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: 2050' $curl_str)
  printf "\n"

bundle exec ruby bin/pumactl -C tcp://$HOST:$CTRL -T test stop
sleep 3s

# ────────────────────────────────────────────────────────────────────────────────── ci_chunk.ru
printf "\n"
bundle exec bin/puma -q -b $bind $puma_args --control-url=tcp://$HOST:$CTRL --control-token=test test/rackup/ci_chunked.ru &
sleep 6s

# below to check body size of response
  printf "\n════════════════════════════════ Checking ci_chunked.ru - curl response body size test\n"
  printf "%7d     1 kB\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: 1' $curl_str)
  printf "%7d    10 kB\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: 10' $curl_str)
  printf "%7d   100 kB\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: 100' $curl_str)
  printf "%7d  2050 kB\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: 2050' $curl_str)
  printf "\n"

bundle exec ruby bin/pumactl -C tcp://$HOST:$CTRL -T test stop
sleep 3s

# ────────────────────────────────────────────────────────────────────────────────── ci_io.ru
printf "\n"
bundle exec bin/puma -q -b $bind $puma_args --control-url=tcp://$HOST:$CTRL --control-token=test test/rackup/ci_io.ru &
sleep 6s

# below to check body size of response
  printf "\n════════════════════════════════ Checking ci_io.ru - curl response body size test\n"
  printf "%7d     1 kB\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: 1' $curl_str)
  printf "%7d    10 kB\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: 10' $curl_str)
  printf "%7d   100 kB\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: 100' $curl_str)
  printf "%7d  2050 kB\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: 2050' $curl_str)
  printf "\n"

bundle exec ruby bin/pumactl -C tcp://$HOST:$CTRL -T test stop
sleep 3s

# ────────────────────────────────────────────────────────────────────────────────── ci_string.ru
printf "\n"
bundle exec bin/puma -q -b $bind $puma_args --control-url=tcp://$HOST:$CTRL --control-token=test test/rackup/ci_string.ru &
sleep 6s

# below to check body size of response
  printf "\n════════════════════════════════ Checking ci_string.ru - curl response body size test\n"
  printf "%7d     1 kB\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: 1' $curl_str)
  printf "%7d    10 kB\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: 10' $curl_str)
  printf "%7d   100 kB\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: 100' $curl_str)
  printf "%7d  2050 kB\n" $(curl -kso /dev/null -w '%{size_download}' -H 'Body-Conf: 2050' $curl_str)
  printf "\n"

bundle exec ruby bin/pumactl -C tcp://$HOST:$CTRL -T test stop
sleep 3s

exit