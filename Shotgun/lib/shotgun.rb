require 'yaml'
require 'shotgun_browser'


class Shotgun
  attr_accessor :debug

  def initialize
    @debug = false
    @cached_field_names = {}
  end

  def config
    @config ||= YAML.load_file(File.dirname(__FILE__) + '/../shotgun_config.yaml')
  end

  def map_custom_fields(entity, params)
    Hash[*params.map do |descrip, val|
      field = config['custom_fields'][entity][descrip.to_s] rescue nil
      [field, val] if field
    end.compact.flatten]
  end

  def browser
    @browser ||= case config['web_browser']
                 when 'safari'
                   ShotgunBrowser::Safari.new(config['shotgun_url'])
                 when 'firefox'
                   ShotgunBrowser::FirefoxSD.new(config['shotgun_url'])
                 else
                   ShotgunBrowser::NullBrowser.new(config['shotgun_url'])
                 end
  end

  FindDefaults = { :filters         => [],
                   :fields          => ['id'],
                   :order           => [],
                   :filter_operator => :all,
                   :limit           => 0,
                   :retired_only    => false }

  def find(entity, opts = {})
    data = {:entity => entity}.merge(FindDefaults).merge(opts)
    data[:fields] = field_names(entity) if data[:fields] == :all
    sg_call('find', data)
  end

  def find_one(entity, opts = {})
    data = {:entity => entity}.merge(FindDefaults).merge(opts)
    data[:fields] = field_names(entity) if data[:fields] == :all
    sg_call('find_one', data)
  end

  def read(entity, id, opts = {})
    args = FindDefaults.merge(opts).merge(:filters => [['id', 'is', id]])
    val = find_one(entity, args)
    fail "Unable to find entity '#{entity}' with ID #{id}" if val.nil?
    val
  end

  def create(entity, data)
    sg_call('create', {:entity => entity, :data => data})
  end

  def update(entity, id, data)
    sg_call('update', {:entity => entity, :id => id, :data => data})
  end

  def delete(entity, id)
    sg_call('delete', {:entity => entity, :id => id})
  end

  def upload(entity, id, path, field = nil, display_name = nil)
    x = sg_call('upload', {:entity => entity, :id => id, :path => String(path), :field_name => field, :display_name => display_name})
    x && x.to_i
  end

  def upload_thumbnail(entity, id, path)
    x = sg_call('upload_thumbnail', {:entity => entity, :id => id, :path => String(path)})
    x && x.to_i
  end

  def field_names(entity)
    @cached_field_names[entity] ||= sg_call('schema_field_read', {:entity => entity}).keys
  end

  def create_field(entity, name, type, attrs = {})
    @cached_field_names[entity] = nil
    x = sg_call('schema_field_create', {:entity => entity, :name => name, :type => type.to_s, :attrs => attrs})
    x && x.split[0]
  end

  def url_for_attachment_id(id)
    x = sg_call('_url_for_attachment_id', {:id => id})
    # Python YAML is dumping the URL string with '\n...\n' added for some reason
    x && URI::parse(x.chomp(' ...')) rescue nil
  end

  private
  def sg_call(method_name, data = nil)
    $stderr.puts("Shotgun: #{method_name} (entity: #{data[:entity]})") if debug
    IO.popen(%Q["#{Shotgun.python_cmd}" "#{File.dirname(__FILE__)}\"/shotgun_slave.py #{method_name}], 'r+') do |io|
      io.puts({:config => auth_config, :data => data}.to_hash_with_string_keys.to_yaml)
      io.close_write
      YAML::load(io.read) || nil
    end
  end

  def auth_config
    {'shotgun_url' => config['shotgun_url'], 'script_name' => config['script_name'], 'script_api_key' => config['api_key']}
  end

  @@python_cmd = nil
  def self.python_cmd
    if @@python_cmd
      @@python_cmd
    else
      paths = %w[python2.6 python2.5 python2.4 pythonw python]
      case RUBY_PLATFORM
      when /mswin32|mingw32/
        paths += %w[C:/Python26/pythonw.exe C:/Python25/pythonw.exe C:/Python24/pythonw.exe]
      end

      begin
        path = paths.shift
        case RUBY_PLATFORM
        when /mswin32|mingw32/
          cmd = path + ' -c "exit()"'
          IO.popen(cmd) {|io| nil }
        else
          fail unless system(path, '-c', 'exit()')
        end
        @@python_cmd = path
      rescue
        if paths.empty?
          fail 'Unable to find Python!'
        else
          retry
        end
      end
    end
  end
end


class Hash
  def to_hash_with_string_keys
    meth = :to_hash_with_string_keys
    convert = lambda do |obj|
      if obj.respond_to? meth
        obj.send(meth)
      elsif obj.is_a? Array
        obj.map {|x| convert.call(x) }
      elsif obj.is_a? Symbol
        obj.to_s
      else
        obj
      end
    end

    inject({}) {|hsh, (k, v)| hsh[String(k)] = convert.call(v); hsh }
  end
end
