# frozen_string_literal: true

require 'sketchup.rb'
require 'base64'
require 'json'

module Dn1sup
  module Su2vis
    # HtmlDialog-панель на Vue 3 + Tailwind (сборка frontend/ -> resources/panel.html).
    # Мост как в comp_add_view: колбэки до show, ответы пушем window.__dn1Event.
    # Долгие задачи — через Jobs (Thread) + опрос jobs_poll из JS.
    module Panel
      PANEL_HTML = File.join(__dir__, 'resources', 'panel.html')

      DIALOG_OPTIONS = {
        dialog_title: 'DN1Sup SU2Vis',
        preferences_key: 'dn1sup_su2vis.panel',
        resizable: true,
        width: 1380,
        height: 760,
        min_width: 1150,
        min_height: 600
      }.freeze

      class << self
        attr_reader :dialog

        def show
          return bring_to_front if @dialog&.visible?

          @dialog = build_dialog
          if File.file?(PANEL_HTML)
            @dialog.set_file(PANEL_HTML)
          else
            @dialog.set_html(fallback_html)
          end
          @dialog.show
          kick_autostart
          @dialog
        rescue StandardError => e
          warn "[Su2vis] Не удалось открыть панель: #{e.message}"
          nil
        end

        def close_all
          return false unless @dialog
          begin
            @dialog.close if @dialog.visible?
          rescue StandardError
            nil
          end
          @dialog = nil
          true
        end

        def push_event(type, id: nil, payload: nil)
          return unless @dialog&.visible?
          evt = { type: type }
          evt[:id] = id if id
          evt[:payload] = payload if payload
          @dialog.execute_script("window.__dn1Event && window.__dn1Event(#{JSON.generate(evt)});")
        rescue StandardError => e
          warn "[Su2vis] push_event: #{e.message}"
        end

        def parse_payload(params)
          data = params.is_a?(String) ? (JSON.parse(params) rescue nil) : params
          data.is_a?(Hash) ? data : {}
        end

        # Файл результата в data-url для просмотра в панели.
        # Только внутри out_dir (иначе — отказ): панель не должна читать
        # произвольные пути. MIME — по содержимому (студия отдаёт PNG,
        # а имя файла может быть .jpg по настройке ext).
        # Пути нормализуем через expand_path с обеих сторон: out_dir
        # собирается из пути модели и несёт бэкслэши, а expand_path файла
        # отдаёт прямые — без этого легальный файл «вне папки».
        def within_dir?(dir, path)
          d = File.expand_path(dir.to_s)
          p = File.expand_path(path.to_s, d)
          p.start_with?(d + File::SEPARATOR) ? p : nil
        end

        def result_data_url(file)
          dir = Settings.out_dir
          path = within_dir?(dir, file)
          raise 'файл вне папки результатов или не найден' if path.nil? || !File.file?(path)
          mime = Client.sniff_mime(path) ||
                 (File.extname(path).downcase == '.png' ? 'image/png' : 'image/jpeg')
          "data:#{mime};base64,#{Base64.strict_encode64(File.binread(path))}"
        end

        private

        # Тихий автозапуск студии при открытии панели (если включён
        # в настройках). Не блокирует показ: подъём — в Thread.
        def kick_autostart
          s = Settings.all
          return unless s['unsloth_autostart'] == true

          Studio.ensure_async(s['unsloth_url'].to_s, s['unsloth_key'].to_s,
                              s['unsloth_cmd'].to_s)
        rescue StandardError => e
          warn "[Su2vis] autostart: #{e.message}"
          nil
        end

        def bring_to_front
          @dialog.bring_to_front
          @dialog
        end

        def build_dialog
          dlg = UI::HtmlDialog.new(DIALOG_OPTIONS)
          dlg.add_action_callback('settings_get') do |_ctx, req_id|
            push_event('result', id: req_id, payload: Settings.all)
          end
          dlg.add_action_callback('settings_save') do |_ctx, req_id, params|
            push_event('result', id: req_id, payload: Settings.save(parse_payload(params)))
          end
          # Проект per-file: состояние папки su2vis/ рядом с .skp,
          # создание папки, перепроверка после сохранения модели.
          # Нативный сейв-диалог не открываем: несохранённую модель
          # пользователь сохраняет сам (Файл → Сохранить), затем жмёт
          # «Проверить снова» — иначе модалка из моста вешает SketchUp.
          dlg.add_action_callback('project_status') do |_ctx, req_id|
            push_event('result', id: req_id, payload: Settings.project_info)
          end
          # Удаление папки проекта: настройки сбрасываются, панель снова
          # предложит создать su2vis/ рядом с файлом.
          dlg.add_action_callback('project_delete') do |_ctx, req_id|
            begin
              payload = Settings.delete_project
              Log.append('project_delete', 'dir' => payload['project_dir'].to_s)
              push_event('result', id: req_id, payload: { ok: true, settings: payload })
            rescue StandardError => e
              push_event('result', id: req_id, payload: { ok: false, error: e.message })
            end
          end
          # Создание папки проекта: su2vis/ + out/ + su2vis.json из текущих.
          dlg.add_action_callback('project_init') do |_ctx, req_id|
            begin
              payload = Settings.init_project
              Log.append('project_init', 'dir' => payload['project_dir'].to_s)
              push_event('result', id: req_id, payload: { ok: true, settings: payload })
            rescue StandardError => e
              push_event('result', id: req_id, payload: { ok: false, error: e.message })
            end
          end
          dlg.add_action_callback('scenes_list') do |_ctx, req_id|
            push_event('result', id: req_id, payload: Scenes.list)
          end
          dlg.add_action_callback('scenes_thumb') do |_ctx, req_id, params|
            data = parse_payload(params)
            white = data.key?('white_bg') ? data['white_bg'] == true : Settings.get('sketch_white_bg') == true
            push_event('result', id: req_id,
                       payload: { index: data['index'].to_i, thumb: Scenes.thumbnail(data['index'].to_i, white_bg: white) })
          end
          dlg.add_action_callback('scenes_sync_view') do |_ctx, req_id, params|
            data = parse_payload(params)
            idx = data['index'].to_i
            ok = Scenes.update_camera(idx)
            white = data.key?('white_bg') ? data['white_bg'] == true : Settings.get('sketch_white_bg') == true
            push_event('result', id: req_id,
                       payload: { index: idx, ok: ok, thumb: Scenes.thumbnail(idx, white_bg: white) })
          end
          dlg.add_action_callback('scenes_capture') do |_ctx, req_id, params|
            data = parse_payload(params)
            begin
              list = Array(data['scenes']).map(&:to_i)
              sk = data['sketch'].is_a?(Hash) ? data['sketch'] : {}
              shots = Scenes.capture_all(list, hd: data['hd'] == true, sketch: sk)
              Log.append('shots_captured', 'scenes' => list, 'hd' => data['hd'] == true, 'sketch' => sk)
              push_event('result', id: req_id, payload: { ok: true, sketches: shots })
            rescue StandardError => e
              push_event('result', id: req_id, payload: { ok: false, error: e.message })
            end
          end
          # Примеси: дополнительные референсы с подписями «что взять».
          # Хранятся в su2vis/mixins/ (см. Mixins), в задачи уходят путями.
          dlg.add_action_callback('mixins_list') do |_ctx, req_id|
            begin
              push_event('result', id: req_id, payload: Mixins.list)
            rescue StandardError => e
              push_event('result', id: req_id, payload: [])
              warn "[Su2vis] mixins_list: #{e.message}"
            end
          end
          dlg.add_action_callback('mixins_add_data') do |_ctx, req_id, params|
            data = parse_payload(params)
            begin
              entry = Mixins.add_data(data['data_url'].to_s, data['name'].to_s)
              push_event('result', id: req_id, payload: { ok: true, entry: entry })
            rescue StandardError => e
              push_event('result', id: req_id, payload: { ok: false, error: e.message })
            end
          end
          dlg.add_action_callback('mixins_add_path') do |_ctx, req_id|
            begin
              sel = UI.openpanel('Картинки-примеси (png/jpg/webp)', Settings.out_dir, '*.png;*.jpg;*.jpeg;*.webp')
              if sel.to_s.empty?
                push_event('result', id: req_id, payload: { ok: false, cancelled: true })
              else
                entry = Mixins.add_path(sel.to_s)
                push_event('result', id: req_id, payload: { ok: true, entry: entry })
              end
            rescue StandardError => e
              push_event('result', id: req_id, payload: { ok: false, error: e.message })
            end
          end
          dlg.add_action_callback('mixins_update') do |_ctx, req_id, params|
            data = parse_payload(params)
            begin
              entry = Mixins.update(data['id'].to_s, caption: data['caption'], active: data['active'], crop: data['crop'], rotation: data['rotation'],
                                    role: data['role'], caption_neg: data['caption_neg'],
                                    weight: data['weight'], apply_to: data['apply_to'], pos: data['pos'])
              push_event('result', id: req_id, payload: { ok: true, entry: entry })
            rescue StandardError => e
              push_event('result', id: req_id, payload: { ok: false, error: e.message })
            end
          end
          dlg.add_action_callback('mixins_reorder') do |_ctx, req_id, params|
            data = parse_payload(params)
            begin
              ids = data['ids'] || data['order'] || []
              push_event('result', id: req_id, payload: Mixins.reorder(Array(ids)))
            rescue StandardError => e
              push_event('result', id: req_id, payload: { ok: false, error: e.message })
            end
          end
          dlg.add_action_callback('mixins_delete') do |_ctx, req_id, params|
            data = parse_payload(params)
            begin
              push_event('result', id: req_id, payload: Mixins.remove(data['id'].to_s))
            rescue StandardError => e
              push_event('result', id: req_id, payload: { ok: false, error: e.message })
            end
          end
          dlg.add_action_callback('mixins_view') do |_ctx, req_id, params|
            data = parse_payload(params)
            begin
              d = File.expand_path(Mixins.base_dir.to_s)
              path = File.expand_path(File.basename(data['id'].to_s), d)
              raise 'файл вне папки примесей' unless path.start_with?(d + File::SEPARATOR)
              raise 'файл не найден' unless File.file?(path)
              mime = Client.sniff_mime(path) || 'image/png'
              require 'base64'
              url = "data:#{mime};base64,#{Base64.strict_encode64(File.binread(path))}"
              push_event('result', id: req_id, payload: { ok: true, data_url: url })
            rescue StandardError => e
              push_event('result', id: req_id, payload: { ok: false, error: e.message })
            end
          end
          dlg.add_action_callback('jobs_start') do |_ctx, req_id, params|
            data = parse_payload(params)
            scenes = Array(data['scenes']).reject { |v| v.nil? || v.to_s.empty? }.map(&:to_i)
            job = Jobs.enqueue(data['kind'] || 'final', scenes,
                               (data['settings'] || {}).merge('out_dir' => Settings.out_dir))
            job_obj = Jobs.find(job[:id])
            job_obj.params['sketches'] = data['sketches'] if data['sketches'].is_a?(Hash)
            job_obj.params['mixins'] = data['mixins'] if data['mixins'].is_a?(Array)
            push_event('result', id: req_id, payload: Jobs.public_view(job_obj))
          end
          dlg.add_action_callback('jobs_poll') do |_ctx, req_id, params|
            data = parse_payload(params)
            job = Jobs.find(data['id'].to_s)
            push_event('result', id: req_id, payload: job ? Jobs.public_view(job) : { error: 'job not found' })
          end
          dlg.add_action_callback('jobs_list') do |_ctx, req_id|
            push_event('result', id: req_id, payload: Jobs.all)
          end
          dlg.add_action_callback('jobs_cancel') do |_ctx, req_id, params|
            data = parse_payload(params)
            push_event('result', id: req_id, payload: Jobs.cancel(data['id'].to_s))
          end
          dlg.add_action_callback('jobs_log') do |_ctx, req_id, params|
            data = parse_payload(params)
            push_event('result', id: req_id, payload: Log.tail((data['limit'] || 50).to_i))
          end
          dlg.add_action_callback('jobs_log_clear') do |_ctx, req_id|
            push_event('result', id: req_id, payload: { ok: Log.clear })
          end
          # Галерея на диске: финалы с сайдкарами параметров.
          # Удаление — только по кнопке на картинке.
          dlg.add_action_callback('gallery_list') do |_ctx, req_id|
            begin
              push_event('result', id: req_id, payload: Gallery.list(Settings.out_dir))
            rescue StandardError => e
              push_event('result', id: req_id, payload: [])
              warn "[Su2vis] gallery_list: #{e.message}"
            end
          end
          dlg.add_action_callback('gallery_delete') do |_ctx, req_id, params|
            data = parse_payload(params)
            begin
              push_event('result', id: req_id, payload: Gallery.remove(Settings.out_dir, data['file']))
            rescue StandardError => e
              push_event('result', id: req_id, payload: { ok: false, error: e.message })
            end
          end
          dlg.add_action_callback('final_view') do |_ctx, req_id, params|
            data = parse_payload(params)
            begin
              url = result_data_url(data['file'])
              push_event('result', id: req_id, payload: { ok: true, data_url: url })
            rescue StandardError => e
              push_event('result', id: req_id, payload: { ok: false, error: e.message })
            end
          end
          # Апсемплер — только в фоне (см. Enhance): колбэк отдаёт задачу
          # сразу, панель опрашивает enhance_poll. Сеть на главном потоке
          # вешает UI на секунды инференса. rescue Exception — наружу
          # из колбэка мосту ничего не должно вылетать.
          dlg.add_action_callback('enhance_preview') do |_ctx, req_id, params|
            data = parse_payload(params)
            begin
              s = Settings.all
              key = s['unsloth_key'].to_s
              raise 'нет ключа Unsloth Studio (окно Подключение в шапке)' if key.empty?
              task = Enhance.start(s['unsloth_url'].to_s, key,
                                   (data['prompt'] || s['prompt']).to_s,
                                   data['reference'].to_s)
              push_event('result', id: req_id, payload: { ok: true, task: task })
            rescue Exception => e # rubocop:disable Lint/RescueException
              push_event('result', id: req_id, payload: { ok: false, error: e.message.to_s })
            end
          end
          dlg.add_action_callback('enhance_poll') do |_ctx, req_id, params|
            data = parse_payload(params)
            begin
              push_event('result', id: req_id, payload: { ok: true, task: Enhance.poll(data['id'].to_s) })
            rescue Exception => e # rubocop:disable Lint/RescueException
              push_event('result', id: req_id, payload: { ok: false, error: e.message.to_s })
            end
          end
          dlg.add_action_callback('gen_progress') do |_ctx, req_id|
            s = Settings.all
            push_event('result', id: req_id, payload: Client.gen_progress(s['unsloth_url'], s['unsloth_key']))
          end
          dlg.add_action_callback('studio_status') do |_ctx, req_id, params|
            data = parse_payload(params)
            s = data['settings'] || Settings.all
            begin
              st = Client.status(s['unsloth_url'].to_s, s['unsloth_key'].to_s)
              push_event('result', id: req_id, payload: { ok: true, status: st })
            rescue StandardError => e
              push_event('result', id: req_id, payload: { ok: false, error: e.message })
            end
          end
          # Автозапуск headless-студии (без GUI): мгновенный ответ,
          # тяжёлый подъём — в Thread (см. Studio.ensure_async).
          # Дубль при живом потоке не стартует.
          dlg.add_action_callback('studio_ensure') do |_ctx, req_id, params|
            data = parse_payload(params)
            s = data['settings'] || Settings.all
            begin
              cmd = s['unsloth_cmd'].to_s
              cmd = Settings.all['unsloth_cmd'].to_s if cmd.strip.empty?
              res = Studio.ensure_async(s['unsloth_url'].to_s, s['unsloth_key'].to_s, cmd)
              push_event('result', id: req_id, payload: res.merge(ok: true))
            rescue StandardError => e
              push_event('result', id: req_id, payload: { ok: false, error: e.message })
            end
          end
          dlg.add_action_callback('studio_state') do |_ctx, req_id|
            push_event('result', id: req_id, payload: { ok: true, state: Studio.state })
          end
          # Только klein: одна запись модели + варианты квантования
          # (gguf-variants) для выбора в окне «Подключение» + статус пайплайна.
          dlg.add_action_callback('studio_models') do |_ctx, req_id, params|
            data = parse_payload(params)
            s = data['settings'] || Settings.all
            begin
              url = s['unsloth_url'].to_s
              key = s['unsloth_key'].to_s
              raise 'нет ключа Unsloth Studio (окно Подключение в шапке)' if key.empty?
              begin
                st = Client.status(url, key)
              rescue StandardError
                st = nil
              end
              variants = []
              default_variant = nil
              begin
                j = Client.gguf_variants(url, key, Client::KLEIN_REPO)
                variants = j.is_a?(Hash) ? (j['variants'] || j['data'] || []) : []
                default_variant = j.is_a?(Hash) ? (j['default_variant'] || j['default']) : nil
              rescue StandardError
                variants = []
              end
              current = st ? st['gguf_filename'].to_s : s['unsloth_gguf'].to_s
              current = Client::KLEIN_GGUF if current.empty?
              preset = Client.preset_for(Client::KLEIN_REPO)
              models = [{ 'id' => Client::KLEIN_REPO, 'loaded' => st ? !!st['loaded'] : false,
                          'task' => 'text-to-image',
                          'quant' => current.sub(/^flux-3-image-klein-(UD-)?/i, '').sub(/\.gguf$/i, ''),
                          'display_name' => Client::KLEIN_REPO,
                          'gguf_file' => current, 'preset' => preset,
                          'variants' => variants, 'default_variant' => default_variant,
                          'current_gguf' => current }]
              push_event('result', id: req_id,
                         payload: { ok: true, models: models, status: st,
                                    studio_defaults: { 'steps' => 16, 'guidance' => 1.0 } })
            rescue StandardError => e
              push_event('result', id: req_id, payload: { ok: false, error: e.message })
            end
          end
          dlg.add_action_callback('open_out_dir') do
            dir = Settings.out_dir
            require 'fileutils'
            FileUtils.mkdir_p(dir)
            UI.openURL("file:///#{dir.tr('\\', '/')}") if Dir.exist?(dir)
          end
          dlg.add_action_callback('select_out_dir') do |_ctx, req_id|
            begin
              # В проекте папка фиксирована (su2vis/out) — выбор только в legacy.
              if Settings.project_state == 'ready'
                push_event('result', id: req_id,
                           payload: { ok: false, error: 'папка проекта фиксирована: su2vis/out рядом с .skp' })
              else
                dir = UI.select_directory({ title: 'Папка для рендеров SU2Vis', directory: Settings.out_dir })
              if dir.to_s.empty?
                push_event('result', id: req_id, payload: { ok: false, cancelled: true })
              else
                saved = Settings.save('out_dir' => dir.to_s)
                Log.append('out_dir', 'dir' => dir.to_s)
                push_event('result', id: req_id, payload: { ok: true, settings: saved })
              end
              end
            rescue StandardError => e
              push_event('result', id: req_id, payload: { ok: false, error: e.message })
            end
          end
          dlg
        end

        def fallback_html
          '<html><body style="font-family:sans-serif;padding:24px">' \
            '<h3>DN1Sup SU2Vis</h3>' \
            '<p>Соберите панель: <code>cd frontend && npm install && npm run build</code></p>' \
            '</body></html>'
        end
      end
    end
  end
end
