#!/usr/bin/env ruby

require "#{ENV["TM_SUPPORT_PATH"]}/lib/dialog"
require "GrailsMate"

gm = GrailsMate.new("install-plugin") do |default|
  Dialog.request_string( 
    :title => "Install Grails Plug-in",
    :prompt => "Enter the Plug-in name",
    :default => ""
  )
end

gm.green_patterns << /Plugin (.)+ installed/
gm.red_patterns << /Plugin (.)+ was not found in repository/
gm.run