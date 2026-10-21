# frozen_string_literal: true

require 'base64'
require 'fileutils'
require 'json'
require 'time'

module Dn1sup
  module Su2vis
    # Картинки-примеси: дополнительные референсы для генерации.
    # Лежат в <проект>/su2vis/mixins/ (legacy — рядом с out_dir):
    # mix_<дата>_<n>.<ext> + сайдкар <файл>.json {caption, active, name}.
    # Подпись указывает, что именно взять с картинки для примеси,
    # при генерации дописывается к промпту.
    module Mixins
      module_function

      IMAGE_EXTS = %w[.png .jpg .jpeg .webp].freeze
      DIRNAME = 'mixins'.freeze

      # Папка примесей: в проекте — su2vis/mixins, иначе — <out_dir>/mixins.
      # dir = :auto — по активной модели; иначе явный путь проекта/out.
      def base_dir(dir = :auto)
        d = dir == :auto ? Settings.project_dir : dir
        if !d.nil? && File.basename(d.to_s) == Settings::PROJECT_DIRNAME
          File.join(d.to_s, DIRNAME)
        else
          out = dir == :auto ? Settings.out_dir : dir.to_s
          File.join(out.to_s, DIRNAME)
        end
      end

      def list(dir = :auto)
        d = base_dir(dir)
        return [] unless File.directory?(d)
        entries = []
        Dir.children(d).each do |name|
          next unless IMAGE_EXTS.include?(File.extname(name).downcase)
          next if name.end_with?('.json')
          img = File.join(d, name)
          next unless File.file?(img)
          meta = read_sidecar("#{img}.json")
          entries << {
            'id' => name, 'file' => img, 'name' => meta['name'] || name,
            'caption' => meta['caption'] || '', 'active' => meta.fetch('active', true),
            'mtime' => File.mtime(img).to_f
          }
        end
        entries.sort_by { |e| e['mtime'] || 0 }
      end

      # data_url картинки из <input type=file> панели -> файл + thumb-data_url.
      def add_data(data_url, name = '', dir = :auto)
        m = data_url.to_s.match(%r{\Adata:image/(png|jpeg|webp);base64,(.+)\z}m)
        raise 'нет картинки (ожидался data-url png/jpeg/webp)' if m.nil?
        raw = Base64.strict_decode64(m[2])
        raise 'пустая картинка' if raw.empty?
        ext = m[1] == 'jpeg' ? '.jpg' : ".#{m[1]}"
        save_bytes(raw, ext, name.to_s, dir)
      end

      # Путь с диска (через UI.openpanel): копируем в папку примесей.
      def add_path(src, dir = :auto)
        s = src.to_s
        raise 'файл не найден' unless File.file?(s)
        raise 'нужна картинка png/jpg/webp' unless IMAGE_EXTS.include?(File.extname(s).downcase)
        save_bytes(File.binread(s), File.extname(s).downcase, File.basename(s), dir)
      end

      def update(id, caption: nil, active: nil, dir: :auto)
        d = File.expand_path(base_dir(dir).to_s)
        img = File.expand_path(File.basename(id.to_s), d)
        raise 'файл вне папки примесей' unless img.start_with?(d + File::SEPARATOR)
        raise 'файл не найден' unless File.file?(img)
        meta = read_sidecar("#{img}.json")
        meta['caption'] = caption.to_s[0, 500] unless caption.nil?
        meta['active'] = (active == true || active.to_s == 'true') unless active.nil?
        write_sidecar("#{img}.json", img, meta)
        { 'id' => File.basename(img), 'file' => img, 'name' => meta['name'],
          'caption' => meta['caption'] || '', 'active' => meta.fetch('active', true) }
      end

      def remove(id, dir = :auto)
        d = File.expand_path(base_dir(dir).to_s)
        img = File.expand_path(File.basename(id.to_s), d)
        raise 'пустое имя файла' if File.basename(id.to_s).empty?
        raise 'файл вне папки примесей' unless img.start_with?(d + File::SEPARATOR)
        raise 'файл не найден' unless File.file?(img)
        FileUtils.rm_f(img)
        FileUtils.rm_f("#{img}.json")
        Log.append('mixins_delete', 'file' => File.basename(img))
        { ok: true, id: File.basename(img) }
      end

      # Активные примеси для задачи: [{path, caption}].
      def active_for_job(items)
        Array(items).filter_map do |m|
          next unless m.is_a?(Hash)
          p = (m['path'] || m['file'] || '').to_s
          next if p.empty? || !File.file?(p)
          cap = (m['caption'] || '').to_s
          next unless m.fetch('active', true) == true || m.fetch('active', true).to_s == 'true'
          { 'path' => p, 'caption' => cap }
        end
      end

      def save_bytes(raw, ext, name, dir)
        d = base_dir(dir)
        FileUtils.mkdir_p(d.to_s)
        base = "mix_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
        path = unique_path(d.to_s, base, ext)
        File.binwrite(path, raw)
        write_sidecar("#{path}.json", path, { 'name' => name.to_s[0, 120], 'caption' => '', 'active' => true })
        entry = { 'id' => File.basename(path), 'file' => path, 'name' => name.to_s,
                  'caption' => '', 'active' => true, 'mtime' => File.mtime(path).to_f }
        Log.append('mixins_add', 'file' => File.basename(path))
        entry
      end

      def read_sidecar(sp)
        return {} unless File.file?(sp.to_s)
        doc = JSON.parse(File.read(sp.to_s, encoding: 'UTF-8')) rescue nil
        doc.is_a?(Hash) ? doc : {}
      end

      def write_sidecar(sp, img, meta)
        m = meta.is_a?(Hash) ? meta : {}
        doc = { 'name' => m['name'] || File.basename(img.to_s),
                'caption' => (m['caption'] || '').to_s,
                'active' => m.fetch('active', true) ? true : false }
        File.write(sp.to_s, JSON.pretty_generate(doc), encoding: 'UTF-8')
        doc
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
