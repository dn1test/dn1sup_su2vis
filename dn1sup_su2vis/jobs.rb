# frozen_string_literal: true

require 'sketchup.rb'
require 'fileutils'
require 'time'

module Dn1sup
  module Su2vis
    # Очередь генераций в фоне: Thread считает, UI.poll_timer пушит события.
    # jobs.rb не трогает UI из потока — только пишет @jobs, диалог читает по таймеру.
    module Jobs
      module_function

      @jobs = {}
      @seq = 0

      Job = Struct.new(:id, :kind, :status, :progress, :results, :error, :params, :cancel_requested, keyword_init: true)
      Cancelled = Class.new(StandardError)

      def all
        @jobs.values.map { |j| public_view(j) }
      end

      def find(id)
        @jobs[id.to_s]
      end

      def public_view(job)
        {
          id: job.id, kind: job.kind, status: job.status,
          progress: job.progress, results: job.results,
          error: job.error, params: job.params
        }
      end

      # Запуск превью (малый размер) или финала (полный размер, тот же seed).
      # scenes: [indexes], settings: hash из Settings.all + prompt и т.д.
      def enqueue(kind, scenes, settings)
        @seq += 1
        id = "job#{@seq}_#{Time.now.to_i}"
        job = Job.new(id: id, kind: kind.to_s, status: 'queued', progress: 0,
                      results: [], error: nil, params: { 'scenes' => scenes, 'settings' => settings },
                      cancel_requested: false)
        @jobs[id] = job
        Thread.new { run(job) }
        public_view(job)
      end

      # Кооперативная остановка: поток проверит флаг перед следующим кадром.
      # Текущий кадр (блокирующий HTTP) дойдёт до конца. Параллельно просим
      # студию остановить генерацию — тогда текущий кадр тоже прервётся.
      def cancel(id)
        job = @jobs[id.to_s]
        return { ok: false, error: 'job not found' } unless job
        return { ok: false, error: "уже #{job.status}" } if %w[done error cancelled].include?(job.status)

        job.cancel_requested = true
        s = job.params['settings'] || {}
        Client.gen_cancel(s['unsloth_url'].to_s, s['unsloth_key'].to_s)
        { ok: true, id: job.id }
      end

      def check_cancel!(job)
        raise Cancelled, 'остановлено пользователем' if job.cancel_requested
      end

      def run(job)
        job.status = 'running'
        t_job = Time.now
        s = job.params['settings'] || {}
        # Колонка «Сцены» выключена: сцен нет — один проход без эскиза
        # (только промпт / только примеси). Размер — из общих настроек.
        raw_scenes = Array(job.params['scenes']).reject { |v| v.nil? || v.to_s.empty? }
        no_sketch = raw_scenes.empty?
        scenes = no_sketch ? [nil] : raw_scenes.map(&:to_i)
        url = s['unsloth_url'].to_s
        key = s['unsloth_key'].to_s
        raise 'нет ключа Unsloth Studio (вкладка Настройки)' if key.empty?

        Log.append('job_start', 'id' => job.id, 'kind' => job.kind, 'scenes' => scenes,
                   'seed' => s['seed'], 'preview' => s['preview_preset'], 'final' => s['final_mode'])
        Client.ensure_loaded!(url, key, s['unsloth_model'], s['unsloth_gguf'], s['memory_mode'])

        seed_base = s['seed'].to_i
        seed_base = Random.new_seed % 2_147_483_647 if seed_base < 0
        seeds = s['seeds'] || {}
        preview_px = Settings.preview_px(s['preview_preset'])
        out_dir = s['out_dir'].to_s.empty? ? Settings.out_dir : s['out_dir'].to_s
        FileUtils.mkdir_p(out_dir) if job.kind == 'final'

        scenes.each_with_index do |idx, n|
          check_cancel!(job)
          begin
            Client.status(url, key)
          rescue StandardError
            raise "студия недоступна (#{url}) — проверь, что `unsloth studio` запущена, и повтори"
          end
          job.progress = { done: n, total: scenes.size, scene: idx }
          sketch =
            if idx.nil?
              # Без сцены: превью финала лежит под ключом 'prompt' (см. фронт
              # savePreviewRefs), иначе — чистый text-to-image без эскиза.
              sk = job.params['sketches'] || {}
              cand = sk['prompt'] || sk[:prompt] || sk['null'] || sk.values.first
              cand = cand.to_s if cand && File.file?(cand.to_s)
              (cand && File.file?(cand.to_s)) ? cand.to_s : nil
            else
              cap = (job.params['sketches'] || {})[idx.to_s] || (job.params['sketches'] || {})[idx]
              cap = Scenes.capture(idx) if cap.to_s.empty? || !File.file?(cap.to_s)
              cap.to_s
            end
          # Финал идёт из байтов превью (from_preview): тот же сюжет seed'ом
          # не воспроизводится — студия недетерминирована. Сила доработки —
          # final_strength (по умолчанию 0.4), размер — обратно до HD.
          from_prev = job.kind == 'final' && (s['from_preview'] == true || s['from_preview'].to_s == 'true')
          # Без эскиза пропорций нет — берём из общих настроек финала.
          w0, h0 = sketch ? (Scenes.dims(sketch) || [1024, 1024]) : default_dims(s)
          # Целевая длинная сторона финала из превью: маленький референс
          # тянем ВВЕРХ (fit_size умеет только уменьшать — 1K/2K иначе
          # залипали бы на размере превью).
          prev_long = final_long_side(s['final_mode'])
          w, h =
            if job.kind == 'preview'
              # Превью 256 идёт ПО ШИРИНЕ, высота — по пропорциям эскиза.
              # api_min_size — страховка минимума API 256: у альбомных
              # эскизов высота выйдет < 256 и всё масштабируется вверх
              # с сохранением пропорций (без холостого 422).
              Client.api_min_size(*Client.scale_to_width(w0, h0, preview_px))
            elsif from_prev && prev_long
              Client.scale_to_long(w0, h0, prev_long)
            else
              final_size(s, w0, h0)
            end
          seed = (seeds[idx.to_s] || seeds[idx] || seeds['prompt'] || seeds['null'] || seed_base + idx.to_i).to_i
          batch = job.kind == 'preview' ? s['preview_variants'].to_i.clamp(1, 4) : 1
          batch_seeds = batch.times.map { |i| seed + i }
          wf = s['workflow'].to_s
          wf = nil if wf.empty? || wf == 'auto'
          up = (job.kind == 'final' ? s['final_upscale'].to_f : 0)
          t_gen = Time.now
          gen_strength = job.kind == 'final' && from_prev ? s.fetch('final_strength', s['strength']).to_f : s['strength'].to_f
          # Примеси: активные референсы + подписи -> дописка к промпту.
          # Превью и финал учитывают их одинаково; apply_to режет по стадии.
          mix = Mixins.active_for_job(job.params['mixins'] || s['mixins'], job.kind)
          # Большие референсы — через ужатые копии (студия режет > 4096px).
          mix_paths = mix.map { |m| Mixins.job_path(m['path'], m['crop'], m['rotation']) }
          mp = Client.mixins_prompt(mix)
          items, gw, gh = Client.generate(
            url, key, sketch,
            prompt: s['prompt'], width: w, height: h,
            steps: s['steps'].to_i, guidance: s['guidance'].to_f,
            strength: gen_strength, seed: batch_seeds.first,
            allow_oversized: s['allow_oversized'] == true || s['allow_oversized'].to_s == 'true',
            batch_size: batch, seeds: batch_seeds,
            enhance_prompt: s['enhance_prompt'],
            upscale: up > 0 ? up : nil, workflow: wf,
            extra_references: mix_paths, mixins_prompt: mp
          )
          gen_s = (Time.now - t_gen).round(1)
          items.each_with_index do |(bytes, meta), i|
            vsed = meta['seed'] || batch_seeds[i] || seed
            entry = { scene: idx, variant: i, seed: vsed, width: gw, height: gh,
                      workflow: meta['workflow'] }
            gmeta = gallery_meta(s, idx, vsed, i, gw, gh, from_prev)
            if job.kind == 'final'
              ext = (s['ext'] || 'jpg').to_s.sub(/^\./, '')
              entry[:file] = File.join(out_dir, expand_name(s, idx, vsed) + ".#{ext}")
              File.binwrite(entry[:file], bytes)
              # Файл обязан лежать на диске: иначе вместо фантомной карточки
              # с вечной «загрузкой» задача сразу падает с понятной ошибкой.
              raise "файл результата не записался: #{entry[:file]}" unless File.file?(entry[:file]) && File.size(entry[:file]) > 0
              Gallery.save_sidecar(entry[:file], 'final', gmeta)
            else
              require 'base64'
              entry[:data_url] = "data:image/png;base64,#{Base64.strict_encode64(bytes)}"
              entry[:file] = Gallery.save_preview(out_dir, bytes, gmeta)
            end
            job.results << entry
            Log.append('scene_done', 'id' => job.id, 'scene' => idx, 'variant' => i,
                       'seed' => vsed, 'size' => "#{gw}x#{gh}", 'gen_s' => gen_s,
                       'file' => entry[:file])
          end
          check_cancel!(job)
        end
        job.progress = { done: scenes.size, total: scenes.size }
        job.status = 'done'
        Log.append('job_done', 'id' => job.id, 'status' => 'done', 'total_s' => (Time.now - t_job).round(1))
      rescue Cancelled => e
        job.status = 'cancelled'
        job.error = e.message
        Log.append('job_done', 'id' => job.id, 'status' => 'cancelled',
                   'done' => job.results.size, 'total_s' => (Time.now - t_job).round(1))
      rescue StandardError => e
        job.status = 'error'
        job.error = e.message
        Log.append('job_done', 'id' => job.id, 'status' => 'error', 'error' => e.message[0, 300],
                   'done' => job.results.size, 'total_s' => (Time.now - t_job).round(1))
      end

      # Мета картинки для сайдкара галереи (описание параметров рядом с файлом).
      def gallery_meta(s, scene, seed, variant, w, h, from_prev)
        { 'scene' => scene, 'seed' => seed, 'variant' => variant,
          'width' => w, 'height' => h, 'prompt' => s['prompt'],
          'strength' => s['strength'], 'steps' => s['steps'],
          'guidance' => s['guidance'], 'workflow' => s['workflow'],
          'enhance_prompt' => s['enhance_prompt'], 'upscale' => s['final_upscale'],
          'final_strength' => s['final_strength'], 'from_preview' => from_prev,
          'mixins' => Array(s['mixins']).map { |m| m.is_a?(Hash) ? { 'file' => File.basename((m['path'] || m['file'] || '').to_s), 'caption' => (m['caption'] || '').to_s, 'caption_neg' => (m['caption_neg'] || '').to_s, 'role' => (m['role'] || 'auto').to_s, 'weight' => (m['weight'] || 1.0).to_f, 'apply_to' => (m['apply_to'] || 'both').to_s, 'crop' => Mixins.norm_crop(m['crop'] || m[:crop]), 'rotation' => Mixins.norm_rotation(m['rotation'] || m[:rotation]) } : nil }.compact,
          'model' => [s['unsloth_model'], s['unsloth_gguf']].compact.join('/') }
      end

      # Размер финала: sketch — точный размер эскиза; 1k/2k — по длинной
      # стороне; custom — final_w x final_h. Всегда кратно 16, 128..2048.
      def final_size(s, w0, h0)
        case s['final_mode'].to_s
        when '1k' then Client.fit_size(w0, h0, 1024)
        when '2k' then Client.fit_size(w0, h0, 2048)
        when 'custom'
          cw = s['final_w'].to_i
          ch = s['final_h'].to_i
          (cw > 0 && ch > 0) ? Client.fit_size(cw, ch) : Client.fit_size(w0, h0)
        else Client.fit_size(w0, h0)
        end
      end

      # Целевая длинная сторона финала из превью (nil = custom, считается
      # отдельно через final_size).
      def final_long_side(mode)
        { 'sketch' => 1600, '1k' => 1024, '2k' => 2048 }[mode.to_s]
      end

      def final_max(mode)
        case mode.to_s
        when '1k' then 1024
        when '2k' then 2048
        else 0 # sketch: точный размер эскиза
        end
      end

      # Пропорции без эскиза (сцены выключены): из общих настроек финала
      # (final_w x final_h). Мусор — квадрат 1024.
      def default_dims(s)
        cw = s['final_w'].to_i
        ch = s['final_h'].to_i
        (cw > 0 && ch > 0) ? Client.fit_size(cw, ch) : [1024, 1024]
      end

      # Шаблон имени: {scene} {seed} {date} {suffix}
      def expand_name(s, idx, seed)
        t = (s['name_template'] || '{scene}{suffix}_{date}').to_s
        t = t.gsub('{scene}', safe_name(idx).to_s)
        t = t.gsub('{seed}', seed.to_s)
        t = t.gsub('{date}', Time.now.strftime('%Y%m%d_%H%M%S'))
        t.gsub('{suffix}', s['suffix'].to_s).gsub(/[^\p{L}\p{N}\-_]+/u, '_')[0, 120]
      end

      def safe_name(idx)
        return 'prompt' if idx.nil?
        model = Sketchup.active_model
        name = model&.pages&.[](idx)&.name || "scene_#{idx}"
        name.gsub(/[^\p{L}\p{N}\-]+/u, '_')[0, 60]
      end
    end
  end
end
