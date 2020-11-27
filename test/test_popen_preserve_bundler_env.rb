# frozen_string_literal: true

require_relative 'helpers/svr_popen'

class TestPOpenPreserveBundlerEnv < ::TestPuma::SvrPOpen
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
    # Must use `bundle exec puma` here, because otherwise Bundler may not be defined, which is required to trigger the bug
    workers 1
    cmd = "--prune-bundler"
    Dir.chdir(File.expand_path("bundle_preservation_test", __dir__)) do
      start_puma cmd, env: env
    end

    assert_match("Gemfile.bundle_env_preservation_test", connect_get_body)

    cli_pumactl :restart
    assert_server_gets cmd_to_log_str(:restart)

    assert_match("Gemfile.bundle_env_preservation_test", connect_get_body)
  end

  def test_phased_restart_preserves_unspecified_bundle_gemfile
    skip_unless_signal_exist? :USR2

    env = {
      "BUNDLE_GEMFILE" => nil,
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    }
    set_release_symlink File.expand_path("bundle_preservation_test/version1", __dir__)
    workers 1
    cmd = "--prune-bundler"
    Dir.chdir(current_release_symlink) do
      start_puma cmd, env: env
    end

    # Bundler itself sets ENV['BUNDLE_GEMFILE'] to the Gemfile it finds if ENV['BUNDLE_GEMFILE'] was unspecified
    expected_gemfile = File.expand_path("bundle_preservation_test/version1/Gemfile", __dir__).inspect
    assert_equal(expected_gemfile, connect_get_body)

    set_release_symlink File.expand_path("bundle_preservation_test/version2", __dir__)

    cli_pumactl :restart
    assert_server_gets cmd_to_log_str(:restart)

    expected_gemfile = File.expand_path("bundle_preservation_test/version2/Gemfile", __dir__).inspect
    assert_equal(expected_gemfile, connect_get_body)
  end

  private

  def current_release_symlink
    File.expand_path "bundle_preservation_test/current", __dir__
  end

  def set_release_symlink(target_dir)
    FileUtils.rm current_release_symlink, force: true
    FileUtils.symlink target_dir, current_release_symlink, force: true
  end
end
