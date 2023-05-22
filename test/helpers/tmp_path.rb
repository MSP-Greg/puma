# frozen_string_literal: true

require 'tempfile'

module TestPuma

  # Contains helper methods that create files for use with the test suite.

  module PumaTempFile # Ruby's std lib is Tempfile

    PUMA_TMPDIR =
      begin
        if (rt = ENV['RUNNER_TEMP']) && Dir.exist?(rt)
          rt
        else
          nil
        end
      end

    # With some macOS configurations, the following error may be raised when
    # creating a UNIXSocket:
    #
    # too long unix socket path (106 bytes given but 104 bytes max) (ArgumentError)
    #
    PUMA_TMP_UNIX =
      begin
        if RUBY_PLATFORM.include? 'darwin'
          dir_temp = File.absolute_path("#{__dir__}/../../tmp")
          Dir.mkdir dir_temp unless Dir.exist? dir_temp
          './tmp'
        elsif (rt = ENV['RUNNER_TEMP']) && Dir.exist?(rt)
          rt
        else
          nil
        end
      end


    def tmp_unix(extension = nil)
      path = Tempfile.create(['', extension], PUMA_TMP_UNIX) { |f| f.path }
      tmp_paths << path
      path
    end

    #
    def tmp_path(extension = nil)
      path = Tempfile.create(['', extension], PUMA_TMPDIR) { |f| f.path }
      tmp_paths << path
      path
    end

    def tmp_path_str(basename, data = nil, mode: File::BINARY)
      fio = Tempfile.create basename, PUMA_TMPDIR, mode: mode
      path = fio.path
      if data
        fio.write data
        fio.flush
      end
      fio.close
      tmp_paths << path
      path
    end

    def tmp_path_io(basename, data = nil, mode: File::BINARY)
      fio = Tempfile.create basename, ENV['RUNNER_TEMP'], mode: mode
      if data
        fio.write data
        fio.flush
        fio.rewind
      end
      @ios_to_close << fio if defined?(@ios_to_close)
      fio
    end

    def tmp_paths
      @tmp_paths ||= []
    end

    def clean_tmp_paths
      while path = tmp_paths.pop
        delete_tmp_path(path)
      end
    end

    def delete_tmp_path(path)
      File.unlink(path)
    rescue Errno::ENOENT
    end
  end
end
