#!/usr/bin/ruby

$: << File.dirname(__FILE__) + '/lib'

require 'rubygems'
require 'cinesync'
require 'json'
require 'shotgun'
require 'shotgun_utils'


CineSync.event_handler do |evt|
  exit if evt.offline?

  $sg = Shotgun.new

  # Check that this session is related to a playlist in our Shotgun
  session_sg = JSON::parse(evt.session.user_data)['shotgun'] rescue nil
  exit unless session_sg and session_sg['playlist_id']
  unless session_sg['url'] == $sg.config['shotgun_url']
    puts "Skipping adding session key to Shotgun because Shotgun URL of session (#{session_sg['url']}) does not match known Shotgun instance at #{$sg.config['shotgun_url']}"
    exit
  end

  $sg.add_session_key_to_playlist(evt.session_key, session_sg['playlist_id'])
  puts "Added session key to Shotgun playlist ID #{session_sg['playlist_id']}"

  $sg.browser.refresh_detail
end
