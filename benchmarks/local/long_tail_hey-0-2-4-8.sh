#!/bin/bash

# benchmarks/local/long_tail_hey-0-2-4-8.sh

# see comments in long_tail_hey.rb

benchmarks/local/long_tail_hey.sh -t5:5 -R100 -d0.2
sleep 2s
benchmarks/local/long_tail_hey.sh -w2 -t5:5 -R100 -d0.2
sleep 2s
benchmarks/local/long_tail_hey.sh -w4 -t5:5 -R100 -d0.2
sleep 2s
benchmarks/local/long_tail_hey.sh -w8 -t5:5 -R100 -d0.2
sleep 2s
benchmarks/local/long_tail_hey.sh -t5:5 -R100 -d0.2 -k
sleep 2s
benchmarks/local/long_tail_hey.sh -w2 -t5:5 -R100 -d0.2 -k
sleep 2s
benchmarks/local/long_tail_hey.sh -w4 -t5:5 -R100 -d0.2 -k
sleep 2s
benchmarks/local/long_tail_hey.sh -w8 -t5:5 -R100 -d0.2 -k
sleep 2s
