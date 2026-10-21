# frozen_string_literal: true
# Тест моделей Unsloth Studio на эскизах из in/ (или конкретном файле).
# Запуск: ruby test_models.rb [файл...]
# Результаты: out/modeltest/

require 'yaml'
require 'json'
require 'net/http'
require 'uri'
require 'base64'
require 'fileutils'
require 'time'

CFG        = YAML.load_file('./config.yaml')
KEY        = ENV['UNSLOTH_API_KEY'] || CFG['unsloth_key']
URL        = CFG['unsloth_url'] || 'http://127.0.0.1:8888'
PROMPT     = CFG['prompt']
SKETCHES   = ARGV.empty? ? Dir.glob(File.join('in', '*.{png,jpg,jpeg,webp,bmp,gif}')) : ARGV
OUT_DIR    = File.expand_path('./out/modeltest')

SEED = 7
MODEL_ID = 'unsloth/flux-3-image-klein-GGUF'
GGUF_FILE = 'flux-3-image-klein-UD-Q4_K_XL.gguf'
MEMORY_MODE = CFG['unsloth_memory_mode'] || 'balanced'
ALLOW_OVERSIZED = CFG.fetch('unsloth_allow_oversized', true)
MODELS = [
  { label: 'k3_s4_str100', steps: 4, guidance: 1.0, strength: 1.00 },
  { label: 'k3_s4_str75',  steps: 4, guidance: 1.0, strength: 0.75 },
  { label: 'k3_s6_str100', steps: 6, guidance: 1.0, strength: 1.00 },
  { label: 'k3_s6_str75',  steps: 6, guidance: 1.0, strength: 0.75 },
  { label: 'k3_s8_str100', steps: 8, guidance: 1.0, strength: 1.00 },
  { label: 'k3_s8_str75',  steps: 8, guidance: 1.0, strength: 0.75 }
].map { |m| m.merge(model: MODEL_ID, gguf: GGUF_FILE) }.freeze

def api
  uri = URI(URL)
  http = Net::HTTP.new(uri.host, uri.port)
  http.open_timeout = 10
  http.read_timeout = 1800
  http
end

def get(path)
  req = Net::HTTP::Get.new(path)
  req['Authorization'] = "Bearer #{KEY}"
  res = api.request(req)
  raise "HTTP #{res.code} на #{path}" unless res.is_a?(Net::HTTPSuccess)
  JSON.parse(res.body)
end

def post(path, body)
  req = Net::HTTP::Post.new(path)
  req['Content-Type'] = 'application/json'
  req['Authorization'] = "Bearer #{KEY}"
  req.body = JSON.generate(body)
  res = api.request(req)
  raise "HTTP #{res.code} на #{path}: #{res.body.to_s[0, 300]}" unless res.is_a?(Net::HTTPSuccess)
  JSON.parse(res.body)
end

def status       = get('/api/inference/images/status')
def load_progress = get('/api/inference/images/load-progress')

def ensure_loaded!(model, gguf)
  st = status
  if st['loaded'] && st['repo_id'] == model && (gguf.nil? || st['gguf_filename'] == gguf)
    puts '    модель уже загружена'
    return
  end
  body = { model_path: model }
  if gguf
    body[:gguf_filename] = gguf
    body[:model_kind] = 'gguf'
  end
  body[:memory_mode] = MEMORY_MODE if MEMORY_MODE && !MEMORY_MODE.to_s.empty?
  post('/api/inference/images/load', body)
  t0 = Time.now
  last = nil
  loop do
    sleep 3
    prog = load_progress
    raise "ошибка загрузки: #{prog['error']}" if prog['error']
    if prog['phase'] == 'downloading' && prog['fraction'].to_f > 0
      pct = (prog['fraction'] * 100).round
      puts "    скачивание: #{pct}%" if pct != last
      last = pct
    end
    break if status['loaded'] && status['repo_id'] == model
    raise "таймаут загрузки (>60 мин)" if Time.now - t0 > 3600
  end
  puts "    загрузка: #{(Time.now - t0).round(1)}s"
end

def sniff_mime(path)
  head = File.binread(path, 12)
  return 'image/png'  if head[0, 8] == "\x89PNG\r\n\x1A\n".b
  return 'image/jpeg' if head[0, 3] == "\xFF\xD8\xFF".b
  return 'image/gif'  if head[0, 3] == 'GIF'
  return 'image/webp' if head[8, 4] == 'WEBP'
  nil
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

def dims_for(path)
  mime = sniff_mime(path)
  image_dims(path, mime) if mime
end

def sizes_for(path)
  w, h = dims_for(path)
  raise 'не PNG/JPEG или нет размеров' unless w && h
  # точные размеры эскиза: кратно 16, в пределах API (256..2048).
  # Большая сторона ужимается до 2048, маленькая тянется вверх до 256 —
  # обе с сохранением пропорций (независимый clamp ломает аспект).
  w, h = [w, h].map(&:to_f)
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

def generate!(data_url, w, h, cfg)
  loop do
    body = {
      prompt:           PROMPT, width: w, height: h,
      steps:            cfg[:steps], guidance: cfg[:guidance],
      allow_oversized:  ALLOW_OVERSIZED,
      init_image:       data_url,
      reference_images: [data_url],
      strength:         cfg.fetch(:strength, 1.0),
      seed:             SEED
    }
    req = Net::HTTP::Post.new('/api/inference/images/generate')
    req['Content-Type'] = 'application/json'
    req['Authorization'] = "Bearer #{KEY}"
    req.body = JSON.generate(body)
    res = api.request(req)
    unless res.is_a?(Net::HTTPSuccess)
      msg = res.body.to_s
      if res.code == '400' && msg =~ /needs about ([\d.]+) GB.*only about ([\d.]+) GB is usable/m
        need, usable = $1.to_f, $2.to_f
        scale = Math.sqrt(usable / need) * 0.97
        nw = [[((w * scale) / 16.0).floor * 16, 256].max, 2048].min
        nh = [[((h * scale) / 16.0).floor * 16, 256].max, 2048].min
        raise 'не удаётся подобрать разрешение под VRAM' if [nw, nh] == [w, h]
        warn "    ! нужно #{need}GB, доступно #{usable}GB — повтор на #{nw}x#{nh}"
        w, h = nw, nh
        next
      end
      raise "HTTP #{res.code} на /api/inference/images/generate: #{msg[0, 300]}"
    end
    j = JSON.parse(res.body)
    img = (j['images'] || []).first
    raise "нет изображения в ответе: #{j.inspect[0, 300]}" unless img
    file_url = img['url'].to_s
    file_url = URL + file_url unless file_url.start_with?('http')
    dl = Net::HTTP::Get.new(URI(file_url).request_uri)
    dl['Authorization'] = "Bearer #{KEY}"
    dres = api.request(dl)
    raise "скачивание не удалось: HTTP #{dres.code}" unless dres.is_a?(Net::HTTPSuccess)
    return [dres.body, img, w, h]
  end
end

# ---------- main ----------

FileUtils.mkdir_p(OUT_DIR)
raise 'нет эскизов в in/ (или передай файлы аргументами)' if SKETCHES.empty?
sketches = SKETCHES.select { |f| File.file?(f) }
raise 'ни один из указанных файлов не найден' if sketches.empty?

results = []
sketches.each do |sketch|
  w, h = sizes_for(sketch)
  mime = sniff_mime(sketch) || 'image/png'
  data_url = "data:#{mime};base64,#{Base64.strict_encode64(File.binread(sketch))}"
  base = File.basename(sketch, '.*').gsub(/[^\p{L}\p{N}\-]+/u, '_')

  puts "\n=== эскиз: #{sketch} (#{w}x#{h}) ==="

  MODELS.each_with_index do |m, i|
    puts "\n[#{i + 1}/#{MODELS.size}] #{m[:label]}  (#{m[:model]}, steps=#{m[:steps]})"
    begin
      t_load = Time.now
      ensure_loaded!(m[:model], m[:gguf])
      load_s = Time.now - t_load

      t_gen = Time.now
      img_bytes, meta, gw, gh = generate!(data_url, w, h, m)
      gen_s = Time.now - t_gen

      stamp = Time.now.strftime('%Y%m%d_%H%M%S')
      out_path = File.join(OUT_DIR, "#{base}__#{m[:label]}__#{stamp}.png")
      File.binwrite(out_path, img_bytes)
      note = (gw != w || gh != h) ? "  (эскиз #{w}x#{h} не влез в VRAM, уменьшено)" : ''
      puts "    готово за #{gen_s.round(1)}s (workflow=#{meta['workflow']}, #{gw}x#{gh}, #{(img_bytes.bytesize / 1024.0).round(1)} KB)#{note}"
      results << { label: m[:label], sketch: File.basename(sketch), ok: true, load: load_s, gen: gen_s,
                   steps: m[:steps], strength: m[:strength], workflow: meta['workflow'], file: out_path }
    rescue StandardError => e
      warn "    ! ОШИБКА: #{e.message}"
      results << { label: m[:label], sketch: File.basename(sketch), ok: false, error: e.message }
    end
  end
end

puts "\n[modeltest] сводка"
results.each do |r|
  if r[:ok]
    puts "  #{r[:sketch]}  #{r[:label]}  ok   load=#{r[:load].round(1)}s  gen=#{r[:gen].round(1)}s  workflow=#{r[:workflow]}"
  else
    puts "  #{r[:sketch]}  #{r[:label]}  FAIL #{r[:error][0, 80]}"
  end
end
exit(results.all? { |r| r[:ok] } ? 0 : 2)
