module ShotgunUtils
  def quicktime_from_version(version)
    # Given a Version object, return the location of its QuickTime movie
    # This can be in the format:
    #     /locally/accessible/path/myVersion.mov
    #     http://assets.example.com/webVersion.mov
    #     ftp://files.example.com/ftpVersion.mov
    # Returning nil will leave the version unlocated.

    config['version_qt_search_order'].each do |field|
      val = version[field]
      next if val.nil?

      if val.respond_to?(:has_key?) and val.has_key? 'url'
        url = URI::parse(val['url']) rescue nil
        location = quicktime_from_url(url) if url
        return location if location
      elsif !val.empty?
        return String(val)
      end
    end
    nil
  end


  def quicktime_from_url(url)
    if url.scheme == 'file'
      URI.decode(url.path)
    elsif url.host == URI(config['shotgun_url']).host and url.path.include? '/file_serve/attachment'
      # Attachment uploaded in Shotgun
      attachment_id = url.path.split('/').last.to_i rescue nil
      url_for_attachment_id(attachment_id) if attachment_id
    else
      # Use the URL, assuming it's a plain HTTP, FTP, etc.
      url
    end
  end


  def add_session_key_to_playlist(key, playlist_id)
    join_url = "cinesync://session/#{key}"
    params = { :cinesync_session_url => {:url => join_url, :name => "Join #{key}"},
               :cinesync_session_key => key }
    update('Playlist', playlist_id, map_custom_fields('Playlist', params))
  end


  def remove_session_key_from_playlist(playlist_id)
    params = { :cinesync_session_url => nil,
               :cinesync_session_key => '' }
    update('Playlist', playlist_id, map_custom_fields('Playlist', params))
  end


  def script_user
    @script_user ||= find('ApiUser', :filters => [[:salted_password, :is, config['api_key']]])[0]
  end
end


class Shotgun
  include ShotgunUtils
end
