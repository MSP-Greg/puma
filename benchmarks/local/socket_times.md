## Running run_socket_times.sh

The code here is based on code from a test suite rewrite I'm working on.

The code consists of two files `run_socket_times.sh` and `socket_times.rb`.  One should be in the Puma repo folder to run `run_socket_times.sh`.

`run_socket_times.sh` starts a Puma server, then runs `socket_times.rb`, which creates multiple clients to the server, then performs a 'phased-restart', then runs `socket_times.rb` again, and finally shuts down the server.  It uses [`test/rackup/realistic_response.ru`](https://github.com/puma/puma/blob/master/test/rackup/realistic_response.ru) for its rackup file, which generates a 100k body.

It has the following arguments:
```
Argument             Description                        Default
-c <int>             client connections per thread loop  50
-l <int>             number of thread loops              20
-s <ssl, tcp, unix>  Puma server bind type               ssl
-t <int:int>         Puma server threads                 5:5
-w <int>             Puma server workers                 2
```

`socket_times.rb` creates several threads in a loop, each with a small time offeset, and each thread runs several clients, with a small delay between each.  It collects the times to connect and write the request for each client, sorts the array of times, and outputs data of the percentile times for the array, an example is:
```
 546.30 Total 2000 connections (40 loops of 50 clients) - send request time
          5%     10%     20%     40%     50%     60%     80%     90%     95%
  mS    0.04    0.05    0.05    0.05    0.06    0.07    0.15    0.30    0.42
```

## Examples:
```
benchmarks/local/run_socket_times.sh -w4 -t10:10 -s unix -l40
```
Runs Puma with four workers (`-w4`), and threads of 10:10 (`-t10:10`), binding to a unix socket (`-s unix`).  2,000 clients are created, using 40 thread loops (`-l40`), and the default of 50 client connections per thread (no `-c` argument).

### Misc Notes

1. Due to some permission issues with my Windows WSL2/Ubuntu, the unix bind path is a file in $HOME (`skt.unix`).

2. `run_socket_times.sh` may need to be set as executable.
    ```
    chmod +x ./misc/run_ssl_socket_times.sh
    ```
3. This was setup to test ssl changes, so the time it takes for Puma to write the response wasn't a concern.  In the test framework, it is accounted for.

4. Locally I run Windows, and recently started runing WSL2/Ubuntu 20.04.  Hence, the script is the first real script I've written and run locally.  It may look like it.