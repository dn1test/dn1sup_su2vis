require 'optparse'
require 'yaml'
require 'fileutils'
require 'json'
require 'net/http'
require 'uri'
require 'base64'

APP_NAME       = 'sketch2photo'
DEFAULT_CONFIG = './config.yaml'
IN_DIR         = './in'
OUT_DIR        = './out'

MIME_BY_EXT = {
  '.png'  => 'image/png',
  '.jpg'  => 'image/jpeg',
  '.jpeg' => 'image/jpeg',
  '.webp' => 'image/webp',
  '.bmp'  => 'image/bmp',
  '.gif'  => 'image/gif'
}.freeze

DEFAULT_PROMPT = <<~PROMPT.strip
  Photorealistic render based on the provided sketch. Keep the exact same composition, geometry, proportions and scale of every object. Replace any silhouette scale figures with a real standing person in casual clothing (jeans, t-shirt) for human scale. Soft natural daylight, architectural photography, ultra-detailed, 8k, magazine quality. No watermarks, no logos, no text, no captions, no signatures, no letters, no words anywhere in the image. Clean editorial photograph without any overlay text.
PROMPT

# ---------- CLI ----------
# Приоритет: CLI-аргументы > config.yaml > встроенные дефолты

options = {
  prompt:        DEFAULT_PROMPT,
  suffix:        '_photorealistic',
  ext:           'jpg',
  in_dir:        IN_DIR,
  out_dir:       OUT_DIR,
  config_path:   DEFAULT_CONFIG,
  unsloth_url:   'http://127.0.0.1:8888',
  unsloth_key:   nil,
  unsloth_model: 'unsloth/flux-3-image-klein-GGUF',
  unsloth_gguf:  'flux-3-image-klein-UD-Q4_K_XL.gguf',
  unsloth_steps: 4,
  unsloth_guidance: 1.0,
  unsloth_allow_oversized: true,
  unsloth_memory_mode: 'balanced'
}
set_by_cli = {}

OptionParser.new do |o|
  o.banner = "Usage: ruby #{File.basename($PROGRAM_NAME)} [options] [files...]"
  o.on('--config FILE',     'Файл настроек (по умолчанию ./config.yaml)')                  { |v| options[:config_path] = v; set_by_cli[:config_path] = true }
  o.on('--prompt TEXT',     'Промпт для генерации')                                       { |v| options[:prompt] = v;        set_by_cli[:prompt] = true }
  o.on('--suffix STR',      'Суффикс имени выходного файла (по умолчанию _photorealistic)') { |v| options[:suffix] = v;       set_by_cli[:suffix] = true }
  o.on('--ext EXT',         'Расширение имени выходного файла: jpg или png')               { |v| options[:ext] = v;           set_by_cli[:ext] = true }
  o.on('--in DIR',          'Входная папка (по умолчанию ./in)')                          { |v| options[:in_dir] = v;        set_by_cli[:in] = true }
  o.on('--out DIR',         'Выходная папка (по умолчанию ./out)')                        { |v| options[:out_dir] = v;       set_by_cli[:out] = true }
  o.on('--unsloth-key KEY', 'Ключ Unsloth Studio (или переменная UNSLOTH_API_KEY)')        { |v| options[:unsloth_key] = v;   set_by_cli[:unsloth_key] = true }
  o.on('--[no-]allow-oversized', 'Как тумблер UI "Allow oversized generations" (по умолчанию вкл)') { |v| options[:unsloth_allow_oversized] = v; set_by_cli[:unsloth_allow_oversized] = true }
  o.on('--memory-mode MODE', 'Политика памяти при загрузке: auto/fast/balanced/low_vram (по умолчанию balanced)') { |v| options[:unsloth_memory_mode] = v; set_by_cli[:unsloth_memory_mode] = true }
  o.on('-h', '--help')      { puts o; exit }
end.parse!

# ---------- Загрузка config.yaml ----------

config_path = options[:config_path]
if File.exist?(config_path)
  begin
    yaml = YAML.load_file(config_path) || {}
    if yaml.is_a?(Hash)
      options[:prompt]        = yaml['prompt']        if yaml['prompt']        && !set_by_cli[:prompt]
      options[:suffix]        = yaml['suffix']        if yaml['suffix']        && !set_by_cli[:suffix]
      options[:ext]           = yaml['ext']           if yaml['ext']           && !set_by_cli[:ext]
      options[:in_dir]        = File.expand_path(yaml['in'])  if yaml['in']  && !set_by_cli[:in]
      options[:out_dir]       = File.expand_path(yaml['out']) if yaml['out'] && !set_by_cli[:out]
      options[:unsloth_url]   = yaml['unsloth_url']   if yaml['unsloth_url']   && !set_by_cli[:unsloth_key]
      options[:unsloth_key]   = yaml['unsloth_key']   if yaml['unsloth_key']   && !set_by_cli[:unsloth_key]
      options[:unsloth_model] = yaml['unsloth_model'] if yaml['unsloth_model']
      options[:unsloth_gguf]  = yaml['unsloth_gguf']  if yaml['unsloth_gguf']
      options[:unsloth_steps] = yaml['unsloth_steps'].to_i if yaml['unsloth_steps']
      options[:unsloth_guidance] = yaml['unsloth_guidance'].to_f if yaml['unsloth_guidance']
      options[:unsloth_allow_oversized] = yaml['unsloth_allow_oversized'] if yaml.key?('unsloth_allow_oversized') && !set_by_cli[:unsloth_allow_oversized]
      options[:unsloth_memory_mode] = yaml['unsloth_memory_mode'] if yaml.key?('unsloth_memory_mode') && !set_by_cli[:unsloth_memory_mode]
    else
      warn "  ! #{config_path}: ожидался Hash на верхнем уровне, проигнорировано"
    end
  rescue Psych::SyntaxError, StandardError => e
    warn "  ! не удалось прочитать #{config_path}: #{e.message}"
  end
elsif config_path != DEFAULT_CONFIG
  warn "  ! конфиг не найден: #{config_path}"
end

# Разворачиваем ./in, ./out и т.п.
%i[in_dir out_dir].each do |k|
  v = options[k]
  options[k] = File.expand_path(v) unless v.start_with?('/') || v =~ /^[A-Z]:[\\\/]/i
end

# ---------- проверки ----------

options[:unsloth_key] = options[:unsloth_key] || ENV['UNSLOTH_API_KEY'] || ''
raise 'нет ключа Unsloth Studio (задай unsloth_key в config.yaml, UNSLOTH_API_KEY или --unsloth-key KEY)' if options[:unsloth_key].to_s.empty?

FileUtils.mkdir_p(options[:out_dir])

# ---------- файлы ----------

files =
  if ARGV.empty?
    Dir.glob(File.join(options[:in_dir], '*.{png,jpg,jpeg,webp,bmp,gif}'))
  else
    ARGV.map { |f| File.expand_path(f) }
  end

files.select! { |f| File.file?(f) }

if files.empty?
  warn "[#{APP_NAME}] Нет изображений."
  warn "  Положи файлы в #{options[:in_dir]}"
  warn "  или передай их аргументами: ruby #{File.basename($PROGRAM_NAME)} file1.png file2.jpg"
  exit 1
end

# ---------- хелперы ----------

# ---------- Unsloth Studio (локальный diffusers-движок) ----------
# flux-3-image-klein (Q4_K_XL GGUF) + reference workflow:
#   init_image + reference_images, steps 4, guidance 1.0 — полностью локально.

def sniff_mime(path)
  head = File.binread(path, 12)
  return 'image/png'  if head[0, 8] == "\x89PNG\r\n\x1A\n".b
  return 'image/jpeg' if head[0, 3] == "\xFF\xD8\xFF".b
  return 'image/gif'  if head[0, 3] == 'GIF'
  return 'image/webp' if head[8, 4] == 'WEBP'
  MIME_BY_EXT[File.extname(path).downcase] || 'application/octet-stream'
end

def image_dims(path, mime)
  case mime
  when 'image/png'
    d = File.binread(path, 33)
    return nil unless d[0, 8] == "\x89PNG\r\n\x1A\n".b
    [d[16, 4].unpack1('N'), d[20, 4].unpack1('N')]
  when 'image/jpeg'
    d = File.binread(path)
    i = 2
    while i < d.bytesize - 9
      return nil if d.getbyte(i) != 0xFF
      m = d.getbyte(i + 1)
      return nil if m == 0xD9 || m == 0xDA
      if m >= 0xC0 && m <= 0xCF && ![0xC4, 0xC8, 0xCC].include?(m)
        return [d[i + 7, 2].unpack1('n'), d[i + 5, 2].unpack1('n')]
      end
      i += 2 + d[i + 2, 2].unpack1('n')
    end
    nil
  end
end

def sketch_sizes(sketch_path)
  mime = sniff_mime(sketch_path)
  dims = mime ? image_dims(sketch_path, mime) : nil
  raise "не удалось определить размеры #{sketch_path} (формат не PNG/JPEG)" unless dims
  # точные размеры эскиза: кратно 16, в пределах API (256..2048).
  # Большая сторона ужимается до 2048, маленькая тянется вверх до 256 —
  # обе с сохранением пропорций (независимый clamp ломает аспект).
  w, h = dims.map(&:to_f)
  if [w, h].max > 2048
    s = 2048.0 / [w, h].max
    w, h = w * s, h * s
  end
  if [w, h].min < 256
    s = 256.0 / [w, h].min
    w, h = w * s, h * s
  end
  [w.round, h.round].map { |v| [[(v / 16.0).round * 16, 256].max, 2048].min }
end

def unsloth_api(url)
  http = Net::HTTP.new(URI(url).host, URI(url).port)
  http.open_timeout = 10
  http.read_timeout = 1800
  http
end

def unsloth_status(url, key)
  req = Net::HTTP::Get.new('/api/inference/images/status')
  req['Authorization'] = "Bearer #{key}"
  res = unsloth_api(url).request(req)
  unless res.is_a?(Net::HTTPSuccess)
    raise "Unsloth Studio: HTTP #{res.code} (проверь unsloth_key и что студия запущена на #{url})"
  end
  JSON.parse(res.body)
end

def unsloth_load_progress(url, key)
  req = Net::HTTP::Get.new('/api/inference/images/load-progress')
  req['Authorization'] = "Bearer #{key}"
  JSON.parse(unsloth_api(url).request(req).body)
end

def unsloth_ensure_loaded!(url, key, model_path, gguf_filename, memory_mode = nil)
  model_path = 'unsloth/flux-3-image-klein-GGUF'
  st = unsloth_status(url, key)
  # Только klein: тот же repo уже загружен — квант не важен (Q8_0/Q4 — та же модель).
  if st['loaded'] && st['repo_id'] == model_path
    return st if gguf_filename.to_s.empty? || st['gguf_filename'].to_s.empty? ||
                 st['gguf_filename'] == gguf_filename
    gguf_filename = st['gguf_filename']
    return st
  end

  puts "  - загружаю модель в студию (#{model_path}#{", memory_mode=#{memory_mode}" if memory_mode})..."
  body = { model_path: model_path }
  body[:memory_mode] = memory_mode if memory_mode && !memory_mode.to_s.empty?
  if gguf_filename
    body[:gguf_filename] = gguf_filename
    body[:model_kind] = 'gguf'
  end
  http = unsloth_api(url)
  req = Net::HTTP::Post.new('/api/inference/images/load')
  req['Content-Type'] = 'application/json'
  req['Authorization'] = "Bearer #{key}"
  req.body = JSON.generate(body)
  res = http.request(req)
  unless res.is_a?(Net::HTTPSuccess)
    raise "Unsloth Studio: загрузка не начата, HTTP #{res.code} #{res.body.to_s[0, 300]}"
  end

  last_printed = nil
  loop do
    sleep 5
    prog = unsloth_load_progress(url, key)
    raise "Unsloth Studio: ошибка загрузки модели — #{prog['error']}" if prog['error']
    if prog['phase'] == 'downloading' && prog['fraction'].to_f > 0
      pct = (prog['fraction'] * 100).round
      puts "  - скачивание весов: #{pct}% (#{(prog['bytes_downloaded'].to_f / 2**30).round(1)}/#{(prog['bytes_total'].to_f / 2**30).round(1)} GB)" if pct != last_printed
      last_printed = pct
    end
    st = unsloth_status(url, key)
    break if st['loaded'] && st['repo_id'] == model_path
  end
  st
end

def unsloth_generate(url, key, sketch_path, prompt:, width:, height:, steps:, guidance:, allow_oversized: true)
  mime = sniff_mime(sketch_path)
  data_url = "data:#{mime};base64,#{Base64.strict_encode64(File.binread(sketch_path))}"
  t0 = Time.now
  w, h = width, height

  loop do
    body = {
      prompt:           prompt.to_s,
      width:            w,
      height:           h,
      steps:            steps,
      guidance:         guidance,
      allow_oversized:  allow_oversized,
      init_image:       data_url,
      reference_images: [data_url],
      strength:         1.0
    }

    http = unsloth_api(url)
    req = Net::HTTP::Post.new('/api/inference/images/generate')
    req['Content-Type'] = 'application/json'
    req['Authorization'] = "Bearer #{key}"
    req.body = JSON.generate(body)
    res = http.request(req)
    unless res.is_a?(Net::HTTPSuccess)
      msg = res.body.to_s
      if res.code == '400' && msg =~ /needs about ([\d.]+) GB.*only about ([\d.]+) GB is usable/m
        need, usable = $1.to_f, $2.to_f
        scale = Math.sqrt(usable / need) * 0.97
        nw = [[((w * scale) / 16.0).floor * 16, 256].max, 2048].min
        nh = [[((h * scale) / 16.0).floor * 16, 256].max, 2048].min
        raise "не удаётся подобрать разрешение под VRAM (эскиз #{width}x#{height})" if [nw, nh] == [w, h]
        puts "  ! нужно #{need}GB, доступно #{usable}GB — повтор на #{nw}x#{nh}"
        w, h = nw, nh
        next
      end
      raise "unsloth: HTTP #{res.code} #{msg[0, 300]}"
    end
    j = JSON.parse(res.body)
    img = (j['images'] || []).first
    raise "unsloth не вернул изображение: #{j.inspect[0, 300]}" unless img

    file_path = img['url'].to_s
    file_path = url + file_path unless file_path.start_with?('http')
    dl = Net::HTTP::Get.new(URI(file_path).request_uri)
    dl['Authorization'] = "Bearer #{key}"
    file_res = unsloth_api(url).request(dl)
    unless file_res.is_a?(Net::HTTPSuccess)
      raise "unsloth: скачивание результата не удалось (HTTP #{file_res.code})"
    end
    note = (w != width || h != height) ? "  (эскиз #{width}x#{height} не влез в VRAM, уменьшено)" : ''
    puts "  - сгенерировано за #{(Time.now - t0).round(1)}s (workflow=#{img['workflow']}, #{w}x#{h})#{note}"
    return file_res.body
  end
end


# ---------- main ----------

if __FILE__ == $PROGRAM_NAME
st = unsloth_ensure_loaded!(options[:unsloth_url], options[:unsloth_key],
                            options[:unsloth_model],
                            options[:unsloth_gguf].to_s.empty? ? nil : options[:unsloth_gguf],
                            options[:unsloth_memory_mode])

puts "[#{APP_NAME}] старт"
puts "  studio: #{options[:unsloth_url]}  model: #{st['repo_id']} (#{st['gguf_variant'] || st['dtype']}, workflows=#{st['workflows'].join(',')})"
puts "  in:  #{options[:in_dir]}"
puts "  out: #{options[:out_dir]}"
puts "  files=#{files.size}"
puts "  oversized=#{options[:unsloth_allow_oversized]} memory_mode=#{options[:unsloth_memory_mode]}"

ok = 0
files.each_with_index do |path, i|
  basename = File.basename(path, '.*')
  stamp = Time.now.strftime('%Y%m%d_%H%M%S')
  out_name = "#{basename}#{options[:suffix]}_#{stamp}.#{options[:ext]}"
  out_path = File.join(options[:out_dir], out_name)
  puts "[#{i + 1}/#{files.size}] #{File.basename(path)} -> #{out_name}"

  begin
    w, h = sketch_sizes(path)
    puts "  - генерирую (#{w}x#{h})..."
    img = unsloth_generate(options[:unsloth_url], options[:unsloth_key], path,
                           prompt:    options[:prompt],
                           width:     w,
                           height:    h,
                           steps:     options[:unsloth_steps],
                           guidance:  options[:unsloth_guidance],
                           allow_oversized: options[:unsloth_allow_oversized])
    File.binwrite(out_path, img)
    size = File.size(out_path)
    puts "  - готово: #{out_path} (#{(size / 1024.0).round(1)} KB)"
    ok += 1
  rescue StandardError => e
    warn "  ! ошибка на #{File.basename(path)}: #{e.message}"
  end
end

puts "[#{APP_NAME}] завершено. успешно: #{ok}/#{files.size}"
exit(ok == files.size ? 0 : 2)
end # __FILE__ == $PROGRAM_NAME
