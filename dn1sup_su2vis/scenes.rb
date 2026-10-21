# frozen_string_literal: true

require 'sketchup.rb'
require 'base64'
require 'fileutils'
require 'tmpdir'

module Dn1sup
  module Su2vis
    # Экспорт эскизов сцен: переключает Pages, пишет PNG вида во врем. папку.
    module Scenes
      module_function

      def tmp_dir
        d = File.join(Dir.tmpdir, 'dn1sup_su2vis')
        FileUtils.mkdir_p(d)
        d
      end

      def list
        model = Sketchup.active_model
        return [] unless model
        pages = model.pages
        current = pages.selected_page
        pages.map.with_index do |p, i|
          { name: p.name, index: i, current: p == current }
        end
      end

      # Скриншот одной сцены по индексу в точном размере w x h (пресеты 4:3).
      # Без w/h — размер текущего вида. Возвращает путь PNG.
      # thin_lines: выключить силуэты на время снимка (тонкие линии 1px).
      def capture(index, w = nil, h = nil, thin_lines: false)
        model = Sketchup.active_model
        raise 'нет активной модели' unless model
        pages = model.pages
        raise 'в модели нет сцен' if pages.count.zero?
        page = pages[index.to_i]
        raise "сцена #{index} не найдена" unless page

        prev = pages.selected_page
        begin
          pages.selected_page = page
          settle_view
          Sketchup.active_model.active_view.refresh
          path = File.join(tmp_dir, "scene_#{index}.png")
          opts = { filename: path }
          opts[:width] = w.to_i if w && w.to_i > 0
          opts[:height] = h.to_i if h && h.to_i > 0
          ok = with_dims_hidden(model, thin_lines: thin_lines) { Sketchup.active_model.active_view.write_image(opts) }
          raise "write_image не удался для сцены #{page.name}" unless ok && File.file?(path)
          path
        ensure
          pages.selected_page = prev if prev && prev != page
        end
      end

      # Эскиз — чистая геометрия: размерные линии (Sketchup::Dimension,
      # включая вложенные в группы/компоненты) прячем на время снимка.
      # thin_lines: заодно выключить силуэты (толстые линии), мелкий
      # формат с профилями превращается в кашу. Через операцию с abort:
      # всё восстанавливается само, модель не пачкается и в undo не попадает.
      def with_dims_hidden(model, thin_lines: false)
        hidden = []
        ro = model.rendering_options
        prev_sil = ro['DrawSilhouettes']
        op = false
        model.start_operation('su2vis: снимок сцены', true)
        op = true
        begin
          collect_dims(model.entities, hidden)
          model.definitions.each do |d|
            collect_dims(d.entities, hidden) unless d.image?
          end
          hidden.each { |e| e.visible = false }
          ro['DrawSilhouettes'] = false if thin_lines
          yield
        ensure
          begin
            ro['DrawSilhouettes'] = prev_sil if thin_lines
          rescue StandardError
            nil
          end
          model.abort_operation if op
        end
      end

      def collect_dims(entities, acc)
        entities.each do |e|
          if e.is_a?(Sketchup::Dimension)
            acc << e if e.visible?
          elsif e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            collect_dims(e.definition.entities, acc)
          end
        end
      end

      # Референс для превью: сцена на длинной стороне 1600, тонкие линии,
      # без размеров. Пропорции — как у текущего вида (не тянем в 4:3,
      # иначе поплывёт композиция). Сам превью генерируется маленьким
      # (256) из этого же файла — студия даунскейлит референс сама.
      def capture_hd(index, long_side = 1600)
        model = Sketchup.active_model
        raise 'нет активной модели' unless model
        view = model.active_view
        vw, vh = view.vpwidth, view.vpheight
        raise 'неизвестный размер вида' unless vw.to_i > 0 && vh.to_i > 0
        s = long_side.to_f / [vw, vh].max
        capture(index, (vw * s).round, (vh * s).round, thin_lines: true)
      end
      # Записать текущую камеру окна в сцену (флаг 1 = camera, проверено
      # вживую 2026-10-20). После орбиты без этого эскиз снимается со старого
      # сохранённого вида и не совпадает с тем, что видит пользователь.
      def update_camera(index)
        model = Sketchup.active_model
        raise 'нет активной модели' unless model
        page = model.pages[index.to_i]
        raise "сцена #{index} не найдена" unless page

        page.update(1) ? true : false
      end
      def shot(index, w = nil, h = nil)
        path = capture(index, w, h)
        "data:image/png;base64,#{Base64.strict_encode64(File.binread(path))}"
      rescue StandardError
        nil
      end

      # Тумба для списка сцен (170x128, base64 data-url): тонкие линии
      # без силуэтов и без размеров — мелкий формат, профили ни к чему.
      THUMB_W = 170
      THUMB_H = 128

      def thumbnail(index)
        path = capture(index, THUMB_W, THUMB_H, thin_lines: true)
        "data:image/png;base64,#{Base64.strict_encode64(File.binread(path))}"
      rescue StandardError
        nil
      end

      # Пакетное снятие сцен на ГЛАВНОМ потоке (колбэки панели уже там):
      # write_image из рабочего Thread отдаёт устаревший кадр framebuffer,
      # поэтому эскизы снимаем до старта фоновой задачи. Анимацию перехода
      # отключаем на время пакета — переключения мгновенные, settle не нужен.
      # Возвращает {index => путь PNG}, в конце возвращает исходную страницу.
      # hd: референс для превью — сцена 1600 по длинной, тонкие линии.
      def capture_all(indexes, hd: false)
        model = Sketchup.active_model
        raise 'нет активной модели' unless model
        opts = model.options['PageOptions']
        prev_transition = opts['ShowTransition']
        prev_page = model.pages.selected_page
        shots = {}
        begin
          opts['ShowTransition'] = false
          Array(indexes).map(&:to_i).uniq.each do |idx|
            shots[idx] = hd ? capture_hd(idx) : capture(idx)
          end
        ensure
          opts['ShowTransition'] = prev_transition
          model.pages.selected_page = prev_page if prev_page
        end
        shots
      end

      # Ждать конца анимации перехода между сценами: камера должна дважды
      # подряд совпасть. Иначе write_image ловит промежуточный кадр,
      # не соответствующий ни одной сцене.
      def settle_view(timeout_s = 6.0)
        view = Sketchup.active_model.active_view
        last = nil
        stable = 0
        t0 = Time.now
        loop do
          cam = view.camera
          cur = (cam.eye.to_a + cam.target.to_a).map { |v| v.round(3) }
          if cur == last
            stable += 1
            break if stable >= 2
          else
            stable = 0
            last = cur
          end
          break if Time.now - t0 > timeout_s
          sleep 0.1
        end
      end

      def dims(path)
        d = File.binread(path, 33)
        return nil unless d[0, 8] == "\x89PNG\r\n\x1A\n".b
        [d[16, 4].unpack1('N'), d[20, 4].unpack1('N')]
      end
    end
  end
end
