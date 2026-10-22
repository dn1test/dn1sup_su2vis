# frozen_string_literal: true

require 'sketchup.rb'

module Dn1sup
  def self.common_menu
    @common_menu ||= UI.menu('Extensions').add_submenu('DN1Sup')
  end
end

module Dn1sup
  module Su2vis
    VERSION = '0.13.0'.freeze

    ID       = 'dn1sup_su2vis'.freeze
    REPO     = 'dn1test/dn1sup_su2vis'.freeze
    ASSET    = "#{ID}.rbz".freeze
    PAGE_URL = "https://github.com/#{REPO}/releases".freeze
    MANIFEST = { id: ID, repo: REPO, version: VERSION, asset: ASSET }.freeze

    require_relative 'settings'
    require_relative 'log'
    require_relative 'client'
    require_relative 'studio'
    require_relative 'scenes'
    require_relative 'enhance'
    require_relative 'jobs'
    require_relative 'gallery'
    require_relative 'mixins'
    require_relative 'dialog'

    def self.unload!
      Panel.close_all if defined?(Panel) && Panel.respond_to?(:close_all)
      Jobs.pump_stop if defined?(Jobs) && Jobs.respond_to?(:pump_stop)
      true
    rescue StandardError => e
      warn "[Su2vis] unload!: #{e.message}"
      false
    end

    unless file_loaded?(__FILE__)
      cmd = UI::Command.new('SU2Vis — эскиз в фото') { Panel.show }.tap do |c|
        c.tooltip = 'SU2Vis: генерация фото из сцен'
        c.status_bar_text = 'Выбор сцен, превью малого разрешения, финал с тем же seed'
        icon = File.join(__dir__, 'resources', 'panel.svg')
        c.small_icon = c.large_icon = icon if File.exist?(icon)
      end

      dn1sup_menu = Dn1sup.common_menu
      menu = dn1sup_menu.add_submenu('SU2Vis')
      menu.add_item(cmd)
      menu.add_item('Открыть папку результатов') do
        require_relative 'settings'
        dir = Settings.out_dir
        require 'fileutils'
        FileUtils.mkdir_p(dir)
        UI.openURL("file:///#{dir.tr('\\', '/')}")
      end

      toolbar = UI::Toolbar.new('DN1Sup SU2Vis')
      toolbar.add_item(cmd)
      if toolbar.get_last_state == -1
        toolbar.show
      else
        toolbar.restore
      end

      file_loaded(__FILE__)
    end
  end
end
