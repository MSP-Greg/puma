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
# -t Puma threads, default 5:5
# -w Puma workers, default 2


export HOST=127.0.0.1
export PORT=40001
export CTRL=40010

while getopts l:C:c:d:r:s:b:t:w: option
do
case "${option}"
in
l) loops=${OPTARG};;
c) connections=${OPTARG};;
r) req_per_client=${OPTARG};;
s) skt_type=${OPTARG};;
b) body_kb=${OPTARG};;
d) dly_app=${OPTARG};;
t) threads=${OPTARG};;
w) workers=${OPTARG};;
C) conf=${OPTARG};;
esac
done

optional_args=""

if test -z "$loops" ; then
  loops=10
fi

if test -z "$connections"; then
  connections=200
fi

if test -z "$req_per_client"; then
  req_per_client=1
fi

if test -n "$dly_app"; then
  optional_args="-d$dly_app"
fi

if test -n "$body_kb"; then
  optional_args="$optional_args -b$body_kb"
fi

if test -z "$skt_type"; then
  skt_type=tcp
fi

if test -n "$workers"; then
  puma_args="-w$workers"
else
  puma_args=""
fi

if test -n "$threads"; then
  puma_args="$puma_args -t$threads"
fi

if test -n "$conf"; then
  puma_args="$puma_args -C $tconf"
fi

case $skt_type in
  ssl)
  bind="ssl://$host:40010?cert=examples/puma/cert_puma.pem&key=examples/puma/puma_keypair.pem&verify_mode=none"
  curl_str=https://$HOST:$PORT
  ;;
  tcp)
  bind=tcp://$HOST:$PORT
  curl_str=http://$HOST:$PORT
  ;;
  unix)
  bind=unix://$HOME/skt.unix
  curl_str="--unix-socket $HOME/skt.unix http:/n"
  ;;
  aunix)
  bind=unix://@skt.aunix
  curl_str="--abstract-unix-socket skt.aunix http:/n"
  ;;
esac
