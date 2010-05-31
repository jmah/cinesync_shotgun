#!/usr/bin/ruby

$: << File.dirname(__FILE__) + '/lib'

require 'rubygems'
require 'cinesync'
require 'json'
require 'shotgun'
require 'shotgun_utils'
require 'tempfile'
require 'date'


# Extend the Shotgun object with some useful things
class Shotgun
  def create_or_update_note(attrs)
    existing_note = self.find_one('Note',
      :filters => [[:subject, :is, attrs[:subject]],
                   [:project, :is, attrs[:project]],
                   [:created_by, :is, script_user],
                   [:note_links, :is, attrs[:note_links][0]]])

    if existing_note
      self.update('Note', existing_note['id'], attrs)
    else
      self.create('Note', attrs)
    end
  end
end


def create_session_notes(evt, session_sg)
  subject = Date.today.strftime("Playlist #{session_sg['playlist_name']} - %b %d %y")
  subject += " (#{evt.session_key})" unless evt.offline?
  note_data = {:subject => subject,
               :content => evt.session.notes,
               :project => {:type => 'Project', :id => session_sg['project_id'].to_i},
               :note_links => [{:type => 'Playlist', :id => session_sg['playlist_id'].to_i}]}
  $sg.create_or_update_note(note_data)
end


def create_media_note(evt, media)
  # Create the note with the same defaults as from a Shotgun Playlist page
  media_sg = JSON::parse(media.user_data)['shotgun']
  name = media_sg['playlist_name'] || media.name
  subject = Date.today.strftime("#{name} - %b %d %y")
  subject += " (#{evt.session_key})" unless evt.offline?

  links = [{:type => 'Version',  :id => media_sg['version_id'].to_i}]
  links << {:type => 'Playlist', :id => media_sg['playlist_id'].to_i} if media_sg['playlist_id']

  # Find the version's linked entity (usually Shot) and task
  sg_links = $sg.read('Version', media_sg['version_id'].to_i, :fields => [:entity, :sg_task, :user])
  links << sg_links['entity'] if sg_links['entity']
  links << sg_links['sg_task'] if sg_links['sg_task']

  note_data = {:subject => subject,
               :content => "(this note is being created by cineSync...)",
               :project => {:type => 'Project', :id => media_sg['project_id'].to_i},
               :note_links => links}
  note_data[:addressings_to] = [sg_links['user']] if sg_links['user']

  unless (sg_note = $sg.create_or_update_note(note_data))
    $stderr.puts "Unable to create note in Shotgun!"
    false
  else
    existing_attachments = $sg.read('Note', sg_note['id'], :fields => ['attachments'])['attachments'] || []

    # Collect notes from media and all frames
    notes = []
    notes << media.notes unless media.notes.empty?
    media.annotations.keys.sort.each do |frame|
      ann = media.annotations[frame]
      frame_notes = "**Frame #{frame}:**"
      frame_notes << ' ' + ann.notes unless ann.notes.empty?

      if !ann.drawing_objects.empty? and (path = evt.saved_frame_path(media, frame))
        # Check if the frame is already uploaded, otherwise attach it
        existing_attach = existing_attachments.find {|att| att['name'] == path.basename.to_s }
        att_id = if existing_attach
          existing_attach['id']
        else
          puts "  Attaching frame #{frame}"
          $sg.upload('Note', sg_note['id'], path.to_s)
        end

        next unless att_id
        href = "#{$sg.config['shotgun_url']}file_serve/attachment/#{att_id}"
        frame_notes << "\n!#{href}!"
      end
      notes << frame_notes
    end

    if notes.empty? or notes.all? {|n| n.empty? }
      # Delete the note from Shotgun if it turned out there's nothing to do
      $sg.delete('Note', sg_note['id'])
      false
    else
      # Write the real note content to Shotgun
      note_data[:content] = notes.join("\n\n")
      sg_note = $sg.create_or_update_note(note_data)
      not sg_note.nil?
    end
  end
end


CineSync.event_handler do |evt|
  $sg = Shotgun.new

  note_count = 0
  status_msg = 'Exporting notes from cineSync...'
  session_sg = JSON::parse(evt.session.user_data)['shotgun'] rescue nil

  unless evt.session.notes.empty?
    if session_sg and session_sg['playlist_id'] and session_sg['url'] == $sg.config['shotgun_url']
      $sg.browser.show_banner("#{status_msg} (session notes)")
      puts "Creating session notes"
      note_count += 1 if create_session_notes(evt, session_sg)
    end
  end

  evt.session.media.each do |media|
    $sg.browser.show_banner("#{status_msg} (#{media.name.chomp('.mov')})")

    # Check that media file is linked to our Shotgun instance
    media_sg = JSON::parse(media.user_data)['shotgun'] rescue nil
    unless media_sg and media_sg['url'] == $sg.config['shotgun_url']
      puts "Skipping #{media.name}: No link to known Shotgun instance"
      next
    end

    # Check if media file has notes
    if media.notes.empty? and media.annotations.empty?
      puts "Skipping #{media.name}: No notes on media"
      next
    end

    puts "Creating notes for #{media.name}"
    begin
      note_count += 1 if create_media_note(evt, media)
    rescue
      puts "Unable to create notes: #{$!}"
    end
  end

  $sg.browser.show_banner('cineSync export complete.')
  if note_count > 0
    $sg.browser.refresh_detail
    CineSync::UI.show_dialog("cineSync has exported #{note_count} note#{note_count == 1 ? '' : 's'} to Shotgun.")
  else
    CineSync::UI.show_dialog("No notes or annotated frames were were found on media linked to Shotgun.")
  end
end
