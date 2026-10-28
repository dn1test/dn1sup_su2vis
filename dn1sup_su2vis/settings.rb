# frozen_string_literal: true

require 'sketchup.rb'
require 'json'
require 'fileutils'

module Dn1sup
  module Su2vis
    # Настройки: подключение (ключ студии) — глобально в SketchUp defaults,
    # всё остальное — per-file: <имя модели>_su2vis/su2vis.yaml рядом с .skp.
    # Старые su2vis/ и su2vis_<имя>/ при создании проекта переезжают под
    # новое имя целиком (см. migrate_legacy_project) — молча в них больше
    # не работаем, иначе папка с именем файла не появляется никогда.
    # Без модели (пустой path) — legacy-режим: чтение/запись через
    # SketchUp defaults, как раньше.
    module Settings
      SECTION = 'dn1sup_su2vis'

      PROJECT_DIRNAME = 'su2vis'.freeze
      PROJECT_FILENAME = 'su2vis.yaml'.freeze
      LEGACY_PROJECT_FILENAME = 'su2vis.json'.freeze
      # Рамки сцен — бэкап атрибутов страниц: переживают выход без
      # сохранения .skp (ключ вне DEFAULTS, только в файле проекта).
      SCENE_BOXES_KEY = 'scene_boxes'.freeze

      # Только ключ, автозапуск и путь бинарника — глобальные (машинные).
      # Остальное — в папке проекта.
      GLOBAL_KEYS = %w[unsloth_key unsloth_autostart unsloth_cmd].freeze

      DEFAULTS = {
        'prompt' => 'Photorealistic render based on the provided sketch. Keep the exact same composition, geometry, proportions and scale of every object. Replace any silhouette scale figures with a real standing person in casual clothing (jeans, t-shirt) for human scale. Soft natural daylight, architectural photography, ultra-detailed, 8k, magazine quality. No watermarks, no logos, no text, no captions, no signatures, no letters, no words anywhere in the image. Clean editorial photograph without any overlay text.',
        'seed' => -1,
        'sketch_preset' => '1600x1200',
        'sketch_source' => 'hd',
        'sketch_style' => 'model',
        'sketch_thin_lines' => true,
        'sketch_hide_dims' => true,
        'sketch_autocrop' => false,
        'sketch_white_bg' => false,
        'sketch_no_shadows' => false,
        'preview_variants' => 1,
        'preview_random_seeds' => true,
        'final_mode' => 'sketch',
        'final_w' => 2048,
        'final_h' => 1536,
        'workflow' => 'auto',
        'geometry_lock' => true,
        'name_template' => '{scene}{suffix}_{date}',
        'strength' => 1.0,
        'steps' => 16,
        'guidance' => 1.0,
        'memory_mode' => 'balanced',
        'studio_precision' => 'auto',
        'studio_text_encoder_precision' => 'default',
        'studio_attention' => 'auto',
        'studio_engine' => 'auto',
        'studio_speed' => 'auto',
        'studio_step_cache' => 'auto',
        'studio_cpu_offload' => true,
        'studio_live_preview' => true,
        'allow_oversized' => true,
        'use_scenes' => true,
        'use_mixins' => true,
        'mixins_default_role' => 'auto',
        'mixins_default_apply' => 'both',
        'suffix' => '_photorealistic',
        'ext' => 'jpg',
        'unsloth_url' => 'http://127.0.0.1:8888',
        'unsloth_key' => '',
        'unsloth_autostart' => true,
        'unsloth_cmd' => 'unsloth',
        'unsloth_model' => 'unsloth/flux-3-image-klein-GGUF',
        'unsloth_gguf' => 'flux-3-image-klein-UD-Q4_K_XL.gguf'
      }.freeze

      SKETCH_PRESETS = %w[1200x900 1600x1200 2000x1500].freeze
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

      # Имя папки проекта из имени модели: <имя .skp>_su2vis. Запрещённые в
      # Windows символы и хвосты «._ » чистятся, длина клампится — иначе
      # FileUtils.mkdir_p на такой папке упадёт. Пустое имя (некуда чистить) —
      # просто su2vis. Старый формат su2vis_<имя> признаётся как чужой-не-свой:
      # чтение/удаление его понимает (project_dirname?), новые папки — только
      # <имя>_su2vis.
      def project_dirname_for(model_path)
        safe = File.basename(model_path.to_s, '.*')
                .gsub(/[\/\\:*?"<>|]+/, '_')
                .gsub(/[.\s]+\z/, '')
                .strip[0, 60].to_s
        safe.empty? ? PROJECT_DIRNAME : "#{safe}_#{PROJECT_DIRNAME}"
      end

      # Папка проекта для пути модели: <dir модели>/su2vis_<имя модели>.
      # Пустой путь — nil.
      def project_dir_for(model_path)
        p = model_path.to_s
        return nil if p.empty?

        File.join(File.dirname(p), project_dirname_for(p))
      end

      # Папка проекта: su2vis (самые старые), su2vis_* (формат 0.20.x),
      # *_su2vis (текущий формат). Чужой путь отклоняется.
      def project_dirname?(base)
        b = base.to_s
        b == PROJECT_DIRNAME || b.start_with?("#{PROJECT_DIRNAME}_") ||
          b.end_with?("_#{PROJECT_DIRNAME}")
      end

      # Переезд со старых папок (su2vis/, su2vis_<имя>/): если новой
      # <имя>_su2vis/ ещё нет (ни папки, ни настроек), а старая с настройками
      # есть рядом — переносим её целиком под новое имя (настройки, out/,
      # mixins/). Новая с настройками всегда побеждает; чужое не трогаем.
      # Возвращает путь старой папки или nil. Данные не теряются: перенос
      # через mv в пределах одной папки; при сбое — предупреждение, старая
      # остаётся на месте.
      def migrate_legacy_project(new_dir)
        return nil if new_dir.nil? || new_dir.to_s.empty?
        return nil if File.basename(new_dir.to_s) == PROJECT_DIRNAME
        return nil if File.exist?(new_dir.to_s) || project_settings_exist?(new_dir)

        dir = File.dirname(new_dir.to_s)
        base = File.basename(new_dir.to_s)
        # 0.20.x: su2vis_<имя> — ищем пару к новой <имя>_su2vis.
        old_prefixed = File.join(dir, "#{PROJECT_DIRNAME}_#{base.sub(/_#{PROJECT_DIRNAME}\z/, '')}")
        old_plain = File.join(dir, PROJECT_DIRNAME)
        old = [old_prefixed, old_plain].find { |c| project_settings_exist?(c) }
        return nil if old.nil?

        FileUtils.mv(old, new_dir)
        Log.append('project_migrated', 'from' => old.to_s, 'to' => new_dir.to_s)
        old
      rescue StandardError => e
        warn "[Su2vis] migrate legacy project: #{e.message}"
        nil
      end

      # Папка проекта активной модели: всегда <имя>_su2vis рядом с .skp
      # (nil — модель не сохранена). Старые папки молча не подхватываются —
      # переезд только через migrate_legacy_project при создании.
      def project_dir
        project_dir_for(model_path)
      end

      def project_settings_path(dir)
        File.join(dir.to_s, PROJECT_FILENAME)
      end

      # Путь настроек 0.20.x (su2vis.json): читаем при переезде,
      # пишем всегда новый su2vis.yaml.
      def legacy_settings_path(dir)
        File.join(dir.to_s, LEGACY_PROJECT_FILENAME)
      end

      # Файл настроек есть в любом формате (yaml — новый, json — переезд).
      def project_settings_exist?(dir)
        return false if dir.nil?

        File.file?(project_settings_path(dir)) || File.file?(legacy_settings_path(dir))
      end

      # Существующий файл настроек (иначе путь нового yaml).
      def project_settings_existing_path(dir)
        sp = project_settings_path(dir)
        return sp if File.file?(sp)

        lp = legacy_settings_path(dir)
        File.file?(lp) ? lp : sp
      end

      # Весь документ настроек: новый yaml предпочтителен, старый json —
      # для переезда (следующая запись переедет в yaml). Мусор — {}.
      def read_project_doc(dir)
        return {} if dir.nil?

        sp = project_settings_path(dir)
        lp = legacy_settings_path(dir)
        path = File.file?(sp) ? sp : (File.file?(lp) ? lp : nil)
        return {} if path.nil?

        parse_project_doc(File.read(path, encoding: 'UTF-8'))
      rescue StandardError
        {}
      end

      def parse_project_doc(str)
        doc = nil
        begin
          require 'psych'
          doc = Psych.safe_load(str)
        rescue StandardError
          doc = nil
        end
        unless doc.is_a?(Hash)
          begin
            doc = JSON.parse(str)
          rescue StandardError
            doc = nil
          end
        end
        doc.is_a?(Hash) ? doc : {}
      end

      def dump_project_doc(doc)
        h = doc.is_a?(Hash) ? doc : {}
        begin
          require 'psych'
          Psych.dump(h)
        rescue StandardError
          JSON.pretty_generate(h)
        end
      end

      def write_project_doc(dir, doc)
        FileUtils.mkdir_p(dir.to_s)
        File.write(project_settings_path(dir), dump_project_doc(doc), encoding: 'UTF-8')
        doc.is_a?(Hash) ? doc : {}
      end

      # Бэкап рамок сцен (Scenes.save_boxes дублирует сюда): переживает
      # выход без сохранения .skp. Ключ — индекс сцены строкой.
      def scene_boxes_backup(dir, index)
        return [] if dir.nil? || dir.to_s.empty?

        doc = read_project_doc(dir)
        map = doc.is_a?(Hash) ? doc[SCENE_BOXES_KEY] : nil
        arr = map.is_a?(Hash) ? map[index.to_i.to_s] : nil
        arr.is_a?(Array) ? arr : []
      rescue StandardError
        []
      end

      def save_scene_boxes_backup(dir, index, boxes)
        return [] if dir.nil? || dir.to_s.empty?

        doc = read_project_doc(dir)
        map = doc[SCENE_BOXES_KEY]
        map = {} unless map.is_a?(Hash)
        arr = boxes.is_a?(Array) ? boxes : []
        if arr.empty?
          map.delete(index.to_i.to_s)
        else
          map[index.to_i.to_s] = arr
        end
        doc[SCENE_BOXES_KEY] = map
        write_project_doc(dir, doc)
        arr
      rescue StandardError
        []
      end

      def project_out_dir(dir)
        File.join(dir.to_s, 'out')
      end

      # Состояние проекта: 'unsaved' | 'missing' | 'ready'.
      # dir = :auto — по активной модели; иначе явный путь (для тестов).
      def project_state(dir = :auto)
        d = dir == :auto ? project_dir : dir
        return 'unsaved' if d.nil? || d.to_s.empty?
        return 'ready' if project_settings_exist?(d)

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
          'settings_path' => d.nil? ? '' : project_settings_existing_path(d)
        }
      end

      # Только klein: модель, файл, шаги и guidance зафиксированы.
      # Остальное (промпт, сила, размеры) — per-file как раньше.
      KLEIN_MODEL = 'unsloth/flux-3-image-klein-GGUF'.freeze
      KLEIN_GGUF = 'flux-3-image-klein-UD-Q4_K_XL.gguf'.freeze

      def force_klein!(h)
        h['unsloth_model'] = KLEIN_MODEL
        h['unsloth_gguf'] = KLEIN_GGUF if h['unsloth_gguf'].to_s.empty?
        h['steps'] = coerce('steps', h['steps'])
        h['guidance'] = 1.0
        h['workflow'] = coerce('workflow', h['workflow'])
        h['memory_mode'] = coerce('memory_mode', h['memory_mode'])
        h['runs'] = coerce('runs', h['runs'])
        h['studio_precision'] = coerce('studio_precision', h['studio_precision'])
        h['studio_text_encoder_precision'] = coerce('studio_text_encoder_precision', h['studio_text_encoder_precision'])
        h['studio_attention'] = coerce('studio_attention', h['studio_attention'])
        h['studio_engine'] = coerce('studio_engine', h['studio_engine'])
        h['studio_speed'] = coerce('studio_speed', h['studio_speed'])
        h['studio_step_cache'] = coerce('studio_step_cache', h['studio_step_cache'])
        h['studio_cpu_offload'] = coerce('studio_cpu_offload', h['studio_cpu_offload'])
        h['studio_live_preview'] = coerce('studio_live_preview', h['studio_live_preview'])
        h
      end

      def all(dir = :auto)
        d = dir == :auto ? project_dir : dir
        if !d.nil? && project_settings_exist?(d)
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
        force_klein!(h)
      end

      def save(hash, dir = :auto)
        d = dir == :auto ? project_dir : dir
        ready = !d.nil? && project_settings_exist?(d)
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

      # Создать папку проекта: <имя>_su2vis/ + out/, затравка su2vis.yaml из
      # текущих эффективных настроек (включая несохранённые правки legacy).
      # Старая su2vis/ или su2vis_<имя>/ рядом сначала переезжает под новое
      # имя целиком (настройки и рендеры сохраняются). Несохранённая модель —
      # исключение: сначала сохранить .skp.
      def init_project(dir = :auto)
        d = dir == :auto ? project_dir : dir
        raise 'модель не сохранена: сохраните .skp (Файл → Сохранить), затем создайте <имя>_su2vis/' if d.nil? || d.to_s.empty?

        migrate_legacy_project(d)
        FileUtils.mkdir_p(d.to_s)
        FileUtils.mkdir_p(project_out_dir(d))
        seed = {}
        cur = all(dir)
        PROJECT_KEYS.each { |k| seed[k] = cur[k] }
        write_project_file(d, seed)
        all(dir)
      end

      # Удаление папки проекта: только su2vis/, su2vis_<имя>/ (старый
      # формат) или <имя>_su2vis/ (проверка имени), рекурсивно. После удаления
      # all() отдаёт legacy/дефолт — панель снова предложит создать папку
      # рядом с файлом. Чужой путь отклоняется.
      def delete_project(dir = :auto)
        d = dir == :auto ? project_dir : dir
        raise 'модель не сохранена: удалять нечего' if d.nil? || d.to_s.empty?
        raise 'это не папка проекта su2vis' unless project_dirname?(File.basename(d.to_s))

        FileUtils.rm_rf(d.to_s) if File.exist?(d.to_s)
        all(dir)
      end

      def out_dir
        d = project_dir
        return project_out_dir(d) if !d.nil? && project_settings_exist?(d)

        legacy_out_dir
      end

      def legacy_out_dir
        stored = Sketchup.read_default(SECTION, 'out_dir', nil)
        return stored.to_s unless stored.to_s.empty?
        File.join(ENV['USERPROFILE'] || Dir.home, 'Documents', 'dn1sup_su2vis', 'out')
      end

      # Значение ключа из файла проекта (nil — нет файла/ключа/битый файл).
      # Старый su2vis.json читается для переезда в yaml.
      def project_file_value(dir, key)
        doc = read_project_doc(dir)
        return nil unless doc.key?(key.to_s)

        doc[key.to_s]
      rescue StandardError
        nil
      end

      def write_project_file(dir, hash)
        cur = read_project_doc(dir)
        h = hash.is_a?(Hash) ? hash : {}
        h.each { |k, v| cur[k.to_s] = v if PROJECT_KEYS.include?(k.to_s) }
        write_project_doc(dir, cur)
      end

      def get(key)
        all[key.to_s]
      end

      def coerce(key, value)
        case key.to_s
        when 'unsloth_model' then KLEIN_MODEL
        when 'unsloth_gguf' then value.to_s.empty? ? KLEIN_GGUF : value.to_s
        when 'steps' then value.to_i.clamp(8, 30)
        when 'guidance' then 1.0
        when 'memory_mode'
          s = value.to_s.strip.downcase
          %w[auto fast balanced low_vram].include?(s) ? s : 'balanced'
        when 'studio_precision'
          s = value.to_s.strip.downcase
          %w[auto off fp16 bf16 int8 fp32].include?(s) ? s : 'auto'
        when 'studio_text_encoder_precision'
          s = value.to_s.strip.downcase
          %w[default auto int8 fp16 bf16 fp32].include?(s) ? s : 'default'
        when 'studio_attention'
          s = value.to_s.strip.downcase
          %w[auto cudnn flash sdpa sage2 sage].include?(s) ? s : 'auto'
        when 'studio_engine'
          s = value.to_s.strip.downcase
          %w[auto diffusers].include?(s) ? s : 'auto'
        when 'studio_speed'
          s = value.to_s.strip.downcase
          %w[auto default fast balanced quality].include?(s) ? s : 'auto'
        when 'studio_step_cache'
          s = value.to_s.strip.downcase
          %w[auto on off].include?(s) ? s : 'auto'
        when 'seed' then value.to_i
        when 'allow_oversized', 'use_scenes', 'use_mixins',
             'sketch_thin_lines', 'sketch_hide_dims', 'sketch_autocrop', 'sketch_white_bg',
             'sketch_no_shadows',
             'unsloth_autostart', 'geometry_lock', 'preview_random_seeds',
             'studio_cpu_offload', 'studio_live_preview' then value == true || value.to_s == 'true'
        # Студия klein принимает только auto (поле не шлём): edit 400,
        # явный reference 400 со strength. Легаси 'edit' из 0.13.0 мигрирует в auto.
        when 'workflow' then 'auto'
        when 'mixins_default_role'
          s = value.to_s.strip.downcase
          %w[auto style material light object].include?(s) ? s : 'auto'
        when 'mixins_default_apply'
          s = value.to_s.strip.downcase
          s = 'final' if s == 'preview'
          %w[both final].include?(s) ? s : 'both'
        when 'unsloth_cmd' then value.to_s.strip.empty? ? 'unsloth' : value.to_s.strip
        when 'sketch_source' then %w[hd view preset].include?(value.to_s) ? value.to_s : 'hd'
        when 'sketch_style'
          s = value.to_s.strip.downcase
          %w[model white sketch custom].include?(s) ? s : 'model'
        when 'final_mode' then %w[sketch 1k 2k custom].include?(value.to_s) ? value.to_s : 'sketch'
        when 'sketch_preset' then SKETCH_PRESETS.include?(value.to_s) ? value.to_s : '1600x1200'
        when 'final_w', 'final_h' then value.to_i.clamp(256, 2048)
        when 'preview_variants' then value.to_i.clamp(1, 4)
        when 'strength', 'final_strength' then value.to_f
        when 'runs', 'preview_preset', 'preview_max' then value.to_i
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
