# frozen_string_literal: true

require 'uri'
require 'net/http'

module Dn1sup
  module Su2vis
    # Автозапуск локального Unsloth Studio в headless-режиме (без GUI):
    # `unsloth studio --api-only -H <host> -p <port>`.
    # Процесс поднимается скрыто (без чёрной консоли) и живёт после
    # закрытия панели; повторный запуск дубля не делает.
    # Долгий опрос готовности — только из фонового Thread (см. ensure_async):
    # колбэки HtmlDialog идут на главном потоке, блокировать его нельзя.
    module Studio
      module_function

      START_TIMEOUT = 90
      POLL_STEP = 2

      @state = { 'status' => 'idle' }
      @thread = nil
      @spawner = nil

      # Подмена спавна для тестов (как Enhance.worker): ->(cmd) { true/false }.
      def spawner=(fn)
        @spawner = fn
      end

      def spawner
        @spawner
      end

      def state
        @state.dup
      end

      def reset_state!
        @thread = nil
        @state = { 'status' => 'idle' }
        { 'status' => 'idle' }
      end

      # 'http://127.0.0.1:8888' -> ['127.0.0.1', 8888]; мусор — дефолт.
      def parse_host_port(url)
        u = URI(url.to_s.strip)
        host = u.host.to_s.empty? ? '127.0.0.1' : u.host
        port = u.port.to_i > 0 ? u.port.to_i : 8888
        [host, port]
      rescue StandardError
        ['127.0.0.1', 8888]
      end

      # Строка запуска headless-сервера. Путь с пробелами — в кавычки.
      def command(url, cmd = nil)
        c = cmd.to_s.strip
        c = 'unsloth' if c.empty?
        c = "\"#{c}\"" if c.include?(' ') && !(c.start_with?('"') && c.end_with?('"'))
        host, port = parse_host_port(url)
        "#{c} studio --api-only -H #{host} -p #{port}"
      end

      # Сервер отвечает хоть что-то (включая 401 без ключа) — процесс жив.
      # Ложь — только на ошибках соединения (процесс не поднят).
      def reachable?(url)
        uri = URI(url.to_s.strip)
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 3
        http.read_timeout = 5
        http.request(Net::HTTP::Get.new('/api/inference/images/status'))
        true
      rescue StandardError
        false
      end

      # Процесс жив И ключ проходит (или ключа нет — тогда только reachable).
      def alive?(url, key)
        return reachable?(url) if key.to_s.empty?

        Client.status(url.to_s, key.to_s)
        true
      rescue StandardError
        false
      end

      # Скрытый detached-запуск без вспышки консоли.
      # Windows: WScript.Shell.Run(cmd, 0, false) — 0 = SW_HIDE, false = не ждать.
      # Остальные: Process.spawn с отводом вывода. Возвращает true/false.
      def spawn_detached(cmd)
        return !!@spawner.call(cmd) if @spawner

        if RUBY_PLATFORM =~ /mingw|mswin/
          begin
            require 'win32ole'
            shell = WIN32OLE.new('WScript.Shell')
            shell.Run(cmd.to_s, 0, false)
            return true
          rescue LoadError, StandardError
            nil
          end
        end
        pid = Process.spawn(cmd.to_s, out: File::NULL, err: File::NULL)
        Process.detach(pid)
        true
      rescue StandardError => e
        warn "[Su2vis] studio spawn: #{e.message}"
        false
      end

      # Синхронно: проверить, при нужде поднять и дождаться готовности.
      # Только из фонового Thread — внутри опрос со sleep до START_TIMEOUT.
      def ensure_running!(url, key, cmd = nil, timeout = START_TIMEOUT)
        url = url.to_s.strip
        url = 'http://127.0.0.1:8888' if url.empty?
        if reachable?(url)
          if key.to_s.empty?
            @state = { 'status' => 'running', 'already' => true }
            return { ok: true, already: true, state: state }
          end
          begin
            st = Client.status(url, key.to_s)
            @state = { 'status' => 'running', 'already' => true }
            return { ok: true, already: true, status: st, state: state }
          rescue StandardError => e
            @state = { 'status' => 'failed', 'error' => e.message.to_s }
            return { ok: false, error: e.message.to_s, state: state }
          end
        end
        full = command(url, cmd)
        unless spawn_detached(full)
          @state = { 'status' => 'failed', 'error' => 'не удалось запустить процесс unsloth (проверь unsloth_cmd в Подключении)' }
          Log.append('studio_fail', 'error' => @state['error'], 'cmd' => full)
          return { ok: false, error: @state['error'], state: state }
        end
        Log.append('studio_autostart', 'cmd' => full, 'url' => url)
        @state = { 'status' => 'starting' }
        deadline = Time.now + timeout.to_i
        last_err = nil
        loop do
          if reachable?(url)
            if key.to_s.empty?
              @state = { 'status' => 'running', 'already' => false }
              Log.append('studio_ready', 'url' => url)
              return { ok: true, already: false, state: state }
            end
            begin
              st = Client.status(url, key.to_s)
              @state = { 'status' => 'running', 'already' => false }
              Log.append('studio_ready', 'url' => url)
              return { ok: true, already: false, status: st, state: state }
            rescue StandardError => e
              last_err = e.message.to_s
              # 401/403 — процесс встал, но ключ не проходит: ждать бесполезно.
              if last_err =~ /401|403|unauthor/i
                @state = { 'status' => 'failed', 'error' => last_err }
                Log.append('studio_fail', 'error' => last_err, 'url' => url)
                return { ok: false, error: last_err, state: state }
              end
            end
          end
          break if Time.now >= deadline

          sleep POLL_STEP
        end
        err = "студия не отвечает на #{url} за #{timeout.to_i}с (процесс запущен: #{full})"
        err = "#{err}: #{last_err}" unless last_err.to_s.empty?
        @state = { 'status' => 'failed', 'error' => err }
        Log.append('studio_fail', 'error' => err, 'url' => url)
        { ok: false, error: err, state: state }
      end

      # Асинхронно с главного потока: мгновенный возврат состояния,
      # тяжёлый ensure_running! — в Thread. Дубль при живом потоке не стартует.
      def ensure_async(url, key, cmd = nil, timeout = START_TIMEOUT)
        if @thread&.alive?
          return { ok: true, started: false, state: state }
        end

        @state = { 'status' => 'starting' }
        @thread = Thread.new { ensure_running!(url, key, cmd, timeout) }
        { ok: true, started: true, state: state }
      rescue StandardError => e
        @state = { 'status' => 'failed', 'error' => e.message.to_s }
        { ok: false, error: e.message.to_s, state: state }
      end
    end
  end
end
