# Explanation of Commit b0e9577

## Commit Details
- **SHA**: b0e95778508e9c6cd9bca678043d330e38a580c6
- **Author**: MSP-Greg <Greg.mpls@gmail.com>
- **Date**: Tue Jan 27 11:19:48 2026 -0600
- **Message**: ci: helper.rb - fixup `UniquePort.call`, remove `sock.setsockopt(:SOCKET, :REUSEADDR, 1)`

## Summary
This commit modifies the `UniquePort.call` method in `test/helper.rb` to fix flaky integration tests in CI environments by removing the use of the `SO_REUSEADDR` socket option.

## What Changed

### Before
```ruby
module UniquePort
  def self.call(host = '127.0.0.1')
    TCPServer.open(host, 0) do |server|
      server.connect_address.ip_port
    end
  end
end
```

### After
```ruby
module UniquePort
  # below is similar to `Addrinfo.bind`, but comments out the
  # `sock.setsockopt(:SOCKET, :REUSEADDR, 1) use
  def self.call(host = '127.0.0.1')
    adddr_info = Addrinfo.tcp(host, 0)
      sock = Socket.new adddr_info.pfamily, adddr_info.socktype, adddr_info.protocol
    begin
      sock.ipv6only! if adddr_info.ipv6?
      # sock.setsockopt(:SOCKET, :REUSEADDR, 1)
      sock.bind adddr_info
      sock.connect_address.ip_port
    rescue Exception => e
      raise e
    ensure
      sock&.close unless sock&.closed?
    end
#    TCPServer.open(host, 0) do |server|
#      server.connect_address.ip_port
#    end
  end
end
```

## Why This Change Was Made

### The Problem: SO_REUSEADDR and Port Reuse Issues

The original implementation used `TCPServer.open`, which internally calls `sock.setsockopt(:SOCKET, :REUSEADDR, 1)`. This socket option allows a socket to bind to a port that is in the `TIME_WAIT` state, which can lead to problems in CI environments:

1. **Port Reuse Too Quickly**: When tests run rapidly in succession, a port that was just released might still be in `TIME_WAIT` state but can be immediately reused due to `SO_REUSEADDR`.

2. **Flaky Tests**: This can cause race conditions where:
   - Test A uses a port and closes it
   - Test B immediately gets the same port
   - Delayed packets from Test A arrive at Test B's socket
   - Test B fails unexpectedly due to receiving unexpected data

3. **CI Environment Sensitivity**: CI environments often run tests in parallel or rapid succession, making these race conditions more likely to occur.

### The Solution

The new implementation manually creates the socket without the `SO_REUSEADDR` option:

1. **Manual Socket Creation**: Instead of using `TCPServer.open`, the code now manually creates a socket using `Socket.new` with address information from `Addrinfo.tcp`.

2. **No SO_REUSEADDR**: The critical line `sock.setsockopt(:SOCKET, :REUSEADDR, 1)` is commented out, preventing immediate port reuse.

3. **Proper Cleanup**: The `ensure` block guarantees the socket is properly closed, preventing resource leaks.

4. **IPv6 Support**: The code still maintains IPv6 support with `sock.ipv6only!` when needed.

## Technical Details

### Key Components

- **`Addrinfo.tcp(host, 0)`**: Creates address information for a TCP socket on the specified host with port 0 (meaning the OS will assign an available port).

- **`Socket.new`**: Creates a raw socket with the family (IPv4/IPv6), socket type (STREAM), and protocol from the address info.

- **`sock.ipv6only!`**: When binding to an IPv6 address, this ensures the socket only accepts IPv6 connections, not IPv4-mapped IPv6 addresses.

- **`sock.bind`**: Binds the socket to the address, causing the OS to assign an available port.

- **`sock.connect_address.ip_port`**: Returns the port number that was assigned by the OS.

### Why Port 0 Works

When you bind a socket to port 0, the operating system automatically assigns an available ephemeral port. Without `SO_REUSEADDR`, the OS is more conservative about port assignment, helping to avoid the race conditions that caused flaky tests.

## Impact

This change makes the test suite more reliable by:
- Reducing flaky test failures in CI environments
- Ensuring better port isolation between test runs
- Maintaining the same functionality (getting a unique available port) but with safer behavior

## Related Issues

This commit is related to fixing flaky integration tests, particularly issue #3870 mentioned in the repository's recent commits.
