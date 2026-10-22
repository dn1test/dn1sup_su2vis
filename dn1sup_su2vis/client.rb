# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'base64'
require 'thread'

module Dn1sup
  module Su2vis
    # HTTP-клиент Unsloth Studio. Порт логики из sketch2photo.rb,
    # плюс seed + strength (нужны для связки превью -> финал).
    module Client
      module_function

      # Реестр живых HTTP-соединений генерации (id задачи -> Net::HTTP).
      # Нужен для мгновенной остановки: Jobs.cancel закрывает сокет,
      # висящий http.request падает с IOError — поток разблокируется сразу,
      # а не через read_timeout (30 мин). Мьютекс — потоки Jobs.
      HTTP_REGISTRY = {}
      HTTP_REGISTRY_MUTEX = Mutex.new

      def register_http(id, http)
        return if id.to_s.empty? || http.nil?

        HTTP_REGISTRY_MUTEX.synchronize { HTTP_REGISTRY[id.to_s] = http }
        nil
      end

      def unregister_http(id)
        return if id.to_s.empty?

        HTTP_REGISTRY_MUTEX.synchronize { HTTP_REGISTRY.delete(id.to_s) }
        nil
      end

      # Закрыть соединение задачи (best-effort). true — было что закрывать.
      def abort(id)
        http = HTTP_REGISTRY_MUTEX.synchronize { HTTP_REGISTRY.delete(id.to_s) }
        return false if http.nil?

        begin
          http.finish
        rescue StandardError
          nil
        end
        true
      end

      def api(url)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 10
        http.read_timeout = 1800
        http
      end

      def get_json(url, key, path)
        req = Net::HTTP::Get.new(path)
        req['Authorization'] = "Bearer #{key}"
        res = api(url).request(req)
        raise "Unsloth Studio: HTTP #{res.code} (проверь ключ и что студия запущена на #{url})" unless res.is_a?(Net::HTTPSuccess)
        JSON.parse(res.body)
      end

      # Работаем только с flux-3-image-klein (distilled, строго 4 шага).
      # Выбор других моделей убран: константы — единый источник истины.
      KLEIN_REPO = 'unsloth/flux-3-image-klein-GGUF'.freeze
      KLEIN_GGUF = 'flux-3-image-klein-UD-Q4_K_XL.gguf'.freeze
      KLEIN_STEPS = 4
      KLEIN_GUIDANCE = 1.0
      # Студия больше не принимает workflow='auto' (422: только
      # 'edit'/'reference'/'outpaint'). Поле вообще не шлём — студия
      # сама выбирает workflow (как sketch2photo.rb, где поля нет).
      # Явный workflow из белого списка пропускаем как есть.
      KLEIN_WORKFLOW = nil
      ALLOWED_WORKFLOWS = %w[edit reference outpaint].freeze
      KLEIN_MEMORY_MODE = 'balanced'.freeze
      KLEIN_MAX_SIDE = 2048
      KLEIN_LABEL = 'klein (distilled)'.freeze

      # Жёсткая дописка для привязки к линиям эскиза. Действие: запрещает
      # модели двигать/добавлять/убирать стены, окна, двери и менять камеру —
      # дорисовывать только материалы, свет и фотореализм поверх линий.
      GEOMETRY_LOCK_TEXT = 'Strictly follow the input sketch linework: do not move, add or remove walls, windows, doors or openings, keep the exact camera and proportions. Photorealistic materials and lighting only, no geometry changes.'.freeze

      # Промпт + опциональный замок геометрии. Действие: при lock=true дописывает
      # GEOMETRY_LOCK_TEXT (если его там ещё нет) — модель держится линий.
      def apply_geometry_lock(prompt, lock_enabled)
        base = prompt.to_s
        return base unless lock_enabled == true || lock_enabled.to_s == 'true'
        return base if base.include?(GEOMETRY_LOCK_TEXT)
        return GEOMETRY_LOCK_TEXT if base.strip.empty?

        "#{base}\n#{GEOMETRY_LOCK_TEXT}"
      end

      def status(url, key)
        get_json(url, key, '/api/inference/images/status')
      end

      # Диагностика списка моделей (для статуса); для выбора
      # больше не используется — генерация только на KLEIN_*.
      def available_models(url, key)
        j = get_json(url, key, '/v1/models')
        arr = j.is_a?(Hash) ? (j['data'] || j['models'] || []) : Array(j)
        Array(arr).filter_map do |m|
          next unless m.is_a?(Hash)
          id = (m['id'] || m['model_id'] || m['repo_id'] || m['name']).to_s
          next if id.empty?
          loaded = m['loaded']
          loaded = m['is_loaded'] if loaded.nil?
          loaded = m['state'].to_s == 'loaded' if loaded.nil? && m['state']
          loaded = m['active'] if loaded.nil?
          st = m['status'].is_a?(Hash) ? (m['status']['value'] || m['status']['state']).to_s : ''
          loaded = true if st == 'loaded'
          { 'id' => id, 'loaded' => !!loaded, 'task' => m['task'].to_s,
            'quant' => (m['quant'] || m['gguf_variant']).to_s,
            'display_name' => (m['display_name'] || id).to_s, 'raw' => m }
        end
      end

      # Только модели генерации картинок: task содержит "image"
      # (text-to-image и будущие image-варианты). LLM, аудио и pup-апсемплер
      # отсекаются — у них task пустой.
      def image_models(url, key)
        available_models(url, key).select { |m| m['task'].to_s.downcase.include?('image') }
      end

      def model_info(url, key, model_id)
        id = model_id.to_s
        raise 'пустой id модели' if id.empty?
        get_json(url, key, "/v1/models/#{URI.encode_www_form_component(id)}")
      end

      # Варианты квантования HF-репозитория: точные имена файлов.
      # GET /api/models/gguf-variants?repo_id=... ->
      # {variants: [{filename, quant, downloaded, ...}], default_variant: {...}}.
      def gguf_variants(url, key, repo_id)
        repo = repo_id.to_s.strip
        raise 'пустой repo_id' if repo.empty?
        get_json(url, key, "/api/models/gguf-variants?repo_id=#{URI.encode_www_form_component(repo)}")
      end

      # Выбор файла из списка вариантов: точное совпадение кванта
      # (сначала скачанные), иначе default_variant. Чистая функция — тестируется.
      def pick_variant(variants, quant, default_variant = nil)
        arr = Array(variants).select { |v| v.is_a?(Hash) }
        q = quant.to_s.strip
        unless q.empty?
          hit = arr.find { |v| v['quant'].to_s == q && v['downloaded'] } ||
                arr.find { |v| v['quant'].to_s.casecmp(q).zero? }
          return hit['filename'].to_s if hit && !hit['filename'].to_s.empty?
        end
        dv = default_variant.is_a?(Hash) ? default_variant : nil
        dv ? dv['filename'].to_s : ''
      end

      # Точное имя GGUF-файла для repo_id (+квант): сначала варианты студии,
      # иначе '' (звать решает fallback по конвенции). Сеть — ошибки наружу.
      def resolve_gguf_filename(url, key, repo_id, quant)
        j = gguf_variants(url, key, repo_id)
        vars = j.is_a?(Hash) ? (j['variants'] || j['data'] || []) : []
        dv = j.is_a?(Hash) ? (j['default_variant'] || j['default']) : nil
        pick_variant(vars, quant, dv)
      end

      # Дефолт генерации студии больше не используется: параметры
      # зафиксированы под klein (distilled 4/1.0). Оставлен заглушкой
      # для совместимости моста.
      def generation_preset(_url, _key)
        { 'steps' => KLEIN_STEPS, 'guidance' => KLEIN_GUIDANCE }
      end

      # Единственный пресет — klein (distilled). Остальные семейства удалены:
      # расширение работает только с flux-3-image-klein.
      IMAGE_PRESETS = [
        { match: %w[flux klein], skip: %w[], steps: 4, guidance: 1.0,
          workflow: nil, memory_mode: 'balanced', max_side: 2048,
          label: 'klein (distilled)', vram: '≈13–16 ГБ' }
      ].freeze

      # 'auto'/пусто/мусор — nil (поле не шлём, студия выбирает сама).
      # Белый список API студии — как есть (в нижнем регистре).
      def normalize_workflow(v)
        s = v.to_s.strip.downcase
        return nil if s.empty? || s == 'auto'
        return s if ALLOWED_WORKFLOWS.include?(s)

        nil
      end

      def norm_id(s)
        s.to_s.downcase.gsub(/[^a-z0-9]/, '')
      end

      # Всегда klein-пресет независимо от входного id: другие модели
      # не поддерживаются. -> {steps, guidance, workflow, memory_mode, ...}.
      def preset_for(_model_id = nil, _studio_defaults = nil)
        { 'steps' => KLEIN_STEPS, 'guidance' => KLEIN_GUIDANCE,
          'workflow' => KLEIN_WORKFLOW, 'memory_mode' => KLEIN_MEMORY_MODE,
          'max_side' => KLEIN_MAX_SIDE, 'label' => KLEIN_LABEL,
          'vram' => '≈13–16 ГБ', 'source' => "пресет #{KLEIN_LABEL}" }
      end

      # id вида "repo:variant" (unsloth run) или "repo/file.gguf" ->
      # [repo, gguf]. Нераспознанное — [id, ''].
      def parse_model_ref(id)
        s = id.to_s.strip
        return ['', ''] if s.empty?
        if s.include?(':')
          repo, variant = s.split(':', 2).map(&:strip)
          gguf = variant.to_s.end_with?('.gguf') ? variant.to_s : "#{variant}.gguf"
          return [repo.to_s, gguf]
        end
        if s.end_with?('.gguf') && s.include?('/')
          parts = s.split('/')
          return [parts[0..-2].join('/'), parts[-1]]
        end
        [s, '']
      end

      def load_progress(url, key)
        get_json(url, key, '/api/inference/images/load-progress')
      end

      # Живой прогресс денойза: {active, step, total_steps, fraction, ...}.
      def gen_progress(url, key)
        get_json(url, key, '/api/inference/images/generate-progress')
      rescue StandardError
        nil
      end

      # Остановка генерации на стороне студии (best-effort).
      def gen_cancel(url, key)
        http = api(url)
        req = Net::HTTP::Post.new('/api/inference/images/generate/cancel')
        req['Content-Type'] = 'application/json'
        req['Authorization'] = "Bearer #{key}"
        req.body = '{}'
        http.request(req)
        true
      rescue StandardError
        false
      end

      # Загрузка модели в студию (первый раз тянет веса). Блокирующий вызов —
      # запускать только из рабочего Thread (см. jobs.rb).
      # Только klein: repo фиксировано. Квант — запрошенный gguf
      # (выбор в окне «Подключение»); пусто — уже загруженный или дефолт.
      def ensure_loaded!(url, key, _model_path = nil, gguf_filename = nil, _memory_mode = nil)
        model_path = KLEIN_REPO
        memory_mode = KLEIN_MEMORY_MODE
        st = status(url, key)
        want = gguf_filename.to_s
        if st['loaded'] && st['repo_id'] == model_path &&
           (want.empty? || st['gguf_filename'].to_s.empty? || st['gguf_filename'] == want)
          return st
        end
        gguf_filename = want.empty? ? KLEIN_GGUF : want

        body = { model_path: model_path, memory_mode: memory_mode,
                 gguf_filename: gguf_filename, model_kind: 'gguf' }
        http = api(url)
        req = Net::HTTP::Post.new('/api/inference/images/load')
        req['Content-Type'] = 'application/json'
        req['Authorization'] = "Bearer #{key}"
        req.body = JSON.generate(body)
        res = http.request(req)
        raise "Unsloth Studio: загрузка не начата, HTTP #{res.code} #{res.body.to_s[0, 300]}" unless res.is_a?(Net::HTTPSuccess)

        loop do
          sleep 5
          prog = load_progress(url, key)
          raise "Unsloth Studio: ошибка загрузки модели — #{prog['error']}" if prog['error']
          st = status(url, key)
          break if st['loaded'] && st['repo_id'] == model_path
        end
        st
      end

      def sniff_mime(path)
        head = File.binread(path, 12)
        return 'image/png' if head[0, 8] == "\x89PNG\r\n\x1A\n".b
        return 'image/jpeg' if head[0, 3] == "\xFF\xD8\xFF".b
        return 'image/gif' if head[0, 3] == 'GIF'
        return 'image/webp' if head[8, 4] == 'WEBP'
        nil
      end

      # Сила 0 запрещена API (strictly greater than 0, иначе HTTP 422) —
      # приводим к диапазону [0.05, ...] в единой точке.
      def norm_strength(v)
        [v.to_f, 0.05].max
      end
      # Размер генерации: кратно 16, в пределах 128..2048.
      # max_side ограничивает длинную сторону (без него — потолок API 2048);
      # если короткая падает ниже 128 — масштабируем ВВЕРХ до 128.
      # Независимый clamp каждой стороны запрещён: он ломает пропорции.
      def fit_size(w, h, max_side = nil)
        w, h = w.to_f, h.to_f
        cap = (max_side && max_side.to_i > 0) ? max_side.to_f : 2048.0
        if [w, h].max > cap
          s = cap / [w, h].max
          w, h = w * s, h * s
        end
        if [w, h].min < 128
          s = 128.0 / [w, h].min
          w, h = w * s, h * s
        end
        [w.round, h.round].map { |v| [[(v / 16.0).round * 16, 128].max, 2048].min }
      end

      # Минимум API студии: каждая сторона >= 256 (иначе HTTP 422).
      # Превью-пресет 128 сам по себе негенерируем — поднимаем короткий
      # край до 256 с сохранением пропорций (длинный выйдет ~224-448).
      def api_min_size(w, h)
        w, h = w.to_f, h.to_f
        if [w, h].min < 256
          s = 256.0 / [w, h].min
          w, h = w * s, h * s
        end
        [w.round, h.round].map { |v| [[(v / 16.0).round * 16, 256].max, 2048].min }
      end
      # Длинная сторона ровно px (вверх или вниз): тот же сюжет превью
      # в полном размере. Пропорции, кратно 16, 256..2048.
      def scale_to_long(w, h, px)
        s = px.to_f / [w.to_f, h.to_f].max
        [w.to_f * s, h.to_f * s].map(&:round).map { |v| [[(v / 16.0).round * 16, 256].max, 2048].min }
      end
      # Ширина ровно px (вверх или вниз): превью 256 идёт по ширине,
      # высота — по пропорциям эскиза. Пропорции, кратно 16, 128..2048;
      # минимум API 256 добирает снаружи api_min_size.
      def scale_to_width(w, h, px)
        s = px.to_f / w.to_f
        [w.to_f * s, h.to_f * s].map(&:round).map { |v| [[(v / 16.0).round * 16, 128].max, 2048].min }
      end

      # Дописка к промпту из подписей примесей: что взять с каждого референса.
      # refs: [{path, caption, caption_neg, role, weight}] — нумерация с 2 (1 — основной эскиз).
      # role: auto/style/material/light/object; weight 0.1..2.0 — подсказка важности.
      def mixins_prompt(refs)
        lines = []
        Array(refs).each_with_index do |m, i|
          next unless m.is_a?(Hash)
          cap = (m['caption'] || m[:caption]).to_s.strip
          neg = (m['caption_neg'] || m[:caption_neg]).to_s.strip
          role = (m['role'] || m[:role]).to_s.strip.downcase
          role = 'auto' unless Mixins::ROLES.include?(role)
          w = (m['weight'] || m[:weight] || 1.0).to_f
          w = 1.0 if w.zero?
          next if cap.empty? && neg.empty? && role == 'auto'
          n = i + 2
          base = cap.empty? ? role_label(role, n) : role_sentence(role, n, cap)
          base = "#{base} (importance #{format_weight(w)})" if (w - 1.0).abs >= 0.05
          base = "#{base} Do NOT take from reference image #{n}: #{neg}." unless neg.empty?
          lines << base
        end
        lines.empty? ? '' : "Additional references:\n#{lines.join("\n")}"
      end

      def role_sentence(role, n, cap)
        case role
        when 'style' then "Take ONLY style/mood from reference image #{n}, ignore geometry: #{cap}."
        when 'material' then "Take ONLY material/texture from reference image #{n}, ignore geometry and composition: #{cap}."
        when 'light' then "Take ONLY lighting/color mood from reference image #{n}, ignore geometry and objects: #{cap}."
        when 'object' then "Take object/detail from reference image #{n} and place it into the scene: #{cap}."
        else "Take from reference image #{n}: #{cap}."
        end
      end

      def role_label(role, n)
        case role
        when 'style' then "Use reference image #{n} for style/mood only, ignore geometry."
        when 'material' then "Use reference image #{n} for material/texture only, ignore geometry and composition."
        when 'light' then "Use reference image #{n} for lighting/color mood only, ignore geometry and objects."
        when 'object' then "Take object/detail from reference image #{n} into the scene."
        else "Use reference image #{n} as additional reference."
        end
      end

      def format_weight(w)
        w = [[w.to_f, 0.1].max, 2.0].min
        (w % 1).zero? ? w.to_i.to_s : format('%.2f', w).sub(/0+\z/, '').sub(/\.\z/, '')
      end

      # Предпросмотр апсемплера без генерации: какой текст реально уйдёт
      # в модель. reference_data_url — data-url эскиза (без него капшн
      # беднее). Ошибки: 409 — апсемплер не скачан, 501 — нет llama-server.
      def enhance_preview(url, key, prompt, reference_data_url = nil)
        body = { prompt: prompt.to_s }
        ref = reference_data_url.to_s
        body[:reference_images] = [ref] unless ref.empty?
        http = api(url)
        req = Net::HTTP::Post.new('/api/inference/images/prompt-upsampler/preview')
        req['Content-Type'] = 'application/json'
        req['Authorization'] = "Bearer #{key}"
        req.body = JSON.generate(body)
        res = http.request(req)
        unless res.is_a?(Net::HTTPSuccess)
          msg = res.body.to_s
          raise 'апсемплер не скачан в студии (открой Unsloth Studio и докачай upsampler)' if res.code == '409'
          raise 'студия без llama-server: предпросмотр недоступен (501)' if res.code == '501'
          raise "unsloth: HTTP #{res.code} #{msg[0, 300]}"
        end
        j = JSON.parse(res.body)
        ep = j['enhanced_prompt'].to_s
        raise 'студия вернула пустой enhanced_prompt' if ep.empty?
        ep
      end

      # Генерация только на klein (distilled: строго 4 шага / 1.0).
      # steps/guidance игнорируются из настроек (фиксированы).
      # geometry_lock: true — дописать замок линий к промпту (точнее держит эскиз).
      # workflow: 'edit' — точнее держит геометрию, 'reference' — свободнее,
      # 'auto'/nil — решает студия. strength: ниже = точнее линии (0.3-0.5),
      # выше = свободнее (0.8-1.0).
      # Возвращает [items, w, h], где items — массив [bytes, meta].
      def generate(url, key, sketch_path, prompt:, width:, height:, steps: 4, guidance: 1.0,
                   strength: 1.0, seed: nil, allow_oversized: true, batch_size: 1,
                   seeds: nil, enhance_prompt: nil, upscale: nil, workflow: nil,
                   extra_references: nil, mixins_prompt: nil, http_id: nil,
                   geometry_lock: true)
        steps = KLEIN_STEPS
        guidance = KLEIN_GUIDANCE
        workflow = normalize_workflow(workflow)
        data_url = nil
        sketch_ok = !sketch_path.to_s.empty? && File.file?(sketch_path.to_s)
        if sketch_ok
          mime = sniff_mime(sketch_path) || 'image/png'
          data_url = "data:#{mime};base64,#{Base64.strict_encode64(File.binread(sketch_path))}"
        end
        refs = Array(extra_references).filter_map do |p|
          next if p.to_s.empty? || !File.file?(p.to_s)
          m2 = sniff_mime(p.to_s) || 'image/png'
          "data:#{m2};base64,#{Base64.strict_encode64(File.binread(p.to_s))}"
        end
        refs = [data_url] + refs unless data_url.nil?
        full_prompt = apply_geometry_lock(prompt.to_s, geometry_lock)
        mp = mixins_prompt.to_s.strip
        full_prompt = "#{full_prompt}\n#{mp}" unless mp.empty?
        w, h = width, height
        payload_seed = seed.nil? || seed.to_i < 0 ? nil : seed.to_i

        loop do
          body = {
            prompt: full_prompt, width: w, height: h,
            steps: steps, guidance: guidance,
            allow_oversized: allow_oversized,
            reference_images: refs
          }
          body[:init_image] = data_url unless data_url.nil?
          body[:strength] = norm_strength(strength) unless data_url.nil?
          body[:seed] = payload_seed unless payload_seed.nil?
          batch = batch_size.to_i < 1 ? 1 : batch_size.to_i
          body[:batch_size] = batch if batch > 1
          body[:seeds] = seeds.map(&:to_i) if seeds.is_a?(Array) && !seeds.empty?
          body[:enhance_prompt] = !!enhance_prompt unless enhance_prompt.nil?
          body[:upscale] = upscale.to_f if upscale && upscale.to_f > 0
          body[:workflow] = workflow.to_s unless workflow.nil? || workflow.to_s.empty?

          http = api(url)
          req = Net::HTTP::Post.new('/api/inference/images/generate')
          req['Content-Type'] = 'application/json'
          req['Authorization'] = "Bearer #{key}"
          req.body = JSON.generate(body)
          register_http(http_id, http)
          begin
            res = http.request(req)
          ensure
            unregister_http(http_id)
          end
          unless res.is_a?(Net::HTTPSuccess)
            msg = res.body.to_s
            if res.code == '422' && [w, h].min < 256
              # Сторона ниже минимума API — поднимаем с сохранением пропорций.
              nw, nh = api_min_size(w, h)
              raise "unsloth: HTTP #{res.code} #{msg[0, 300]}" if [nw, nh] == [w, h]
              w, h = nw, nh
              next
            end
            if res.code == '400' && msg =~ /needs about ([\d.]+) GB.*only about ([\d.]+) GB is usable/m
              need, usable = $1.to_f, $2.to_f
              scale = Math.sqrt(usable / need) * 0.97
              nw = [[((w * scale) / 16.0).floor * 16, 128].max, 2048].min
              nh = [[((h * scale) / 16.0).floor * 16, 128].max, 2048].min
              raise "не удаётся подобрать разрешение под VRAM (#{width}x#{height})" if [nw, nh] == [w, h]
              raise "не хватает VRAM даже на минимальный размер 256 (#{width}x#{height})" if [nw, nh].min < 256
              w, h = nw, nh
              next
            end
            raise "unsloth: HTTP #{res.code} #{msg[0, 300]}"
          end
          j = JSON.parse(res.body)
          imgs = (j['images'] || [])
          raise "unsloth не вернул изображение: #{j.inspect[0, 300]}" if imgs.empty?

          items = imgs.map do |img|
            file_path = img['url'].to_s
            file_path = url + file_path unless file_path.start_with?('http')
            dl = Net::HTTP::Get.new(URI(file_path).request_uri)
            dl['Authorization'] = "Bearer #{key}"
            dl_http = api(url)
            register_http(http_id, dl_http)
            begin
              file_res = dl_http.request(dl)
            ensure
              unregister_http(http_id)
            end
            raise "unsloth: скачивание результата не удалось (HTTP #{file_res.code})" unless file_res.is_a?(Net::HTTPSuccess)
            meta = { 'workflow' => img['workflow'], 'seed' => img['seed'] }
            [file_res.body, meta]
          end
          return [items, w, h]
        end
      end
    end
  end
end
