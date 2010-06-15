#!/usr/bin/ruby

# We'll install the plist code in /private/tmp
$: << '/private/tmp'

require 'pathname'
require 'plist'


puts 'Configuring scripts in cineSync preferences'

PrefsRoot = Pathname('~/Library/Preferences').expand_path
ScriptsRoot = Pathname('~/Library/Application Support/cineSync/Scripts').expand_path
ScriptDefaults = { :drawings_scope => 0, :save_frames_scope => 0, :trigger_event => 1, :trigger_event_enabled => false }

path = PrefsRoot + "com.risingsunresearch.cineSync.plist"
csc_prefs = {}
if path.exist?
  csc_prefs = Plist::parse_xml(%x[plutil -convert xml1 -o - "#{path}"])
end

plist_scripts = csc_prefs['UserScripts'] || []


# Remove obsolete scripts from <= 1.0b2
plist_scripts.delete_if {|scr| scr['name'] == 'Show Version in Shotgun (nice)' }

[
  { :path => 'Shotgun/Open from Shotgun.rb' },
  { :path => 'Shotgun/Add Session Key to Shotgun Playlist.rb', :trigger_event => 1, :trigger_event_enabled => true },
  { :path => 'Shotgun/Show Version in Shotgun.rb' },
  { :path => 'Shotgun/Show Version in Shotgun.rb', :name => 'Show Version Banner in Shotgun', :args => '--banner', :trigger_event => 2, :trigger_event_enabled => true },
  { :path => 'Shotgun/Export Notes to Shotgun.rb', :save_frames_scope => 2, :drawings_scope => 2 },
  { :path => 'Shotgun/Remove Session Key from Shotgun Playlist.rb' },
].each do |script_def|
  props = ScriptDefaults.merge(script_def)
  props[:path] = ScriptsRoot + props[:path]
  props[:name] = props[:path].basename.to_s.split('.')[0...-1].join('.') unless props[:name]

  props[:command] = [%Q{"#{props[:path]}"}, Array(props[:args])].flatten.join(' ')

  plist_scripts.delete_if {|scr| scr['name'] == props[:name] }

  plist_scripts << {
    :name => props[:name],
    :command => props[:command],
    :triggerEvent => props[:trigger_event],
    :triggerEventEnabled => props[:trigger_event_enabled],
    :drawingsScope => props[:drawings_scope],
    :saveFramesScope => props[:save_frames_scope] }
end

csc_prefs['UserScripts'] = plist_scripts
File.open(path, 'w') {|f| f.puts csc_prefs.to_plist }

puts 'Scripts configured.'
