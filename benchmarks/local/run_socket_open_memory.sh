#!/bin/sh

# run from Puma directory

# c connections per client thread default
# l client threads (loops)
# Total connections = l * c
#
# s Puma bind socket type, default ssl, also tcp or unix
# t Puma threads, default 5:5
# w Puma workers, default 2
#
while getopts b:c:k:l:r:s:t:w: option
do
case "${option}"
in
b) body_kb=${OPTARG};;
c) connections=${OPTARG};;
k) keep_alive==${OPTARG};;
l) loops=${OPTARG};;
r) requests_per_client=${OPTARG};;
s) skt_type=${OPTARG};;
t) threads=${OPTARG};;
w) workers=${OPTARG};;
esac
done

if test -z "$body_kb"; then
  body_kb=200
fi

if test -z "$connections"; then
  connections=200
fi

if test -z "$keep_alive"; then
  keep_alive=true
fi

if test -z "$loops" ; then
  loops=10
fi

if test -z "$requests_per_client" ; then
  requests_per_client=2
fi

if test -z "$skt_type"; then
  skt_type=ssl
fi

if test -z "$threads"; then
  threads=5:5
fi

if test -z "$workers"; then
  workers=2
fi

case $skt_type in
  ssl)
  bind="ssl://127.0.0.1:40010?cert=examples/puma/cert_puma.pem&key=examples/puma/puma_keypair.pem&verify_mode=none"
  ;;
  tcp)
  bind=tcp://127.0.0.1:40010
  ;;
  unix)
  bind=unix://$HOME/skt.unix
  ;;
esac

bundle exec ruby -Ilib bin/puma -q -b $bind -t$threads -w$workers --control-url=tcp://127.0.0.1:40001 --control-token=test test/rackup/ci_string.ru &

sleep 5s
temp='kB Response'
echo "────────────────────────────────────────────────────────────"
ruby ./benchmarks/local/socket_open_memory.rb $connections $loops $skt_type $body_kb $keep_alive $requests_per_client

bundle exec ruby -Ilib bin/pumactl -C tcp://127.0.0.1:40001 -T test stop
