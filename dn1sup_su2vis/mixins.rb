# frozen_string_literal: true

require 'base64'
require 'fileutils'
require 'json'
require 'time'

module Dn1sup
  module Su2vis
    # Картинки-примеси: дополнительные референсы для генерации.
    # Лежат в <проект>/su2vis_<имя модели>/mixins/ (старые проекты — su2vis/,
    # legacy — рядом с out_dir): mix_<дата>_<n>.<ext> + сайдкар <файл>.json
    # {caption, active, name}. Подпись указывает, что именно взять с картинки
    # для примеси, при генерации дописывается к промпту.
    module Mixins
      module_function

      IMAGE_EXTS = %w[.png .jpg .jpeg .webp].freeze
      DIRNAME = 'mixins'.freeze
      ROLES = %w[auto style material light object].freeze
      APPLY_TO = %w[both final].freeze
      # Нормальный размер примеси: референсы уходят в студию base64 в JSON,
      # большие фото раздувают запрос и VRAM. Длинная сторона — 1024,
      # файл — до 4 МБ. Фронт жмёт на canvas до отправки (см. MixinsCol),
      # здесь — страховка для пути «Из файла» и прямых вызовов.
      MAX_LONG_SIDE = 1024
      MAX_BYTES = 4 * 1024 * 1024

      # Папка примесей: в проекте — su2vis[_<имя>]/mixins, иначе — <out_dir>/mixins.
      # dir = :auto — по активной модели; иначе явный путь проекта/out.
      def base_dir(dir = :auto)
        d = dir == :auto ? Settings.project_dir : dir
        if !d.nil? && Settings.project_dirname?(File.basename(d.to_s))
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
          meta = normalize_meta(read_sidecar("#{img}.json"), img)
          entries << {
            'id' => name, 'file' => img, 'name' => meta['name'] || name,
            'caption' => meta['caption'] || '', 'caption_neg' => meta['caption_neg'] || '',
            'role' => meta['role'] || 'auto', 'weight' => meta['weight'] || 1.0,
            'apply_to' => meta['apply_to'] || 'both', 'pos' => meta['pos'] || 0,
            'crop' => meta['crop'], 'rotation' => meta['rotation'] || 0.0,
            'boxes' => meta['boxes'] || [],
            'active' => meta.fetch('active', true),
            'mtime' => File.mtime(img).to_f
          }
        end
        entries.sort_by { |e| [e['pos'] || 0, e['mtime'] || 0] }
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

      def update(id, caption: nil, active: nil, dir: :auto, role: nil, caption_neg: nil, weight: nil, apply_to: nil, pos: nil, crop: :__unset__, rotation: :__unset__, boxes: :__unset__)
        d = File.expand_path(base_dir(dir).to_s)
        img = File.expand_path(File.basename(id.to_s), d)
        raise 'файл вне папки примесей' unless img.start_with?(d + File::SEPARATOR)
        raise 'файл не найден' unless File.file?(img)
        meta = normalize_meta(read_sidecar("#{img}.json"), img)
        meta['caption'] = caption.to_s[0, 500] unless caption.nil?
        meta['active'] = (active == true || active.to_s == 'true') unless active.nil?
        meta['role'] = norm_role(role) unless role.nil?
        meta['caption_neg'] = caption_neg.to_s[0, 500] unless caption_neg.nil?
        meta['weight'] = norm_weight(weight) unless weight.nil?
        meta['apply_to'] = norm_apply_to(apply_to) unless apply_to.nil?
        meta['pos'] = pos.to_i unless pos.nil?
        meta['crop'] = norm_crop(crop) unless crop == :__unset__
        meta['rotation'] = norm_rotation(rotation) unless rotation == :__unset__
        meta['boxes'] = norm_boxes(boxes) unless boxes == :__unset__
        write_sidecar("#{img}.json", img, meta)
        { 'id' => File.basename(img), 'file' => img, 'name' => meta['name'],
          'caption' => meta['caption'] || '', 'caption_neg' => meta['caption_neg'] || '',
          'role' => meta['role'] || 'auto', 'weight' => meta['weight'] || 1.0,
          'apply_to' => meta['apply_to'] || 'both', 'pos' => meta['pos'] || 0,
          'crop' => meta['crop'], 'rotation' => meta['rotation'] || 0.0,
          'boxes' => meta['boxes'] || [],
          'active' => meta.fetch('active', true) }
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

      # Удалить все примеси (кнопка «Удалить все» в панели). Каждая — через
      # remove; сбой одиночного файла очистку не роняет.
      def clear(dir = :auto)
        n = 0
        list(dir).each do |e|
          remove(e['id'], dir)
          n += 1
        rescue StandardError
          next
        end
        Log.append('mixins_delete_all', 'count' => n)
        { ok: true, deleted: n }
      end

      # Активные примеси для задачи: [{path, caption, caption_neg, role, weight}].
      # kind оставлен для совместимости ('final' — всё активное).
      def active_for_job(items, kind = nil)
        Array(items).filter_map do |m|
          next unless m.is_a?(Hash)
          p = (m['path'] || m['file'] || '').to_s
          next if p.empty? || !File.file?(p)
          cap = (m['caption'] || '').to_s
          next unless m.fetch('active', true) == true || m.fetch('active', true).to_s == 'true'
          apply = norm_apply_to(m['apply_to'] || m[:apply_to])
          if kind && apply != 'both' && apply != kind.to_s && apply != 'final'
            next
          end
          { 'path' => p, 'caption' => cap,
            'caption_neg' => (m['caption_neg'] || m[:caption_neg]).to_s,
            'role' => norm_role(m['role'] || m[:role]),
            'weight' => norm_weight(m['weight'] || m[:weight]),
            'crop' => norm_crop(m['crop'] || m[:crop]),
            'rotation' => norm_rotation(m['rotation'] || m[:rotation]),
            'boxes' => norm_boxes(m['boxes'] || m[:boxes]) }
        end
      end

      # Порядок карточек: ids сверху вниз. Пишем pos в сайдкары.
      def reorder(ids, dir = :auto)
        list = Array(ids).map(&:to_s).reject(&:empty?)
        raise 'пустой порядок' if list.empty?
        d = base_dir(dir)
        list.each_with_index do |id, i|
          img = File.expand_path(File.basename(id), d.to_s)
          raise 'файл вне папки примесей' unless img.start_with?(File.expand_path(d.to_s) + File::SEPARATOR)
          next unless File.file?(img)
          meta = normalize_meta(read_sidecar("#{img}.json"), img)
          meta['pos'] = i
          write_sidecar("#{img}.json", img, meta)
        end
        { ok: true }
      end

      def save_bytes(raw, ext, name, dir)
        raw, ext = normalize_mixin_bytes(raw, ext.to_s)
        d = base_dir(dir)
        FileUtils.mkdir_p(d.to_s)
        base = "mix_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
        path = unique_path(d.to_s, base, ext)
        File.binwrite(path, raw)
        # Дефолты новых примесей — из настроек колонки (что брать / где учитывать).
        meta = normalize_meta({ 'name' => name.to_s[0, 120], 'caption' => '', 'active' => true,
                                'role' => Settings.get('mixins_default_role'),
                                'apply_to' => Settings.get('mixins_default_apply') }, path)
        write_sidecar("#{path}.json", path, meta)
        entry = { 'id' => File.basename(path), 'file' => path, 'name' => meta['name'],
                  'caption' => '', 'caption_neg' => '', 'role' => meta['role'],
                  'weight' => 1.0,
                  'apply_to' => meta['apply_to'], 'pos' => meta['pos'] || 0,
                  'crop' => nil, 'rotation' => 0.0, 'boxes' => [],
                  'active' => true, 'mtime' => File.mtime(path).to_f }
        Log.append('mixins_add', 'file' => File.basename(path))
        entry
      end

      # Привести байты примеси к норме (MAX_LONG_SIDE / MAX_BYTES):
      # маленькое — как есть; большое — даунскейл; не вышло — понятная
      # ошибка вместо тяжёлого запроса, падающего в студии.
      def normalize_mixin_bytes(raw, ext)
        ext = ext.to_s.downcase
        ext = '.jpg' if ext == '.jpeg'
        return [raw, ext] unless oversized?(raw, ext)

        d = dims_from_bytes(raw, ext)
        size_mb = (raw.bytesize.to_f / 1_048_576).round(1)
        label = d ? "#{d[0]}x#{d[1]}, #{size_mb} МБ" : "#{size_mb} МБ"
        resized = try_powershell_downscale(raw, ext)
        return resized if resized

        raise "картинка большая (#{label}) — сожми до #{MAX_LONG_SIDE} " \
              'по длинной стороне и добавь снова'
      end

      def oversized?(raw, ext)
        return true if raw.bytesize > MAX_BYTES

        d = dims_from_bytes(raw, ext)
        !d.nil? && d.max > MAX_LONG_SIDE
      end

      # Размеры картинки из байтов (без внешних библиотек).
      # Неизвестный формат — nil (тогда давит только лимит по байтам).
      def dims_from_bytes(raw, ext)
        case ext.to_s.downcase
        when '.png' then png_dims_from_bytes(raw)
        when '.jpg', '.jpeg' then jpeg_dims_from_bytes(raw)
        when '.webp' then webp_dims_from_bytes(raw)
        end
      rescue StandardError
        nil
      end

      def png_dims_from_bytes(raw)
        return nil if raw.bytesize < 24
        return nil unless raw.getbyte(0) == 0x89 && raw[1, 3] == 'PNG'
        return nil unless raw[12, 4] == 'IHDR' && raw[8, 4].unpack1('N') == 13

        w, h = raw[16, 4].unpack1('N'), raw[20, 4].unpack1('N')
        (w.to_i > 0 && h.to_i > 0 && w <= 100_000 && h <= 100_000) ? [w, h] : nil
      end

      # JPEG: идём по маркерам до SOF (там ширина/высота).
      def jpeg_dims_from_bytes(raw)
        n = raw.bytesize
        return nil if n < 4 || raw.getbyte(0) != 0xFF || raw.getbyte(1) != 0xD8

        sof = [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
               0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF].freeze
        i = 2
        while i + 3 < n
          return nil unless raw.getbyte(i) == 0xFF

          m = raw.getbyte(i + 1)
          if m == 0xFF
            i += 1
            next
          end
          if m == 0xD8 || m == 0xD9 || m == 0x01 || (0xD0..0xD7).include?(m)
            i += 2
            next
          end
          return nil if i + 3 >= n

          len = (raw.getbyte(i + 2) << 8) + raw.getbyte(i + 3)
          return nil if len < 2 || i + 1 + len >= n
          if sof.include?(m)
            return nil if i + 9 >= n

            h = (raw.getbyte(i + 5) << 8) + raw.getbyte(i + 6)
            w = (raw.getbyte(i + 7) << 8) + raw.getbyte(i + 8)
            return (w > 0 && h > 0) ? [w, h] : nil
          end
          i += 2 + len
        end
        nil
      end

      # WebP: RIFF....WEBP + чанки VP8 (lossy) / VP8L (lossless) / VP8X.
      def webp_dims_from_bytes(raw)
        return nil if raw.bytesize < 30
        return nil unless raw[0, 4] == 'RIFF' && raw[8, 4] == 'WEBP'

        case raw[12, 4]
        when 'VP8 '
          w = raw[26, 2].unpack1('v') & 0x3FFF
          h = raw[28, 2].unpack1('v') & 0x3FFF
          (w > 0 && h > 0) ? [w, h] : nil
        when 'VP8L'
          b1 = raw.getbyte(21)
          b2 = raw.getbyte(22)
          b3 = raw.getbyte(23)
          b4 = raw.getbyte(24)
          w = (b1 | ((b2 & 0x3F) << 8)) + 1
          h = (((b2 >> 6) | (b3 << 2) | ((b4 & 0x0F) << 10))) + 1
          (w > 0 && h > 0) ? [w, h] : nil
        when 'VP8X'
          w = raw.getbyte(21) | (raw.getbyte(22) << 8) | (raw.getbyte(23) << 16)
          h = raw.getbyte(24) | (raw.getbyte(25) << 8) | (raw.getbyte(26) << 16)
          w += 1
          h += 1
          (w > 0 && h > 0) ? [w, h] : nil
        end
      end

      # Запуск внешней команды без вспышки чёрного консольного окна.
      # system("powershell ...") на Windows идёт через cmd.exe + conhost —
      # при старте превью это видно как моргнувшее чёрное окно
      # (см. try_powershell_downscale / try_powershell_transform).
      # WScript.Shell.Run(cmd, 0, true): 0 = SW_HIDE, true = ждать выхода,
      # возвращает код выхода. Fallback — обычный system.
      def run_hidden(cmd)
        begin
          require 'win32ole'
          shell = WIN32OLE.new('WScript.Shell')
          return shell.Run(cmd, 0, true) == 0
        rescue LoadError, StandardError
          nil
        end
        system(cmd)
      end

      # Даунскейл штатными средствами Windows (System.Drawing): без новых
      # зависимостей в поставке. WebP GDI+ не читает — пропускаем.
      # Возвращает [bytes, ext] или nil (не Windows / ошибка / нечего жать).
      def try_powershell_downscale(raw, ext)
        return nil unless RUBY_PLATFORM =~ /mingw|mswin/
        return nil if ext.to_s.downcase == '.webp'

        require 'tmpdir'
        require 'timeout'
        Dir.mktmpdir do |d|
          src = File.join(d, "in#{ext}")
          dst = File.join(d, "out#{ext}")
          ps = File.join(d, 'shrink.ps1')
          File.binwrite(src, raw)
          File.write(ps, powershell_shrink_script, encoding: 'UTF-8')
          cmd = "powershell -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass " \
                "-File \"#{ps}\" -In \"#{src}\" -Out \"#{dst}\" -Max #{MAX_LONG_SIDE}"
          ok = Timeout.timeout(90) { run_hidden(cmd) }
          return nil unless ok && File.file?(dst) && File.size(dst) > 0

          out = File.binread(dst)
          return nil if oversized?(out, ext)

          [out, ext.to_s.downcase]
        end
      rescue StandardError
        nil
      end

      def powershell_shrink_script
        <<~PS
          param([string]$In, [string]$Out, [int]$Max = #{MAX_LONG_SIDE})
          Add-Type -AssemblyName System.Drawing
          $s = [System.Drawing.Bitmap]::FromFile($In)
          try {
            $w = $s.Width; $h = $s.Height
            $sc = [Math]::Min(1.0, $Max / [Math]::Max($w, $h))
            if ($sc -ge 1) { $s.Dispose(); exit 0 }
            $nw = [Math]::Max(1, [int]($w * $sc)); $nh = [Math]::Max(1, [int]($h * $sc))
            $d = New-Object System.Drawing.Bitmap($nw, $nh)
            try {
              $g = [System.Drawing.Graphics]::FromImage($d)
              try {
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.DrawImage($s, 0, 0, $nw, $nh)
              } finally { $g.Dispose() }
              $e = [System.IO.Path]::GetExtension($Out).ToLower()
              if ($e -eq '.png') {
                $d.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
              } else {
                $c = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
                $p = New-Object System.Drawing.Imaging.EncoderParameters(1)
                $p.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]85)
                $d.Save($Out, $c[0], $p)
                $p.Dispose()
              }
            } finally { $d.Dispose() }
          } finally { $s.Dispose() }
        PS
      end

      # Путь референса для задачи: большое жмём во временную копию (кэш по
      # размеру+mtime исходника), маленькое — как есть. Покрывает примеси,
      # добавленные до сжатия при добавлении, и старые панели без даунскейла:
      # студия режет референсы шире 4096px с HTTP 400, тяжёлые жрут VRAM.
      def job_path(path, crop = nil, rotation = nil)
        p = path.to_s
        return p unless File.file?(p)
        ext = File.extname(p).downcase
        return p unless IMAGE_EXTS.include?(ext)
        crop_n = norm_crop(crop)
        rot_n = norm_rotation(rotation)
        raw = File.binread(p) rescue (return p)
        need_t = needs_transform?(crop_n, rot_n)
        return p unless oversized?(raw, ext) || need_t

        cached_transform(p, raw, ext, crop_n, rot_n) || p
      end

      # Путь референса для задачи с боксами: job_path (кроп/поворот/сжатие),
      # затем дорисовать красные рамки с номерами. Координаты боксов — в
      # системе ТРАНСФОРМИРОВАННОЙ картинки. Возвращает [путь, ок]:
      # ок=false — рамки не нарисованы (не Windows / webp / сбой GDI+),
      # jobs.rb тогда не включает боксы в промпт (текст без рамок на
      # картинке только путает модель). Кэш аннотаций — по размеру+mtime
      # исходника + хеш боксов.
      def annotated_job_path(path, crop = nil, rotation = nil, boxes = nil)
        p = job_path(path, crop, rotation)
        bs = norm_boxes(boxes)
        return [p, false] if p.empty? || bs.empty? || !File.file?(p)
        ext = File.extname(p).downcase
        return [p, false] unless %w[.png .jpg .jpeg].include?(ext)

        st = File.stat(p) rescue (return [p, false])
        d = shrink_cache_dir
        return [p, false] if d.nil?
        dst = File.join(d, "#{File.basename(p, '.*')}_#{st.size}_#{st.mtime.to_i}_#{boxes_suffix(bs)}#{ext}")
        return [dst, true] if File.file?(dst) && File.size(dst) > 0

        raw = File.binread(p) rescue (return [p, false])
        dims = dims_from_bytes(raw, ext)
        return [p, false] if dims.nil?
        out = try_powershell_boxes(p, ext, dims, bs)
        return [p, false] if out.nil? || out.empty? || oversized?(out, ext)

        File.binwrite(dst, out)
        Log.append('mixins_boxes', 'file' => File.basename(p), 'boxes' => bs.size)
        [dst, true]
      rescue StandardError
        [p, false]
      end

      def boxes_suffix(bs)
        str = bs.map { |b| "#{b['x']}-#{b['y']}-#{b['w']}-#{b['h']}-#{b['label']}" }.join(';')
        require 'zlib'
        Zlib.crc32(str).to_s(36)
      end

      # Нарисовать боксы через System.Drawing (GDI+ не читает webp — для
      # него annotated_job_path заранее вернул false). Пиксельные координаты
      # считает Ruby — в скрипт идут только целые, без парсинга дробей.
      def try_powershell_boxes(path, ext, dims, bs)
        return nil unless RUBY_PLATFORM =~ /mingw|mswin/

        require 'tmpdir'
        require 'timeout'
        w, h = dims
        long = [w, h].max
        t = [[(long / 300.0).round, 2].max, 6].min
        rects = bs.each_with_index.map do |b, i|
          x0 = (b['x'] * w).round
          y0 = (b['y'] * h).round
          x1 = [[x0 + (b['w'] * w).round, x0 + t].max, w - 1].min
          y1 = [[y0 + (b['h'] * h).round, y0 + t].max, h - 1].min
          "#{x0},#{y0},#{x1},#{y1},#{i + 1}"
        end.join(';')
        Dir.mktmpdir do |dir|
          src = File.join(dir, "in#{ext}")
          dst = File.join(dir, "out#{ext}")
          ps = File.join(dir, 'boxes.ps1')
          File.binwrite(src, File.binread(path))
          File.write(ps, powershell_boxes_script, encoding: 'UTF-8')
          cmd = "powershell -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass " \
                "-File \"#{ps}\" -In \"#{src}\" -Out \"#{dst}\" -T #{t} -Boxes \"#{rects}\""
          ok = Timeout.timeout(120) { run_hidden(cmd) }
          return nil unless ok && File.file?(dst) && File.size(dst) > 0

          File.binread(dst)
        end
      rescue StandardError
        nil
      end

      def powershell_boxes_script
        <<~PS
          param([string]$In, [string]$Out, [int]$T = 3, [string]$Boxes = '')
          Add-Type -AssemblyName System.Drawing
          $s = [System.Drawing.Bitmap]::FromFile($In)
          try {
            $g = [System.Drawing.Graphics]::FromImage($s)
            try {
              $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(222, 30, 38), 1)
              $bg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
              $fg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(20, 20, 20))
              $font = New-Object System.Drawing.Font('Arial', [float]([Math]::Max(10, [int][Math]::Round([Math]::Max($s.Width, $s.Height) / 25.0))), [System.Drawing.FontStyle]::Bold)
              foreach ($part in $Boxes.Split(';')) {
                if ($part -eq '') { continue }
                $c = $part.Split(',')
                if ($c.Count -lt 5) { continue }
                $x0 = [int]$c[0]; $y0 = [int]$c[1]; $x1 = [int]$c[2]; $y1 = [int]$c[3]; $num = $c[4]
                for ($k = 0; $k -lt $T; $k++) {
                  $g.DrawRectangle($pen, $x0 + $k, $y0 + $k, ($x1 - $x0 - 2 * $k), ($y1 - $y0 - 2 * $k))
                }
                $sz = $g.MeasureString($num, $font)
                $bw = [int][Math]::Ceiling($sz.Width) + 4
                $bh = [int][Math]::Ceiling($sz.Height)
                $bx = [Math]::Max(0, [Math]::Min($x0, $s.Width - $bw - 1))
                $by = [Math]::Max(0, [Math]::Min($y0, $s.Height - $bh - 1))
                $g.FillRectangle($bg, $bx, $by, $bw, $bh)
                $g.DrawString($num, $font, $fg, [float]($bx + 2), [float]$by)
              }
            } finally { $g.Dispose() }
            $e = [System.IO.Path]::GetExtension($Out).ToLower()
            if ($e -eq '.png') {
              $s.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
            } else {
              $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
              $pp = New-Object System.Drawing.Imaging.EncoderParameters(1)
              $pp.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]90)
              $s.Save($Out, $codec[0], $pp)
              $pp.Dispose()
            }
          } finally { $s.Dispose() }
        PS
      end

      def cached_shrink(path, raw, ext)
        cached_transform(path, raw, ext, nil, 0.0)
      end

      def cached_transform(path, raw, ext, crop, rotation)
        st = File.stat(path) rescue (return nil)
        crop_n = norm_crop(crop)
        rot_n = norm_rotation(rotation)
        key = "#{File.basename(path, '.*')}_#{st.size}_#{st.mtime.to_i}#{transform_key_suffix(crop_n, rot_n)}"
        d = shrink_cache_dir
        return nil if d.nil?

        dst = File.join(d, "#{key}#{ext}")
        return dst if File.file?(dst) && File.size(dst) > 0
        out = needs_transform?(crop_n, rot_n) ? try_powershell_transform(raw, ext, crop_n, rot_n) : try_powershell_downscale(raw, ext)
        return nil if out.nil?

        File.binwrite(dst, out[0])
        Log.append('mixins_shrink', 'file' => File.basename(path), 'to' => File.basename(dst))
        dst
      rescue StandardError
        nil
      end

      def transform_key_suffix(crop, rotation)
        r = norm_rotation(rotation)
        return '' if crop.nil? && r == 0.0
        c = crop.nil? ? 'full' : "#{(crop['x'] * 10_000).round}-#{(crop['y'] * 10_000).round}-#{(crop['w'] * 10_000).round}-#{(crop['h'] * 10_000).round}"
        "_t#{c}_r#{format('%.1f', r).tr('.', 'p').tr('-', 'm')}"
      end

      def needs_transform?(crop, rotation)
        return true unless norm_crop(crop).nil?
        norm_rotation(rotation) != 0.0
      end

      def try_powershell_transform(raw, ext, crop, rotation)
        crop_n = norm_crop(crop)
        rot_n = norm_rotation(rotation)
        return try_powershell_downscale(raw, ext) if crop_n.nil? && rot_n == 0.0
        return nil unless RUBY_PLATFORM =~ /mingw|mswin/
        return nil if ext.to_s.downcase == '.webp' && !crop_n.nil?

        require 'tmpdir'
        require 'timeout'
        Dir.mktmpdir do |d|
          src = File.join(d, "in#{ext}")
          dst = File.join(d, "out#{ext}")
          ps = File.join(d, 'crop.ps1')
          File.binwrite(src, raw)
          File.write(ps, powershell_transform_script, encoding: 'UTF-8')
          cx = crop_n.nil? ? -1 : crop_n['x'].to_f
          cy = crop_n.nil? ? -1 : crop_n['y'].to_f
          cw = crop_n.nil? ? -1 : crop_n['w'].to_f
          ch = crop_n.nil? ? -1 : crop_n['h'].to_f
          cmd = "powershell -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass " \
                "-File \"#{ps}\" -In \"#{src}\" -Out \"#{dst}\" -Max #{MAX_LONG_SIDE} " \
                "-Angle #{rot_n} -Cx #{cx} -Cy #{cy} -Cw #{cw} -Ch #{ch}"
          ok = Timeout.timeout(120) { run_hidden(cmd) }
          return nil unless ok && File.file?(dst) && File.size(dst) > 0

          out = File.binread(dst)
          return nil if out.empty? || oversized?(out, ext)

          [out, ext.to_s.downcase]
        end
      rescue StandardError
        nil
      end

      def powershell_transform_script
        <<~PS
          param([string]$In, [string]$Out, [int]$Max = #{MAX_LONG_SIDE},
                [double]$Angle = 0, [double]$Cx = -1, [double]$Cy = -1,
                [double]$Cw = -1, [double]$Ch = -1)
          Add-Type -AssemblyName System.Drawing
          $s = [System.Drawing.Bitmap]::FromFile($In)
          try {
            $cur = $s
            if ($Cx -ge 0 -and $Cy -ge 0 -and $Cw -gt 0 -and $Ch -gt 0) {
              $rx = [Math]::Max(0, [int][Math]::Round($cur.Width * $Cx))
              $ry = [Math]::Max(0, [int][Math]::Round($cur.Height * $Cy))
              $rw = [Math]::Min($cur.Width - $rx, [Math]::Max(1, [int][Math]::Round($cur.Width * $Cw)))
              $rh = [Math]::Min($cur.Height - $ry, [Math]::Max(1, [int][Math]::Round($cur.Height * $Ch)))
              if ($rw -le 0 -or $rh -le 0) { throw 'bad crop rect' }
              $crop = New-Object System.Drawing.Bitmap($rw, $rh)
              try {
                $g2 = [System.Drawing.Graphics]::FromImage($crop)
                try {
                  $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                  $g2.DrawImage($cur, (New-Object System.Drawing.Rectangle(0, 0, $rw, $rh)),
                    $rx, $ry, $rw, $rh, [System.Drawing.GraphicsUnit]::Pixel)
                } finally { $g2.Dispose() }
                if ($cur -ne $s) { $cur.Dispose() }
                $cur = $crop
              } catch { $crop.Dispose(); throw }
            }
            if ([Math]::Abs($Angle) -ge 0.05) {
              $rad = $Angle * [Math]::PI / 180.0
              $c = [Math]::Abs([Math]::Cos($rad)); $sn = [Math]::Abs([Math]::Sin($rad))
              $nw = [Math]::Max(1, [int][Math]::Round($cur.Width * $c + $cur.Height * $sn))
              $nh = [Math]::Max(1, [int][Math]::Round($cur.Width * $sn + $cur.Height * $c))
              $d = New-Object System.Drawing.Bitmap($nw, $nh)
              try {
                $g = [System.Drawing.Graphics]::FromImage($d)
                try {
                  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                  $g.Clear([System.Drawing.Color]::Transparent)
                  $g.TranslateTransform($nw / 2.0, $nh / 2.0)
                  $g.RotateTransform($Angle)
                  $g.TranslateTransform(-$cur.Width / 2.0, -$cur.Height / 2.0)
                  $g.DrawImage($cur, 0, 0, $cur.Width, $cur.Height)
                } finally { $g.Dispose() }
                if ($cur -ne $s) { $cur.Dispose() }
                $cur = $d
              } catch { $d.Dispose(); throw }
            }
            $w = $cur.Width; $h = $cur.Height
            $sc = [Math]::Min(1.0, $Max / [Math]::Max($w, $h))
            $fin = $cur
            if ($sc -lt 1) {
              $nw2 = [Math]::Max(1, [int]($w * $sc)); $nh2 = [Math]::Max(1, [int]($h * $sc))
              $d2 = New-Object System.Drawing.Bitmap($nw2, $nh2)
              try {
                $g3 = [System.Drawing.Graphics]::FromImage($d2)
                try {
                  $g3.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                  $g3.DrawImage($cur, 0, 0, $nw2, $nh2)
                } finally { $g3.Dispose() }
                if ($cur -ne $s) { $cur.Dispose() }
                $fin = $d2
              } catch { $d2.Dispose(); throw }
            }
            try {
              $e = [System.IO.Path]::GetExtension($Out).ToLower()
              if ($e -eq '.png') {
                $fin.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
              } else {
                $c2 = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
                $pp = New-Object System.Drawing.Imaging.EncoderParameters(1)
                $pp.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]85)
                $fin.Save($Out, $c2[0], $pp)
                $pp.Dispose()
              }
            } finally { if ($fin -ne $cur -and $fin -ne $s) { $fin.Dispose() } }
            if ($cur -ne $s) { $cur.Dispose() }
          } finally { $s.Dispose() }
        PS
      end

      def shrink_cache_dir
        require 'tmpdir'
        d = File.join(Dir.tmpdir, 'dn1sup_su2vis', 'mix_small')
        FileUtils.mkdir_p(d)
        d
      rescue StandardError
        nil
      end

      def read_sidecar(sp)
        return {} unless File.file?(sp.to_s)
        doc = JSON.parse(File.read(sp.to_s, encoding: 'UTF-8')) rescue nil
        doc.is_a?(Hash) ? doc : {}
      end

      def write_sidecar(sp, img, meta)
        m = normalize_meta(meta.is_a?(Hash) ? meta : {}, img)
        doc = { 'name' => m['name'] || File.basename(img.to_s),
                'caption' => (m['caption'] || '').to_s,
                'caption_neg' => (m['caption_neg'] || '').to_s,
                'role' => m['role'] || 'auto',
                'weight' => m['weight'] || 1.0,
                'apply_to' => m['apply_to'] || 'both',
                'pos' => (m['pos'] || 0).to_i,
                'crop' => m['crop'],
                'rotation' => m['rotation'] || 0.0,
                'boxes' => m['boxes'] || [],
                'active' => m.fetch('active', true) ? true : false }
        File.write(sp.to_s, JSON.pretty_generate(doc), encoding: 'UTF-8')
        doc
      end

      def norm_role(v)
        s = v.to_s.strip.downcase
        ROLES.include?(s) ? s : 'auto'
      end

      def norm_apply_to(v)
        s = v.to_s.strip.downcase
        s = 'final' if s == 'preview'
        APPLY_TO.include?(s) ? s : 'both'
      end

      def norm_weight(v)
        f = v.to_f
        f = 1.0 if f.nil? || (v.to_s.empty? && f.zero?)
        [[f, 0.1].max, 2.0].min.round(2)
      rescue StandardError
        1.0
      end

      def norm_crop(v)
        return nil if v.nil?
        return nil if v.is_a?(String) && v.strip.empty?
        h = v.is_a?(Hash) ? v : nil
        return nil unless h
        x = (h['x'] || h[:x] || 0).to_f
        y = (h['y'] || h[:y] || 0).to_f
        w = (h['w'] || h[:w] || 0).to_f
        hh = (h['h'] || h[:h] || 0).to_f
        return nil if w <= 0.005 || hh <= 0.005
        x = [[x, 0.0].max, 0.99].min
        y = [[y, 0.0].max, 0.99].min
        w = [[w, 0.01].max, 1.0 - x].min
        hh = [[hh, 0.01].max, 1.0 - y].min
        return nil if w < 0.01 || hh < 0.01
        { 'x' => x.round(4), 'y' => y.round(4), 'w' => w.round(4), 'h' => hh.round(4) }
      rescue StandardError
        nil
      end

      def norm_rotation(v)
        return 0.0 if v.nil?
        return 0.0 if v.to_s.strip.empty?
        f = v.to_f
        return 0.0 unless f.finite?
        f = ((f + 180.0) % 360.0) - 180.0
        f = 180.0 if f == -180.0
        f = f.round(1)
        f.abs < 0.05 ? 0.0 : [[f, -180.0].max, 180.0].min
      rescue StandardError
        0.0
      end

      # Дефолты для старых сайдкаров (только caption/active).
      def normalize_meta(m, img = nil)
        h = m.is_a?(Hash) ? m.dup : {}
        h['name'] = (h['name'] || (img ? File.basename(img.to_s) : '')).to_s[0, 120]
        h['caption'] = (h['caption'] || '').to_s[0, 500]
        h['caption_neg'] = (h['caption_neg'] || h['ignore'] || '').to_s[0, 500]
        h['role'] = norm_role(h['role'])
        h['weight'] = norm_weight(h.key?('weight') ? h['weight'] : 1.0)
        h['apply_to'] = norm_apply_to(h['apply_to'])
        h['pos'] = (h['pos'] || 0).to_i
        h['crop'] = norm_crop(h['crop'])
        h['rotation'] = norm_rotation(h['rotation'])
        h['boxes'] = norm_boxes(h['boxes'])
        h['active'] = h.fetch('active', true) ? true : false
        h
      end

      # Боксы с подписями: единая нормализация из Scenes (загружается
      # раньше mixins в main.rb, чистая функция — работает и под стабом).
      def norm_boxes(v)
        Scenes.norm_boxes(v)
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
