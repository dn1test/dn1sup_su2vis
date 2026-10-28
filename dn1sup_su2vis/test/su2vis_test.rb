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
        assert(Settings.respond_to?(:project_dirname_for), 'нет Settings.project_dirname_for')
        assert(Settings.respond_to?(:project_dirname?), 'нет Settings.project_dirname?')
        assert(Settings.respond_to?(:legacy_project_fallback), 'нет Settings.legacy_project_fallback')
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
        assert(Scenes.respond_to?(:norm_boxes), 'нет Scenes.norm_boxes')
        assert(Scenes.respond_to?(:boxes), 'нет Scenes.boxes')
        assert(Scenes.respond_to?(:save_boxes), 'нет Scenes.save_boxes')
        assert(Scenes.respond_to?(:boxes_prompt), 'нет Scenes.boxes_prompt')
        assert(Scenes.respond_to?(:annotated_sketch), 'нет Scenes.annotated_sketch')
        assert(Scenes.respond_to?(:draw_boxes_png), 'нет Scenes.draw_boxes_png')
        assert(Jobs.respond_to?(:enqueue), 'нет Jobs.enqueue')
        assert(Jobs.respond_to?(:cancel), 'нет Jobs.cancel')
        assert(Jobs.respond_to?(:pump_start), 'нет Jobs.pump_start')
        assert(Gallery.respond_to?(:list), 'нет Gallery.list')
        assert(Gallery.respond_to?(:remove), 'нет Gallery.remove')
        assert(Gallery.respond_to?(:clear), 'нет Gallery.clear')
        assert(Gallery.respond_to?(:unique_path), 'нет Gallery.unique_path')
        assert(Gallery.respond_to?(:save_sidecar), 'нет Gallery.save_sidecar')
        assert(Mixins.respond_to?(:list), 'нет Mixins.list')
        assert(Mixins.respond_to?(:add_data), 'нет Mixins.add_data')
        assert(Mixins.respond_to?(:add_path), 'нет Mixins.add_path')
        assert(Mixins.respond_to?(:update), 'нет Mixins.update')
        assert(Mixins.respond_to?(:remove), 'нет Mixins.remove')
        assert(Mixins.respond_to?(:clear), 'нет Mixins.clear')
        assert(Client.respond_to?(:mixins_prompt), 'нет Client.mixins_prompt')
        assert(Client.respond_to?(:boxes_sentence), 'нет Client.boxes_sentence')
        assert(Mixins.respond_to?(:annotated_job_path), 'нет Mixins.annotated_job_path')
        assert(Studio.respond_to?(:ensure_async), 'нет Studio.ensure_async')
        assert(Studio.respond_to?(:ensure_running!), 'нет Studio.ensure_running!')
        assert(Studio.respond_to?(:state), 'нет Studio.state')
        assert(Panel.respond_to?(:show), 'нет Panel.show')
        assert(Panel.respond_to?(:parse_payload), 'нет Panel.parse_payload')
      end

      test 'проект: только машинные ключи глобальные, остальное per-file' do
        assert_equal(%w[unsloth_key unsloth_autostart unsloth_cmd], Settings::GLOBAL_KEYS)
        %w[unsloth_key unsloth_autostart unsloth_cmd].each do |k|
          assert(!Settings::PROJECT_KEYS.include?(k), "#{k} не должен лежать в файле проекта")
        end
        assert(Settings::PROJECT_KEYS.include?('prompt'), 'промпт должен быть per-file')
        assert_equal((Settings::DEFAULTS.keys - %w[unsloth_key unsloth_autostart unsloth_cmd]).sort, Settings::PROJECT_KEYS.sort)
      end

      test 'проект: папка <имя модели>_su2vis рядом с моделью' do
        assert(Settings.project_dir_for('').nil?, 'пустой путь — nil')
        assert(Settings.project_dir_for(nil).nil?, 'nil — nil')
        d = Settings.project_dir_for('D:/work/house.skp')
        assert(d.to_s.end_with?('house_su2vis'), "папка проекта: #{d.inspect}")
        assert_equal(File.dirname('D:/work/house.skp'), File.dirname(d.to_s))
      end

      test 'проект: имя папки чистится от запрещённых символов Windows' do
        assert_equal('house_su2vis', Settings.project_dirname_for('D:/work/house.skp'), 'обычное имя')
        assert_equal('a_b_c_d_su2vis', Settings.project_dirname_for('C:/x/a<b>c"d.skp'), 'запрещённые символы → _')
        assert_equal('my_house_su2vis', Settings.project_dirname_for('C:/x/my*house.skp'), 'звёздочка → _')
        assert_equal('дом_su2vis', Settings.project_dirname_for('C:/x/дом. ..skp'), 'хвостовые точки/пробелы')
        assert_equal('su2vis', Settings.project_dirname_for(''), 'пустой путь — просто su2vis')
        long = 'у' * 100
        assert_equal(67, Settings.project_dirname_for("C:/x/#{long}.skp").length, 'кламп длины 60 + _su2vis')
      end

      test 'проект: project_dirname? признаёт все форматы' do
        assert(Settings.project_dirname?('su2vis'), 'самое старое имя su2vis')
        assert(Settings.project_dirname?('su2vis_house'), 'формат 0.20.x su2vis_<модель>')
        assert(Settings.project_dirname?('house_su2vis'), 'текущий формат <модель>_su2vis')
        assert(!Settings.project_dirname?('su2visss'), 'похожее, но чужое')
        assert(!Settings.project_dirname?('housesu2vis'), 'без подчёркивания — чужое')
        assert(!Settings.project_dirname?('out'), 'чужая папка')
        assert(!Settings.project_dirname?(nil), 'nil — не папка проекта')
      end

      test 'проект: фолбэк на старые su2vis/ и su2vis_<имя>/ пока новой нет' do
        Dir.mktmpdir do |d|
          newd = File.join(d, 'house_su2vis')
          assert(Settings.legacy_project_fallback(nil).nil?, 'nil — nil')
          assert(Settings.legacy_project_fallback(newd).nil?, 'без старых папок — nil')
          old = File.join(d, 'su2vis')
          Settings.init_project(old)
          assert_equal(old, Settings.legacy_project_fallback(newd), 'старая su2vis/ с настройками должна вернуться')
          assert(Settings.legacy_project_fallback(old).nil?, 'папка su2vis сама себе проект — фолбэк не нужен')
          # Формат 0.20.x перекрывает древний, но уступает готовому новому.
          old20 = File.join(d, 'su2vis_house')
          Settings.init_project(old20)
          assert_equal(old20, Settings.legacy_project_fallback(newd), 'su2vis_house/ должна вернуться')
          Settings.init_project(newd)
          assert(Settings.legacy_project_fallback(newd).nil?, 'новая папка уже готова — фолбэк не нужен')
        end
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
          assert(File.file?(File.join(proj, 'su2vis.yaml')), 'файл проекта yaml не записан')
          assert(!File.file?(File.join(proj, 'su2vis.json')), 'старого json быть не должно')
          assert(File.directory?(File.join(proj, 'out')), 'out не создан')
          doc = Settings.read_project_doc(proj)
          assert(!doc.key?('unsloth_key'), 'ключ не должен лежать в файле проекта')
          assert(!doc.key?('unsloth_autostart'), 'autostart не должен лежать в файле проекта')
          assert(!doc.key?('unsloth_cmd'), 'cmd не должен лежать в файле проекта')
          assert(doc.key?('prompt'), 'промпт должен быть в файле проекта')
          # save в готовый проект пишет только файл, ключ/global не трогаем:
          # в hash нет глобальных ключей и out_dir — defaults не пишутся.
          Settings.save({ 'prompt' => 'тест-промпт', 'bogus_key' => 1 }, proj)
          doc2 = Settings.read_project_doc(proj)
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
          # новое имя <модель>_su2vis тоже удаляется, старый формат — тоже
          proj2 = File.join(d, 'house_su2vis')
          Settings.init_project(proj2)
          Settings.delete_project(proj2)
          assert(!File.exist?(proj2), 'папка house_su2vis не удалилась')
          proj3 = File.join(d, 'su2vis_house')
          Settings.init_project(proj3)
          Settings.delete_project(proj3)
          assert(!File.exist?(proj3), 'старая папка su2vis_house не удалилась')
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
        %w[prompt seed sketch_preset preview_variants final_mode final_w final_h workflow name_template strength steps unsloth_url version].each do |k|
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
        assert_equal({ 'kind' => 'final' }, Panel.parse_payload('kind' => 'final'))
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

      test 'панель: resources/panel.html собран из Vue (3 колонки)' do
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
        assert(content.include?('Рендер'), 'panel.html без кнопки рендера — устаревшая сборка')
        assert(content.include?('Соотношение сторон') || content.include?('Aspect ratio'), 'panel.html без настроек размера — устаревшая сборка')
        assert(content.include?('Картинок за раз'), 'panel.html без выбора числа картинок — устаревшая сборка')
        assert(content.include?('final_view'), 'panel.html без просмотра финала — устаревшая сборка')
        assert(content.include?('enhance_preview'), 'panel.html без предпросмотра enhance — устаревшая сборка')
        assert(content.include?('select_out_dir'), 'panel.html без выбора папки — устаревшая сборка')
        assert(content.include?('project_init'), 'panel.html без создания su2vis/ — устаревшая сборка')
        assert(content.include?('Проверить снова'), 'panel.html без перепроверки проекта — устаревшая сборка')
        assert(content.include?('Соотношение сторон'), 'panel.html без выбора аспекта — устаревшая сборка')
        assert(content.include?('Resolution'), 'panel.html без выбора разрешения — устаревшая сборка')
        assert(content.include?('Random if empty'), 'panel.html без seed-плейсхолдера — устаревшая сборка')
        assert(content.include?('Advanced'), 'panel.html без секции Advanced — устаревшая сборка')
        assert(content.include?('project_delete'), 'panel.html без удаления su2vis/ — устаревшая сборка')
        assert(content.include?('Повторить'), 'panel.html без повтора загрузки картинки — устаревшая сборка')
        assert(content.include?('load_error'), 'panel.html без видимой ошибки загрузки — устаревшая сборка')
        assert(content.include?('Папка для рендеров'), 'panel.html без поля папки — устаревшая сборка')
        assert(content.include?('загружаю…'), 'panel.html без тумб финала — устаревшая сборка')
        assert(content.include?('overflow-y-auto'), 'panel.html без прокрутки контента — устаревшая сборка')
        assert(content.include?('flex-col'), 'panel.html без колоночной раскладки — устаревшая сборка')
        assert(content.include?('scroll-slim'), 'panel.html без скрытых скроллбаров — устаревшая сборка')
        assert(!content.include?('preview_save'), 'panel.html с легаси сохранением превью — устаревшая сборка')
        assert(!content.include?('select-preview'), 'panel.html с легаси выбором превью — устаревшая сборка')
        assert(!content.include?('В финал'), 'panel.html с легаси кнопкой в финал — устаревшая сборка')
        assert(content.include?('gallery_list'), 'panel.html без чтения галереи — устаревшая сборка')
        assert(content.include?('gallery_delete'), 'panel.html без удаления файлов — устаревшая сборка')
        assert(content.include?('gallery_delete_all'), 'panel.html без «удалить все» в рендере — устаревшая сборка')
        assert(content.include?('mixins_list'), 'panel.html без списка примесей — устаревшая сборка')
        assert(content.include?('mixins_add_data'), 'panel.html без добавления примесей — устаревшая сборка')
        assert(content.include?('mixins_update'), 'panel.html без подписей примесей — устаревшая сборка')
        assert(content.include?('Примеси'), 'panel.html без примесей — устаревшая сборка')
        assert(content.include?('mixins_delete_all'), 'panel.html без «удалить все» в примесях — устаревшая сборка')
        assert(content.include?('Удалить все'), 'panel.html без кнопки Удалить все — устаревшая сборка')
        assert(content.include?('Удалить файл'), 'panel.html без иконки удаления — устаревшая сборка')
        assert(content.include?('Выделить / повернуть'), 'panel.html без редактора выделения — устаревшая сборка')
        assert(content.include?('scenes_boxes_save'), 'panel.html без рамок сцены — устаревшая сборка')
        assert(content.include?('Рамки'), 'panel.html без редактора рамок — устаревшая сборка')
        assert(content.include?('Квантование GGUF'), 'panel.html без выбора квантования klein — устаревшая сборка')
        assert(content.include?('Эскиз-референс'), 'panel.html без настроек эскиза-референса — устаревшая сборка')
        assert(content.include?('скрыть размеры'), 'panel.html без тумблера размеров — устаревшая сборка')
        assert(content.include?('автообрезка'), 'panel.html без тумблера автокропа — устаревшая сборка')
        assert(content.include?('toggle-enabled'), 'panel.html без выключателей колонок — устаревшая сборка')
        assert(content.include?('только по промпту'), 'panel.html без режима только-промпт — устаревшая сборка')
        assert(content.include?('Показать оригинал'), 'panel.html без просмотра оригинала — устаревшая сборка')
        assert(content.include?('type="radio"') || content.include?('su2vis-scene'), 'panel.html без radio выбора одной сцены — устаревшая сборка')
        assert(content.include?('Что брать по умолчанию') || content.include?('Для новых примесей'), 'panel.html без дефолтов примесей — устаревшая сборка')
        assert(content.include?('Случайные сиды'), 'panel.html без тумблера случайных сидов — устаревшая сборка')
        assert(content.include?('Шаги'), 'panel.html без слайдера шагов — устаревшая сборка')
        assert(content.include?('Precision'), 'panel.html без точности Precision — устаревшая сборка')
        assert(content.include?('Text encoder precision'), 'panel.html без точности текст-энкодера — устаревшая сборка')
        assert(content.include?('Attention'), 'panel.html без выбора attention — устаревшая сборка')
        assert(content.include?('Step cache'), 'panel.html без степ-кеша — устаревшая сборка')
        assert(content.include?('CPU offload'), 'panel.html без CPU offload — устаревшая сборка')
        assert(content.include?('Live preview'), 'panel.html без live preview — устаревшая сборка')
        assert(content.include?('Loaded build'), 'panel.html без блока loaded build — устаревшая сборка')
        assert(!content.include?('select-all'), 'panel.html с кнопкой Все — устаревшая сборка')
        assert(content.bytesize > 50_000, 'panel.html подозрительно мал — бандл не встроен')
      end

      test 'jobs: final_max/final_size по режимам' do
        assert_equal(1024, Jobs.final_max('1k'))
        assert_equal(2048, Jobs.final_max('2k'))
        assert_equal(0, Jobs.final_max('sketch'))
        assert_equal([1024, 768], Jobs.final_size({ 'final_mode' => 'custom', 'final_w' => 1024, 'final_h' => 768 }, 1920, 1080))
      end

      test 'jobs: LEGACY preview_px (совместимость)' do
        assert_equal(128, Settings.preview_px('128'))
        assert_equal(256, Settings.preview_px('256'))
        assert_equal(512, Settings.preview_px(512))
        assert_equal(768, Settings.preview_px('768'))
        assert_equal(256, Settings.preview_px('64'))
        assert_equal(256, Settings.preview_px(nil))
      end

      test 'jobs: batch variants приводится к числу' do
        assert_equal(3, Settings.coerce('preview_variants', '3'))
        assert_equal(1, Settings.coerce('preview_variants', nil).to_i.clamp(1, 4))
      end

      test 'settings: final_w/final_h клампятся к 256..2048 (не к 1..4)' do
        assert_equal(1024, Settings.coerce('final_w', '1024'))
        assert_equal(1536, Settings.coerce('final_h', 1536))
        assert_equal(256, Settings.coerce('final_w', '4'), 'битые 4px из 0.17.0 лечатся в 256')
        assert_equal(2048, Settings.coerce('final_h', '9999'))
        assert_equal(2048, Settings.coerce('final_w', 2048))
      end

      test 'settings: final_mode только sketch/1k/2k/custom' do
        assert_equal('sketch', Settings.coerce('final_mode', 'sketch'))
        assert_equal('1k', Settings.coerce('final_mode', '1k'))
        assert_equal('custom', Settings.coerce('final_mode', 'custom'))
        assert_equal('sketch', Settings.coerce('final_mode', 'мусор'))
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

      test 'settings: steps по умолчанию 16, диапазон 8..30' do
        assert_equal(16, Settings::DEFAULTS['steps'])
        assert_equal(8, Settings.coerce('steps', 2))
        assert_equal(30, Settings.coerce('steps', 99))
        assert_equal(20, Settings.coerce('steps', 20))
        assert(Settings.all.key?('steps'), 'нет ключа steps')
      end

      test 'client: norm_strength не даёт 0 (API требует > 0)' do
        assert_equal(0.05, Client.norm_strength(0))
        assert_equal(0.05, Client.norm_strength(-1))
        assert_equal(0.05, Client.norm_strength(nil))
        assert_equal(0.4, Client.norm_strength(0.4))
        assert_equal(1.0, Client.norm_strength(1.0))
      end

      test 'client: workflow в generate не шлётся (klein: только auto)' do
        assert(Client.normalize_workflow('auto').nil?, 'auto должен стать nil')
        assert(Client.normalize_workflow('').nil?, 'пусто должен стать nil')
        assert(Client.normalize_workflow(nil).nil?, 'nil должен остаться nil')
        assert(Client.normalize_workflow('мусор').nil?, 'мусор должен стать nil')
        assert_equal('reference', Client.normalize_workflow('reference'), 'reference проходит')
        assert_equal('reference', Client.normalize_workflow('Reference'), 'регистр нормализуется')
        assert_equal('edit', Client.normalize_workflow('edit'), 'edit проходит')
        assert_equal('outpaint', Client.normalize_workflow('outpaint'), 'outpaint проходит')
        assert(Client.preset_for['workflow'].nil?, "preset workflow должен быть nil: #{Client.preset_for.inspect}")
        assert(Client::KLEIN_WORKFLOW.nil?, 'KLEIN_WORKFLOW должен быть nil')
      end

      test 'client: preset_for всегда klein 16/1.0 (другие модели не поддерживаются)' do
        klein = Client.preset_for('unsloth/flux-3-image-klein-GGUF')
        assert_equal(16, klein['steps'], "klein steps: #{klein.inspect}")
        assert_equal(1.0, klein['guidance'], "klein guidance: #{klein.inspect}")
        assert_equal('balanced', klein['memory_mode'], "klein memory: #{klein.inspect}")
        assert_equal(2048, klein['max_side'], "klein max_side: #{klein.inspect}")
        # даже чужой id даёт klein — выбор моделей убран
        other = Client.preset_for('Qwen-Image-GGUF', { 'steps' => 50, 'guidance' => 4.0 })
        assert_equal(16, other['steps'], "чужой id всё равно klein: #{other.inspect}")
        assert_equal(1.0, other['guidance'], "чужой id всё равно klein: #{other.inspect}")
        assert_equal(Client::KLEIN_REPO, 'unsloth/flux-3-image-klein-GGUF')
        assert_equal(Client::KLEIN_GGUF, 'flux-3-image-klein-UD-Q4_K_XL.gguf')
      end

      test 'только klein: coerce фиксирует модель/шаги' do
        assert_equal('unsloth/flux-3-image-klein-GGUF', Settings.coerce('unsloth_model', 'мусор'))
        assert_equal('flux-3-image-klein-UD-Q4_K_XL.gguf', Settings.coerce('unsloth_gguf', ''))
        # квант внутри klein-репо сохраняется (Q8_0 уже скачан в студии)
        assert_equal('flux-3-image-klein-Q8_0.gguf', Settings.coerce('unsloth_gguf', 'flux-3-image-klein-Q8_0.gguf'))
        assert_equal('flux-3-image-klein-Q6_K.gguf', Settings.coerce('unsloth_gguf', 'flux-3-image-klein-Q6_K.gguf'))
        assert_equal(30, Settings.coerce('steps', 50))
        assert_equal(1.0, Settings.coerce('guidance', 7.0))
        assert_equal('auto', Settings.coerce('workflow', 'manual'))
        assert_equal('auto', Settings.coerce('workflow', 'EDIT'))
        assert_equal('auto', Settings.coerce('workflow', 'reference'))
        assert_equal('auto', Settings.coerce('workflow', 'auto'))
        assert_equal('low_vram', Settings.coerce('memory_mode', 'low_vram'))
        assert_equal('balanced', Settings.coerce('memory_mode', 'мусор'))
        assert_equal('auto', Settings.coerce('memory_mode', 'auto'))
        assert_equal('fast', Settings.coerce('memory_mode', 'fast'))
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

      test 'gallery: финал сохраняется с сайдкаром параметров' do
        Dir.mktmpdir do |d|
          f = File.join(d, 'render_s0_seed7.jpg')
          File.binwrite(f, "\xFF\xD8\xFF".b + 'x' * 16)
          Gallery.save_sidecar(f, 'final',
                               { 'scene' => 0, 'seed' => 7, 'variant' => 1,
                                 'width' => 1024, 'height' => 768, 'prompt' => 'p',
                                 'steps' => 16 })
          sp = "#{f}.json"
          assert(File.file?(sp), 'сайдкар не записан')
          m = JSON.parse(File.read(sp, encoding: 'UTF-8'))
          assert_equal('final', m['kind'], 'вид в сайдкаре')
          assert_equal(7, m['seed'], 'seed в сайдкаре')
          assert_equal('p', m['prompt'], 'промпт в сайдкаре')
          list = Gallery.list(d)
          assert_equal(1, list.size, "список: #{list.inspect}")
          e = list.first
          assert_equal('final', e['kind'], 'вид в списке')
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

      test 'jobs: целевая длинная сторона по режиму' do
        assert_equal(1600, Jobs.final_long_side('sketch'))
        assert_equal(1024, Jobs.final_long_side('1k'))
        assert_equal(2048, Jobs.final_long_side('2k'))
        assert(Jobs.final_long_side('custom').nil?, 'custom считается отдельно')
        w, h = Client.scale_to_long(368, 256, Jobs.final_long_side('1k'))
        assert(w == 1024 && h >= 256, "1K: #{[w, h].inspect}")
        w, h = Client.scale_to_long(368, 256, Jobs.final_long_side('2k'))
        assert(w == 2048 && h >= 256, "2K: #{[w, h].inspect}")
      end

      test 'jobs: cancel несуществующей задачи — вежливый отказ' do
        r = Jobs.cancel('no-such-job')
        assert_equal(false, r[:ok])
      end

      test 'jobs: GVL-памп стартует один раз и останавливается' do
        Jobs.pump_stop
        assert_equal(false, Jobs.pump_active?, 'после stop неактивен')
        id1 = Jobs.pump_start
        assert(!id1.nil?, 'старт должен вернуть id таймера')
        assert_equal(true, Jobs.pump_active?, 'после start активен')
        id2 = Jobs.pump_start
        assert_equal(id1, id2, 'повторный старт — тот же таймер')
        Jobs.pump_stop
        assert_equal(false, Jobs.pump_active?, 'после stop неактивен')
        Jobs.pump_stop
        assert_equal(false, Jobs.pump_active?, 'двойной stop без ошибки')
      end

      test 'client: abort закрывает соединение задачи (реестр http_id)' do
        assert_equal(false, Client.abort('no-such-http'), 'пустой реестр — false')
        fake = Object.new
        finished = []
        fake.define_singleton_method(:finish) { finished << true }
        Client.register_http('j1', fake)
        assert_equal(true, Client.abort('j1'), 'живое соединение — true')
        assert_equal([true], finished, 'finish не вызван')
        assert_equal(false, Client.abort('j1'), 'повторный abort — false')
        Client.register_http('', fake)
        assert_equal(false, Client.abort(''), 'пустой id не регистрируется')
      end

      test 'client: generate снимает http с учёта после запроса (стаб)' do
        fake = Object.new
        fake.define_singleton_method(:request) { |_req| raise 'стоп-тест' }
        orig_api = Client.method(:api)
        Client.define_singleton_method(:api) { |_url| fake }
        begin
          begin
            Client.generate('http://127.0.0.1:9', 'k', nil, prompt: 'p', width: 256, height: 256,
                            http_id: 'reg-test')
            assert(false, 'generate должен был дойти до HTTP')
          rescue RuntimeError => e
            raise unless e.message == 'стоп-тест'
          end
        ensure
          Client.define_singleton_method(:api, orig_api)
        end
        assert_equal(false, Client.abort('reg-test'), 'соединение осталось в реестре после запроса')
      end

      test 'log: append/tail/clear через временный файл' do
        require 'tmpdir'
        Dir.mktmpdir do |d|
          Log.path_override = File.join(d, 't.log')
          begin
            Log.append('job_start', 'id' => 'j1', 'kind' => 'final')
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

      test 'mixins: clear удаляет все примеси' do
        Dir.mktmpdir do |d|
          out = File.join(d, 'out')
          require 'base64'
          url = "data:image/png;base64,#{Base64.strict_encode64("\x89PNG\r\n\x1A\n".b + 'x' * 16)}"
          Mixins.add_data(url, 'а.png', out)
          Mixins.add_data(url, 'б.png', out)
          r = Mixins.clear(out)
          assert(r[:ok], 'clear не ok')
          assert_equal(2, r[:deleted], "счётчик: #{r.inspect}")
          assert_equal([], Mixins.list(out), 'список после clear не пуст')
          leftovers = Dir.children(File.join(out, 'mixins')).reject { |n| n.end_with?('.json') }
          assert_equal([], leftovers, 'картинки примесей остались')
          assert_equal(0, Mixins.clear(out)[:deleted], 'повторный clear — 0')
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

      test 'эскиз-референс: настройки съёма по умолчанию и coerce' do
        assert_equal('hd', Settings::DEFAULTS['sketch_source'], 'дефолт sketch_source')
        assert_equal('1600x1200', Settings::DEFAULTS['sketch_preset'], 'дефолт sketch_preset')
        assert_equal('model', Settings::DEFAULTS['sketch_style'], 'дефолт sketch_style')
        assert_equal(Settings::SKETCH_PRESETS, %w[1200x900 1600x1200 2000x1500], 'только 1200/1600/2000')
        assert_equal(true, Settings::DEFAULTS['sketch_thin_lines'], 'дефолт thin_lines')
        assert_equal(true, Settings::DEFAULTS['sketch_hide_dims'], 'дефолт hide_dims')
        assert_equal(false, Settings::DEFAULTS['sketch_white_bg'], 'дефолт white_bg выкл')
        assert_equal(false, Settings::DEFAULTS['sketch_no_shadows'], 'дефолт no_shadows выкл')
        assert(Settings::PROJECT_KEYS.include?('sketch_source'), 'sketch_source должен быть per-file')
        assert(Settings::PROJECT_KEYS.include?('sketch_style'), 'sketch_style должен быть per-file')
        assert(Settings::PROJECT_KEYS.include?('sketch_no_shadows'), 'sketch_no_shadows должен быть per-file')
        assert_equal('view', Settings.coerce('sketch_source', 'view'))
        assert_equal('preset', Settings.coerce('sketch_source', 'preset'))
        assert_equal('hd', Settings.coerce('sketch_source', 'мусор'), 'мусор — hd')
        assert_equal('1600x1200', Settings.coerce('sketch_preset', '1600x1200'))
        assert_equal('1600x1200', Settings.coerce('sketch_preset', '1024x768'), 'старый пресет — дефолт')
        assert_equal('1600x1200', Settings.coerce('sketch_preset', 'мусор'), 'чужой пресет — дефолт')
        assert_equal('white', Settings.coerce('sketch_style', 'white'))
        assert_equal('custom', Settings.coerce('sketch_style', 'custom'))
        assert_equal('model', Settings.coerce('sketch_style', 'мусор'), 'чужой стиль — model')
        assert_equal(false, Settings.coerce('sketch_thin_lines', false))
        assert_equal(true, Settings.coerce('sketch_hide_dims', 'true'))
        assert_equal(true, Settings.coerce('sketch_no_shadows', 'true'))
        assert_equal(false, Settings.coerce('sketch_no_shadows', '0'))
        assert_equal(false, Settings::DEFAULTS['sketch_autocrop'], 'дефолт autocrop выкл')
        assert(Settings::PROJECT_KEYS.include?('sketch_autocrop'), 'sketch_autocrop должен быть per-file')
        assert_equal(true, Settings.coerce('sketch_autocrop', true))
        assert_equal(false, Settings.coerce('sketch_autocrop', '0'))
      end

      test 'эскиз-референс: capture/capture_all принимают параметры съёма' do
        assert(Scenes.method(:capture).parameters.include?([:key, :thin_lines]), 'у capture нет thin_lines:')
        assert(Scenes.method(:capture).parameters.include?([:key, :hide_dims]), 'у capture нет hide_dims:')
        assert(Scenes.method(:capture).parameters.include?([:key, :white_bg]), 'у capture нет white_bg:')
        assert(Scenes.method(:capture).parameters.include?([:key, :no_shadows]), 'у capture нет no_shadows:')
        assert(Scenes.method(:capture_all).parameters.include?([:key, :sketch]), 'у capture_all нет sketch:')
        assert(Scenes.method(:capture_hd).parameters.include?([:key, :no_shadows]), 'у capture_hd нет no_shadows:')
        assert(Scenes.method(:thumbnail).parameters.include?([:key, :no_shadows]), 'у thumbnail нет no_shadows:')
        assert(Scenes.method(:with_dims_hidden).parameters.include?([:key, :hide_dims]), 'у with_dims_hidden нет hide_dims:')
        assert(Scenes.method(:with_dims_hidden).parameters.include?([:key, :no_shadows]), 'у with_dims_hidden нет no_shadows:')
      end

      test 'проект: yaml-хранилище и переезд со старого su2vis.json' do
        Dir.mktmpdir do |d|
          proj = File.join(d, 'house_su2vis')
          FileUtils.mkdir_p(proj)
          File.write(File.join(proj, 'su2vis.json'), JSON.generate({ 'prompt' => 'из json', 'sketch_preset' => '800x600' }), encoding: 'UTF-8')
          assert_equal('ready', Settings.project_state(proj), 'старый json — тоже ready')
          back = Settings.all(proj)
          assert_equal('из json', back['prompt'], 'all читает старый json')
          assert_equal('1600x1200', back['sketch_preset'], 'старый пресет нормализуется в дефолт')
          Settings.save({ 'prompt' => 'новый' }, proj)
          assert(File.file?(File.join(proj, 'su2vis.yaml')), 'запись переехала в yaml')
          yaml_text = File.read(File.join(proj, 'su2vis.yaml'), encoding: 'UTF-8')
          assert(yaml_text.include?('новый'), 'yaml содержит новое значение')
          assert_equal('новый', Settings.read_project_doc(proj)['prompt'], 'yaml читается обратно')
          assert_equal('новый', Settings.all(proj)['prompt'], 'all читает yaml')
        end
      end

      test 'проект: бэкап рамок сцен в yaml переживает выход' do
        Dir.mktmpdir do |d|
          proj = File.join(d, 'house_su2vis')
          assert_equal([], Settings.scene_boxes_backup(nil, 0), 'nil-папка — пусто')
          assert_equal([], Settings.scene_boxes_backup(proj, 3), 'нет файла — пусто')
          boxes = [{ 'x' => 0.1, 'y' => 0.2, 'w' => 0.3, 'h' => 0.4, 'label' => 'диван' }]
          Settings.save_scene_boxes_backup(proj, 3, boxes)
          assert(File.file?(File.join(proj, 'su2vis.yaml')), 'бэкап создал yaml')
          got = Settings.scene_boxes_backup(proj, 3)
          assert_equal(boxes, got, 'бэкап вернулся')
          assert_equal([], Settings.scene_boxes_backup(proj, 4), 'чужая сцена — пусто')
          assert_equal('ready', Settings.project_state(proj), 'один бэкап — проект ready')
          Settings.save_scene_boxes_backup(proj, 3, [])
          assert_equal([], Settings.scene_boxes_backup(proj, 3), 'очистка стирает бэкап')
        end
      end

      test 'автокроп: рамка контента на синтетике и roundtrip' do
        require 'zlib'
        bg = [200, 200, 200]
        mk = lambda do |w, h, fg|
          raw = +''.b
          h.times do |yy|
            raw << 0.chr
            w.times do |xx|
              inside = fg && xx >= fg[0] && xx < fg[0] + fg[2] && yy >= fg[1] && yy < fg[1] + fg[3]
              raw << (inside ? [40, 40, 40] : bg).pack('C3')
            end
          end
          chunk = lambda do |type, data|
            d = data.b
            [d.bytesize].pack('N') + type + d + [Zlib.crc32(type + d)].pack('N')
          end
          "\x89PNG\r\n\x1A\n".b + chunk.call('IHDR', [w, h, 8, 2, 0, 0, 0].pack('NNC5')) +
            chunk.call('IDAT', Zlib.deflate(raw)) + chunk.call('IEND', '')
        end
        pic = mk.call(64, 48, [10, 8, 30, 20])
        assert_equal([10, 8, 30, 20], Scenes.content_bbox(pic), 'рамка контента')
        assert(Scenes.content_bbox(mk.call(32, 32, nil)).nil?, 'пустой кадр — nil')
        assert(Scenes.png_pixels('мусор'.b).nil?, 'мусор — nil')
        assert(Scenes.crop_png(pic, [-1, 0, 10, 10]).nil?, 'кроп мимо кадра — nil')
        out = Scenes.crop_png(pic, [10, 8, 30, 20])
        dec = Scenes.png_pixels(out)
        assert_equal([30, 20], [dec[:w], dec[:h]], 'размер кропа')
        assert_equal([40, 40, 40], dec[:rows][0][0, 3], 'контент на месте')
        Dir.mktmpdir do |d|
          f = File.join(d, 'sk.png')
          File.binwrite(f, pic)
          assert_equal(f, Scenes.maybe_autocrop(f, false), 'выкл — тот же путь')
          got = Scenes.autocrop(f, 0.05)
          assert_equal(f, got, 'тот же путь после кропа')
          # поля 5%: mx=2, my=1 -> [8, 7, 34, 22]
          assert_equal([34, 22], Scenes.dims(f), "размер с полями: #{Scenes.dims(f).inspect}")
        end
      end

      test 'scenes: превью — размер задаёт фронт, thumbnail санитизирует' do
        assert_equal(800, Scenes::THUMB_W)
        assert_equal(600, Scenes::THUMB_H)
        assert_equal(1_600, Scenes::THUMB_MAX)
        assert_equal(800, Scenes.thumb_dim(nil, Scenes::THUMB_W))
        assert_equal(600, Scenes.thumb_dim('мусор', Scenes::THUMB_H))
        assert_equal(650, Scenes.thumb_dim('650', Scenes::THUMB_W))
        assert_equal(1_600, Scenes.thumb_dim(9_999, Scenes::THUMB_W))
        assert_equal(nil, Settings::DEFAULTS['preview_size'], 'preview_size должен быть удалён из настроек')
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

      test 'gallery: старые preview_ файлы игнорируются' do
        Dir.mktmpdir do |d|
          File.binwrite(File.join(d, 'preview_s0_seed7.png'), "\x89PNG\r\n\x1A\n".b + 'x' * 16)
          File.binwrite(File.join(d, 'render.jpg'), "\xFF\xD8\xFF".b + 'x' * 16)
          list = Gallery.list(d)
          assert_equal(1, list.size, "список: #{list.inspect}")
          assert_equal('final', list.first['kind'], 'вид в списке')
        end
      end

      test 'gallery: clear удаляет финалы и сироты, preview_ и лог не трогает' do
        Dir.mktmpdir do |d|
          f1 = File.join(d, 'render_a.jpg')
          File.binwrite(f1, "\xFF\xD8\xFF".b + 'x' * 16)
          Gallery.save_sidecar(f1, 'final', { 'scene' => 0, 'seed' => 1 })
          f2 = File.join(d, 'old_final.png')
          File.binwrite(f2, "\x89PNG\r\n\x1A\n".b + 'x' * 16)
          prev = File.join(d, 'preview_old.png')
          File.binwrite(prev, "\x89PNG\r\n\x1A\n".b + 'x' * 16)
          log = File.join(d, 'su2vis.log')
          File.write(log, '{}')
          r = Gallery.clear(d)
          assert(r[:ok], 'clear не ok')
          assert_equal(2, r[:deleted], "счётчик: #{r.inspect}")
          assert(!File.exist?(f1) && !File.exist?("#{f1}.json"), 'финал с сайдкаром остался')
          assert(!File.exist?(f2), 'сирота осталась')
          assert(File.exist?(prev), 'preview_ не должен удаляться')
          assert(File.exist?(log), 'лог не должен удаляться')
          assert_equal([], Gallery.list(d), 'список после clear не пуст')
          assert_equal(0, Gallery.clear(d)[:deleted], 'повторный clear — 0')
        end
      end

      test 'gallery: unique_path не даёт перезаписать файл или сайдкар' do
        Dir.mktmpdir do |d|
          assert_equal(File.join(d, 'a.jpg'), Gallery.unique_path(d, 'a', '.jpg'), 'свободное имя')
          File.binwrite(File.join(d, 'a.jpg'), 'x')
          assert_equal(File.join(d, 'a_2.jpg'), Gallery.unique_path(d, 'a', '.jpg'), 'файл занят → _2')
          File.write(File.join(d, 'a_2.jpg.json'), '{}')
          assert_equal(File.join(d, 'a_3.jpg'), Gallery.unique_path(d, 'a', '.jpg'), 'сайдкар занял _2 → _3')
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

      test 'enhance: старт мгновенный, опрос доводит до done (стаб-воркер)' do
        assert(Enhance.respond_to?(:start), 'нет Enhance.start')
        assert(Enhance.respond_to?(:poll), 'нет Enhance.poll')
        prev_worker = Enhance.worker
        Enhance.worker = ->(_url, _key, _prompt, _ref) { 'капшн-стаб' }
        begin
          t0 = Time.now
          task = Enhance.start('http://127.0.0.1:9', 'k', 'промпт', 'ref')
          assert(Time.now - t0 < 5, 'старт должен вернуться сразу, без сети')
          assert_equal('running', task['status'], 'старт — running')
          assert(!task['id'].to_s.empty?, 'нет id задачи')
          done = nil
          100.times do
            done = Enhance.poll(task['id'])
            break if done['status'] != 'running'
            sleep 0.05
          end
          assert_equal('done', done['status'], "задача не done: #{done.inspect}")
          assert_equal('капшн-стаб', done['text'], 'текст воркера потерян')
        ensure
          Enhance.worker = prev_worker
        end
      end

      test 'enhance: ошибка воркера — статус error, чужой id — вежливый отказ' do
        prev_worker = Enhance.worker
        Enhance.worker = ->(_url, _key, _prompt, _ref) { raise 'студия упала' }
        begin
          task = Enhance.start('http://127.0.0.1:9', 'k', 'p', '')
          err = nil
          100.times do
            err = Enhance.poll(task['id'])
            break if err['status'] != 'running'
            sleep 0.05
          end
          assert_equal('error', err['status'], "статус не error: #{err.inspect}")
          assert(err['error'].to_s.include?('студия упала'), "текст ошибки потерян: #{err.inspect}")
        ensure
          Enhance.worker = prev_worker
        end
        miss = Enhance.poll('no-such-enhance')
        assert_equal('error', miss['status'], 'чужой id должен дать error')
      end

      test 'студия: дефолты автозапуска и coerce' do
        assert_equal(true, Settings::DEFAULTS['unsloth_autostart'], 'дефолт autostart')
        assert_equal('unsloth', Settings::DEFAULTS['unsloth_cmd'], 'дефолт cmd')
        assert_equal(true, Settings.coerce('unsloth_autostart', true))
        assert_equal(false, Settings.coerce('unsloth_autostart', 'false'))
        assert_equal(true, Settings.coerce('unsloth_autostart', 'true'))
        assert_equal('unsloth', Settings.coerce('unsloth_cmd', ''))
        assert_equal('unsloth', Settings.coerce('unsloth_cmd', nil))
        assert_equal('C:/tools/unsloth.exe', Settings.coerce('unsloth_cmd', 'C:/tools/unsloth.exe'))
      end

      test 'студия: parse_host_port и headless-команда' do
        assert_equal(['127.0.0.1', 8888], Studio.parse_host_port('http://127.0.0.1:8888'))
        assert_equal(['192.168.1.5', 9999], Studio.parse_host_port('http://192.168.1.5:9999'))
        assert_equal(['127.0.0.1', 8888], Studio.parse_host_port('мусор'))
        assert_equal('unsloth studio --api-only -H 127.0.0.1 -p 8888',
                     Studio.command('http://127.0.0.1:8888', 'unsloth'))
        assert_equal('unsloth studio --api-only -H 127.0.0.1 -p 8888',
                     Studio.command('http://127.0.0.1:8888', ''))
        assert_equal('"C:/my tools/unsloth.exe" studio --api-only -H 127.0.0.1 -p 8888',
                     Studio.command('http://127.0.0.1:8888', 'C:/my tools/unsloth.exe'))
      end

      test 'студия: живой сервер не спавнит процесс' do
        orig_reachable = Studio.method(:reachable?)
        orig_status = Client.method(:status)
        spawned = []
        Studio.spawner = ->(cmd) { spawned << cmd; true }
        Studio.reset_state!
        Studio.define_singleton_method(:reachable?) { |_url| true }
        Client.define_singleton_method(:status) { |_url, _key| { 'loaded' => true } }
        begin
          res = Studio.ensure_running!('http://127.0.0.1:8888', 'k', 'unsloth', 5)
          assert_equal(true, res[:ok], "результат: #{res.inspect}")
          assert_equal(true, res[:already], 'должен признать уже запущенную')
          assert(spawned.empty?, "спавн при живом сервере: #{spawned.inspect}")
          assert_equal('running', Studio.state['status'], 'состояние running')
        ensure
          Studio.define_singleton_method(:reachable?, orig_reachable)
          Client.define_singleton_method(:status, orig_status)
          Studio.spawner = nil
          Studio.reset_state!
        end
      end

      test 'студия: ensure_async мгновенный, дубль не стартует' do
        orig_running = Studio.method(:ensure_running!)
        calls = []
        Studio.define_singleton_method(:ensure_running!) do |*args|
          calls << args
          sleep 0.3
          { ok: true, already: false, state: Studio.state }
        end
        Studio.reset_state!
        begin
          t0 = Time.now
          first = Studio.ensure_async('http://127.0.0.1:8888', 'k', 'unsloth', 5)
          assert(Time.now - t0 < 5, 'ensure_async должен вернуться сразу')
          assert_equal(true, first[:ok], "первый: #{first.inspect}")
          second = Studio.ensure_async('http://127.0.0.1:8888', 'k', 'unsloth', 5)
          assert_equal(false, second[:started], "дубль при живом потоке: #{second.inspect}")
          sleep 0.5
          assert_equal(1, calls.size, "потоков должно быть один: #{calls.size}")
        ensure
          Studio.define_singleton_method(:ensure_running!, orig_running)
          Studio.reset_state!
        end
      end

      test 'точность линий: замок геометрии дописывается один раз' do
        assert_equal(true, Settings::DEFAULTS['geometry_lock'], 'дефолт замка')
        assert_equal(false, Settings.coerce('geometry_lock', false))
        assert_equal(true, Settings.coerce('geometry_lock', 'true'))
        assert(Settings::PROJECT_KEYS.include?('geometry_lock'), 'geometry_lock должен быть per-file')
        base = 'modern kitchen'
        locked = Client.apply_geometry_lock(base, true)
        assert(locked.include?(base), 'исходный промпт потерян')
        assert(locked.include?(Client::GEOMETRY_LOCK_TEXT), 'замок не дописан')
        assert_equal(locked, Client.apply_geometry_lock(locked, true), 'двойной замок')
        assert_equal(base, Client.apply_geometry_lock(base, false), 'выкл — без дописки')
        assert_equal(Client::GEOMETRY_LOCK_TEXT, Client.apply_geometry_lock('', true), 'пустой промпт — один замок')
      end

      test 'точность линий: auto шлёт strength, reference без strength, edit запрещён' do
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
            sk = File.join(d, 'sk.png')
            File.binwrite(sk, "\x89PNG\r\n\x1A\n".b + 'x' * 16)
            gen = lambda do |**kw|
              begin
                Client.generate('http://127.0.0.1:9', 'k', sk, prompt: 'kitchen', width: 256, height: 256, **kw)
              rescue RuntimeError => e
                raise unless e.message == 'стоп-тест'
              end
            end
            gen.call(geometry_lock: true, strength: 0.4)
            gen.call(workflow: 'reference', geometry_lock: true, strength: 0.4)
            begin
              gen.call(workflow: 'edit')
              assert(false, 'edit должен упасть до HTTP')
            rescue ArgumentError => e
              assert(e.message.include?('klein'), "не то сообщение: #{e.message}")
            end
          end
        ensure
          Client.define_singleton_method(:api, orig_api)
        end
        auto, ref = bodies
        assert(!auto.key?('workflow'), "auto шлёт workflow: #{auto.inspect}")
        assert_equal(0.4, auto['strength'], 'strength не ушёл в студию в auto')
        assert(auto['prompt'].include?(Client::GEOMETRY_LOCK_TEXT), 'замок не ушёл в студию')
        assert_equal('reference', ref['workflow'], "workflow потерян: #{ref.inspect}")
        assert(!ref.key?('strength'), "reference со strength — студия 400: #{ref.inspect}")
      end

      test 'примеси: дефолты новых карточек из настроек колонки' do
        assert_equal('auto', Settings::DEFAULTS['mixins_default_role'], 'дефолт роли')
        assert_equal('both', Settings::DEFAULTS['mixins_default_apply'], 'дефолт учёта')
        assert(Settings::PROJECT_KEYS.include?('mixins_default_role'), 'mixins_default_role должен быть per-file')
        assert(Settings::PROJECT_KEYS.include?('mixins_default_apply'), 'mixins_default_apply должен быть per-file')
        assert_equal('material', Settings.coerce('mixins_default_role', 'material'))
        assert_equal('auto', Settings.coerce('mixins_default_role', 'мусор'))
        assert_equal('final', Settings.coerce('mixins_default_apply', 'preview'))
        assert_equal('final', Settings.coerce('mixins_default_apply', 'FINAL'))
        assert_equal('both', Settings.coerce('mixins_default_apply', 'мусор'))
      end

      test 'примеси: save_bytes подставляет дефолты роли и учёта' do
        old_role = Settings.get('mixins_default_role')
        old_apply = Settings.get('mixins_default_apply')
        begin
          Settings.save({ 'mixins_default_role' => 'material', 'mixins_default_apply' => 'final' })
          Dir.mktmpdir do |d|
            out = File.join(d, 'out')
            raw = "\x89PNG\r\n\x1A\n".b + 'x' * 16
            require 'base64'
            url = "data:image/png;base64,#{Base64.strict_encode64(raw)}"
            e = Mixins.add_data(url, 'тест.png', out)
            assert_equal('material', e['role'], 'роль не из настроек колонки')
            assert_equal('final', e['apply_to'], 'учёт не из настроек колонки')
            list = Mixins.list(out)
            assert_equal(1, list.size, "список: #{list.inspect}")
            assert_equal('material', list.first['role'], 'роль не в списке')
            assert_equal('final', list.first['apply_to'], 'учёт не в списке')
          end
        ensure
          Settings.save({ 'mixins_default_role' => old_role, 'mixins_default_apply' => old_apply })
        end
      end

      test 'рендер: случайные сиды батча, не по порядку' do
        assert_equal(true, Settings::DEFAULTS['preview_random_seeds'], 'дефолт — случайные')
        assert(Settings::PROJECT_KEYS.include?('preview_random_seeds'), 'preview_random_seeds должен быть per-file')
        assert_equal(false, Settings.coerce('preview_random_seeds', false))
        assert_equal(true, Settings.coerce('preview_random_seeds', 'true'))
        assert_equal([7, 8, 9], Jobs.batch_seed_list(7, 3, false), 'выкл — по порядку')
        assert_equal([7, 8, 9], Jobs.batch_seed_list(7, 3, nil), 'nil — по порядку')
        assert_equal([5], Jobs.batch_seed_list(5, 1, false), 'одиночный выкл — базовый сид')
        one = Jobs.batch_seed_list(5, 1, true)
        assert_equal(1, one.size, 'одиночный батч')
        assert(one.first.is_a?(Integer) && one.first >= 0 && one.first < 2_147_483_647, "сид вне диапазона: #{one.inspect}")
        rnd = Jobs.batch_seed_list(7, 4, true)
        assert_equal(4, rnd.size, 'батч из 4')
        assert(rnd.all? { |s| s.is_a?(Integer) && s >= 0 && s < 2_147_483_647 }, "сиды вне диапазона: #{rnd.inspect}")
      end

      test 'панель: enhance опрашивается (enhance_poll в сборке)' do
        html = File.join(__dir__, '..', 'resources', 'panel.html')
        skip('нет собранной панели') unless File.file?(html)
        content = File.read(html, encoding: 'UTF-8')
        assert(content.include?('enhance_poll'), 'panel.html без опроса enhance — устаревшая сборка')
      end

      test 'steps: дефолт 16, coerce 8..30' do
        assert_equal(16, Settings::DEFAULTS['steps'])
        assert(Settings::PROJECT_KEYS.include?('steps'), 'steps должен быть per-file')
        assert_equal(8, Settings.coerce('steps', 0))
        assert_equal(8, Settings.coerce('steps', nil))
        assert_equal(30, Settings.coerce('steps', 99))
        assert_equal(20, Settings.coerce('steps', 20))
      end

      test 'advanced load-time: дефолты и coerce' do
        assert_equal('auto', Settings::DEFAULTS['studio_precision'])
        assert_equal('default', Settings::DEFAULTS['studio_text_encoder_precision'])
        assert_equal('auto', Settings::DEFAULTS['studio_attention'])
        assert_equal('auto', Settings::DEFAULTS['studio_engine'])
        assert_equal('auto', Settings::DEFAULTS['studio_speed'])
        assert_equal('auto', Settings::DEFAULTS['studio_step_cache'])
        assert_equal(true, Settings::DEFAULTS['studio_cpu_offload'])
        assert_equal(true, Settings::DEFAULTS['studio_live_preview'])
        assert_equal('fp16', Settings.coerce('studio_precision', 'FP16'))
        assert_equal('auto', Settings.coerce('studio_precision', 'мусор'))
        assert_equal('int8', Settings.coerce('studio_text_encoder_precision', 'INT8'))
        assert_equal('default', Settings.coerce('studio_text_encoder_precision', 'мусор'))
        assert_equal('cudnn', Settings.coerce('studio_attention', 'cuDNN'))
        assert_equal('auto', Settings.coerce('studio_attention', 'мусор'))
        assert_equal('diffusers', Settings.coerce('studio_engine', 'diffusers'))
        assert_equal('auto', Settings.coerce('studio_engine', 'мусор'))
        assert_equal('fast', Settings.coerce('studio_speed', 'fast'))
        assert_equal('auto', Settings.coerce('studio_speed', 'мусор'))
        assert_equal('on', Settings.coerce('studio_step_cache', 'on'))
        assert_equal('auto', Settings.coerce('studio_step_cache', 'мусор'))
        assert_equal(false, Settings.coerce('studio_cpu_offload', false))
        assert_equal(true, Settings.coerce('studio_cpu_offload', 'true'))
        assert_equal(false, Settings.coerce('studio_live_preview', 'false'))
      end

      test 'client: build_load_body шлёт только не-auto тюнинг' do
        b = Client.build_load_body('repo', 'f.gguf', 'balanced', {})
        assert_equal('repo', b[:model_path])
        assert_equal('balanced', b[:memory_mode])
        assert(!b.key?(:precision), "пустые opts не должны слать precision: #{b.inspect}")
        assert(!b.key?(:cpu_offload), "без флага не шлём cpu_offload: #{b.inspect}")
        b2 = Client.build_load_body('repo', 'f.gguf', 'low_vram',
                                    { 'studio_precision' => 'fp16', 'studio_attention' => 'cudnn',
                                      'studio_cpu_offload' => false, 'studio_step_cache' => 'auto' })
        assert_equal('fp16', b2[:precision])
        assert_equal('cudnn', b2[:attention])
        assert_equal(false, b2[:cpu_offload])
        assert(!b2.key?(:step_cache), "auto step_cache не шлём: #{b2.inspect}")
      end

      test 'boxes: norm_boxes чистит мусор и режет до 12' do
        assert_equal([], Scenes.norm_boxes(nil), 'nil — пусто')
        assert_equal([], Scenes.norm_boxes('мусор'), 'строка — пусто')
        assert_equal([], Scenes.norm_boxes([{ 'x' => 0.1, 'y' => 0.1, 'w' => 0, 'h' => 0.5 }]), 'нулевой ширины — долой')
        b = Scenes.norm_boxes([{ 'x' => -0.5, 'y' => 0.2, 'w' => 2, 'h' => 0.1, 'label' => '  остров  ' }])
        assert_equal([{ 'x' => 0.0, 'y' => 0.2, 'w' => 1.0, 'h' => 0.1, 'label' => 'остров' }], b, 'кламп и trim')
        sym = Scenes.norm_boxes([{ x: 0.1, y: 0.2, w: 0.3, h: 0.1, label: 's' }])
        assert_equal(0.1, sym.first['x'], 'символьные ключи')
        many = Array.new(20) { |i| { 'x' => 0.0, 'y' => 0.0, 'w' => 0.1, 'h' => 0.1, 'label' => i.to_s } }
        assert_equal(Scenes::BOXES_MAX, Scenes.norm_boxes(many).size, 'лимит боксов')
      end

      test 'boxes: boxes_prompt нумерует по позиции, пустые подписи пропускает' do
        assert_equal('', Scenes.boxes_prompt([]), 'пусто — пусто')
        assert_equal('', Scenes.boxes_prompt([{ 'x' => 0, 'y' => 0, 'w' => 0.5, 'h' => 0.5, 'label' => '  ' }]), 'без подписи — пусто')
        got = Scenes.boxes_prompt([
                                   { 'x' => 0, 'y' => 0, 'w' => 0.5, 'h' => 0.5, 'label' => 'остров' },
                                   { 'x' => 0, 'y' => 0, 'w' => 0.5, 'h' => 0.5, 'label' => '' },
                                   { 'x' => 0, 'y' => 0, 'w' => 0.5, 'h' => 0.5, 'label' => 'шкаф' }
                                 ])
        assert(got.include?('Red box 1: остров.'), "бокс 1: #{got.inspect}")
        assert(!got.include?('Red box 2'), 'бокс без подписи попал в текст')
        assert(got.include?('Red box 3: шкаф.'), 'нумерация по позиции массива')
      end

      test 'boxes: draw_boxes_png рисует рамки и бейдж, annotated_sketch кэширует' do
        require 'zlib'
        w, h = 200, 100
        raw = +''.b
        h.times do
          raw << 0.chr
          w.times { raw << [235, 235, 235].pack('C3') }
        end
        chunk = lambda do |type, data|
          d = data.b
          [d.bytesize].pack('N') + type + d + [Zlib.crc32(type + d)].pack('N')
        end
        png = "\x89PNG\r\n\x1A\n".b + chunk.call('IHDR', [w, h, 8, 2, 0, 0, 0].pack('NNC5')) +
              chunk.call('IDAT', Zlib.deflate(raw)) + chunk.call('IEND', '')
        assert(Scenes.draw_boxes_png(png, []).nil?, 'нет боксов — nil')
        assert(Scenes.draw_boxes_png('мусор'.b, [{ 'x' => 0, 'y' => 0, 'w' => 0.5, 'h' => 0.5 }]).nil?, 'не PNG — nil')
        bs = [{ 'x' => 0.1, 'y' => 0.1, 'w' => 0.5, 'h' => 0.5, 'label' => 'остров' }]
        out = Scenes.draw_boxes_png(png, bs)
        dec = Scenes.png_pixels(out)
        assert_equal([200, 100], [dec[:w], dec[:h]], 'размер сохранился')
        px = ->(x, y) { dec[:rows][y][x * 3, 3] }
        assert_equal(Scenes::BOX_COLOR, px.call(30, 10), 'верхняя граница рамки (y=10)')
        assert_equal(Scenes::BOX_COLOR, px.call(20, 30), 'левая граница рамки (x=20)')
        assert_equal(Scenes::BOX_COLOR, px.call(100, 59), 'нижняя граница рамки (y1=60)')
        assert_equal([235, 235, 235], px.call(40, 40), 'внутри контура — фон не закрашен')
        # бейдж: левый верхний угол рамки — белый фон, чёрная цифра «1»
        assert_equal([255, 255, 255], px.call(28, 20), 'бейдж белый (правее цифры)')
        assert_equal(Scenes::BADGE_FG, px.call(24, 13), 'цифра номера чёрная')
        # annotated_sketch: пишет файл, кэш на второй вызов
        Dir.mktmpdir do |d|
          src = File.join(d, 'scene_0.png')
          File.binwrite(src, png)
          got = Scenes.annotated_sketch(src, bs)
          assert(!got.nil? && got != src, 'аннотированная копия не создана')
          assert(File.file?(got), 'файл копии не записан')
          assert_equal(got, Scenes.annotated_sketch(src, bs), 'кэш не сработал')
          assert_equal(src, Scenes.annotated_sketch(src, []), 'пустые боксы — исходный путь')
          assert_equal('', Scenes.annotated_sketch('', bs), 'пустой путь — пусто без падения')
        end
      end

      test 'boxes: mixins хранят боксы в сайдкаре и прокидывают в задачу' do
        Dir.mktmpdir do |d|
          out = File.join(d, 'out')
          raw = "\x89PNG\r\n\x1A\n".b + 'x' * 16
          require 'base64'
          url = "data:image/png;base64,#{Base64.strict_encode64(raw)}"
          e = Mixins.add_data(url, 'с_боксами.png', out)
          bs = [{ 'x' => 0.1, 'y' => 0.1, 'w' => 0.4, 'h' => 0.4, 'label' => 'фактура' }]
          u = Mixins.update(e['id'], boxes: bs, dir: out)
          assert_equal(bs, u['boxes'], 'боксы не сохранились')
          list = Mixins.list(out)
          assert_equal(bs, list.first['boxes'], 'боксы в списке')
          got = Mixins.active_for_job([{ 'path' => e['file'], 'caption' => 'x', 'active' => true, 'boxes' => bs }])
          assert_equal(bs, got.first['boxes'], 'боксы в задаче')
          got2 = Mixins.active_for_job([{ 'path' => e['file'], 'caption' => 'x', 'active' => true, 'boxes' => [{ 'x' => 5, 'y' => 5, 'w' => 0, 'h' => 0 }] }])
          assert_equal([], got2.first['boxes'], 'мусорные боксы не выжили')
          u2 = Mixins.update(e['id'], dir: out)
          assert_equal(bs, u2['boxes'], 'update без boxes: не должен затирать')
          u3 = Mixins.update(e['id'], boxes: [], dir: out)
          assert_equal([], u3['boxes'], 'сброс боксов пустым массивом')
          doc = JSON.parse(File.read("#{e['file']}.json", encoding: 'UTF-8'))
          assert_equal([], doc['boxes'], 'пустой массив в сайдкаре')
        end
      end

      test 'boxes: mixins annotated_job_path — сбой рисовалки даёт исходный путь, успех — кэш' do
        Dir.mktmpdir do |d|
          small = File.join(d, 'm.png')
          File.binwrite(small, "\x89PNG\r\n\x1A\n".b + "\x00\x00\x00\x0D".b + 'IHDR'.b +
                        [100].pack('N') + [100].pack('N') + ("\x00".b * 64))
          bs = [{ 'x' => 0.1, 'y' => 0.1, 'w' => 0.5, 'h' => 0.5, 'label' => 'x' }]
          # фолбэк без боксов: путь как есть
          assert_equal([small, false], Mixins.annotated_job_path(small, nil, nil, []), 'без боксов — false')
          # стаб сбоя PowerShell: [путь, false]
          orig = Mixins.method(:try_powershell_boxes)
          Mixins.define_singleton_method(:try_powershell_boxes) { |_p, _e, _d, _b| nil }
          begin
            got = Mixins.annotated_job_path(small, nil, nil, bs)
            assert_equal([small, false], got, 'сбой рисовалки — исходный путь и false')
          ensure
            Mixins.define_singleton_method(:try_powershell_boxes, orig)
          end
          # стаб успеха: рисованый PNG попадает в кэш
          fake_png = "\x89PNG\r\n\x1A\n".b + 'ok'
          Mixins.define_singleton_method(:try_powershell_boxes) { |_p, _e, _d, _b| fake_png }
          begin
            got2 = Mixins.annotated_job_path(small, nil, nil, bs)
            assert(got2[1], 'успех должен дать true')
            assert(got2[0] != small, 'успех должен дать другой путь')
            assert_equal(fake_png, File.binread(got2[0]), 'в кэше не то, что вернул рисователь')
            assert_equal(got2, Mixins.annotated_job_path(small, nil, nil, bs), 'кэш аннотации не сработал')
          ensure
            Mixins.define_singleton_method(:try_powershell_boxes, orig)
          end
          # webp: рисовалка не умеет — заранее false
          webp = File.join(d, 'm.webp')
          File.binwrite(webp, 'RIFF'.b + [18].pack('V') + 'WEBP'.b + 'VP8 '.b + [10].pack('V') + "\x00".b * 10)
          assert_equal([webp, false], Mixins.annotated_job_path(webp, nil, nil, bs), 'webp без рамок')
        end
      end

      test 'boxes: mixins_prompt описывает рамки, boxes_ok=false глушит' do
        bs = [{ 'x' => 0.1, 'y' => 0.1, 'w' => 0.4, 'h' => 0.4, 'label' => 'фактура кирпича' },
              { 'x' => 0.5, 'y' => 0.5, 'w' => 0.2, 'h' => 0.2, 'label' => ' ' }]
        got = Client.mixins_prompt([{ 'caption' => 'стена', 'boxes' => bs }])
        assert(got.include?('Reference image 2: red box 1 — фактура кирпича.'), "боксы потеряны: #{got.inspect}")
        assert(!got.include?('red box 2'), 'пустая подпись попала')
        got2 = Client.mixins_prompt([{ 'caption' => 'стена', 'boxes' => bs, 'boxes_ok' => false }])
        assert(!got2.include?('red box'), 'boxes_ok=false должен глушить текст')
        assert(got2.include?('стена'), 'подпись без боксов должна остаться')
      end

      test 'boxes: generate добавляет boxes_prompt в тело запроса' do
        bodies = []
        fake = Object.new
        fake.define_singleton_method(:request) do |req|
          bodies << JSON.parse(req.body)
          raise 'стоп-тест'
        end
        orig_api = Client.method(:api)
        Client.define_singleton_method(:api) { |_url| fake }
        begin
          begin
            Client.generate('http://127.0.0.1:9', 'k', nil, prompt: 'p', width: 256, height: 256,
                            boxes_prompt: "Red box 1: остров.")
            raise 'не дошло'
          rescue RuntimeError => e
            raise unless e.message == 'стоп-тест'
          end
        ensure
          Client.define_singleton_method(:api, orig_api)
        end
        assert(bodies.first['prompt'].include?("Red box 1: остров."), 'boxes_prompt потерян')
      end

      test 'boxes: диалоговые колбэки зарегистрированы' do
        src = File.read(File.join(__dir__, '..', 'dialog.rb'), encoding: 'UTF-8')
        assert(src.include?("add_action_callback('scenes_boxes_save')"), 'нет колбэка scenes_boxes_save')
        assert(src.include?("data.fetch('boxes'"), 'mixins_update не прокидывает boxes')
        assert(src.include?("add_action_callback('mixins_delete_all')"), 'нет колбэка mixins_delete_all')
        assert(src.include?("add_action_callback('gallery_delete_all')"), 'нет колбэка gallery_delete_all')
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
