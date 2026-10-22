# frozen_string_literal: true
# Тесты «DN1Sup SU2Vis». Запуск: внутри SketchUp через ext_test;
# локально — ruby dn1sup_su2vis/test/su2vis_test.rb (модельные уйдут в skip).
#
# Тесты не пишут настройки пользователя (Settings.save не вызывается),
# не открывают диалогов и не ходят в сеть.

require_relative 'test_helper'
require 'tmpdir'

module Dn1sup
  module Su2vis
    module Test
      test 'версия расширения задана' do
        assert(/\A\d+\.\d+\.\d+\z/.match?(VERSION), "неожидаемый формат версии: #{VERSION.inspect}")
      end

      test 'версия регистратора совпадает с VERSION' do
        registrar = File.expand_path("../../#{ID}.rb", __dir__)
        skip('регистратор не найден рядом с папкой расширения') unless File.file?(registrar)

        ver = File.read(registrar, encoding: 'UTF-8')[/\.version\s*=\s*['"]([^'"]+)['"]/, 1]
        assert_equal(VERSION, ver, 'версия в регистраторе')
      end

      test 'модули отвечают на API' do
        assert(Settings.respond_to?(:all), 'нет Settings.all')
        assert(Settings.respond_to?(:project_info), 'нет Settings.project_info')
        assert(Settings.respond_to?(:project_state), 'нет Settings.project_state')
        assert(Settings.respond_to?(:project_dir_for), 'нет Settings.project_dir_for')
        assert(Settings.respond_to?(:init_project), 'нет Settings.init_project')
        assert(Client.respond_to?(:generate), 'нет Client.generate')
        assert(Client.respond_to?(:enhance_preview), 'нет Client.enhance_preview')
        assert(Client.respond_to?(:fit_size), 'нет Client.fit_size')
        assert(Client.respond_to?(:gen_progress), 'нет Client.gen_progress')
        assert(Client.respond_to?(:gen_cancel), 'нет Client.gen_cancel')
        assert(Scenes.respond_to?(:list), 'нет Scenes.list')
        assert(Scenes.respond_to?(:settle_view), 'нет Scenes.settle_view')
        assert(Scenes.respond_to?(:capture_all), 'нет Scenes.capture_all')
        assert(Scenes.respond_to?(:update_camera), 'нет Scenes.update_camera')
        assert(Jobs.respond_to?(:enqueue), 'нет Jobs.enqueue')
        assert(Jobs.respond_to?(:cancel), 'нет Jobs.cancel')
        assert(Gallery.respond_to?(:list), 'нет Gallery.list')
        assert(Gallery.respond_to?(:remove), 'нет Gallery.remove')
        assert(Gallery.respond_to?(:save_preview), 'нет Gallery.save_preview')
        assert(Mixins.respond_to?(:list), 'нет Mixins.list')
        assert(Mixins.respond_to?(:add_data), 'нет Mixins.add_data')
        assert(Mixins.respond_to?(:add_path), 'нет Mixins.add_path')
        assert(Mixins.respond_to?(:update), 'нет Mixins.update')
        assert(Mixins.respond_to?(:remove), 'нет Mixins.remove')
        assert(Client.respond_to?(:mixins_prompt), 'нет Client.mixins_prompt')
        assert(Panel.respond_to?(:show), 'нет Panel.show')
        assert(Panel.respond_to?(:parse_payload), 'нет Panel.parse_payload')
      end

      test 'проект: только ключ глобальный, остальное per-file' do
        assert_equal(%w[unsloth_key], Settings::GLOBAL_KEYS)
        assert(!Settings::PROJECT_KEYS.include?('unsloth_key'), 'ключ не должен лежать в файле проекта')
        assert(Settings::PROJECT_KEYS.include?('prompt'), 'промпт должен быть per-file')
        assert_equal((Settings::DEFAULTS.keys - %w[unsloth_key]).sort, Settings::PROJECT_KEYS.sort)
      end

      test 'проект: папка su2vis/ рядом с моделью' do
        assert(Settings.project_dir_for('').nil?, 'пустой путь — nil')
        assert(Settings.project_dir_for(nil).nil?, 'nil — nil')
        d = Settings.project_dir_for('D:/work/house.skp')
        assert(d.to_s.end_with?('su2vis'), "папка проекта: #{d.inspect}")
        assert_equal(File.dirname('D:/work/house.skp'), File.dirname(d.to_s))
      end

      test 'проект: init/load roundtrip во временной папке (без записи defaults)' do
        Dir.mktmpdir do |d|
          proj = File.join(d, 'su2vis')
          assert_equal('missing', Settings.project_state(proj), 'до init — missing')
          begin
            Settings.init_project(nil)
            assert(false, 'init без модели должен бросить исключение')
          rescue StandardError => e
            assert(e.message.include?('не сохранена'), "не то исключение: #{e.message}")
          end
          all = Settings.init_project(proj)
          assert_equal('ready', all['project_state'], 'после init — ready')
          assert(File.file?(File.join(proj, 'su2vis.json')), 'файл проекта не записан')
          assert(File.directory?(File.join(proj, 'out')), 'out не создан')
          doc = JSON.parse(File.read(File.join(proj, 'su2vis.json'), encoding: 'UTF-8'))
          assert(!doc.key?('unsloth_key'), 'ключ не должен лежать в файле проекта')
          assert(doc.key?('prompt'), 'промпт должен быть в файле проекта')
          # save в готовый проект пишет только файл, ключ/global не трогаем:
          # в hash нет глобальных ключей и out_dir — defaults не пишутся.
          Settings.save({ 'prompt' => 'тест-промпт', 'bogus_key' => 1 }, proj)
          doc2 = JSON.parse(File.read(File.join(proj, 'su2vis.json'), encoding: 'UTF-8'))
          assert_equal('тест-промпт', doc2['prompt'], 'save не записал в файл проекта')
          assert(!doc2.key?('bogus_key'), 'мусорный ключ попал в файл')
          back = Settings.all(proj)
          assert_equal('тест-промпт', back['prompt'], 'all не читает файл проекта')
          assert_equal(File.join(proj, 'out'), back['out_dir'], 'out_dir не из проекта')
        end
      end

      test 'проект: delete_project сносит su2vis/ и сбрасывает настройки' do
        Dir.mktmpdir do |d|
          proj = File.join(d, 'su2vis')
          Settings.init_project(proj)
          Settings.save({ 'prompt' => 'мусор' }, proj)
          assert_equal('мусор', Settings.all(proj)['prompt'], 'затравка не записалась')
          back = Settings.delete_project(proj)
          assert(!File.exist?(proj), 'папка проекта осталась')
          assert_equal('missing', back['project_state'], 'состояние должно стать missing')
          assert(back['prompt'] != 'мусор', 'настройки не сброшены')
          begin
            Settings.delete_project(File.join(d, 'other'))
            assert(false, 'чужую папку должны отклонить')
          rescue StandardError => e
            assert(e.message.include?('не папка проекта'), "не тот отказ: #{e.message}")
          end
          begin
            Settings.delete_project(nil)
            assert(false, 'без модели должны отклонить')
          rescue StandardError => e
            assert(e.message.include?('не сохранена'), "не тот отказ: #{e.message}")
          end
        end
      end

      test 'проект: save без проекта не создаёт папку' do        Dir.mktmpdir do |d|
          proj = File.join(d, 'su2vis')
          # только неизвестный ключ: ни файл, ни defaults не пишутся.
          back = Settings.save({ 'bogus_key' => 1 }, proj)
          assert(!File.exist?(proj), 'папка проекта создалась без спроса')
          assert_equal('missing', back['project_state'], 'состояние должно остаться missing')
        end
      end

      test 'настройки читаются без записи (read-only)' do
        h = Settings.all
        %w[prompt seed sketch_preset preview_preset preview_variants final_mode final_w final_h final_upscale final_strength workflow enhance_prompt name_template strength steps unsloth_url version].each do |k|
          assert(h.key?(k), "нет ключа #{k}")
        end
        assert_equal(VERSION, h['version'])
        assert(Settings.parse_size('1024x768') == [1024, 768], 'parse_size 4:3')
        assert(Settings.parse_size('мусор').nil?, 'parse_size мусора — nil')
      end

      test 'api_min_size: ниже 256 поднимает с пропорциями' do
        assert_equal([256, 256], Client.api_min_size(128, 128), 'квадрат 128')
        w, h = Client.api_min_size(224, 128)
        assert(h == 256, "короткая сторона должна стать 256, получили #{[w, h].inspect}")
        assert((w.to_f / h - 224.0 / 128).abs < 0.05, "пропорции поплыли: #{[w, h].inspect}")
        assert([w, h].all? { |v| (v % 16).zero? }, 'кратно 16')
        assert_equal([448, 256], Client.api_min_size(448, 256), 'легальный размер не трогаем')
        w2, h2 = Client.api_min_size(*Client.fit_size(1920, 1080, 128))
        assert(w2 >= 256 && h2 >= 256, "превью 128 должно стать легальным: #{[w2, h2].inspect}")
      end

      test 'fit_size: превью уменьшает, финал держит размер, минимум 128' do
        assert_equal([768, 432], Client.fit_size(1920, 1080, 768), 'превью 768')
        w, h = Client.fit_size(1920, 1080, 0)
        assert(w == 1920 && (h - 1080).abs <= 8, "финал должен держать размер эскиза, получили #{[w, h].inspect}")
        assert_equal([128, 128], Client.fit_size(100, 100, nil), 'минимум 128')
        assert_equal([2048, 2048], Client.fit_size(4096, 4096, 0), 'максимум 2048')
        assert(Client.fit_size(1920, 1080, 768).all? { |v| (v % 16).zero? }, 'кратно 16')
      end

      test 'fit_size: превью 128 по длинной стороне' do
        w, h = Client.fit_size(1920, 1080, 128)
        assert(h == 128 || w == 128, "короткая/длинная должна стать 128, получили #{[w, h].inspect}")
        assert([w, h].all? { |v| (v % 16).zero? }, 'кратно 16')
      end

      test 'fit_size: короткая сторона не ломает пропорции в квадрат' do
        w, h = Client.fit_size(2624, 1844, 128)
        assert(h == 128, "короткая сторона должна стать 128, получили #{[w, h].inspect}")
        assert((w.to_f / h - 2624.0 / 1844).abs < 0.05, "пропорции поплыли: #{[w, h].inspect}")
        assert([w, h].all? { |v| (v % 16).zero? }, 'кратно 16')
      end

      test 'fit_size: большая сторона ужимается до 2048 с пропорциями' do
        w, h = Client.fit_size(2624, 1844)
        assert(w == 2048, "длинная сторона должна стать 2048, получили #{[w, h].inspect}")
        assert((w.to_f / h - 2624.0 / 1844).abs < 0.05, "пропорции поплыли: #{[w, h].inspect}")
      end

      test 'sniff_mime различает PNG и JPEG по содержимому' do
        Dir.mktmpdir do |d|
          png = File.join(d, 'a.bin')
          File.binwrite(png, "\x89PNG\r\n\x1A\n".b + "\x00" * 16)
          assert_equal('image/png', Client.sniff_mime(png))

          jpg = File.join(d, 'b.bin')
          File.binwrite(jpg, "\xFF\xD8\xFF\xE0".b + "\x00" * 16)
          assert_equal('image/jpeg', Client.sniff_mime(jpg))
        end
      end

      test 'иконка тулбара resources/panel.svg на месте' do
        path = File.join(__dir__, '..', 'resources', 'panel.svg')
        assert(File.file?(path), "нет иконки #{path}")
        content = File.read(path, encoding: 'UTF-8')
        assert(content.include?('<svg'), 'panel.svg без корня <svg>')
        assert(content.include?('viewBox'), 'panel.svg без viewBox')
      end

      test 'frontend: в script setup нет голых $props/$emit (ломает ввод)' do
        src = File.expand_path('../../frontend/src', __dir__)
        skip('нет исходников frontend') unless File.directory?(src)
        bad = []
        Dir.glob(File.join(src, '**', '*.vue')).each do |f|
          content = File.read(f, encoding: 'UTF-8')
          script = content[/<script setup>(.*?)<\/script>/m, 1] || ''
          bad << File.basename(f) if script =~ /\$props/ || script =~ /\$emit/
        end
        assert(bad.empty?, "голые $props/$emit в script setup (ввод молча падает): #{bad.inspect}")
      end

      test 'панель: payload разбирается из JSON-строки' do
        assert_equal({ 'a' => 1 }, Panel.parse_payload('{"a":1}'))
        assert_equal({}, Panel.parse_payload('битая { json'))
        assert_equal({}, Panel.parse_payload(nil))
        assert_equal({ 'kind' => 'preview' }, Panel.parse_payload('kind' => 'preview'))
      end

      test 'final_view: чужой и несуществующий путь отклоняются' do
        assert(Panel.respond_to?(:result_data_url), 'нет Panel.result_data_url')
        begin
          Panel.result_data_url(File.join(Settings.out_dir, '..', 'secret.txt'))
          assert(false, 'выход за out_dir должны отклонить')
        rescue StandardError => e
          assert(e.message.include?('вне папки') || e.message.include?('не найден'), "не тот отказ: #{e.message}")
        end
        begin
          Panel.result_data_url(File.join(Settings.out_dir, 'no-such-file-12345.jpg'))
          assert(false, 'несуществующий файл должны отклонить')
        rescue StandardError
          assert(true)
        end
      end

      test 'панель: resources/panel.html собран из Vue (4 колонки)' do
        html = File.join(__dir__, '..', 'resources', 'panel.html')
        assert(File.file?(html), "нет собранной панели #{html}")
        content = File.read(html, encoding: 'UTF-8')
        assert(content.include?('id="app"'), 'panel.html без корня Vue (#app)')
        assert(content.include?('jobs_start'), 'panel.html без моста jobs_start — устаревшая сборка')
        assert(content.include?('jobs_cancel'), 'panel.html без кнопки Стоп — устаревшая сборка')
        assert(content.include?('jobs_log'), 'panel.html без журнала — устаревшая сборка')
        assert(content.include?('gen_progress'), 'panel.html без живого прогресса — устаревшая сборка')
        assert(content.include?('scenes_capture'), 'panel.html без съёма эскизов — устаревшая сборка')
        assert(content.include?('Журнал'), 'panel.html без вкладки журнала — устаревшая сборка')
        assert(content.include?('апсемплер'), 'panel.html без тумблера enhance — устаревшая сборка')
        assert(content.include?('scenes_sync_view'), 'panel.html без синхронизации вида — устаревшая сборка')
        assert(content.include?('В финал'), 'panel.html без кнопки финала — устаревшая сборка')
        assert(content.include?('Финальный размер'), 'panel.html без настроек финала — устаревшая сборка')
        assert(content.include?('Вариантов'), 'panel.html без выбора числа вариантов — устаревшая сборка')
        assert(content.include?('final_view'), 'panel.html без просмотра финала — устаревшая сборка')
        assert(content.include?('enhance_preview'), 'panel.html без предпросмотра enhance — устаревшая сборка')
        assert(content.include?('Предпросмотр Enhance'), 'panel.html без блока предпросмотра — устаревшая сборка')
        assert(content.include?('select_out_dir'), 'panel.html без выбора папки — устаревшая сборка')
        assert(content.include?('project_init'), 'panel.html без создания su2vis/ — устаревшая сборка')
        assert(content.include?('Проверить снова'), 'panel.html без перепроверки проекта — устаревшая сборка')
        assert(content.include?('Aspect ratio'), 'panel.html без выбора аспекта — устаревшая сборка')
        assert(content.include?('Resolution'), 'panel.html без выбора разрешения — устаревшая сборка')
        assert(content.include?('Batch size'), 'panel.html без batch size — устаревшая сборка')
        assert(content.include?('Random if empty'), 'panel.html без seed-плейсхолдера — устаревшая сборка')
        assert(content.include?('Advanced'), 'panel.html без секции Advanced — устаревшая сборка')
        assert(content.include?('project_delete'), 'panel.html без удаления su2vis/ — устаревшая сборка')
        assert(content.include?('Повторить'), 'panel.html без повтора загрузки картинки — устаревшая сборка')
        assert(content.include?('load_error'), 'panel.html без видимой ошибки загрузки — устаревшая сборка')
        assert(content.include?('Папка для рендеров'), 'panel.html без поля папки — устаревшая сборка')
        assert(content.include?('Выбрать…'), 'panel.html без кнопки выбора папки — устаревшая сборка')
        assert(content.include?('загружаю…'), 'panel.html без тумб финала — устаревшая сборка')
        assert(content.include?('overflow-y-auto'), 'panel.html без прокрутки контента — устаревшая сборка')
        assert(content.include?('flex-col'), 'panel.html без колоночной раскладки — устаревшая сборка')
        assert(content.include?('scroll-slim'), 'panel.html без скрытых скроллбаров — устаревшая сборка')
        assert(content.include?('preview_save'), 'panel.html без сохранения превью для финала — устаревшая сборка')
        assert(content.include?('Доработка финала') || content.include?('final_strength'), 'panel.html без силы финала — устаревшая сборка')
        assert(content.include?('select-preview'), 'panel.html без выбора превью — устаревшая сборка')
        assert(content.include?('gallery_list'), 'panel.html без чтения галереи — устаревшая сборка')
        assert(content.include?('gallery_delete'), 'panel.html без удаления файлов — устаревшая сборка')
        assert(content.include?('mixins_list'), 'panel.html без списка примесей — устаревшая сборка')
        assert(content.include?('mixins_add_data'), 'panel.html без добавления примесей — устаревшая сборка')
        assert(content.include?('mixins_update'), 'panel.html без подписей примесей — устаревшая сборка')
        assert(content.include?('Примеси'), 'panel.html без колонки примесей — устаревшая сборка')
        assert(content.include?('Удалить файл'), 'panel.html без иконки удаления — устаревшая сборка')
        assert(content.include?('Выделить / повернуть'), 'panel.html без редактора выделения — устаревшая сборка')
        assert(content.include?('Только выделение'), 'panel.html без тумблера выделения — устаревшая сборка')
        assert(content.include?('toggle-enabled'), 'panel.html без выключателей колонок — устаревшая сборка')
        assert(content.include?('только по промпту'), 'panel.html без режима только-промпт — устаревшая сборка')
        assert(content.include?('Показать оригинал'), 'panel.html без просмотра оригинала — устаревшая сборка')
        assert(content.include?('type="radio"') || content.include?('su2vis-scene'), 'panel.html без radio выбора одной сцены — устаревшая сборка')
        assert(!content.include?('select-all'), 'panel.html с кнопкой Все — устаревшая сборка')
        assert(content.bytesize > 50_000, 'panel.html подозрительно мал — бандл не встроен')
      end

      test 'jobs: final_max/final_size по режимам' do
        assert_equal(1024, Jobs.final_max('1k'))
        assert_equal(2048, Jobs.final_max('2k'))
        assert_equal(0, Jobs.final_max('sketch'))
        assert_equal([1024, 768], Jobs.final_size({ 'final_mode' => 'custom', 'final_w' => 1024, 'final_h' => 768 }, 1920, 1080))
      end

      test 'jobs: preview_px 128/256/512/768, мусор — 256' do
        assert_equal(128, Settings.preview_px('128'))
        assert_equal(256, Settings.preview_px('256'))
        assert_equal(512, Settings.preview_px(512))
        assert_equal(768, Settings.preview_px('768'))
        assert_equal(256, Settings.preview_px('64'))
        assert_equal(256, Settings.preview_px(nil))
      end

      test 'jobs: preview_variants приводится к числу' do
        assert_equal(3, Settings.coerce('preview_variants', '3'))
        assert_equal(1, Settings.coerce('preview_variants', nil).to_i.clamp(1, 4))
      end

      test 'client: scale_to_long тянет длинную к px' do
        assert_equal([1600, 1120], Client.scale_to_long(368, 256, 1600))
        assert_equal([1600, 1600], Client.scale_to_long(100, 100, 1600))
        w, h = Client.scale_to_long(1600, 1124, 1600)
        assert(w == 1600 && (h - 1124).abs <= 8, "пропорции: #{[w, h].inspect}")
        assert([w, h].all? { |v| (v % 16).zero? }, 'кратно 16')
      end

      test 'client: scale_to_width держит ширину px' do
        assert_equal([256, 192], Client.scale_to_width(1600, 1200, 256), 'альбом 4:3')
        assert_equal([256, 336], Client.scale_to_width(1200, 1600, 256), 'портрет')
        assert_equal([256, 256], Client.scale_to_width(100, 100, 256), 'квадрат')
        w, h = Client.scale_to_width(1600, 1124, 256)
        assert(w == 256 && (h - 180).abs <= 8, "пропорции: #{[w, h].inspect}")
        assert([w, h].all? { |v| (v % 16).zero? }, 'кратно 16')
      end

      test 'jobs: превью 256 по ширине, альбом добирает api_min' do
        w, h = Client.api_min_size(*Client.scale_to_width(1600, 1200, 256))
        assert(h == 256, "короткая сторона должна стать 256, получили #{[w, h].inspect}")
        w2, h2 = Client.api_min_size(*Client.scale_to_width(1200, 1600, 256))
        assert_equal(256, w2, "портрет держит ширину 256: #{[w2, h2].inspect}")
      end

      test 'settings: final_strength по умолчанию 0.4' do
        assert_equal(0.4, Settings.coerce('final_strength', '0.4'))
        assert(Settings.all.key?('final_strength'), 'нет ключа final_strength')
      end

      test 'client: norm_strength не даёт 0 (API требует > 0)' do
        assert_equal(0.05, Client.norm_strength(0))
        assert_equal(0.05, Client.norm_strength(-1))
        assert_equal(0.05, Client.norm_strength(nil))
        assert_equal(0.4, Client.norm_strength(0.4))
        assert_equal(1.0, Client.norm_strength(1.0))
      end

      test 'client: preset_for klein даёт 4 шага, остальным — дефолт студии' do
        klein = Client.preset_for('unsloth/flux-3-image-klein-GGUF')
        assert_equal(4, klein['steps'], "klein steps: #{klein.inspect}")
        assert_equal(1.0, klein['guidance'], "klein guidance: #{klein.inspect}")
        assert_equal('balanced', klein['memory_mode'], "klein memory: #{klein.inspect}")
        klein2 = Client.preset_for('unsloth/FLUX.2-klein-9B-GGUF')
        assert_equal(4, klein2['steps'], "flux2-klein steps: #{klein2.inspect}")
        qwen = Client.preset_for('Qwen-Image-GGUF')
        assert_equal(50, qwen['steps'], "qwen steps: #{qwen.inspect}")
        assert_equal('low_vram', qwen['memory_mode'], "qwen memory: #{qwen.inspect}")
        # LLM без image-семьи — не klein
        llm = Client.preset_for('unsloth/Qwen3.8-27B-GGUF', { 'steps' => 16, 'guidance' => 1.0 })
        assert_equal(16, llm['steps'], "fallback steps: #{llm.inspect}")
        assert_equal('дефолт студии', llm['source'], "fallback source: #{llm.inspect}")
        assert(llm['memory_mode'].nil?, 'fallback память не трогаем')
      end

      test 'client: pick_variant берёт точный файл, сначала скачанный' do
        vars = [
          { 'filename' => 'flux-2-klein-9b-BF16.gguf', 'quant' => 'BF16', 'downloaded' => false },
          { 'filename' => 'flux-2-klein-9b-Q8_0.gguf', 'quant' => 'Q8_0', 'downloaded' => true },
          { 'filename' => 'flux-2-klein-9b-Q6_K.gguf', 'quant' => 'Q6_K', 'downloaded' => false }
        ]
        assert_equal('flux-2-klein-9b-Q8_0.gguf', Client.pick_variant(vars, 'Q8_0'))
        assert_equal('flux-2-klein-9b-Q6_K.gguf', Client.pick_variant(vars, 'q6_k'))
        assert_equal('flux-2-klein-9b-BF16.gguf',
                     Client.pick_variant(vars, 'NOPE', { 'filename' => 'flux-2-klein-9b-BF16.gguf' }))
        assert_equal('', Client.pick_variant(vars, 'NOPE'))
        assert_equal('', Client.pick_variant([], 'Q8_0'))
      end

      test 'gallery: превью сохраняется с сайдкаром параметров' do
        Dir.mktmpdir do |d|
          f = Gallery.save_preview(d, "\x89PNG\r\n\x1A\n".b + 'x' * 16,
                                   { 'scene' => 0, 'seed' => 7, 'variant' => 1,
                                     'width' => 336, 'height' => 256, 'prompt' => 'p',
                                     'steps' => 4 })
          assert(File.file?(f), 'картинка не записана')
          sp = "#{f}.json"
          assert(File.file?(sp), 'сайдкар не записан')
          m = JSON.parse(File.read(sp, encoding: 'UTF-8'))
          assert_equal('preview', m['kind'], 'вид в сайдкаре')
          assert_equal(7, m['seed'], 'seed в сайдкаре')
          assert_equal('p', m['prompt'], 'промпт в сайдкаре')
          list = Gallery.list(d)
          assert_equal(1, list.size, "список: #{list.inspect}")
          e = list.first
          assert_equal('preview', e['kind'], 'вид в списке')
          assert_equal(0, e['scene'], 'сцена в списке')
          r = Gallery.remove(d, f)
          assert(r[:ok], 'remove не ok')
          assert(!File.exist?(f) && !File.exist?(sp), 'файлы остались после remove')
        end
      end

      test 'gallery: чужой путь отклоняется, старый финал виден' do
        Dir.mktmpdir do |d|
          File.binwrite(File.join(d, 'old_final.jpg'), "\xFF\xD8\xFF".b + 'x' * 16)
          list = Gallery.list(d)
          assert_equal(1, list.size, "список: #{list.inspect}")
          assert_equal('final', list.first['kind'], 'вид legacy')
          begin
            Gallery.remove(d, File.join(d, '..', 'evil.png'))
            assert(false, 'чужой файл должны отклонить')
          rescue StandardError => e
            assert(e.message.include?('вне папки') || e.message.include?('не найден'), "не тот отказ: #{e.message}")
          end
          assert_equal([], Gallery.list(File.join(d, 'no-such-dir')), 'нет папки — пусто')
        end
      end

      test 'jobs: финал из превью тянется вверх до режима' do
        assert_equal(1600, Jobs.final_long_side('sketch'))
        assert_equal(1024, Jobs.final_long_side('1k'))
        assert_equal(2048, Jobs.final_long_side('2k'))
        assert(Jobs.final_long_side('custom').nil?, 'custom считается отдельно')
        w, h = Client.scale_to_long(368, 256, Jobs.final_long_side('1k'))
        assert(w == 1024 && h >= 256, "1K из превью: #{[w, h].inspect}")
        w, h = Client.scale_to_long(368, 256, Jobs.final_long_side('2k'))
        assert(w == 2048 && h >= 256, "2K из превью: #{[w, h].inspect}")
      end

      test 'jobs: cancel несуществующей задачи — вежливый отказ' do
        r = Jobs.cancel('no-such-job')
        assert_equal(false, r[:ok])
      end

      test 'log: append/tail/clear через временный файл' do
        require 'tmpdir'
        Dir.mktmpdir do |d|
          Log.path_override = File.join(d, 't.log')
          begin
            Log.append('job_start', 'id' => 'j1', 'kind' => 'preview')
            Log.append('job_done', 'id' => 'j1', 'status' => 'done', 'total_s' => 1.5)
            all = Log.tail(50)
            assert_equal(2, all.size, 'две записи')
            assert_equal('job_start', all[0]['event'])
            assert_equal('done', all[1]['status'])
            assert(Log.clear, 'clear')
            assert_equal([], Log.tail(50), 'после clear пусто')
          ensure
            Log.path_override = nil
          end
        end
      end

      test 'jobs: expand_name подставляет плейсхолдеры' do
        name = Jobs.expand_name({ 'name_template' => '{scene}{suffix}_{date}', 'suffix' => '_ph' }, 0, 7)
        assert(name.include?('_ph_'), "суффикс потерян: #{name.inspect}")
        assert(!name.include?('{'), 'плейсхолдеры не раскрыты')
        assert(name.length <= 130, 'имя слишком длинное')
      end

      test 'mixins: add_data/update/list/remove roundtrip' do
        Dir.mktmpdir do |d|
          out = File.join(d, 'out')
          raw = "\x89PNG\r\n\x1A\n".b + 'x' * 16
          require 'base64'
          url = "data:image/png;base64,#{Base64.strict_encode64(raw)}"
          e = Mixins.add_data(url, 'кирпич.png', out)
          assert(File.file?(e['file']), 'картинка не записана')
          assert(File.file?("#{e['file']}.json"), 'сайдкар не записан')
          u = Mixins.update(e['id'], caption: 'фактура кирпича', dir: out)
          assert_equal('фактура кирпича', u['caption'], 'подпись не сохранилась')
          u2 = Mixins.update(e['id'], active: false, dir: out)
          assert_equal(false, u2['active'], 'флаг active не сохранился')
          list = Mixins.list(out)
          assert_equal(1, list.size, "список: #{list.inspect}")
          assert_equal('фактура кирпича', list.first['caption'], 'подпись в списке')
          # active_for_job отсекает выключенные
          assert_equal([], Mixins.active_for_job([{ 'path' => e['file'], 'caption' => 'x', 'active' => false }]), 'выключенная попала в задачу')
          got = Mixins.active_for_job([{ 'path' => e['file'], 'caption' => 'фактура', 'active' => true }])
          assert_equal(1, got.size, 'активная не попала в задачу')
          r = Mixins.remove(e['id'], out)
          assert(r[:ok], 'remove не ok')
          assert(!File.exist?(e['file']), 'файл остался после remove')
          begin
            Mixins.remove('../evil.png', out)
            assert(false, 'выход за папку должны отклонить')
          rescue StandardError => e2
            assert(e2.message.include?('вне папки') || e2.message.include?('не найден'), "не тот отказ: #{e2.message}")
          end
        end
      end

      test 'mixins: dims_from_bytes различает PNG/JPEG/WebP' do
        png = "\x89PNG\r\n\x1A\n".b + "\x00\x00\x00\x0D".b + 'IHDR'.b +
              [64].pack('N') + [48].pack('N') + ("\x00".b * 8)
        assert_equal([64, 48], Mixins.dims_from_bytes(png, '.png'))
        jpg = "\xFF\xD8\xFF\xC0\x00\x0B\x08\x00\x10\x00\x20\x01\x01\x11\x00\xFF\xD9".b
        assert_equal([32, 16], Mixins.dims_from_bytes(jpg, '.jpg'))
        assert_equal([32, 16], Mixins.dims_from_bytes(jpg, '.jpeg'))
        webp = 'RIFF'.b + [18].pack('V') + 'WEBP'.b + 'VP8X'.b + [10].pack('V') +
               "\x00".b + [99].pack('V')[0, 3] + [49].pack('V')[0, 3] + "\x00\x00\x00".b
        assert_equal([100, 50], Mixins.dims_from_bytes(webp, '.webp'))
        assert(Mixins.dims_from_bytes('мусор'.b, '.png').nil?, 'мусор — nil')
        assert(Mixins.dims_from_bytes('мусор'.b, '.xxx').nil?, 'неизвестный ext — nil')
      end

      test 'mixins: oversized давит по длинной стороне и байтам' do
        small_png = "\x89PNG\r\n\x1A\n".b + "\x00\x00\x00\x0D".b + 'IHDR'.b +
                    [800].pack('N') + [600].pack('N') + ("\x00".b * 8)
        assert(!Mixins.oversized?(small_png, '.png'), '800x600 — норма')
        big_png = "\x89PNG\r\n\x1A\n".b + "\x00\x00\x00\x0D".b + 'IHDR'.b +
                  [4000].pack('N') + [3000].pack('N') + ("\x00".b * 8)
        assert(Mixins.oversized?(big_png, '.png'), '4000px — oversize')
        fat = 'x'.b * (Mixins::MAX_BYTES + 1)
        assert(Mixins.oversized?(fat, '.jpg'), 'байты сверх лимита — oversize')
      end

      test 'mixins: normalize маленькое пропускает, мусор-гигант отклоняет' do
        png = "\x89PNG\r\n\x1A\n".b + "\x00\x00\x00\x0D".b + 'IHDR'.b +
              [100].pack('N') + [100].pack('N') + ("\x00".b * 64)
        out, ext = Mixins.normalize_mixin_bytes(png, '.png')
        assert_equal('.png', ext, 'ext малой картинки')
        assert_equal(png, out, 'малую картинку не трогаем')
        fat = 'x'.b * (Mixins::MAX_BYTES + 1)
        begin
          Mixins.normalize_mixin_bytes(fat, '.jpg')
          assert(false, 'гиганта должны отклонить или сжать')
        rescue StandardError => e
          assert(e.message.include?('большая') || e.message.include?('сожми'), "не тот отказ: #{e.message}")
        end
      end
      test 'mixins: norm_crop/norm_rotation чистят мусор' do
        assert(Mixins.norm_crop(nil).nil?, 'nil — nil')
        assert(Mixins.norm_crop('').nil?, 'пусто — nil')
        assert(Mixins.norm_crop({ 'x' => 0.1, 'y' => 0.2, 'w' => 0.5, 'h' => 0.4 }) == { 'x' => 0.1, 'y' => 0.2, 'w' => 0.5, 'h' => 0.4 }, 'норма')
        assert(Mixins.norm_crop({ 'x' => -1, 'y' => 0, 'w' => 0.001, 'h' => 0.5 }).nil?, 'кроха — nil')
        assert(Mixins.norm_crop({ 'x' => 0.9, 'y' => 0.9, 'w' => 0.5, 'h' => 0.5 }) == { 'x' => 0.9, 'y' => 0.9, 'w' => 0.1, 'h' => 0.1 }, 'обрезка у края')
        assert(Mixins.norm_crop({ x: 0.2, y: 0.3, w: 0.4, h: 0.2 }) == { 'x' => 0.2, 'y' => 0.3, 'w' => 0.4, 'h' => 0.2 }, 'символьные ключи')
        assert_equal(0.0, Mixins.norm_rotation(nil), 'nil — 0')
        assert_equal(0.0, Mixins.norm_rotation(''), 'пусто — 0')
        assert_equal(90.0, Mixins.norm_rotation(90), '90')
        assert_equal(-90.0, Mixins.norm_rotation(-90), '-90')
        assert_equal(-90.0, Mixins.norm_rotation(270), '270 -> -90')
        assert_equal(0.0, Mixins.norm_rotation(0.01), 'кроха — 0')
        assert_equal(0.0, Mixins.norm_rotation('мусор'), 'мусор — 0')
      end

      test 'mixins: update хранит crop/rotation, job_path без трансформов не трогает файл' do
        Dir.mktmpdir do |d|
          out = File.join(d, 'out')
          raw = "\x89PNG\r\n\x1A\n".b + "\x00\x00\x00\x0D".b + 'IHDR'.b +
                [100].pack('N') + [100].pack('N') + ("\x00".b * 64)
          require 'base64'
          url = "data:image/png;base64,#{Base64.strict_encode64(raw)}"
          e = Mixins.add_data(url, 'фр.png', out)
          u = Mixins.update(e['id'], crop: { 'x' => 0.1, 'y' => 0.1, 'w' => 0.5, 'h' => 0.5 }, rotation: 90, dir: out)
          assert_equal({ 'x' => 0.1, 'y' => 0.1, 'w' => 0.5, 'h' => 0.5 }, u['crop'], 'кроп не сохранился')
          assert_equal(90.0, u['rotation'], 'поворот не сохранился')
          list = Mixins.list(out)
          assert_equal(u['crop'], list.first['crop'], 'кроп в списке')
          assert_equal(90.0, list.first['rotation'], 'поворот в списке')
          got = Mixins.active_for_job([{ 'path' => e['file'], 'caption' => 'x', 'active' => true, 'crop' => u['crop'], 'rotation' => 90 }])
          assert_equal(u['crop'], got.first['crop'], 'кроп в задаче')
          assert_equal(90.0, got.first['rotation'], 'поворот в задаче')
          u2 = Mixins.update(e['id'], crop: nil, rotation: 0, dir: out)
          assert(u2['crop'].nil?, 'сброс кропа')
          assert_equal(0.0, u2['rotation'], 'сброс поворота')
          assert_equal(e['file'], Mixins.job_path(e['file']), 'без трансформов файл не трогаем')
          assert_equal(e['file'], Mixins.job_path(e['file'], nil, 0), 'нули — тот же файл')
        end
      end

      test 'panel: within_dir держит файл внутри, .. режет' do
        assert(Panel.respond_to?(:within_dir?), 'нет Panel.within_dir?')
        assert_equal(File.expand_path('/a/b/r.jpg'), Panel.within_dir?('/a/b', '/a/b/r.jpg'))
        assert(Panel.within_dir?('/a/b', '/a/b/../evil.jpg').nil?, 'выход через .. должны отклонить')
        assert(Panel.within_dir?('/a/b', '/a/other.jpg').nil?, 'чужую папку должны отклонить')
      end

      test 'panel: within_dir чинит смешанные сепараторы Windows' do
        skip('только Windows: бэкслэши в пути') unless RUBY_PLATFORM =~ /mingw|mswin/
        dir = 'C:\\su2vis_mix_test\\out'
        f = 'C:\\su2vis_mix_test\\out\\Scene_6.jpg'
        assert_equal(File.expand_path(f), Panel.within_dir?(dir, f), 'легальный финал вне папки')
      end

      test 'mixins: job_path мелочь пропускает как есть' do
        Dir.mktmpdir do |d|
          small = File.join(d, 'ok.png')
          File.binwrite(small, "\x89PNG\r\n\x1A\n".b + "\x00\x00\x00\x0D".b + 'IHDR'.b +
                        [100].pack('N') + [100].pack('N') + ("\x00".b * 64))
          assert_equal(small, Mixins.job_path(small), 'малую не трогаем')
          assert_equal(File.join(d, 'nope.png'), Mixins.job_path(File.join(d, 'nope.png')), 'нет файла — тот же путь')
          txt = File.join(d, 'note.txt')
          File.write(txt, 'x')
          assert_equal(txt, Mixins.job_path(txt), 'не картинку не трогаем')
        end
      end

      test 'mixins: запуск powershell скрыт — нет system() с видимой консолью' do
        src = File.read(File.join(__dir__, '..', 'mixins.rb'), encoding: 'UTF-8')
        assert(Mixins.respond_to?(:run_hidden), 'нет Mixins.run_hidden')
        assert(src.include?('WScript.Shell'), 'run_hidden без WScript.Shell.Run(…, 0, …)')
        assert(src.include?('-WindowStyle Hidden'), 'powershell без -WindowStyle Hidden')
        assert(!src.include?('2> NUL'), 'остался редирект через cmd.exe (2> NUL) — идёт через видимую консоль')
        %w[try_powershell_downscale try_powershell_transform].each do |m|
          body = src[/def #{m}.*?(?=^      def |\z)/m, 0] || ''
          assert(body.include?('run_hidden'), "#{m} не использует run_hidden")
          assert(!body.match?(/system\s*\(/), "#{m} зовёт system() напрямую — окно будет моргать")
        end
      end

      test 'mixins: run_hidden ждёт выхода и возвращает успех' do
        ok = Mixins.run_hidden('ruby -e "exit 0"')
        assert_equal(true, ok, 'exit 0 должен дать true')
        bad = Mixins.run_hidden('ruby -e "exit 3"')
        assert_equal(false, bad, 'ненулевой код должен дать false')
      end

      test 'mixins: job_path большую жмёт в кэш' do
        skip('только Windows: даунскейл через System.Drawing') unless RUBY_PLATFORM =~ /mingw|mswin/
        require 'tmpdir'
        Dir.mktmpdir do |d|
          src = File.join(d, 'big.png')
          ps = File.join(d, 'gen.ps1')
          File.write(ps, "Add-Type -AssemblyName System.Drawing\n" \
                         "$b = New-Object System.Drawing.Bitmap(2000, 1500)\n" \
                         "$b.Save('#{src}', [System.Drawing.Imaging.ImageFormat]::Png)\n" \
                         "$b.Dispose()\n", encoding: 'UTF-8')
          ok = Mixins.run_hidden("powershell -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File \"#{ps}\"")
          skip('powershell не сгенерировал картинку') unless ok && File.file?(src)
          got = Mixins.job_path(src)
          assert(got != src, "большую должны ужать, вернули исходник: #{got}")
          dims = Mixins.dims_from_bytes(File.binread(got), '.png')
          assert(dims && dims.max <= Mixins::MAX_LONG_SIDE, "кэш не в норме: #{dims.inspect}")
          assert_equal(got, Mixins.job_path(src), 'второй раз — тот же кэш')
        end
      end
      test 'client: mixins_prompt нумерует референсы со 2 и пропускает пустые' do
        assert_equal('', Client.mixins_prompt([]), 'пусто — пустая строка')
        assert_equal('', Client.mixins_prompt([{ 'caption' => '  ' }]), 'пустая подпись — пусто')
        got = Client.mixins_prompt([{ 'caption' => 'фактура кирпича' }, { 'caption' => '' }])
        assert(got.include?('reference image 2'), "нумерация: #{got.inspect}")
        assert(got.include?('фактура кирпича'), "подпись потеряна: #{got.inspect}")
        assert(!got.include?('reference image 3'), "пустая подпись попала: #{got.inspect}")
      end

      test 'scenes: capture прячет размеры (with_dims_hidden/collect_dims)' do
        assert(Scenes.respond_to?(:with_dims_hidden), 'нет Scenes.with_dims_hidden')
        assert(Scenes.respond_to?(:collect_dims), 'нет Scenes.collect_dims')
      end

      test 'scenes: HD-референс превью (capture_hd 1600)' do
        assert(Scenes.respond_to?(:capture_hd), 'нет Scenes.capture_hd')
        assert(Scenes.method(:capture_all).parameters.include?([:key, :hd]), 'у capture_all нет hd:')
      end

      test 'scenes: тумбы 170x128 с тонкими линиями' do
        assert_equal(170, Scenes::THUMB_W)
        assert_equal(128, Scenes::THUMB_H)
        assert(Scenes.method(:capture).parameters.include?([:key, :thin_lines]), 'у capture нет thin_lines:')
      end

      test 'выключатели колонок: дефолты, coerce, per-file' do
        assert_equal(true, Settings::DEFAULTS['use_scenes'], 'дефолт use_scenes')
        assert_equal(true, Settings::DEFAULTS['use_mixins'], 'дефолт use_mixins')
        assert(Settings::PROJECT_KEYS.include?('use_scenes'), 'use_scenes должен быть per-file')
        assert(Settings::PROJECT_KEYS.include?('use_mixins'), 'use_mixins должен быть per-file')
        assert_equal(false, Settings.coerce('use_scenes', 'false'))
        assert_equal(true, Settings.coerce('use_scenes', 'true'))
        assert_equal(true, Settings.coerce('use_mixins', true))
        assert_equal(false, Settings.coerce('use_mixins', false))
      end

      test 'jobs: режим без сцены (nil) — имена и размеры из настроек' do
        assert_equal('prompt', Jobs.safe_name(nil), 'safe_name(nil)')
        name = Jobs.expand_name({ 'name_template' => '{scene}{suffix}_{date}', 'suffix' => '_ph' }, nil, 7)
        assert(name.include?('prompt'), "имя без сцены: #{name.inspect}")
        assert(!name.include?('{'), 'плейсхолдеры не раскрыты')
        w, h = Jobs.default_dims({ 'final_w' => 1280, 'final_h' => 960 })
        assert_equal([1280, 960], [w, h], 'размер из настроек')
        assert_equal([1024, 1024], Jobs.default_dims({ 'final_w' => 0, 'final_h' => 0 }), 'мусор — квадрат')
      end

      test 'gallery: превью без сцены пишется с тегом prompt' do
        Dir.mktmpdir do |d|
          f = Gallery.save_preview(d, "\x89PNG\r\n\x1A\n".b + 'x' * 16,
                                   { 'scene' => nil, 'seed' => 7, 'variant' => 0,
                                     'width' => 256, 'height' => 256 })
          assert(File.file?(f), 'картинка не записана')
          assert(File.basename(f).start_with?('preview_prompt_'), "тег prompt потерян: #{f.inspect}")
          m = JSON.parse(File.read("#{f}.json", encoding: 'UTF-8'))
          assert(m['scene'].nil?, 'сцена в сайдкаре должна быть nil')
        end
      end

      test 'client: generate без эскиза шлёт только примеси (без init_image/strength)' do
        bodies = []
        fake = Object.new
        fake.define_singleton_method(:request) do |req|
          bodies << JSON.parse(req.body)
          raise 'стоп-тест'
        end
        orig_api = Client.method(:api)
        Client.define_singleton_method(:api) { |_url| fake }
        begin
          Dir.mktmpdir do |d|
            ref = File.join(d, 'ref.png')
            File.binwrite(ref, "\x89PNG\r\n\x1A\n".b + 'x' * 16)
            begin
              Client.generate('http://127.0.0.1:9', 'k', nil, prompt: 'p', width: 256, height: 256,
                              extra_references: [ref], mixins_prompt: 'доп')
              assert(false, 'generate должен был дойти до HTTP')
            rescue RuntimeError => e
              raise unless e.message == 'стоп-тест'
            end
          end
        ensure
          Client.define_singleton_method(:api, orig_api)
        end
        assert_equal(1, bodies.size, 'должен быть один запрос')
        b = bodies.first
        assert(!b.key?('init_image'), "init_image без эскиза: #{b.keys.inspect}")
        assert(!b.key?('strength'), "strength без эскиза: #{b.keys.inspect}")
        assert_equal(1, b['reference_images'].size, 'только примесь в референсах')
        assert(b['prompt'].include?('доп'), 'дописка примесей потеряна')
      end

      test 'scenes: список сцен читается (пустая модель — пустой список)' do
        skip('вне SketchUp: нет активной модели') unless defined?(Sketchup) && Sketchup.active_model

        list = Scenes.list
        assert(list.is_a?(Array), 'list должен вернуть массив')
      end
    end
  end
end

# Прямой запуск печатает отчёт; внутри SketchUp тесты гоняет ext_test.
if $PROGRAM_NAME == __FILE__
  require 'json'
  report = Dn1sup::Su2vis::Test.run!
  puts JSON.pretty_generate(report)
  exit(1) unless report['failures'].empty?
end
