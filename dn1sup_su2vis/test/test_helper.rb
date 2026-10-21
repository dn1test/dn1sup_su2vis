# frozen_string_literal: true
# test_helper.rb — мини-харнесс тестов «DN1Sup SU2Vis» (как в comp_add_view).
# Внутри SketchUp — запуск через ext_test; локально — ruby test/su2vis_test.rb
# (модельные тесты уходят в skip по отсутствию Sketchup.active_model).

unless defined?(Sketchup)
  stub_dir = File.expand_path('../../tools/test_stub', __dir__)
  $LOAD_PATH.unshift(stub_dir) if File.directory?(stub_dir)
end

require_relative '../main' unless defined?(Dn1sup::Su2vis::VERSION)

module Dn1sup
  module Su2vis
    module Test
      class Failure < StandardError; end
      class Skip    < StandardError; end

      @tests = []

      class << self
        attr_reader :tests

        def test(name, &block)
          @tests << [name, block]
        end

        def assert(condition, msg = 'утверждение ложно')
          raise Failure, msg unless condition
        end

        def assert_equal(expected, actual, msg = nil)
          return if expected == actual

          raise Failure, "#{msg ? "#{msg}: " : ''}ожидали #{expected.inspect}, получили #{actual.inspect}"
        end

        def skip(reason = 'пропуск')
          raise Skip, reason
        end

        # Ключи отчёта СТРОЧНЫЕ: через мост Symbol-ключи теряются.
        def run!
          results = { 'total' => @tests.size, 'failures' => [], 'skipped' => [] }
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @tests.each do |name, block|
            begin
              block.call
            rescue Skip => e
              results['skipped'] << { 'name' => name, 'reason' => e.message }
            rescue Failure => e
              results['failures'] << { 'name' => name, 'error' => e.message }
            rescue Exception => e # rubocop:disable Lint/RescueException
              results['failures'] << { 'name' => name, 'error' => "#{e.class}: #{e.message}",
                                       'backtrace' => Array(e.backtrace).first(5) }
            end
          end
          results['duration_ms'] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round(1)
          results['passed'] = results['total'] - results['failures'].size - results['skipped'].size
          reset!
          results
        end

        def reset!
          @tests = []
        end
      end
    end
  end
end

# Алиас для харнесса ext_test: он вызывает <Camelize(id)>::Test,
# т.е. Dn1supSu2vis::Test — тот же объект, тесты регистрируются один раз.
Dn1supSu2vis = Dn1sup::Su2vis unless defined?(Dn1supSu2vis)
