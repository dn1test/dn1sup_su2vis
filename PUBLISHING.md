# PUBLISHING.md — DN1Sup SU2Vis (стаб)

См. мастер `U:\dn1code\sketchup_ext\PUBLISHING.md`.

Локальный чек-лист:
1. `cd frontend && npm install && npm run build` → проверить `dn1sup_su2vis/resources/panel.html`.
2. Доставить в живой SketchUp под тем же id → `ext_test` → `view_png`.
3. `ruby tools/pack.rb` → установка `.rbz` из `dist/` → smoke-тест.
4. Версия в регистраторе + `registry.json`, запись в `CHANGELOG.md`, коммит + тег `v<версия>`.
