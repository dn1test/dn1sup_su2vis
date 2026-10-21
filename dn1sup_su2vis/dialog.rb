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
        def result_data_url(file)
          dir = Settings.out_dir
          path = File.expand_path(file.to_s, dir)
          unless path.start_with?(dir + File::SEPARATOR) && File.file?(path)
            raise 'файл вне папки результатов или не найден'
          end
          mime = Client.sniff_mime(path) ||
                 (File.extname(path).downcase == '.png' ? 'image/png' : 'image/jpeg')
          "data:#{mime};base64,#{Base64.strict_encode64(File.binread(path))}"
        end

        private

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
            push_event('result', id: req_id,
                       payload: { index: data['index'].to_i, thumb: Scenes.thumbnail(data['index'].to_i) })
          end
          dlg.add_action_callback('scenes_sync_view') do |_ctx, req_id, params|
            data = parse_payload(params)
            idx = data['index'].to_i
            ok = Scenes.update_camera(idx)
            push_event('result', id: req_id,
                       payload: { index: idx, ok: ok, thumb: Scenes.thumbnail(idx) })
          end
          dlg.add_action_callback('scenes_capture') do |_ctx, req_id, params|
            data = parse_payload(params)
            begin
              list = Array(data['scenes']).map(&:to_i)
              shots = Scenes.capture_all(list, hd: data['hd'] == true)
              Log.append('shots_captured', 'scenes' => list, 'hd' => data['hd'] == true)
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
              entry = Mixins.update(data['id'].to_s, caption: data['caption'], active: data['active'])
              push_event('result', id: req_id, payload: { ok: true, entry: entry })
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
            job = Jobs.enqueue(data['kind'] || 'preview',
                               Array(data['scenes']).map(&:to_i),
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
          # Галерея на диске: что лежит в папке пользователя (превью+финалы
          # с сайдкарами параметров). Удаление — только по кнопке на картинке.
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
          dlg.add_action_callback('enhance_preview') do |_ctx, req_id, params|
            data = parse_payload(params)
            begin
              s = Settings.all
              raise 'нет ключа Unsloth Studio (вкладка Настройки)' if s['unsloth_key'].to_s.empty?
              ep = Client.enhance_preview(s['unsloth_url'], s['unsloth_key'],
                                          data['prompt'] || s['prompt'], data['reference'])
              push_event('result', id: req_id, payload: { ok: true, enhanced_prompt: ep })
            rescue StandardError => e
              push_event('result', id: req_id, payload: { ok: false, error: e.message })
            end
          end
          # Байты превью из панели — во временный файл для финала:
          # финал дорабатывает именно эту картинку, а не переснимает сцену.
          dlg.add_action_callback('preview_save') do |_ctx, req_id, params|
            data = parse_payload(params)
            begin
              url = data['data_url'].to_s
              m = url.match(%r{\Adata:image/(png|jpeg);base64,(.+)\z}m)
              raise 'нет картинки превью' if m.nil?
              raw = Base64.strict_decode64(m[2])
              raise 'пустая картинка' if raw.empty?
              require 'fileutils'
              FileUtils.mkdir_p(Scenes.tmp_dir)
              path = File.join(Scenes.tmp_dir, "prev_#{data['scene'].to_i}_#{data['seed'].to_i}.png")
              File.binwrite(path, raw)
              push_event('result', id: req_id, payload: { ok: true, path: path })
            rescue StandardError => e
              push_event('result', id: req_id, payload: { ok: false, error: e.message })
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
