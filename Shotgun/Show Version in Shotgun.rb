#!/usr/bin/ruby

$: << File.dirname(__FILE__) + '/lib'

require 'rubygems'
require 'cinesync'
require 'json'
require 'shotgun'


CineSync.event_handler do |evt|
  $sg = Shotgun.new

  session_sg = JSON::parse(evt.session.user_data)['shotgun'] rescue nil

  media = evt.session.media.find {|m| m.active? }
  media_sg = JSON::parse(media.user_data)['shotgun'] rescue nil

  show_banner = ARGV.include? '--banner'
  if media_sg and media_sg['url'] == $sg.config['shotgun_url']
    version_url = "#{media_sg['url']}detail/Version/#{media_sg['version_id']}"
    $sg.browser.show_version(version_url, media.name, show_banner)
  elsif session_sg and session_sg['url'] == $sg.config['shotgun_url']
    $sg.browser.show_banner(%Q[cineSync is viewing #{media.name}]) if show_banner
  end
end
