require_relative "helper"
require_relative "helpers/integration"

class TestPreserveBundlerEnv < TestIntegration

  BUNDLE_CACHE = ENV['BUNDLE_CACHE_PATH']

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

    env = {
      # Intentionally set this to something we wish to keep intact on restarts
      "BUNDLE_GEMFILE" => "Gemfile.bundle_env_preservation_test",
      # Don't allow our (rake test's) original env to interfere with the child process
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    }
    env['BUNDLE_CACHE_PATH'] = BUNDLE_CACHE if BUNDLE_CACHE
    Dir.chdir(File.expand_path("bundle_preservation_test", __dir__)) do
      cli_server "-q -w 1 -t1:5 --prune-bundler", env: env
    end
    skt = send_http
    initial_reply = skt.read_body
    assert_match("Gemfile.bundle_env_preservation_test", initial_reply)
    restart_server skt
    new_reply = skt.read_body
    assert_match("Gemfile.bundle_env_preservation_test", new_reply)
  end

  def test_worker_forking_preserves_bundler_config_path
    skip_unless_signal_exist? :TERM

    env = {
      # Disable the .bundle/config file in the bundle_app_config_test directory
      "BUNDLE_APP_CONFIG" => "/dev/null",
      # Don't allow our (rake test's) original env to interfere with the child process
      "BUNDLE_GEMFILE" => nil,
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    }
    env['BUNDLE_CACHE_PATH'] = BUNDLE_CACHE if BUNDLE_CACHE
    Dir.chdir File.expand_path("bundle_app_config_test", __dir__) do
      cli_server "-q -w 1 -t1:5 --prune-bundler", env: env
    end
    body = send_http_read_resp_body
    assert_equal "Hello World", body
  end

  def test_phased_restart_preserves_unspecified_bundle_gemfile
    skip_unless_signal_exist? :USR1

    env = {
      "BUNDLE_GEMFILE" => nil,
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    }
    env['BUNDLE_CACHE_PATH'] = BUNDLE_CACHE if BUNDLE_CACHE
    set_release_symlink File.expand_path("bundle_preservation_test/version1", __dir__)
    Dir.chdir(current_release_symlink) do
      cli_server "-q -w 1 -t1:5 --prune-bundler", env: env
    end

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

    assert wait_for_server_to_match(/booted in [.\d]+s, phase: 1/)
  end
end
