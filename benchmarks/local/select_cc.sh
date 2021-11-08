# run from Puma directory

# see comments in select_cc.rb

source benchmarks/local/bench_base.sh

StartPuma

ruby -I./lib benchmarks/local/select_cc.rb $ruby_args
