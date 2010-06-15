#!/usr/bin/ruby

require 'pathname'
require 'yaml'


install_dir = Pathname(ARGV[0])
config_path = install_dir + 'shotgun_config.yaml'

if config_path.exist?
  config = YAML.load_file(config_path)
  # Maps to the CSCBrowserTag enum
  web_browser_map = { 'none' => 0, 'safari' => 1, 'firefox' => 2 }
  puts [config['shotgun_url'],
        config['script_name'],
        config['api_key'],
        (web_browser_map[config['web_browser']] || 0).to_s].join("\n")
  exit 0
else
  exit 1
end
