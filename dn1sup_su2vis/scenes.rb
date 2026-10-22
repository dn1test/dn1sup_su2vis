# frozen_string_literal: true

require 'sketchup.rb'
require 'base64'
require 'fileutils'
require 'tmpdir'
require 'zlib'

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
      # hide_dims: прятать размерные линии (иначе летят в референс модели).
      # white_bg: убрать любой фон (небо/земля/фон) — только белый.
      def capture(index, w = nil, h = nil, thin_lines: false, hide_dims: true, white_bg: false)
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
          ok = with_dims_hidden(model, thin_lines: thin_lines, hide_dims: hide_dims, white_bg: white_bg) { Sketchup.active_model.active_view.write_image(opts) }
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
      # hide_dims: false — размеры остаются в кадре (для схем с размерами).
      # white_bg: true — на время снимка фон/небо/земля белые, небо и земля
      # скрыты. Всё возвращается в ensure, модель не пачкается.
      # Цвета фона в разных версиях SU лежат под разными ключами —
      # пишем только те, что есть, ошибки игнорируем.
      WHITE_BG_COLOR_KEYS = %w[BackgroundColor SkyColor GroundColor HorizonColor].freeze
      WHITE_BG_HIDE_KEYS = %w[DrawGround DrawHorizon].freeze

      def with_dims_hidden(model, thin_lines: false, hide_dims: true, white_bg: false)
        hidden = []
        ro = model.rendering_options
        prev_sil = ro['DrawSilhouettes']
        prev_bg = {}
        op = false
        model.start_operation('su2vis: снимок сцены', true)
        op = true
        begin
          if hide_dims
            collect_dims(model.entities, hidden)
            model.definitions.each do |d|
              collect_dims(d.entities, hidden) unless d.image?
            end
            hidden.each { |e| e.visible = false }
          end
          ro['DrawSilhouettes'] = false if thin_lines
          prev_bg = apply_white_bg(ro) if white_bg
          yield
        ensure
          begin
            ro['DrawSilhouettes'] = prev_sil if thin_lines
          rescue StandardError
            nil
          end
          begin
            restore_bg(ro, prev_bg) unless prev_bg.empty?
          rescue StandardError
            nil
          end
          model.abort_operation if op
        end
      end

      def white_color
        if defined?(Sketchup::Color)
          Sketchup::Color.new(255, 255, 255)
        else
          [255, 255, 255]
        end
      end

      # Выставить белый фон: цвета — в белый, небо/землю — скрыть.
      # Возвращает сохранённые прежние значения для restore_bg.
      def apply_white_bg(ro)
        prev = {}
        white = white_color
        WHITE_BG_COLOR_KEYS.each do |k|
          begin
            prev[k] = ro[k]
            ro[k] = white
          rescue StandardError
            prev.delete(k)
          end
        end
        WHITE_BG_HIDE_KEYS.each do |k|
          begin
            prev[k] = ro[k]
            ro[k] = false
          rescue StandardError
            prev.delete(k)
          end
        end
        prev
      rescue StandardError
        prev
      end

      def restore_bg(ro, prev)
        prev.each do |k, v|
          begin
            ro[k] = v
          rescue StandardError
            next
          end
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
      def capture_hd(index, long_side = 1600, thin_lines: true, hide_dims: true, white_bg: false)
        model = Sketchup.active_model
        raise 'нет активной модели' unless model
        view = model.active_view
        vw, vh = view.vpwidth, view.vpheight
        raise 'неизвестный размер вида' unless vw.to_i > 0 && vh.to_i > 0
        s = long_side.to_f / [vw, vh].max
        capture(index, (vw * s).round, (vh * s).round, thin_lines: thin_lines, hide_dims: hide_dims, white_bg: white_bg)
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

      def thumbnail(index, white_bg: false)
        path = capture(index, THUMB_W, THUMB_H, thin_lines: true, white_bg: white_bg)
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
      # sketch: {source, preset_w, preset_h, thin_lines, hide_dims, autocrop, white_bg}
      # из настроек колонки «Сцены» — source: hd (1600) / view (размер вида)
      # / preset (точный размер из sketch_preset); hd: true = как source hd.
      # autocrop: резать поля до контента (+5%) перед отдачей в модель.
      # white_bg: белый фон вместо неба/земли/фона модели.
      def capture_all(indexes, hd: false, sketch: nil)
        model = Sketchup.active_model
        raise 'нет активной модели' unless model
        sk = sketch.is_a?(Hash) ? sketch : {}
        thin = sk.key?('thin_lines') ? sk['thin_lines'] == true : true
        hide = sk.key?('hide_dims') ? sk['hide_dims'] != false : true
        crop = sk['autocrop'] == true
        white = sk['white_bg'] == true
        src = sk['source'].to_s
        src = 'hd' if hd || src.empty?
        pw = sk['preset_w'].to_i
        ph = sk['preset_h'].to_i
        opts = model.options['PageOptions']
        prev_transition = opts['ShowTransition']
        prev_page = model.pages.selected_page
        shots = {}
        begin
          opts['ShowTransition'] = false
          Array(indexes).map(&:to_i).uniq.each do |idx|
            shot =
              if src == 'preset' && pw > 0 && ph > 0
                capture(idx, pw, ph, thin_lines: thin, hide_dims: hide, white_bg: white)
              elsif src == 'view'
                capture(idx, nil, nil, thin_lines: thin, hide_dims: hide, white_bg: white)
              else
                capture_hd(idx, 1600, thin_lines: thin, hide_dims: hide, white_bg: white)
              end
            shots[idx] = maybe_autocrop(shot, crop)
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

      # Автокроп полей эскиза: ужать PNG до контента + поля margin
      # (доля от размера контента, 0.05). Путь переписывается на месте,
      # возвращается тот же путь. Нет контента / не PNG / чужой формат —
      # файл не трогаем. Ошибки наружу не пускаем: вызываем через
      # maybe_autocrop.
      def maybe_autocrop(path, do_crop, margin = 0.05)
        return path unless do_crop
        autocrop(path, margin)
      rescue StandardError
        path
      end

      def autocrop(path, margin = 0.05)
        bytes = File.binread(path)
        box = content_bbox(bytes)
        return path if box.nil?

        x, y, cw, chh = box
        mx = (cw * margin).round
        my = (chh * margin).round
        pic = png_pixels(bytes)
        x0 = [x - mx, 0].max
        y0 = [y - my, 0].max
        x1 = [x + cw + mx, pic[:w]].min
        y1 = [y + chh + my, pic[:h]].min
        return path if x0.zero? && y0.zero? && x1 == pic[:w] && y1 == pic[:h]

        out = crop_png(bytes, [x0, y0, x1 - x0, y1 - y0])
        return path if out.nil?

        File.binwrite(path, out)
        path
      end

      # Рамка контента [x, y, w, h] по неоднородным пикселям (фон —
      # средний цвет углов, допуск tolerance на канал). nil — весь кадр
      # однородный или формат не разобран. Чистая функция — тестируется.
      def content_bbox(bytes, tolerance = 4, min_keep = 0.25)
        pic = png_pixels(bytes)
        return nil unless pic

        w, h, ch, rows = pic[:w], pic[:h], pic[:ch], pic[:rows]
        n = [ch, 3].min
        corners = [rows[0][0, n], rows[0][-ch, n], rows[-1][0, n], rows[-1][-ch, n]]
        bg = corners.transpose.map { |cc| cc.sum / cc.size }
        same = lambda do |pix|
          n.times.all? { |k| (pix[k] - bg[k]).abs <= tolerance }
        end
        top = 0
        top += 1 while top < h && rows[top].each_slice(ch).all? { |px| same.call(px) }
        return nil if top >= h

        bot = h - 1
        bot -= 1 while bot > top && rows[bot].each_slice(ch).all? { |px| same.call(px) }
        left = 0
        left += 1 while left < w && rows[top..bot].all? { |r| same.call(r[left * ch, ch]) }
        right = w - 1
        right -= 1 while right > left && rows[top..bot].all? { |r| same.call(r[right * ch, ch]) }
        cw = right - left + 1
        chh = bot - top + 1
        return nil if cw < w * min_keep || chh < h * min_keep

        [left, top, cw, chh]
      end

      # Мини-декодер PNG: только depth 8, без interlace, типы 0/2/6
      # (серый/RGB/RGBA). Чужое — nil. Чистая функция — тестируется.
      def png_pixels(bytes)
        d = bytes.b
        return nil unless d[0, 8] == "\x89PNG\r\n\x1A\n".b

        pos = 8
        idat = +''.b
        w = h = depth = ctype = interlace = nil
        while pos + 8 <= d.bytesize
          len = d[pos, 4].unpack1('N')
          type = d[pos + 4, 4]
          data = d[pos + 8, len] || ''.b
          if type == 'IHDR'
            w, h = data[0, 4].unpack1('N'), data[4, 4].unpack1('N')
            depth, ctype = data[8].ord, data[9].ord
            interlace = data[12].ord
          elsif type == 'IDAT'
            idat << data
          elsif type == 'IEND'
            break
          end
          pos += 12 + len
        end
        ch = { 0 => 1, 2 => 3, 6 => 4 }[ctype]
        return nil unless w && ch && depth == 8 && interlace == 0 && !idat.empty?

        begin
          raw = Zlib.inflate(idat)
        rescue StandardError
          return nil
        end
        stride = w * ch
        return nil unless raw.bytesize == h * (stride + 1)

        rows = []
        prev = Array.new(stride, 0)
        off = 0
        h.times do
          f = raw.getbyte(off)
          off += 1
          cur = raw.byteslice(off, stride).bytes
          off += stride
          stride.times do |i|
            a = i >= ch ? cur[i - ch] : 0
            b = prev[i]
            c = i >= ch ? prev[i - ch] : 0
            add = case f
                  when 1 then a
                  when 2 then b
                  when 3 then (a + b) / 2
                  when 4 then paeth(a, b, c)
                  else 0
                  end
            cur[i] = (cur[i] + add) & 0xFF
          end
          rows << cur
          prev = cur
        end
        { w: w, h: h, ch: ch, ctype: ctype, rows: rows }
      end

      def paeth(a, b, c)
        p = a + b - c
        pa = (p - a).abs
        pb = (p - b).abs
        pc = (p - c).abs
        pa <= pb && pa <= pc ? a : (pb <= pc ? b : c)
      end

      # Вырезать [x, y, w, h] из PNG-байтов (фильтр None на строках).
      # nil — не разобрали. Чистая функция — тестируется.
      def crop_png(bytes, box)
        pic = png_pixels(bytes)
        return nil unless pic

        x, y, cw, chh = box
        return nil unless x >= 0 && y >= 0 && cw > 0 && chh > 0 &&
                          x + cw <= pic[:w] && y + chh <= pic[:h]

        raw = +''.b
        chh.times do |r|
          raw << 0.chr
          raw << pic[:rows][y + r][x * pic[:ch], cw * pic[:ch]].pack('C*')
        end
        sig = "\x89PNG\r\n\x1A\n".b
        ihdr = [cw, chh, 8, pic[:ctype], 0, 0, 0].pack('NNC5')
        sig + png_chunk('IHDR', ihdr) + png_chunk('IDAT', Zlib.deflate(raw)) + png_chunk('IEND', '')
      end

      def png_chunk(type, data)
        d = data.b
        [d.bytesize].pack('N') + type + d + [Zlib.crc32(type + d)].pack('N')
      end
    end
  end
end
