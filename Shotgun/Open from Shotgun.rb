#!/usr/bin/ruby

$: << File.dirname(__FILE__) + '/lib'

require 'rubygems'
require 'cinesync'
require 'active_support'
require 'shotgun'
require 'shotgun_utils'
require 'uri'
require 'cgi'
require 'json'
require 'tmpdir'


CineSync.event_handler do |evt|
  unless evt.url
    CineSync::UI.show_dialog("This script must be run as a response to a URL request from Shotgun, and is not meant to be triggered from the scripts menu.")
    exit 1
  end

  # Decode the URI parameters
  trigger_uri = URI::parse(evt.url)
  query_hash = Hash[*trigger_uri.query.split('&').map do |keyval|
    keyval.split('=', 2).map {|x| URI.decode(x)}
  end.flatten]

  if query_hash['selected_ids'].empty?
    $stderr.puts "No objects were selected in Shotgun."
    exit 0
  end


  # Create Shotgun RPC proxy
  $sg = Shotgun.new

  # Find the playlists and/or versions
  playlist = nil
  versions = []

  case query_hash['entity_type']
  when 'Playlist'
    id = query_hash['selected_ids'].split(',')[0].to_i
    status_msg = 'Loading playlist in cineSync...'

    puts "Reading information for playlist ID #{id}"
    $sg.browser.show_banner("#{status_msg} (reading playlist)")
    playlist = $sg.read('Playlist', id, :fields => [:project, :code, :versions])
    puts "Reading sort order of versions"
    $sg.browser.show_banner("#{status_msg} (reading sort order)")
    cx = $sg.find('PlaylistVersionConnection',
                  :filters => [['playlist', 'is', playlist]],
                  :fields => [:version, :sg_sort_order])
    puts "Reading information for versions in playlist"
    $sg.browser.show_banner("#{status_msg} (reading versions)")
    versions = $sg.find('Version',
                        :filters => [['playlists', 'is', playlist]],
                        :fields => :all).sort_by do |ver|
      # Use the sort order from PlaylistVersionConnection
      cx.find {|x| x['version']['id'] == ver['id'] }['sg_sort_order'] || 999
    end

    unless evt.offline?
      # We started online, so add the session key now (the "going online" event was already fired)
      $sg.add_session_key_to_playlist(evt.session_key, id)
      puts "Added session key to Shotgun playlist ID #{id}"
      $sg.browser.refresh_detail
    end
  when 'Version'
    # Shotgun API doesn't support 'in' for versions, so fetch them individually
    status_msg = 'Loading versions in cineSync...'
    versions = query_hash['selected_ids'].split(',').map {|str| str.to_i }.map do |id|
      puts "Reading information for version ID #{id}"
      $sg.browser.show_banner("#{status_msg} (reading version ID #{id})")
      $sg.read('Version', id, :fields => :all)
    end
  else
    $stderr.puts "Script invoked with unsupported entity: #{query_hash['entity_type']}"
    exit 1
  end

  $sg.browser.show_banner(status_msg)


  # Create cineSync session
  puts "Creating cineSync session file"
  shotgun_info = {:url => $sg.config['shotgun_url'], :project_id => query_hash['project_id'] }
  session = CineSync::Session.new
  if playlist
    shotgun_info[:playlist_id] = playlist['id']
    shotgun_info[:playlist_name] = playlist['code']
    session.user_data = {:shotgun => shotgun_info}.to_json
  end

  session.media = versions.map do |vers|
    # Find the QuickTime location for each version
    qt = $sg.quicktime_from_version(vers) # Could return nil
    {:qt => qt, :id => vers['id'], :name => vers['code']}
  end.map do |info|
    # Create a media file for each version
    loc = info[:qt] || (info[:name] + '.mov')
    returning CineSync::MediaFile.new(loc) do |med|
      med.name = info[:name] + '.mov'
      med.user_data = {:shotgun => shotgun_info.merge(:version_id => info[:id])}.to_json
    end
  end

  name = playlist ? playlist['code'] : "Versions from Shotgun"
  CineSync::Commands.open_session!(session, name)
end
