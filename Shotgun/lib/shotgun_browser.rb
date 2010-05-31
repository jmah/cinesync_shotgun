#!/usr/bin/ruby

require 'uri'


module ShotgunBrowser
  # Common Shotgun-specific JavaScript code
  module ShotgunJS
    def self.refresh_detail
      return <<-JS
        (function() {
          var click = document.createEvent('MouseEvents');
          click.initMouseEvent('click', true, true, window, 0,0,0,0,0,false,false,false,false,0,null);
          document.getElementsByClassName('refresh_control')[0].dispatchEvent(click);
        })();
      JS
    end

    def self.show_banner(msg, show_close = true)
      %Q{window.Shotgun.Message.show({
           html: '#{msg.gsub("'", "\\\\'")}', close_x: #{String(show_close)} });}
    end
  end


  class Base
    attr_reader :host_uri

    def initialize(host_uri)
      @host_uri = host_uri
    end
  end


  class NullBrowser < Base
    def method_missing(symbol, *args)
      nil
    end
  end


  class FirefoxSD < Base
    def initialize(host_uri)
      super
      @port = 8274
    end

    def refresh_detail
      run_in_firefox <<-JS
        #{find_shotgun_browsers_js}.forEach(function(browser) {
          #{window_script_js(ShotgunJS.refresh_detail)};
        });
      JS
    end

    def refresh_version_notes
      run_in_firefox <<-JS
        #{find_shotgun_browsers_js}.forEach(function(browser) {
          var path = browser.currentURI.path;
          var pc = path.split('/');
          if (pc[1] == 'detail' && pc[2] == 'Version' && path.indexOf('#') == -1) {
            #{window_script_js(ShotgunJS.refresh_detail)};
          }
        });
      JS
    end

    def show_banner(arg)
      run_in_firefox <<-JS
        #{find_shotgun_browsers_js}.forEach(function(browser) {
          #{window_script_js(ShotgunJS.show_banner(arg))};
        });
      JS
    end

    def show_version(version_url, name, as_banner = false)
      if as_banner
        show_banner(%Q[cineSync is viewing <a href="#{version_url}">#{name}</a>])
      else
        run_in_firefox <<-JS
          var browsers = #{find_shotgun_browsers_js};
          if (browsers.length > 0) {
            browsers[0].loadURI('#{version_url}');
          } else {
            window.open('#{version_url}');
          }
        JS
      end
    end


    private
    def run_in_firefox(js)
      require 'socket'
      begin
        sock = TCPSocket.open('127.0.0.1', @port)
        # SD Connector will eval each line in its own function, as:
        #     eval("(function() { return (" + data + ") })")
        # So to return our own values, we need to wrap it in another anonymous function
        # TODO This will currently fail if 'js' contains line comments! Remove them.
        # There also seems to be soem problems with using double quotes in the source.
        wrapped_js = '(function() {' + js.split("\n").join(' ').gsub('"', "\\\\\"") + '})()'
        sock.puts wrapped_js
        sock.close
      rescue
        puts "Unable to communicate with Firefox SD Connector extension (port #{@port})"
      end
    end

    def find_shotgun_browsers_js
      host = URI(host_uri).host
      return <<-JS
        (function() {
          var windows = #{GetWindowsJS};
          return windows.map(function(window) {
            return window.getBrowser();
          }).filter(function (browser) {
            try {
              return (browser.currentURI.host == '#{host}');
            } catch (ex) {
              return false;
            }
          });
        })()
      JS
    end

    GetWindowsJS = <<-JS
      (function() {
        var wm = Components.classes['@mozilla.org/appshell/window-mediator;1']
                           .getService(Components.interfaces.nsIWindowMediator);
        var enum = wm.getEnumerator('navigator:browser');
        var windows = [];
        while (enum.hasMoreElements())
          windows.push(enum.getNext());
        return windows;
      })()
    JS

    def window_script_js(js_src)
      # Encode the script to be run in the context of the page for Firefox's security model
      enc_src = URI.encode(js_src, /[^#{URI::PATTERN::UNRESERVED}]|'/)
      "browser.loadURI('javascript:#{enc_src}')"
    end
  end


  class Safari < Base
    def show_banner(arg)
      shotgun_tabs.each do |tab|
        tab.do_JavaScript(ShotgunJS.show_banner(arg))
      end
    end

    def show_version(version_url, name, as_banner = false)
      if as_banner
        show_banner(%Q[cineSync is viewing <a href="#{version_url}">#{name}</a>])
      else
        require 'appscript'
        Appscript.app('Safari').activate unless safari_running?

        tabs = shotgun_tabs
        if tabs.empty?
          Appscript.app('Safari').open_location(version_url)
        else
          tabs.each {|tab| tab.URL.set(version_url) }
        end
      end
    end

    def refresh_detail
      shotgun_tabs.each do |tab|
        tab.do_JavaScript(ShotgunJS.refresh_detail)
      end
    end

    def refresh_version_notes
      shotgun_tabs.each do |tab|
        uri = URI(tab.URL.get)
        pc = uri.path.split('/')
        if pc[1] == 'detail' and pc[2] == 'Version' and (uri.fragment.nil? or uri.fragment.empty?)
          tab.do_JavaScript(ShotgunJS.refresh_detail)
        end
      end
    end


    private
    def safari_running?
      require 'appscript'
      Appscript.app('System Events').processes.name.get.include? 'Safari'
    end

    def shotgun_tabs
      return [] unless safari_running?
      require 'appscript'
      Appscript.app('Safari').windows.get.map {|win| win.current_tab }.select do |tab|
        (tab.URL.get[0...(host_uri.length)] == host_uri) rescue false
      end
    end
  end
end
