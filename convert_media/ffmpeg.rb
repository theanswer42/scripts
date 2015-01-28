require 'logger'
class ConvertMedia::Ffmpeg
  FFPROBE = "/opt/ffmpeg/bin/ffprobe"
  FFMPEG = "/opt/ffmpeg/bin/ffmpeg"
  
  
  private
  # return stdout+stderr
  def self.run_command(command)
    command = "#{command} 2>&1"
    output = status = nil
    begin
      output = `#{command}`
      status = $?.success?
    rescue Exception => e
      output = e.inspect
      status = false
    end
    ConvertMedia::Logger.log_command(command, output)
    if !status
      puts command
      puts output
      raise "command failed"
    end
    return output
  end

  def self.ffmpeg(input_options, input_filename, output_options, output_filename)
    run_command("#{FFMPEG} #{input_options.join(' ')} -i \"#{input_filename}\" #{output_options.join(' ')} \"#{output_filename}\""
  end
  
  def self.ffprobe(filename)
    @ffprobe_output||={}
    
    if @ffprobe_output[filename]
      return @ffprobe_output[filename]
    end
    
    ffprobe_output = run_command("#{FFPROBE} -show_streams -i \"#{filename}\"").split("\n").collect {|l| l.strip }

    stream_keys = ["codec_type", "codec_name", "TAG:language"]
    key_map = {"TAG:language" => "language"}
    
    streams = []
    
    stream_indexes = {}
    
    current_stream = {}
    ffprobe_output.each do |line|
      next if line == "[STREAM]"
      
      if line == "[/STREAM]"
        streams << current_stream
        current_stream = {}
        next
      end
      
      key, value = line.split("=")
      current_stream[(key_map[key] || key).to_sym] = value if stream_keys.include?(key)
      if key == "codec_type"
        current_stream[:stream_specifier] = "#{value[0]}:#{stream_indexes[value] ||= 0}"
        stream_indexes[value] += 1
      end
    end
    @ffprobe_output[filename] = streams
    
    return streams
  end

end
