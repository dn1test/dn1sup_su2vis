# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'

module Dn1sup
  module Su2vis
    # Галерея на диске: превью и финалы живут в папке пользователя (out_dir),
    # рядом с каждой картинкой — сайдкар .json с параметрами генерации.
    # Удаление — только по явной команде из панели (иконка ✕ на картинке),
    # автоматической чистки нет.
    module Gallery
      module_function

      IMAGE_EXTS = %w[.png .jpg .jpeg].freeze

      # Превью: байты + мета -> файл "<имя>.png" и сайдкар "<имя>.png.json".
      # Возвращает полный путь картинки.
      def save_preview(dir, bytes, meta = {})
        FileUtils.mkdir_p(dir.to_s)
        base = "preview_s#{meta['scene'].to_i}_seed#{meta['seed'].to_i}" \
               "_v#{meta['variant'].to_i}_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
        path = unique_path(dir.to_s, base, '.png')
        File.binwrite(path, bytes)
        write_sidecar(path, 'preview', meta)
        path
      end

      # Финал: сайдкар к уже записанному файлу. Best-effort: ошибку только
      # предупреждаем, генерацию не роняем.
      def save_sidecar(path, kind, meta = {})
        write_sidecar(path.to_s, kind.to_s, meta)
        true
      rescue StandardError => e
        warn "[Su2vis] gallery sidecar: #{e.message}"
        false
      end

      # Все записи папки: сначала сайдкары (*.json), затем одиночные картинки
      # без сайдкара (старые финалы). Новейшие первыми.
      def list(dir)
        d = dir.to_s
        return [] if d.empty? || !File.directory?(d)
        entries = []
        Dir.glob(File.join(d, '*.json')).each do |sp|
          m = JSON.parse(File.read(sp, encoding: 'UTF-8')) rescue nil
          next unless m.is_a?(Hash) && m['file']
          img = File.join(d, File.basename(m['file'].to_s))
          next unless File.file?(img)
          entries << normalize(m.merge('file' => img, 'mtime' => File.mtime(img).to_f))
        end
        have = entries.map { |e| e['file'] }.to_h { |f| [f, true] }
        Dir.children(d).each do |name|
          next unless IMAGE_EXTS.include?(File.extname(name).downcase)
          next if File.exist?(File.join(d, "#{name}.json"))
          img = File.join(d, name)
          next if have[img]
          kind = name.start_with?('preview_') ? 'preview' : 'final'
          entries << { 'kind' => kind, 'file' => img, 'scene' => nil,
                       'seed' => nil, 'variant' => nil, 'width' => nil,
                       'height' => nil, 'mtime' => File.mtime(img).to_f }
        end
        entries.sort_by { |e| -(e['mtime'] || 0) }
      end

      # Удаление картинки + её сайдкара. Только внутри dir, только по имени
      # файла (пути с .. отклоняются). Возвращает {ok} / бросает исключение.
      def remove(dir, file)
        d = File.expand_path(dir.to_s)
        img = File.expand_path(File.basename(file.to_s), d)
        raise 'пустое имя файла' if File.basename(file.to_s).empty?
        raise 'файл вне папки результатов' unless img.start_with?(d + File::SEPARATOR)
        raise 'файл не найден' unless File.file?(img)
        FileUtils.rm_f(img)
        FileUtils.rm_f("#{img}.json")
        Log.append('gallery_delete', 'file' => File.basename(img))
        { ok: true, file: img }
      end

      def write_sidecar(path, kind, meta)
        m = meta.is_a?(Hash) ? meta : {}
        doc = {
          'kind' => kind, 'file' => File.basename(path.to_s),
          'scene' => m['scene'], 'seed' => m['seed'], 'variant' => m['variant'],
          'width' => m['width'], 'height' => m['height'],
          'prompt' => m['prompt'], 'strength' => m['strength'],
          'steps' => m['steps'], 'guidance' => m['guidance'],
          'workflow' => m['workflow'], 'enhance_prompt' => m['enhance_prompt'],
          'upscale' => m['upscale'], 'final_strength' => m['final_strength'],
          'from_preview' => m['from_preview'], 'model' => m['model'],
          'mixins' => m['mixins'],
          'created_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S')
        }.compact
        File.write("#{path}.json", JSON.pretty_generate(doc), encoding: 'UTF-8')
        doc
      end

      def normalize(m)
        %w[scene seed variant width height].each do |k|
          m[k] = m[k].to_i unless m[k].nil?
        end
        m
      end

      def unique_path(dir, base, ext)
        path = File.join(dir, "#{base}#{ext}")
        n = 1
        while File.exist?(path) || File.exist?("#{path}.json")
          n += 1
          path = File.join(dir, "#{base}_#{n}#{ext}")
        end
        path
      end
    end
  end
end
