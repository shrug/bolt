require 'yaml'
require 'bolt/cli'
require 'logging'

module Bolt
  Config = Struct.new(
    :concurrency,
    :format,
    :inventoryfile,
    :log_level,
    :modulepath,
    :transport,
    :transports
  ) do

    DEFAULTS = {
      concurrency: 100,
      transport: 'ssh',
      format: 'human'
    }.freeze

    TRANSPORT_OPTIONS = %i[host_key_check password run_as sudo_password extensions
                           ssl key tty tmpdir user connect_timeout cacert
                           token_file orch_task_environment service_url].freeze

    TRANSPORT_DEFAULTS = {
      connect_timeout: 10,
      orch_task_environment: 'production',
      tty: false
    }.freeze

    TRANSPORT_SPECIFIC_DEFAULTS = {
      ssh: {
        host_key_check: true
      },
      winrm: {
        ssl: true
      },
      pcp: {}
    }.freeze

    TRANSPORTS = %i[ssh winrm pcp].freeze

    def initialize(**kwargs)
      super()
      @logger = Logging.logger[self]
      DEFAULTS.merge(kwargs).each { |k, v| self[k] = v }

      self[:transports] ||= {}
      TRANSPORTS.each do |transport|
        unless self[:transports][transport]
          self[:transports][transport] = {}
        end
        TRANSPORT_DEFAULTS.each do |k, v|
          unless self[:transports][transport][k]
            self[:transports][transport][k] = v
          end
        end

        TRANSPORT_SPECIFIC_DEFAULTS[transport].each do |k, v|
          unless self[:transports][transport].key? k
            self[:transports][transport][k] = v
          end
        end
      end
    end

    def default_paths
      root_path = File.expand_path(File.join('~', '.puppetlabs'))
      [File.join(root_path, 'bolt.yaml'), File.join(root_path, 'bolt.yml')]
    end

    def update_from_file(data)
      if data['modulepath']
        self[:modulepath] = data['modulepath'].split(File::PATH_SEPARATOR)
      end

      if data['inventoryfile']
        self[:inventoryfile] = data['inventoryfile']
      end

      if data['concurrency']
        self[:concurrency] = data['concurrency']
      end

      if data['format']
        self[:format] = data['format'] if data['format']
      end

      if data['ssh']
        if data['ssh']['private-key']
          self[:transports][:ssh][:key] = data['ssh']['private-key']
        end
        if data['ssh'].key?('host-key-check')
          self[:transports][:ssh][:host_key_check] = data['ssh']['host-key-check']
        end
        if data['ssh']['connect-timeout']
          self[:transports][:ssh][:connect_timeout] = data['ssh']['connect-timeout']
        end
        if data['ssh']['tmpdir']
          self[:transports][:ssh][:tmpdir] = data['ssh']['tmpdir']
        end
        if data['ssh']['run-as']
          self[:transports][:ssh][:run_as] = data['ssh']['run-as']
        end
      end

      if data['winrm']
        if data['winrm']['connect-timeout']
          self[:transports][:winrm][:connect_timeout] = data['winrm']['connect-timeout']
        end
        if data['winrm'].key?('ssl')
          self[:transports][:winrm][:ssl] = data['winrm']['ssl']
        end
        if data['winrm']['tmpdir']
          self[:transports][:winrm][:tmpdir] = data['winrm']['tmpdir']
        end
        if data['winrm']['cacert']
          self[:transports][:winrm][:cacert] = data['winrm']['cacert']
        end
        if data['winrm']['extensions']
          # Accept a single entry or a list, ensure each is prefixed with '.'
          self[:transports][:winrm][:extensions] =
            [data['winrm']['extensions']].flatten.map { |ext| ext[0] != '.' ? '.' + ext : ext }
        end
      end

      if data['pcp']
        if data['pcp']['service-url']
          self[:transports][:pcp][:service_url] = data['pcp']['service-url']
        end
        if data['pcp']['cacert']
          self[:transports][:pcp][:cacert] = data['pcp']['cacert']
        end
        if data['pcp']['token-file']
          self[:transports][:pcp][:token_file] = data['pcp']['token-file']
        end
        if data['pcp']['task-environment']
          self[:transports][:pcp][:orch_task_environment] = data['pcp']['task-environment']
        end
      end
    end

    def load_file(path)
      data = Bolt::Util.read_config_file(path, default_paths, 'config')
      update_from_file(data) if data
    end

    def update_from_cli(options)
      %i[concurrency transport format modulepath inventoryfile].each do |key|
        self[key] = options[key] if options[key]
      end

      if options[:debug]
        self[:log_level] = :debug
      elsif options[:verbose]
        self[:log_level] = :info
      end

      TRANSPORT_OPTIONS.each do |key|
        TRANSPORTS.each do |transport|
          unless %i[ssl host_key_check].any? { |k| k == key }
            self[:transports][transport][key] = options[key] if options[key]
            next
          end
          if key == :ssl && transport == :winrm
            # this defaults to true so we need to check the presence of the key
            self[:transports][transport][key] = options[key] if options.key?(key)
            next
          elsif key == :host_key_check && transport == :ssh
            # this defaults to true so we need to check the presence of the key
            self[:transports][transport][key] = options[key] if options.key?(key)
            next
          end
        end
      end
    end

    def transport_conf
      { transport: self[:transport],
        transports: self[:transports] }
    end

    def validate
      TRANSPORTS.each do |transport|
        self[:transports][transport]
      end

      unless %w[human json].include? self[:format]
        raise Bolt::CLIError, "Unsupported format: '#{self[:format]}'"
      end

      if self[:transports][:ssh][:sudo_password] && self[:transports][:ssh][:run_as].nil?
        @logger.warn("--sudo-password will not be used without specifying a " \
                     "user to escalate to with --run-as")
      end

      self[:transports].each_value do |v|
        timeout_value = v[:connect_timeout]
        unless timeout_value.is_a?(Integer) || timeout_value.nil?
          error_msg = "connect-timeout value must be an Integer, received #{timeout_value}:#{timeout_value.class}"
          raise Bolt::CLIError, error_msg
        end
      end
    end
  end
end
