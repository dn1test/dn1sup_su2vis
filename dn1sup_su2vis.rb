# frozen_string_literal: true

# Author: DN1Sup <dn1codegen@gmail.com>
# License: MIT

require 'sketchup.rb'
require 'extensions.rb'

module Dn1sup
  module Su2vis
    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new(
        'DN1Sup SU2Vis',
        File.join('dn1sup_su2vis', 'main')
      )
      extension.description = 'Генерация фотореалистичных картинок из эскизов сцен через локальный Unsloth Studio (flux-3-klein).'
      extension.version     = '0.20.0'
      extension.creator     = 'DN1Sup'
      extension.copyright   = '2026 DN1Sup <dn1codegen@gmail.com> (MIT)'
      extension.id          = 'dn1sup_su2vis' if extension.respond_to?(:id=)

      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
