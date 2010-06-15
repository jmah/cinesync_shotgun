require 'yaml'

APP_KEY_RE = /^[0-9a-f]{40}$/

class CineSyncShotgunSetup < Shoes
  url '/', :intro
  url '/form', :form
  url '/verify', :verify
  url '/end', :end

  @@install_path = "#{(ENV['ProgramFiles(x86)'] || ENV['ProgramFiles'])}/cineSync/Scripts/Shotgun"
  @@sample_shotgun_url = 'https://your.shotgun.site/'
  @@shotgun_url = @@sample_shotgun_url
  @@script_name = 'cineSync'
  @@application_key = ''
  @@enable_firefox = true
  @@connector_url = 'http://www.cinesync.com/files/cinesync_connector_latest.xpi'

  @@loaded = false

  def intro
    unless @@loaded
      config_path = @@install_path + '/shotgun_config.yaml'
      if File.exist? config_path
        config = YAML.load_file(config_path)
        @@shotgun_url = config['shotgun_url']
        @@script_name = config['script_name']
        @@application_key = config['api_key']
        @@enable_firefox = (config['web_browser'] == 'firefox')
      end
      @@loaded = true
    end

    installer_style(:next => '/form') do
      para "Welcome to the cineSync Shotgun setup tool.\n\n",
           "You will need a script name and application key from your Shotgun database.",
           "This may need to be created by an administrator and supplied to you.\n\n",
           "Please close cineSync before continuing.", :size => 10
    end
  end

  def form
    installer_style(:next => '/verify', :prev => '/') do
      w = 94
      stack(:width => w) do
        inscription 'Shotgun URL:', :align => 'right'
      end
      stack(:width => -w) do
        @shotgun_url_line = edit_box(@@shotgun_url, :width => '100%', :height => 25) do |el|
          str = el.text.split("\r\n").join('')
          el.text = str unless el.text == str
          @@shotgun_url = el.text
        end
      end

      stack(:margin => 8) { image('Shotgun Scripts.png') }

      stack(:width => w) do
        inscription 'Script Name:', :size => 8, :align => 'right'
        inscription 'Application Key:', :size => 8, :align => 'right'
      end
      stack(:width => -w) do
        edit_box(@@script_name, :width => 116, :height => 25) do |el|
          str = el.text.split("\r\n").join('')
          el.text = str unless el.text == str
          @@script_name = el.text
        end
        stack(:height => 8) # Spacer
        edit_box(@@application_key, :width => '100%', :height => 25) do |el|
          str = el.text.split("\r\n").join('')
          el.text = str unless el.text == str
          @@application_key = el.text
        end

        flow(:displace_top => 6) do
          @enable_firefox_btn = check { @@enable_firefox = @enable_firefox_btn.checked? }
          @enable_firefox_btn.checked = @@enable_firefox
          inscription('Enable Firefox browser integration')
        end

        button('Install Firefox Extension', :width => 140) { visit(@@connector_url) }
      end
    end.validate do
      require 'uri'
      uri = URI(@@shotgun_url) rescue nil
      if @@shotgun_url =~ /_/
        alert("Shotgun URLs containing underscores ('_') are not supported. " +
              "Please contact support@cinesync.com for a workaround.")
        false
      elsif @@shotgun_url == @@sample_shotgun_url or uri.nil? or
            not %w[http https].include?(uri.scheme)
        alert('Please specify the full URL of your Shotgun instance. ' +
              'For example: https://example.shotgunstudio.com/')
        false
      elsif @@script_name.empty?
        alert('Please provide the Script Name from the Scripts area ' +
              'of your Shotgun admin section.')
        false
      elsif @@application_key.downcase !~ APP_KEY_RE
        alert('Please provide a valid application key. This can be found ' +
              'in the Scripts area of your Shotgun admin section.')
        false
      else
        true
      end
    end
  end

  def verify
    installer_style() do
      stack do
        @status = para 'Checking...'
        stack(:height => 8) # Spacer
        @p = progress(:width => '100%')

        timer(1) do
          @p.fraction = 0.2
          begin
            success = start_setup_shotgun
          rescue
            error($!)
            success = false
          end
          if success
            @p.fraction = 1.0
            @status.text = 'Shotgun configured.'
            timer(2) { visit('/end') }
          else
            @p.fraction = 1.0
            @status.text = 'Unable to connect to Shotgun.'
            timer(2) { visit('/form') }
          end
        end
      end
    end
  end

  def end
    installer_style(:next => :exit, :next_label => 'Exit') do
      para "cineSync has been configured to integrate with Shotgun. ",
           "You can now open a playlist or version from Shotgun ",
           "by selecting \"Open in cineSync...\".\n", :size => 10

      image('Open in cineSync.png')
    end
  end


  private
  def start_setup_shotgun
    script_path = @@install_path + '/Install/setup_shotgun.rb'
    browser_tag = @@enable_firefox ? 2 : 0
    sg_root = URI(@@shotgun_url)
    sg_root.path = '/'
    argv = ['C:/Ruby/bin/rubyw.exe', script_path, @@install_path, String(sg_root), @@script_name, @@application_key, browser_tag.to_s]
    info(argv.join(' '))
    system(*argv)
  end

  def installer_style(opts = {})
    opts = { :prev_label => 'Go Back',
             :next_label => 'Continue',
             :validate_next => lambda {true} }.merge(opts)

    background '#ededed'
    background('Background.png', :width => 640, :height => 420)

    stack(:displace_left => 181, :displace_top => 6) do
      para strong('cineSync Shotgun Integration Setup'), :size => 11

      flow(:width => 418, :height => 330) do
        background rgb(255, 255, 255, 0.58)
        border '#928f96', :strokewidth => 1

        flow(:margin => 20) { yield }
      end
    end

    flow(:displace_left => 410, :displace_top => 14) do
      stack(:width => 100) do
        button(opts[:prev_label], :width => 90, :state => (opts[:prev] ? nil : 'disabled')) do
          visit(opts[:prev]) if opts[:prev]
        end
      end
      button(opts[:next_label], :width => 90, :state => (opts[:next] ? nil : 'disabled')) do
        if opts[:validate_next].call
          if opts[:next] == :exit
            exit
          elsif opts[:next]
            visit(opts[:next])
          end
        end
      end
    end

    stub = Object.new
    stub.instance_variable_set('@opts', opts)
    def stub.validate(&block)
      @opts[:validate_next] = block
    end

    stub
  end
end


Shoes.app :title => 'cineSync Shotgun Setup', :width => 620, :height => 418, :resizable => false
