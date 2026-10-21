# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'

module Dn1sup
  module Su2vis
    # Журнал работы: JSON-строки в su2vis.log рядом с результатами.
    # События: job_start / scene_done / job_done (status, error, длительности).
    module Log
      module_function

      @path_override = nil

      def path_override=(p)
        @path_override = p
      end

      def path
        @path_override || File.join(Settings.out_dir, 'su2vis.log')
      end

      def append(event, data = {})
        FileUtils.mkdir_p(File.dirname(path))
        entry = { 'time' => Time.now.strftime('%Y-%m-%d %H:%M:%S'), 'event' => event.to_s }
        data.each { |k, v| entry[k.to_s] = v }
        File.open(path, 'a', encoding: 'UTF-8') { |f| f.puts(JSON.generate(entry)) }
        entry
      rescue StandardError => e
        warn "[Su2vis] log: #{e.message}"
        nil
      end

      def tail(n = 50)
        return [] unless File.file?(path)
        lines = File.readlines(path, encoding: 'UTF-8').last(n.to_i)
        lines.filter_map { |l| JSON.parse(l) rescue nil }
      rescue StandardError
        []
      end

      def clear
        FileUtils.rm_f(path)
        true
      end
    end
  end
end
