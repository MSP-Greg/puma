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
while getopts c:l:s:t:w: option
do
case "${option}"
in
c) connections=${OPTARG};;
l) loops=${OPTARG};;
r) resp_kb=${OPTARG};;
s) skt_type=${OPTARG};;
t) threads=${OPTARG};;
w) workers=${OPTARG};;
esac
done

if test -z "$connections"; then
  connections=200
fi

if test -z "$loops" ; then
  loops=10
fi

if test -z "$resp_kb"; then
  resp_kb=200
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
echo ────────────────────────────────────────────────────────────  Memory
ps -eo pid,tid,class,rtprio,stat,vsz,rss,comm

echo ────────────────────────────────────────────────────────────  10kB Response
ruby ./benchmarks/misc/socket_times.rb $connections $loops $skt_type 10

sleep 1
echo ────────────────────────────────────────────────────────────  Memory
ps -eo pid,tid,class,rtprio,stat,vsz,rss,comm

#bundle exec ruby -Ilib bin/pumactl -C tcp://127.0.0.1:40001 -T test restart
#sleep 4s

sleep 2
echo ──────────────────────────────────────────────────────────── 200kB Response
ruby ./benchmarks/misc/socket_times.rb $connections $loops $skt_type 200

sleep 1
echo ────────────────────────────────────────────────────────────  Memory
bundle exec ruby -Ilib bin/pumactl -C tcp://127.0.0.1:40001 -T test gc
sleep 1
ps -eo pid,tid,class,rtprio,stat,vsz,rss,comm

bundle exec ruby -Ilib bin/pumactl -C tcp://127.0.0.1:40001 -T test phased-restart
sleep 4
ps -eo pid,tid,class,rtprio,stat,vsz,rss,comm

echo ──────────────────────────────────────────────────────────── 200kB Response
ruby ./benchmarks/misc/socket_times.rb $connections $loops $skt_type 200

sleep 1
echo ────────────────────────────────────────────────────────────  Memory
ps -eo pid,tid,class,rtprio,stat,vsz,rss,comm

echo ──────────────────────────────────────────────────────────── 200kB Response
ruby ./benchmarks/misc/socket_times.rb $connections $loops $skt_type 200

sleep 1
echo ────────────────────────────────────────────────────────────  Memory
ps -eo pid,tid,class,rtprio,stat,vsz,rss,comm

bundle exec ruby -Ilib bin/pumactl -C tcp://127.0.0.1:40001 -T test stop
sleep 1s
