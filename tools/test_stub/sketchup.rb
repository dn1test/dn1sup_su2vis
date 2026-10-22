# frozen_string_literal: true

# Мини-заглушка SketchUp API для локального запуска тестов вне SketchUp
# (ruby test/su2vis_test.rb). В пакет .rbz не попадает (tools/ не пакуется).

module Sketchup
  @defaults = {}

  def self.active_model; end

  def self.version
    '0.0.0'
  end

  def self.read_default(section, key, default = nil)
    @defaults.key?([section, key]) ? @defaults[[section, key]] : default
  end

  def self.write_default(section, key, value)
    @defaults[[section, key]] = value
  end
end

module UI
  class Command
    def initialize(_name); end

    def tooltip=(_); end

    def status_bar_text=(_); end

    def small_icon=(_); end

    def large_icon=(_); end
  end

  class Toolbar
    def initialize(_name); end

    def add_item(_); end

    def get_last_state
      -1
    end

    def show; end

    def restore; end
  end

  class Menu
    def add_submenu(_name)
      self
    end

    def add_item(_item = nil, &_block)
      self
    end

    def add_separator; end
  end

  class HtmlDialog
    def initialize(_opts = {}); end

    def add_action_callback(_name, &_block); end

    def set_file(_path); end

    def set_html(_html); end

    def show; end
  end

  def self.menu(_name)
    @menu ||= Menu.new
  end

  @timer_seq = 0

  def self.start_timer(_interval, _repeat, &_block)
    @timer_seq = (@timer_seq || 0) + 1
  end

  def self.stop_timer(_id); end

  def self.openURL(_url); end
end

$dn1sup_stub_loaded_files = {}

def file_loaded?(path)
  $dn1sup_stub_loaded_files[path.to_s] ? true : false
end

def file_loaded(path)
  $dn1sup_stub_loaded_files[path.to_s] = true
end
