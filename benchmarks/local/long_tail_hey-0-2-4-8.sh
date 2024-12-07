#!/bin/bash

# benchmarks/local/long_tail_hey-0-2-4-8.sh
#
# takes one argument which is app delay, default to 0.2
#
# see comments in long_tail_hey.rb

if [[ -n $1 ]]; then
  DLY=$1
else
  DLY=0.2
fi

SECONDS=0

benchmarks/local/long_tail_hey.sh -t5:5 -R100 -d$DLY
sleep 2s
benchmarks/local/long_tail_hey.sh -w2 -t5:5 -R100 -d$DLY
sleep 2s
benchmarks/local/long_tail_hey.sh -w4 -t5:5 -R100 -d$DLY
sleep 2s
benchmarks/local/long_tail_hey.sh -w8 -t5:5 -R100 -d$DLY
sleep 2s
benchmarks/local/long_tail_hey.sh -t5:5 -R100 -d$DLY -k
sleep 2s
benchmarks/local/long_tail_hey.sh -w2 -t5:5 -R100 -d$DLY -k
sleep 2s
benchmarks/local/long_tail_hey.sh -w4 -t5:5 -R100 -d$DLY -k
sleep 2s
benchmarks/local/long_tail_hey.sh -w8 -t5:5 -R100 -d$DLY -k
sleep 2s

TZ=UTC0 printf '\n%(%H:%M:%S)T All Total Time\n' $SECONDS
