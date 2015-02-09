require 'fileutils'

module ConvertMedia
  class Logger

    attr_reader :logfile
    def initialize(log_dir)
      @logfilename = File.join(log_dir, "#{Time.now.to_i}_#{rand(1000)}.log")
      @logfile = File.open(@logfilename, "a")
      self.class.registerLogger(self)
    end

    def close
      @logfile.close
    end
    
    def log(text, options={})
      logfile << text
      if text[-1] != "\n"
        logfile << "\n"
      end
      if options[:verbose]
        puts text
      end    
    end

    def self.registerLogger(logger)
      @logger = logger
    end
    
    def self.log_command(command, output)
      text = "#{Time.now.to_s}\n"
      text << "#{command}\n"
      text << "---\n"
      text << output
      text << "\n---\n"
      self.log(text)
    end

    def self.log_line(line)
      self.log("#{Time.now} : #{line}\n")
      puts line
    end

    def self.log(text, options={})
      if @logger
        @logger.log(text, options)
      else
        puts text
      end
    end
  end
end
