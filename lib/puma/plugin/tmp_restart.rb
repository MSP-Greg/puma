# frozen_string_literal: true

require 'puma/plugin'

Puma::Plugin.create do
  def start(launcher)
    path = File.join("tmp", "restart.txt")

    orig = nil

    # If we can't write to the path, then just don't bother with this plugin
    begin
      File.write(path, "") unless File.exist?(path)
      orig = File.mtime path
    rescue SystemCallError
      return
    end

    in_background do
      while true
        sleep 1

        begin
          mtime = File.mtime path
        rescue SystemCallError
          # If the file has disappeared, assume that means don't restart
        else
          if mtime > orig
            launcher.restart
            break
          end
        end
      end
    end
  end
end
