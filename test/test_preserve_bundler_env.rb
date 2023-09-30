require_relative "helper"
require_relative "helpers/integration"

class TestPreserveBundlerEnv < TestIntegration
  def setup
    skip_unless :fork
    super
  end

  def teardown
    return if skipped?
    FileUtils.rm current_release_symlink, force: true
    super
  end

  # It does not wipe out BUNDLE_GEMFILE et al
  def test_usr2_restart_preserves_bundler_environment
    skip_unless_signal_exist? :USR2

    @bind_port = new_port
    env = {
      # Intentionally set this to something we wish to keep intact on restarts
      "BUNDLE_GEMFILE" => "Gemfile.bundle_env_preservation_test",
      # Don't allow our (rake test's) original env to interfere with the child process
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    }
    # Must use `bundle exec puma` here, because otherwise Bundler may not be defined, which is required to trigger the bug
    cmd = "bundle exec puma -q -w 1 --prune-bundler -b #{bind_uri_str}"
    Dir.chdir(File.expand_path("bundle_preservation_test", __dir__)) do
      @server = IO.popen(env, cmd.split, "r")
    end
    wait_for_server_to_boot
    @pid = @server.pid
    socket = send_http
    initial_reply = socket.read_body
    assert_match("Gemfile.bundle_env_preservation_test", initial_reply)
    restart_server socket
    new_reply = socket.read_body
    assert_match("Gemfile.bundle_env_preservation_test", new_reply)
  end

  def test_worker_forking_preserves_bundler_config_path
    skip_unless_signal_exist? :TERM

    @bind_port = new_port
    env = {
      # Disable the .bundle/config file in the bundle_app_config_test directory
      "BUNDLE_APP_CONFIG" => "/dev/null",
      # Don't allow our (rake test's) original env to interfere with the child process
      "BUNDLE_GEMFILE" => nil,
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    }
    cmd = "bundle exec puma -q -w 1 --prune-bundler -b #{bind_uri_str}"
    Dir.chdir File.expand_path("bundle_app_config_test", __dir__) do
      @server = IO.popen(env, cmd.split, "r")
    end
    wait_for_server_to_boot
    @pid = @server.pid
    reply = send_http_read_resp_body
    assert_equal("Hello World", reply)
  end

  def test_phased_restart_preserves_unspecified_bundle_gemfile
    skip_unless_signal_exist? :USR1

    @bind_port = new_port
    env = {
      "BUNDLE_GEMFILE" => nil,
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    }
    set_release_symlink File.expand_path("bundle_preservation_test/version1", __dir__)
    cmd = "bundle exec puma -q -w 1 --prune-bundler -b #{bind_uri_str}"
    Dir.chdir(current_release_symlink) do
      @server = IO.popen(env, cmd.split, "r")
    end
    wait_for_server_to_boot
    @pid = @server.pid

    # Bundler itself sets ENV['BUNDLE_GEMFILE'] to the Gemfile it finds if ENV['BUNDLE_GEMFILE'] was unspecified
    initial_reply = send_http_read_resp_body
    expected_gemfile = File.expand_path("bundle_preservation_test/version1/Gemfile", __dir__).inspect
    assert_equal(expected_gemfile, initial_reply)

    set_release_symlink File.expand_path("bundle_preservation_test/version2", __dir__)
    start_phased_restart

    new_reply = send_http_read_resp_body
    expected_gemfile = File.expand_path("bundle_preservation_test/version2/Gemfile", __dir__).inspect
    assert_equal(expected_gemfile, new_reply)
  end

  private

  def current_release_symlink
    File.expand_path "bundle_preservation_test/current", __dir__
  end

  def set_release_symlink(target_dir)
    FileUtils.rm current_release_symlink, force: true
    FileUtils.symlink target_dir, current_release_symlink, force: true
  end

  def start_phased_restart
    Process.kill :USR1, @pid

    true while @server.gets !~ /booted in [.0-9]+s, phase: 1/
  end
end
