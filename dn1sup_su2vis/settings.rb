# frozen_string_literal: true

require 'sketchup.rb'
require 'json'
require 'fileutils'

module Dn1sup
  module Su2vis
    # Настройки: подключение (ключ студии) — глобально в SketchUp defaults,
    # всё остальное — per-file: su2vis/su2vis.json рядом с .skp модели.
    # Без модели (пустой path) или без папки проекта — legacy-режим:
    # чтение/запись через SketchUp defaults, как раньше.
    module Settings
      SECTION = 'dn1sup_su2vis'

      PROJECT_DIRNAME = 'su2vis'
      PROJECT_FILENAME = 'su2vis.json'

      # Только ключ — глобальный (машинный). Остальное — в папке проекта.
      GLOBAL_KEYS = %w[unsloth_key].freeze

      DEFAULTS = {
        'prompt' => 'Photorealistic render based on the provided sketch. Keep the exact same composition, geometry, proportions and scale of every object. Replace any silhouette scale figures with a real standing person in casual clothing (jeans, t-shirt) for human scale. Soft natural daylight, architectural photography, ultra-detailed, 8k, magazine quality. No watermarks, no logos, no text, no captions, no signatures, no letters, no words anywhere in the image. Clean editorial photograph without any overlay text.',
        'seed' => -1,
        'seed_locked' => false,
        'sketch_preset' => '1024x768',
        'preview_preset' => '256',
        'preview_variants' => 1,
        'preview_max' => 256,
        'final_strength' => 0.4,
        'final_mode' => 'sketch',
        'final_w' => 2048,
        'final_h' => 1536,
        'final_upscale' => 0.0,
        'workflow' => 'auto',
        'enhance_prompt' => true,
        'name_template' => '{scene}{suffix}_{date}',
        'strength' => 1.0,
        'steps' => 4,
        'guidance' => 1.0,
        'memory_mode' => 'balanced',
        'allow_oversized' => true,
        'use_scenes' => true,
        'use_mixins' => true,
        'suffix' => '_photorealistic',
        'ext' => 'jpg',
        'unsloth_url' => 'http://127.0.0.1:8888',
        'unsloth_key' => '',
        'unsloth_model' => 'unsloth/flux-3-image-klein-GGUF',
        'unsloth_gguf' => 'flux-3-image-klein-UD-Q4_K_XL.gguf'
      }.freeze

      SKETCH_PRESETS = %w[800x600 1024x768 1280x960].freeze
      PREVIEW_PRESETS = %w[512x384 640x480 768x576].freeze
      PREVIEW_SIZES = [128, 256, 512, 768].freeze

      PROJECT_KEYS = (DEFAULTS.keys - GLOBAL_KEYS).freeze

      module_function

      # Путь активной модели ('' — не сохранена). Только чтение, без записи.
      def model_path
        m = Sketchup.active_model
        return '' if m.nil?
        return '' unless m.respond_to?(:path)

        m.path.to_s
      rescue StandardError
        ''
      end

      # Папка проекта для пути модели: <dir модели>/su2vis. Пустой путь — nil.
      def project_dir_for(model_path)
        p = model_path.to_s
        return nil if p.empty?

        File.join(File.dirname(p), PROJECT_DIRNAME)
      end

      # Папка проекта активной модели (nil — модель не сохранена).
      def project_dir
        project_dir_for(model_path)
      end

      def project_settings_path(dir)
        File.join(dir.to_s, PROJECT_FILENAME)
      end

      def project_out_dir(dir)
        File.join(dir.to_s, 'out')
      end

      # Состояние проекта: 'unsaved' | 'missing' | 'ready'.
      # dir = :auto — по активной модели; иначе явный путь (для тестов).
      def project_state(dir = :auto)
        d = dir == :auto ? project_dir : dir
        return 'unsaved' if d.nil? || d.to_s.empty?
        return 'ready' if File.file?(project_settings_path(d))

        'missing'
      end

      # Сводка для панели: состояние + пути. Только чтение.
      def project_info(dir = :auto)
        d = dir == :auto ? project_dir : dir
        mp = dir == :auto ? model_path : ''
        {
          'state' => project_state(dir),
          'model_path' => mp,
          'model_name' => mp.empty? ? '' : File.basename(mp, '.skp'),
          'project_dir' => d.to_s,
          'out_dir' => d.nil? ? legacy_out_dir : project_out_dir(d),
          'settings_path' => d.nil? ? '' : project_settings_path(d)
        }
      end

      def all(dir = :auto)
        d = dir == :auto ? project_dir : dir
        if !d.nil? && File.file?(project_settings_path(d))
          h = {}
          DEFAULTS.each do |k, v|
            stored = GLOBAL_KEYS.include?(k) ? Sketchup.read_default(SECTION, k, nil) : nil
            stored = project_file_value(d, k) if stored.nil? && PROJECT_KEYS.include?(k)
            stored = Sketchup.read_default(SECTION, k, nil) if stored.nil?
            h[k] = stored.nil? ? v : coerce(k, stored)
          end
          h['out_dir'] = project_out_dir(d)
        else
          h = {}
          DEFAULTS.each do |k, v|
            stored = Sketchup.read_default(SECTION, k, nil)
            h[k] = stored.nil? ? v : coerce(k, stored)
          end
          h['out_dir'] = legacy_out_dir
        end
        info = project_info(dir)
        h['project_state'] = info['state']
        h['project_dir'] = info['project_dir']
        h['model_name'] = info['model_name']
        h['version'] = Dn1sup::Su2vis::VERSION
        h
      end

      def save(hash, dir = :auto)
        d = dir == :auto ? project_dir : dir
        ready = !d.nil? && File.file?(project_settings_path(d))
        h = hash.is_a?(Hash) ? hash : {}
        if ready
          proj = {}
          h.each do |k, v|
            key = k.to_s
            proj[key] = coerce(key, v) if PROJECT_KEYS.include?(key)
          end
          write_project_file(d, proj) unless proj.empty?
        else
          h.each do |k, v|
            key = k.to_s
            next unless DEFAULTS.key?(key)
            next if key == 'out_dir'

            Sketchup.write_default(SECTION, key, coerce(key, v))
          end
        end
        h.each do |k, v|
          key = k.to_s
          Sketchup.write_default(SECTION, key, coerce(key, v)) if GLOBAL_KEYS.include?(key)
        end
        # out_dir вручную — только в legacy-режиме (в проекте путь фиксирован).
        if !ready && (h.key?('out_dir') || h.key?('outDir'))
          Sketchup.write_default(SECTION, 'out_dir', (h['out_dir'] || h['outDir']).to_s)
        end
        all(dir)
      end

      # Создать папку проекта: su2vis/ + out/, затравка su2vis.json из
      # текущих эффективных настроек (включая несохранённые правки legacy).
      # Несохранённая модель — исключение: сначала сохранить .skp.
      def init_project(dir = :auto)
        d = dir == :auto ? project_dir : dir
        raise 'модель не сохранена: сохраните .skp (Файл → Сохранить), затем создайте su2vis/' if d.nil? || d.to_s.empty?

        FileUtils.mkdir_p(d.to_s)
        FileUtils.mkdir_p(project_out_dir(d))
        seed = {}
        cur = all(dir)
        PROJECT_KEYS.each { |k| seed[k] = cur[k] }
        write_project_file(d, seed)
        all(dir)
      end

      # Удаление папки проекта: только su2vis/ (проверка имени), рекурсивно.
      # После удаления all() отдаёт legacy/дефолт — панель снова предложит
      # создать папку рядом с файлом. Чужой путь отклоняется.
      def delete_project(dir = :auto)
        d = dir == :auto ? project_dir : dir
        raise 'модель не сохранена: удалять нечего' if d.nil? || d.to_s.empty?
        raise 'это не папка проекта su2vis' unless File.basename(d.to_s) == PROJECT_DIRNAME

        FileUtils.rm_rf(d.to_s) if File.exist?(d.to_s)
        all(dir)
      end

      def out_dir
        d = project_dir
        return project_out_dir(d) if !d.nil? && File.file?(project_settings_path(d))

        legacy_out_dir
      end

      def legacy_out_dir
        stored = Sketchup.read_default(SECTION, 'out_dir', nil)
        return stored.to_s unless stored.to_s.empty?
        File.join(ENV['USERPROFILE'] || Dir.home, 'Documents', 'dn1sup_su2vis', 'out')
      end

      # Значение ключа из файла проекта (nil — нет файла/ключа/битый JSON).
      def project_file_value(dir, key)
        sp = project_settings_path(dir)
        return nil unless File.file?(sp)

        doc = JSON.parse(File.read(sp, encoding: 'UTF-8'))
        return nil unless doc.is_a?(Hash) && doc.key?(key.to_s)

        doc[key.to_s]
      rescue StandardError
        nil
      end

      def write_project_file(dir, hash)
        sp = project_settings_path(dir)
        cur = {}
        if File.file?(sp)
          doc = JSON.parse(File.read(sp, encoding: 'UTF-8')) rescue nil
          cur = doc if doc.is_a?(Hash)
        end
        h = hash.is_a?(Hash) ? hash : {}
        h.each { |k, v| cur[k.to_s] = v if PROJECT_KEYS.include?(k.to_s) }
        FileUtils.mkdir_p(dir.to_s)
        File.write(sp, JSON.pretty_generate(cur), encoding: 'UTF-8')
        cur
      end

      def get(key)
        all[key.to_s]
      end

      def coerce(key, value)
        case key
        when 'seed' then value.to_i
        when 'seed_locked', 'allow_oversized', 'enhance_prompt', 'use_scenes', 'use_mixins' then value == true || value.to_s == 'true'
        when 'preview_max', 'steps', 'final_w', 'final_h', 'preview_variants' then value.to_i
        when 'strength', 'guidance', 'final_upscale', 'final_strength' then value.to_f
        else value.to_s
        end
      end

      # '1024x768' -> [1024, 768]; мусор -> nil
      def parse_size(str)
        m = str.to_s.strip.match(/\A(\d{3,4})\s*x\s*(\d{3,4})\z/i)
        m ? [m[1].to_i, m[2].to_i] : nil
      end

      # Размер превью зафиксирован: 256 ПО ШИРИНЕ (минимум API студии,
      # меньше — HTTP 422). Высота — по пропорциям эскиза.
      # preview_px оставлен для совместимости сохранённых настроек.
      def preview_px(str)
        px = str.to_s.strip.to_i
        PREVIEW_SIZES.include?(px) ? px : 256
      end
    end
  end
end
