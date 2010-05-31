#!/usr/bin/ruby

$: << File.dirname(__FILE__) + '/lib'

require 'rubygems'
require 'cinesync'
require 'json'
require 'shotgun'
require 'shotgun_utils'


CineSync.event_handler do |evt|
  $sg = Shotgun.new

  # Check that this session is related to a playlist in our Shotgun
  session_sg = JSON::parse(evt.session.user_data)['shotgun'] rescue nil
  exit unless session_sg and session_sg['playlist_id'] and session_sg['url'] == $sg.config['shotgun_url']

  $sg.remove_session_key_from_playlist(session_sg['playlist_id'])
  puts "Removed session key from Shotgun playlist ID #{session_sg['playlist_id']}"

  $sg.browser.refresh_detail
  $sg.browser.show_banner('Removed cineSync session key.')
end
