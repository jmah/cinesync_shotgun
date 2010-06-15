#!/usr/bin/ruby

# This script checks the passed Shotgun URL and API key, configure the Shotgun
# instance, and build the shotgun_config.yaml file. It is idempotent when
# configuring Shotgun (if it has run once, running it again should not
# duplicate any actions).

require 'pathname'
require 'yaml'


install_dir, $shotgun_url, $script_name, $api_key, browser_index = ARGV[0..4]
install_dir = Pathname(install_dir)

config_path = install_dir + 'shotgun_config.yaml'

# Maps from the CSCBrowserTag enum
web_browser_map = { 0 => 'none', 1 => 'safari', 2 => 'firefox' }

$config_vars = {}
$config_vars.merge!(YAML.load_file(config_path)) if config_path.exist?

$config_vars['shotgun_url'] = $shotgun_url
$config_vars['script_name'] = $script_name
$config_vars['api_key'] = $api_key
$config_vars['web_browser'] = web_browser_map[browser_index.to_i]
$config_vars['version_qt_search_order'] ||= %w[sg_path_to_movie sg_uploaded_movie sg_qt]
$config_vars['custom_fields'] ||= {}


$: << (Pathname(__FILE__).dirname + 'lib')
require 'shotgun'

$sg = Shotgun.new
# Override Shotgun config with a custom one
$sg.instance_variable_set(:@config, $config_vars)


# If the URL or API key is invalid, this will either throw or return nil
playlist_fields = $sg.field_names('Playlist')
fail unless playlist_fields


# Set up Playlist fields
def sg_field_expectation(name)
  # Our expectation for how Shotgun will name a field
  Regexp.new("sg_#{name}".downcase.gsub(' ', '_') + '(_\d\+)?')
end

field_info =
  { 'cinesync_session_url' => {
      :entity => 'Playlist', :type => :url,
      :name   => 'cineSync Session URL' },
    'cinesync_session_key' => {
      :entity => 'Playlist', :type => :text,
      :name   => 'cineSync Session Key' }}
$config_vars['custom_fields']['Playlist'] ||= {}
field_info.each do |key, info|
  re = sg_field_expectation(info[:name])
  existing_field = playlist_fields.find {|f| f =~ re }
  field_name = existing_field || $sg.create_field('Playlist', info[:name], info[:type])
  $config_vars['custom_fields']['Playlist'][key] = field_name
end


# Set up action menu item
OpenInCineSyncName = 'Open in cineSync...'
menu_items = $sg.find('ActionMenuItem',
                      :filters => [[:title, :is, OpenInCineSyncName]])
if menu_items.empty?
  %w[Version Playlist].each do |ent|
    $sg.create('ActionMenuItem',
      :title => OpenInCineSyncName,
      :url => 'cinesync://script/Open%20from%20Shotgun',
      :entity_type => ent)
  end
  puts 'Open in cineSync menu item created.'
end


# Write config file
install_dir.mkpath
File.open(config_path, 'w') {|f| YAML.dump($config_vars, f) }
