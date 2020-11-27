# frozen_string_literal: true

require_relative 'helpers/svr_popen'

class TestPOpenPhasedRestartChangeGemVersion < ::TestPuma::SvrPOpen

  def setup
    @puma_dir = File.absolute_path Dir.pwd
    super
  end

  def teardown
    return if skipped?
    FileUtils.rm current_release_symlink, force: true
    unless @puma_dir == File.absolute_path(Dir.pwd)
      Dir.chdir @puma_dir
    end
    super
  end

  def test_changing_nio4r_version
    change_gem_version old_app_dir: 'change_gem_version/old_nio4r',
                       old_version: '2.3.0',
                       new_app_dir: 'change_gem_version/new_nio4r',
                       new_version: '2.3.1'
  end

  def test_changing_json_version
    change_gem_version old_app_dir: 'change_gem_version/old_json',
                       old_version: '2.3.1',
                       new_app_dir: 'change_gem_version/new_json',
                       new_version: '2.3.0'
  end

  def test_changing_json_version_after_querying_stats_from_status_server
    ctrl_type :tcp
    before_restart = ->() do
      cli_pumactl('stats').read
    end

    change_gem_version before_restart: before_restart,
                       old_app_dir: 'change_gem_version/old_json',
                       old_version: '2.3.1',
                       new_app_dir: 'change_gem_version/new_json',
                       new_version: '2.3.0'
  end

  def test_changing_json_version_after_querying_gc_stats_from_status_server
    ctrl_type :tcp
    before_restart = ->() do
      cli_pumactl('gc-stats').read
    end

    change_gem_version before_restart: before_restart,
                       old_app_dir: 'change_gem_version/old_json',
                       old_version: '2.3.1',
                       new_app_dir: 'change_gem_version/new_json',
                       new_version: '2.3.0'
  end

  def test_changing_json_version_after_querying_thread_backtraces_from_status_server
    ctrl_type :tcp
    before_restart = ->() do
      cli_pumactl('thread-backtraces').read
    end

    change_gem_version before_restart: before_restart,
                       old_app_dir: 'change_gem_version/old_json',
                       old_version: '2.3.1',
                       new_app_dir: 'change_gem_version/new_json',
                       new_version: '2.3.0'
  end

  def test_changing_json_version_after_accessing_puma_stats_directly
    change_gem_version old_app_dir: 'change_gem_version/old_json_with_puma_stats_after_fork',
                       old_version: '2.3.1',
                       new_app_dir: 'change_gem_version/new_json_with_puma_stats_after_fork',
                       new_version: '2.3.0'
  end

  private

  def change_gem_version(old_app_dir:,
                         new_app_dir:,
                         old_version:,
                         new_version:,
                         before_restart: nil)
    skip_unless_signal_exist? :USR1

    if ENV['PUMA_CI_WORKER_GEM_INDEPENDENCE']
      @system_out = STDOUT
      @server_log = true
    else
      @system_out = File::NULL
      @server_log = nil
    end

    set_release_symlink File.expand_path(old_app_dir, __dir__)

    Dir.chdir(current_release_symlink) do
      with_unbundled_env do
        system("bundle config --local path vendor/bundle", out: @system_out, err: @system_out)
        system("bundle install", out: @system_out, err: @system_out)
        start_puma "-q --prune-bundler -w 1", log: @server_log
      end
    end

    assert_equal old_version, connect_get_body

    before_restart.call if before_restart

    set_release_symlink File.expand_path(new_app_dir, __dir__)
    Dir.chdir(current_release_symlink) do
      with_unbundled_env do
        system("bundle config --local path vendor/bundle", out: @system_out, err: @system_out)
        system("bundle install", out: @system_out, err: @system_out)
      end
    end
    start_phased_restart

    assert_equal new_version, connect_get_body
  end

  def current_release_symlink
    File.expand_path "change_gem_version/current", __dir__
  end

  def set_release_symlink(target_dir)
    FileUtils.rm current_release_symlink, force: true
    FileUtils.symlink target_dir, current_release_symlink, force: true
  end

  def start_phased_restart
    Process.kill :USR1, @pid
    assert_server_gets(/booted in [.0-9]+s, phase: 1/, log: @server_log)
  end

  def with_unbundled_env
    bundler_ver = Gem::Version.new(Bundler::VERSION)
    if bundler_ver < Gem::Version.new('2.1.0')
      Bundler.with_clean_env { yield }
    else
      Bundler.with_unbundled_env { yield }
    end
  end
end if ::Process.respond_to?(:fork)
