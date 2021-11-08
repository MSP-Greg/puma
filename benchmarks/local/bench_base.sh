#!/bin/bash

# -l client threads (loops)
# -c connections per client thread
# -r requests per client
#
# Total connections/requests = l * c * r
#
# -b response body size kB
# -d app delay
#
# -s Puma bind socket type, default ssl, also tcp or unix
# -t Puma threads
# -w Puma workers
# -r Puma rackup file

PUMA_BENCH_CMD=$0
PUMA_BENCH_ARGS=$@

export PUMA_BENCH_CMD
export PUMA_BENCH_ARGS

export PUMA_TEST_HOST4=127.0.0.1
export PUMA_TEST_HOST6=::1
export PUMA_TEST_PORT=40001
export PUMA_TEST_CTRL=40010
export PUMA_TEST_STATE=tmp/bench_test_puma.state

while getopts l:C:c:d:r:R:s:b:T:t:w: option
do
case "${option}"
in
#———————————————————— create_clients options
l) loops=${OPTARG};;
c) connections=${OPTARG};;
r) req_per_client=${OPTARG};;
#———————————————————— Puma options
C) conf=${OPTARG};;
t) threads=${OPTARG};;
w) workers=${OPTARG};;
R) rackup_file=${OPTARG};;
#———————————————————— app/common options
b) body_conf=${OPTARG};;
s) skt_type=${OPTARG};;
d) dly_app=${OPTARG};;
#———————————————————— wrk options
# c (connections) is also used for wrk
T) time=${OPTARG};;
esac
done

# -n not empty, -z is empty

ruby_args="-S $PUMA_TEST_STATE"

if [ -n "$loops" ] ; then
  ruby_args="$ruby_args -l$loops"
fi

if [ -n "$connections" ]; then
  ruby_args="$ruby_args -c$connections"
fi

if [ -n "$time" ] ; then
  ruby_args="$ruby_args -T$time"
fi

if [ -n "$req_per_client" ]; then
  ruby_args="$ruby_args -r$req_per_client"
fi

if [ -n "$dly_app" ]; then
  ruby_args="$ruby_args -d$dly_app"
fi

if [ -n "$body_conf" ]; then
  ruby_args="$ruby_args -b $body_conf"
  export CI_TEST_KB=$body_conf
fi

if [ -z "$skt_type" ]; then
  skt_type=tcp
fi

ruby_args="$ruby_args -s $skt_type"

puma_args="-S $PUMA_TEST_STATE"

if [ -n "$workers" ]; then
  puma_args="$puma_args -w$workers"
  ruby_args="$ruby_args -w$workers"
fi

if [ -z "$threads" ]; then
  threads=0:5
fi

puma_args="$puma_args -t$threads"
ruby_args="$ruby_args -t$threads"

if [ -n "$conf" ]; then
  puma_args="$puma_args -C $conf"
fi

if [ -z "$rackup_file" ]; then
  rackup_file="test/rackup/ci_select.ru"
fi

ip4=$PUMA_TEST_HOST4:$PUMA_TEST_PORT
ip6=[$PUMA_TEST_HOST6]:$PUMA_TEST_PORT

case $skt_type in
  ssl4)
  bind="ssl://$PUMA_TEST_HOST4:$PUMA_TEST_PORT?cert=examples/puma/cert_puma.pem&key=examples/puma/puma_keypair.pem&verify_mode=none"
  curl_str=https://$ip4
  wrk_str=https://$ip4
  ;;
  ssl)
  bind="ssl://$ip4?cert=examples/puma/cert_puma.pem&key=examples/puma/puma_keypair.pem&verify_mode=none"
  curl_str=https://$ip4
  wrk_str=https://$ip4
  ;;
  ssl6)
  bind="ssl://$ip6?cert=examples/puma/cert_puma.pem&key=examples/puma/puma_keypair.pem&verify_mode=none"
  curl_str=https://$ip6
  wrk_str=https://$ip6
  ;;
  tcp4)
  bind=tcp://$ip4
  curl_str=http://$ip4
  wrk_str=http://$ip4
  ;;
  tcp)
  bind=tcp://$ip4
  curl_str=http://$ip4
  wrk_str=http://$ip4
  ;;
  tcp6)
  bind=tcp://$ip6
  curl_str=http://$ip6
  wrk_str=http://$ip6
  ;;
  unix)
  bind=unix://tmp/benchmark_skt.unix
  curl_str="--unix-socket tmp/benchmark_skt.unix http:/n"
  ;;
  aunix)
  bind=unix://@benchmark_skt.aunix
  curl_str="--abstract-unix-socket benchmark_skt.aunix http:/n"
  ;;
esac

StartPuma()
{
  if [ -n "$1" ]; then
    rackup_file=$1
  fi
  printf "\nbundle exec bin/puma -q -b $bind $puma_args --control-url=tcp://$PUMA_TEST_HOST4:$PUMA_TEST_CTRL --control-token=test $rackup_file\n\n"
  bundle exec bin/puma -q -b $bind $puma_args --control-url=tcp://$PUMA_TEST_HOST4:$PUMA_TEST_CTRL --control-token=test $rackup_file &
  sleep 6s
}
