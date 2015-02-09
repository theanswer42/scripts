require 'optparse'
require 'yaml'
require 'ostruct'
require 'fileutils'
require 'pp'

require 'logger'
require 'converter'

class ConvertMedia::ConvertMedia
  private
  def get_options(args)
    options = OpenStruct.new
    
    # These are the defaults
    options.pid = File.join(ENV["HOME"], "log", "convert_video", "convert_video.pid")
    options.log = File.join(ENV["HOME"], "log", "convert_video")
    
    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: convert_media.rb options"
      opts.separator ""
      opts.separator "Options:"
      opts.on("--file FILENAME",
              "Convert a single file") do |filename|
        
        options.filename = filename
      end
      opts.on("--config FILENAME",
              "Use a config file to read options (will be overridden by options given here)") do |filename|
        options.config_file = filename
      end
      opts.on("--source DIRECTORY",
              "Convert a directory recursively") do |directory|
        options.source = directory
      end
      opts.on("--converted DIRECTORY",
              "Move converted files to this directory") do |directory|
        options.converted = directory
      end
      opts.on("--failed DIRECTORY",
              "Move failed conversions to this directory") do | directory|
        options.failed = directory
      end
      opts.on("--original DIRECTORY",
              "Move source files after conversion into this directory") do |directory|
        options.original = directory
      end
      opts.on("--pid FILENAME",
              "Path to the pid file to use") do |filename|
        options.pid = filename
      end
      opts.on("--log DIRECTORY",
              "Log directory to use") do |directory|
        options.log = directory
      end
      opts.on("--dry-run",
              "Only print out what will be done without doing it (will still run ffprobe)") do
        options.dry_run = true
      end
      opts.on_tail("--help", "Show this message") do
        puts opts
        exit 0
      end
    end
    opt_parser.parse!(args)

    if(options.config_file)
      raise "--config #{filename} - file does not exist" unless File.exists?(filename)
      config = YAML.load(File.read(config_file))
      config.merge!(options.to_h)
      options = OpenStruct.new(config)
    end

    # Check all the options! 
    if options.filename && !File.exists?(options.filename)
      raise "file not found: #{options.filename}"
    end
    if !File.directory?(options.log)
      raise "log directory does not exist: #{options.log}"
    end
    if !File.directory?(File.dirname(options.pid))
      raise "pid directory does not exist: #{File.dirname(options.pid)}"
    end
    [:source, :converted, :failed, :original].each do |dir|
      if options[dir] && !File.directory?(options[dir])
        raise "#{dir} directory does not exist: #{options[dir]}"
      end
    end
    if !options.filename && !options.source
      raise "Either filename or source directory must be given"
    end
    
    options
    
  end

  def check_pid
    if File.exists?(options.pid)
      raise "Another convert process is running: #{File.read(options.pid)}"
    end
    pid = File.open(options.pid, "w")
    pid << "#{Process.pid}\n"
    pid.close
    return true
  end

  def release_pid
    FileUtils.rm(options.pid)
  end

  # Result always has these keys:
  #  :converted => []
  #  :failed => []
  #  :original => []
  def handle_result(path, result)
    relative_path_dir = ""
    if options.source
      relative_path_dir = File.dirname(path.gsub(/^#{source}/, '').gsub(/^\//, ''))
    end

    [:converted, :failed, :original].each do |key|
      if options[key] && !result[key].empty?
        destination_dir = File.join(options[key], relative_path_dir)
        unless File.directory?(destination_dir)
          ConvertMedia::Logger.log_line("mkdir -p #{destination_dir}")
          FileUtils.mkdir_p(destination_dir) unless options.dry_run
        end
        
        result[key].each do |r|
          ConvertMedia::Logger.log_line("mv #{r} #{destination_dir}")
          FileUtils.mv(r, destination_dir) unless options.dry_run
        end
      end
    end
  end

  
  public
  
  attr_reader :options
  def initialize(args)
    @options = get_options(args)
    @logger = ConvertMedia::Logger.new(@options.log)
  end
  
  def work
    check_pid
    
    if options.filename
      handle_result(ConvertMedia::Converter.convert(options.filename, :dry_run => options.dry_run))
    else
      Dir.glob(File.join(options.source, "**", "*")) do |path|
        if File.file?(path)
          handle_result(ConvertMedia::Converter.convert(path, :dry_run => options.dry_run))
        end
      end
    end
    
  ensure
    release_pid
    @logger.close
  end
end

cm = ConvertMedia::ConvertMedia.new(ARGV)
cm.work
