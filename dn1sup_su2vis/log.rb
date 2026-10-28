# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'

module Dn1sup
  module Su2vis
    # Журнал работы: JSON-строки в su2vis.log рядом с настройками проекта.
    # События: job_start / scene_done / job_done (status, error, длительности).
    module Log
      module_function

      @path_override = nil

      def path_override=(p)
        @path_override = p
      end

      # Журнал — в папке настроек проекта (<имя>_su2vis/su2vis.log, рядом
      # с su2vis.yaml), а не в out/ (иначе «удалить все» в галерее и
      # ручная чистка out/ уносят историю). Папка проекта без настроек
      # (ещё не создана) — фолбэк в legacy_out_dir, чтобы лог не создавал
      # пустые папки раньше времени; как и модель не сохранена.
      def path
        return @path_override if @path_override

        d = Settings.project_dir
        d = nil unless d && Settings.project_settings_exist?(d)
        d = Settings.legacy_out_dir if d.nil? || d.to_s.empty?
        File.join(d.to_s, 'su2vis.log')
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
