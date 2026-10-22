# frozen_string_literal: true

module Dn1sup
  module Su2vis
    # Апсемплер промпта в фоне: сеть держать в HtmlDialog-колбэке НЕЛЬЗЯ —
    # колбэки выполняются на главном потоке, UI виснет на всё время
    # инференса студии (окно «закрывается» / процесс убивают).
    # Поток пишет только @tasks (url/key/промпт/референс сняты в plain-строки
    # ещё на главном), панель опрашивает enhance_poll. SketchUp API
    # из потока не трогаем (как в Jobs).
    module Enhance
      @tasks = {}
      @seq = 0
      @mutex = Mutex.new
      @worker = nil

      KEEP_DONE = 20

      class << self
        # Подмена исполнителя для тестов (по умолчанию — студия по сети).
        attr_writer :worker

        def worker
          @worker ||= ->(url, key, prompt, ref) { Client.enhance_preview(url, key, prompt, ref) }
        end

        # Старт задачи, сразу {id, status: 'running'}. Сеть — в потоке.
        def start(url, key, prompt, reference)
          w = worker
          task = nil
          @mutex.synchronize do
            @seq += 1
            task = { 'id' => "enh#{@seq}_#{Time.now.to_i}", 'status' => 'running',
                     'text' => nil, 'error' => nil }
            @tasks[task['id']] = task
            done = @tasks.values.select { |t| t['status'] != 'running' }
            done[0...(done.size - KEEP_DONE)].each { |t| @tasks.delete(t['id']) } if done.size > KEEP_DONE
          end
          u, k, p, r = url.to_s, key.to_s, prompt.to_s, reference.to_s
          Thread.new do
            begin
              finish(task['id'], 'done', w.call(u, k, p, r).to_s, nil)
            rescue Exception => e # rubocop:disable Lint/RescueException
              finish(task['id'], 'error', nil, e.message.to_s)
            end
          end
          public_view(task['id'])
        end

        def poll(id)
          v = public_view(id.to_s)
          v.nil? ? { 'id' => id.to_s, 'status' => 'error', 'text' => nil, 'error' => 'задача не найдена' } : v
        end

        def clear
          @mutex.synchronize { @tasks.clear }
          true
        end

        private

        def finish(id, status, text, error)
          @mutex.synchronize do
            t = @tasks[id]
            next if t.nil?

            t['status'] = status
            t['text'] = text
            t['error'] = error
          end
        end

        def public_view(id)
          t = @mutex.synchronize { @tasks[id.to_s] }
          t.nil? ? nil : { 'id' => t['id'], 'status' => t['status'], 'text' => t['text'], 'error' => t['error'] }
        end
      end
    end
  end
end
