#!/usr/bin/env ruby
# frozen_string_literal: true

# tools/pack.rb — сборка .rbz из рабочей копии (как в comp_add_view).
#   ruby tools/pack.rb
# Результат: dist/dn1sup_su2vis-<version>.rbz

require 'fileutils'
require 'tmpdir'
require 'zlib'

CONFIG = {
  id:         'dn1sup_su2vis',
  loader:     'dn1sup_su2vis.rb',
  dir:        'dn1sup_su2vis',
  target_dir: 'dn1sup_su2vis'
}.freeze

EXCLUDE_FILES = %w[
  dev_updater.rb README.md README.MD
  .gitignore package.json package-lock.json CHANGELOG.md NOTES.md
].map(&:downcase).freeze

EXCLUDE_DIRS = %w[
  test tests archive dist frontend node_modules .git .zcode _old _tmp
  in out
].map(&:downcase).freeze

def dos_parts(t)
  [(t.year - 1980) << 9 | t.month << 5 | t.day, t.hour << 11 | t.min << 5 | t.sec / 2]
end

def write_zip(path, entries)
  date, time = dos_parts(Time.now)
  body = +''.b
  central = +''.b
  entries.each do |name, data|
    name_b = name.dup.force_encoding(Encoding::BINARY)
    data_b = data.b
    offset = body.bytesize
    crc = Zlib.crc32(data_b)
    body << [0x04034b50, 20, 0, 0, time, date, crc, data_b.bytesize, data_b.bytesize,
             name_b.bytesize, 0].pack('VvvvvvVVVvv') << name_b << data_b
    central << [0x02014b50, 20, 20, 0, 0, time, date, crc, data_b.bytesize, data_b.bytesize,
                name_b.bytesize, 0, 0, 0, 0, 0, offset].pack('VvvvvvvVVVvvvvvVV') << name_b
  end
  eocd = [0x06054b50, 0, 0, entries.size, entries.size, central.bytesize,
          body.bytesize, 0].pack('VvvvvVVv')
  File.binwrite(path, body << central << eocd)
end

root = File.expand_path('..', __dir__)
cfg = CONFIG
src_loader = File.join(root, cfg[:loader])
src_dir    = File.join(root, cfg[:dir])

raise "Нет loader-файла #{src_loader}" unless File.file?(src_loader)
raise "Нет директории #{src_dir}" unless File.directory?(src_dir)

version = nil
content = File.read(src_loader)
version = $1 if content =~ /(?:extension|ext)\.version\s*=\s*['"]([^'"]+)['"]/i
if version.nil?
  main_rb = File.join(src_dir, 'main.rb')
  version = $1 if File.file?(main_rb) && File.read(main_rb) =~ /VERSION\s*=\s*['"]([^'"]+)['"]/
end
raise 'Не удалось определить версию расширения' unless version

require 'json'
registry_path = File.join(root, 'registry.json')
registry_data = nil
if File.file?(registry_path)
  registry_data = begin
    JSON.parse(File.read(registry_path))
  rescue StandardError
    nil
  end
  if registry_data.is_a?(Array)
    registry_data.each do |e|
      e['version'] = version if e.is_a?(Hash) && e['id'].to_s == cfg[:id].to_s
    end
    File.write(registry_path, JSON.pretty_generate(registry_data) + "\n")
    puts "registry.json: version -> #{version}"
  end
end

Dir.mktmpdir do |tmp|
  stage = File.join(tmp, 'stage')
  FileUtils.mkdir_p(stage)

  loader_text = File.read(src_loader)
  File.write(File.join(stage, "#{cfg[:id]}.rb"), loader_text)

  dest = File.join(stage, cfg[:target_dir])
  FileUtils.mkdir_p(dest)
  entries = []

  copy_dir = lambda do |src, dst, rel|
    Dir.each_child(src) do |name|
      child = File.join(src, name)
      rel_name = rel.empty? ? name : File.join(rel, name)
      base = name.downcase
      next if File.directory?(child) && EXCLUDE_DIRS.include?(base)
      next if File.file?(child) && EXCLUDE_FILES.include?(base)
      if File.directory?(child)
        copy_dir.call(child, File.join(dst, name), rel_name)
      else
        FileUtils.mkdir_p(dst)
        FileUtils.cp(child, dst)
        entries << [File.join(cfg[:target_dir], rel_name).tr('\\', '/'), File.binread(child)]
      end
    end
  end
  copy_dir.call(src_dir, dest, '')

  entries << ["#{cfg[:id]}.rb", loader_text.b]

  if registry_data.is_a?(Array)
    FileUtils.cp(registry_path, File.join(dest, 'registry.json'))
    entries << [File.join(cfg[:target_dir], 'registry.json').tr('\\', '/'),
                File.binread(File.join(dest, 'registry.json'))]
  end

  out_dir = File.join(root, 'dist')
  FileUtils.mkdir_p(out_dir)
  out = File.join(out_dir, "#{cfg[:id]}-#{version}.rbz")
  FileUtils.rm_f(out)
  write_zip(out, entries.sort_by(&:first))
  puts "Собран #{out} (v#{version}, файлов: #{entries.size})"
end
