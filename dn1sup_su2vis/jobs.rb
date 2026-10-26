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

      # GVL-памп: рабочие потоки задач в живом SketchUp голодают, пока
      # главный поток висит в цикле сообщений (наблюдалось: задача висит
      # в blocking-IO минутами, а 30-секундный sleep на главном потоке
      # доводит её до done). Повторяющийся таймер дёргает Thread.pass —
      # потоки получают кванты, UI остаётся отзывчивым (пассы — микросекунды,
      # пока рабочим нечего делать). Только пока есть активные задачи;
      # блок сам гасит таймер, когда задач не осталось (переживает reload).
      @pump_timer = nil

      def any_running?
        @jobs.values.any? { |j| !%w[done error cancelled].include?(j.status) }
      end

      def pump_active?
        !@pump_timer.nil?
      end

      def pump_start
        return @pump_timer unless @pump_timer.nil?
        return nil unless defined?(UI) && UI.respond_to?(:start_timer)

        id = UI.start_timer(0.2, true) do
          20.times { Thread.pass }
          begin
            unless any_running?
              UI.stop_timer(id)
              # Флаг тоже чистим здесь (а не только в maybe_pump_stop):
              # рабочий поток под голоданием доходит до ветки завершения
              # с запозданием, а висящий true + мёртвый таймер заставил бы
              # следующий enqueue переиспользовать мёртвый id без пампа.
              # Охрана == id: чужой (новый) таймер не трогаем.
              @pump_timer = nil if @pump_timer == id
            end
          rescue StandardError
            nil
          end
        end
        @pump_timer = id
      rescue StandardError
        nil
      end

      def pump_stop
        id = @pump_timer
        @pump_timer = nil
        begin
          UI.stop_timer(id) if id && defined?(UI) && UI.respond_to?(:stop_timer)
        rescue StandardError
          nil
        end
        nil
      end

      def maybe_pump_stop
        pump_stop unless any_running?
      end

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
        pump_start
        Thread.new { run(job) }
        public_view(job)
      end

      # Кооперативная остановка: поток проверит флаг перед следующим кадром.
      # Текущий кадр (блокирующий HTTP) дойдёт до конца. Параллельно просим
      # студию остановить генерацию — тогда текущий кадр тоже прервётся.
      # Плюс закрываем висящее HTTP-соединение задачи (см. Client.abort):
      # иначе поток торчит в http.request до read_timeout (30 мин),
      # а зависший на стороне студии запрос — вечно.
      def cancel(id)
        job = @jobs[id.to_s]
        return { ok: false, error: 'job not found' } unless job
        return { ok: false, error: "уже #{job.status}" } if %w[done error cancelled].include?(job.status)

        job.cancel_requested = true
        s = job.params['settings'] || {}
        Client.gen_cancel(s['unsloth_url'].to_s, s['unsloth_key'].to_s)
        Client.abort(job.id)
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
        raise 'нет ключа Unsloth Studio (окно Подключение в шапке)' if key.empty?

        Log.append('job_start', 'id' => job.id, 'kind' => job.kind, 'scenes' => scenes,
                   'seed' => s['seed'], 'steps' => s['steps'], 'final' => s['final_mode'])
        Client.ensure_loaded!(url, key, s['unsloth_model'], s['unsloth_gguf'], s['memory_mode'], s)

        seed_base = s['seed'].to_i
        seed_base = Random.new_seed % 2_147_483_647 if seed_base < 0
        seeds = s['seeds'] || {}
        out_dir = s['out_dir'].to_s.empty? ? Settings.out_dir : s['out_dir'].to_s
        FileUtils.mkdir_p(out_dir)
        total_steps = scenes.size
        done_steps = 0

        scenes.each_with_index do |idx, n|
          check_cancel!(job)
          begin
            Client.status(url, key)
          rescue StandardError
            raise "студия недоступна (#{url}) — проверь, что `unsloth studio` запущена, и повтори"
          end
          job.progress = { done: done_steps, total: total_steps, scene: idx }
          sketch, boxes_prompt =
            if idx.nil?
              [nil, '']
            else
              cap = (job.params['sketches'] || {})[idx.to_s] || (job.params['sketches'] || {})[idx]
              # Фолбэк (эскиз не снят на главном потоке): те же параметры
              # съёма, что в колонке «Референс» — тонкие линии, скрытие размеров,
              # автокроп полей.
              if cap.to_s.empty? || !File.file?(cap.to_s)
                cap = Scenes.capture(idx, nil, nil,
                                     thin_lines: s['sketch_thin_lines'] != false,
                                     hide_dims: s['sketch_hide_dims'] != false)
                cap = Scenes.maybe_autocrop(cap, s['sketch_autocrop'] == true ||
                                                 s['sketch_autocrop'].to_s == 'true')
              end
              # Рамки с описанием сцены: копия с нарисованными красными
              # боксами уходит в модель, исходный эскиз остаётся чистым.
              sboxes = Scenes.boxes(idx)
              [Scenes.annotated_sketch(cap, sboxes), Scenes.boxes_prompt(sboxes)]
            end
          # Без эскиза пропорций нет — берём из общих настроек финала.
          w0, h0 = sketch ? (Scenes.dims(sketch) || [1024, 1024]) : default_dims(s)
          w, h = final_size(s, w0, h0)
          base_seed = (seeds[idx.to_s] || seeds[idx] || seeds['prompt'] || seeds['null'] || seed_base + idx.to_i).to_i
          batch = (s['preview_variants'] || s['variants'] || 1).to_i.clamp(1, 4)
          random_seeds = s['preview_random_seeds']
          # Примеси: активные референсы + подписи -> дописка к промпту.
          mix = Mixins.active_for_job(job.params['mixins'] || s['mixins'], 'final')
          # Большие референсы — через ужатые копии (студия режет > 4096px),
          # с боксами — ещё и с нарисованными рамками.
          mix_refs = mix.map do |m|
            p2, boxes_ok = Mixins.annotated_job_path(m['path'], m['crop'], m['rotation'], m['boxes'])
            m.merge('job_path' => p2, 'boxes_ok' => boxes_ok)
          end
          mix_paths = mix_refs.map { |m| m['job_path'] }
          mp = Client.mixins_prompt(mix_refs)
          check_cancel!(job)
          run_seed = random_seeds == true || random_seeds.to_s == 'true' ? Random.new_seed % 2_147_483_647 : base_seed
          batch_seeds = batch_seed_list(run_seed, batch, random_seeds)
          t_gen = Time.now
          gen_strength = s['strength'].to_f
          # Студия klein: workflow всегда auto (поле не шлём), upscale не шлём,
          # enhance-флаг игнорируется — не шлём. strength действует только в auto.
          items, gw, gh = Client.generate(
            url, key, sketch,
            prompt: s['prompt'], width: w, height: h,
            steps: s['steps'].to_i.clamp(Client::STEPS_MIN, Client::STEPS_MAX), guidance: s['guidance'].to_f,
            strength: gen_strength, seed: batch_seeds.first,
            allow_oversized: s['allow_oversized'] == true || s['allow_oversized'].to_s == 'true',
            batch_size: batch, seeds: batch_seeds,
            extra_references: mix_paths, mixins_prompt: mp, boxes_prompt: boxes_prompt,
            http_id: job.id, geometry_lock: s.fetch('geometry_lock', true)
          )
          gen_s = (Time.now - t_gen).round(1)
          items.each_with_index do |(bytes, meta), i|
            vsed = meta['seed'] || batch_seeds[i] || run_seed
            entry = { scene: idx, variant: i, seed: vsed, width: gw, height: gh,
                      workflow: meta['workflow'] }
            gmeta = gallery_meta(s, idx, vsed, i, gw, gh, false)
            ext = (s['ext'] || 'jpg').to_s.sub(/^\./, '')
            # Не перезаписываем старые рендеры: коллизия по файлу или сайдкару
            # даёт суффикс _2, _3… (иначе binwrite молча затирал бы прошлый
            # файл, который пользователь не удалял).
            entry[:file] = Gallery.unique_path(out_dir, expand_name(s, idx, vsed), ".#{ext}")
            File.binwrite(entry[:file], bytes)
            # Файл обязан лежать на диске: иначе вместо фантомной карточки
            # с вечной «загрузкой» задача сразу падает с понятной ошибкой.
            raise "файл результата не записался: #{entry[:file]}" unless File.file?(entry[:file]) && File.size(entry[:file]) > 0
            Gallery.save_sidecar(entry[:file], 'final', gmeta)
            job.results << entry
            Log.append('scene_done', 'id' => job.id, 'scene' => idx, 'variant' => i,
                       'seed' => vsed, 'size' => "#{gw}x#{gh}", 'gen_s' => gen_s,
                       'file' => entry[:file])
          end
          done_steps += 1
          job.progress = { done: done_steps, total: total_steps, scene: idx }
          check_cancel!(job)
        end
        job.progress = { done: done_steps, total: total_steps }
        job.status = 'done'
        Log.append('job_done', 'id' => job.id, 'status' => 'done', 'total_s' => (Time.now - t_job).round(1))
        maybe_pump_stop
      rescue Cancelled => e
        job.status = 'cancelled'
        job.error = e.message
        Log.append('job_done', 'id' => job.id, 'status' => 'cancelled',
                   'done' => job.results.size, 'total_s' => (Time.now - t_job).round(1))
        maybe_pump_stop
      rescue StandardError => e
        # Соединение закрыто по cancel (Client.abort) — это остановка,
        # а не ошибка: флаг проверяется здесь, т.к. обрыв прилетает
        # из заблокированного http.request, а не из check_cancel!.
        if job.cancel_requested
          job.status = 'cancelled'
          job.error = 'остановлено пользователем'
          Log.append('job_done', 'id' => job.id, 'status' => 'cancelled',
                     'done' => job.results.size, 'total_s' => (Time.now - t_job).round(1))
          maybe_pump_stop
        else
          job.status = 'error'
          job.error = e.message
          Log.append('job_done', 'id' => job.id, 'status' => 'error', 'error' => e.message[0, 300],
                     'done' => job.results.size, 'total_s' => (Time.now - t_job).round(1))
          maybe_pump_stop
        end
      end

      # Сиды батча: random=true — каждый случайный (варианты
      # максимально разные), иначе по порядку от seed.
      def batch_seed_list(seed, batch, random)
        n = batch.to_i.clamp(1, 4)
        return (0...n).map { |i| seed.to_i + i } unless random == true || random.to_s == 'true'

        n.times.map { Random.new_seed % 2_147_483_647 }
      end

      # Мета картинки для сайдкара галереи (описание параметров рядом с файлом).
      def gallery_meta(s, scene, seed, variant, w, h, _from_prev = false)
        { 'scene' => scene, 'seed' => seed, 'variant' => variant,
          'width' => w, 'height' => h, 'prompt' => s['prompt'],
          'strength' => s['strength'], 'steps' => s['steps'],
          'guidance' => s['guidance'], 'workflow' => 'auto',
          'geometry_lock' => s.fetch('geometry_lock', true),
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
