#!/usr/bin/ruby

require 'fileutils'

class CvLogger
  LOG_DIR = File.join(ENV["HOME"], "log/convert_video")
  
  def self.logfilename
    unless @logfilename
      FileUtils.mkdir_p(LOG_DIR)
      @logfilename ||= "#{Time.now.to_i}_#{rand(1000)}.log"
    end
    @logfilename
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
    line = "#{Time.now} : #{line}\n"
    self.log("#{Time.now} : #{line}\n")
    puts line
  end

  def self.log(text, options={})
    
    FileUtils.mkdir_p(LOG_DIR)
    file = File.open(File.join(LOG_DIR, self.logfilename), "a")
    file << text
    if text[-1] != "\n"
      file << "\n"
    end
    file.close
    if options[:verbose]
      puts text
    end
  end
end

class VideoConverter
  # This is a pretty good summary of how i'm going to encode:
  CODECS = {
    :video => {
      :copy => ["h264", "png", "mjpeg"],
      :encode => ["mpeg4", "msmpeg4v3", "theora", "none"],
      :options => "libx264 -preset slow -crf 18",
    },
    :audio => {
      :copy => ["aac", "mp3"],
      :encode => ["ac3", "dts", "flac", "vorbis"],
      :options => "libfdk_aac -cutoff 15000 -vbr 5",
    },
    :subtitle => {
      :copy => ["mov_text"],
      :encode => ["srt", "ass", "xsub", "microdvd", "text"],
      :options => "mov_text",
    }
  }

  attr_reader :filename, :videoname
  def initialize(filename)
    @filename = filename
    @videoname = filename.gsub(/^(.*)\.[a-zA-Z0-9]*$/, '\1')
  end

  def get_stream_options(stream)
    codecs = CODECS[stream[:codec_type].to_sym]
    return "" unless codecs
    
    if codecs[:copy].include?(stream[:codec_name])
      return "copy"
    elsif codecs[:encode].include?(stream[:codec_name])
      return codecs[:options]
    else
      return ""
    end
  end

  def get_sub_stream(streams)
    subtitle_streams = streams.select {|stream| stream[:codec_type] == 'subtitle' }
    subtitle_streams.detect {|stream| stream[:codec_name] != "ass" && stream[:language] == "eng"} ||
      subtitle_streams.detect {|stream| stream[:language] == "eng"} ||
      subtitle_streams.first
  end
  
  # return stdout+stderr
  def run_command(command)
    command = "#{command} 2>&1"
    output = status = nil
    begin
      output = `#{command}`
      status = $?.success?
    rescue Exception => e
      output = e.inspect
      status = false
    end
    CvLogger.log_command(command, output)
    if !status
      puts command
      puts output
      raise "command failed"
    end
    return output
  end

  def ffprobe(filename)
    ffprobe_output = run_command("ffprobe -show_streams -i \"#{filename}\"").split("\n").collect {|l| l.strip }

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
    return streams
  end

  def convert_video(filename)
    return filename if File.extname(filename) == ".mp4"

    streams = ffprobe(filename)
    unless streams.detect {|stream| stream[:codec_type] == 'video' }
      raise "no video stream found for: \"#{filename}\""
    end
    
    videoname = filename.gsub(/^(.*)\.[a-zA-Z0-9]*$/, '\1')
    mp4_name = "#{videoname}.mp4"
    
    # First, generate an mp4 file: 
    unless File.exists?(mp4_name)
      options = [" -fix_sub_duration -i \"#{filename}\""]
      stream_counts = {}
      streams.each do |stream|
        # We'll handle subs later
        next if stream[:codec_type] == "subtitle"
        
        stream_options = get_stream_options(stream)
        unless stream_options.empty?
          options << "-map #{stream[:stream_specifier]} -c:#{stream[:stream_specifier]} #{stream_options}"
          stream_counts[stream[:codec_type]] ||= 0
          stream_counts[stream[:codec_type]] += 1
        else
          stream[:skipped] = true
        end
      end

      # Note that I'm applying subtitle options to all sub streams (c:s <options>)
      # This is because with multiple sub tracks in the input, it seems to confuse
      # ffmpeg and doesn't seem to pick up the specific sub option correctly. 
      if sub_stream = get_sub_stream(streams)
        sub_options = get_stream_options(sub_stream)
        options << "-map #{sub_stream[:stream_specifier]} -c:s #{sub_options} -metadata:#{sub_stream[:stream_specifier]} title=\"English\"" if sub_options
      end
      
      options << "\"#{mp4_name}\""
      
      # We can now run the encode
      begin
        run_command("ffmpeg -nostats #{options.join(' ')}")
      rescue Exception => e
        File.delete(mp4_name) if File.exists?(mp4_name)
        raise e
      end
    end
    return mp4_name
  end

  def extract_srt(mp4_name)
    srt_name = "#{videoname}.srt"

    # next up, generate an srt file.
    unless File.exists?(srt_name)
      # Usually, extracting the first subtitle track should be enough. Maybe extract
      # The first english subtitle track.
      # But one of the videos picked for testing had a particularly problematic ass stream
      # Even though it works in vlc, doing anything with it results in an empty srt or mov_text
      # stream and also a weird second "chapters" sub stream shows up.
      #
      # To get around this problem, we'll use the following rules:
      # First, try and find an english srt
      # Then the first english
      # finally, just pick the first
      
      streams = ffprobe(mp4_name)    
      extract_subs_options = [" -fix_sub_duration -i \"#{mp4_name}\""]
      
      if sub_stream = get_sub_stream(streams)
        extract_subs_options << "-map #{sub_stream[:stream_specifier]} -c:#{sub_stream[:stream_specifier]} srt"
        extract_subs_options << "\"#{videoname}.srt\""
        begin
          run_command("ffmpeg -nostats #{extract_subs_options.join(' ')}")
        rescue Exception => e
          File.delete(srt_name) if File.exists?(srt_name)
          raise e
        end
      else
        return nil
      end
    end
    # Here, its possible that the srt could be empty. In this case, I want to return empty.
    if File.read(srt_name).strip.empty?
      return nil
    end

    return srt_name
  end

  def extract_vtt(srt_name)
    vtt_name = "#{videoname}.vtt"

    # next up, generate an srt file.
    unless File.exists?(vtt_name)
      begin
        run_command("ffmpeg -nostats -i \"#{srt_name}\" -map s:0 -c:s webvtt \"#{vtt_name}\"")
      rescue Exception => e
        File.delete(vtt_name) if File.exists?(vtt_name)
        raise e
      end
    end
    return vtt_name
  end
  
  def convert
    result = {}
    raise "Not a file: #{filename}" unless(File.file?(filename))
    result[:mp4_name] = convert_video(filename)
    result[:srt_name] = extract_srt(result[:mp4_name])
    result[:vtt_name] = extract_vtt(result[:srt_name]) if result[:srt_name]
    return result
  end
end


# There are four ways to call this:
# convert_video.rb filename
#   - This will convert a single file
# convert_video.rb directory
#   - This will recursively convert all the video files in this directory. Result files will
#     be kept where the source files are found.
# convert_video.rb source_directory destination_directory
#   - same as convert directory, but now the converted files will be copied in the same path
#     in the destination_directory
# convert_video.rb source_directory destination_directory failure_directory
#   - same as convert directory with destination. Except now, anything that
#     fails gets moved over to the failure_directory.
#     This allows scheduling the converter. 

VIDEO_EXTENSIONS = [".avi", ".divx", ".m4v", ".mkv", ".mp4", ".ogm"]

PID_FILE_PATH = File.join(ENV["HOME"], "log", "convert_video", "convert_video.pid")
def check_pid()
  if File.exists?(PID_FILE_PATH)
    raise "Another convert process is running: #{File.read(PID_FILE_PATH)}"
  end
  pid = File.open(PID_FILE_PATH, "w")
  pid << "#{Process.pid}\n"
  pid.close
  return true
end

def release_pid()
  FileUtils.rm(PID_FILE_PATH)
end

check_pid()

source = ARGV[0]
if File.file?(source)
  begin
    v = VideoConverter.new(ARGV[0])
    v.convert
  rescue Exception => e
    CvLogger.log_line("Exception while processing: #{ARGV[0]}")
    CvLogger.log(e.inspect + "\n" + e.backtrace.join("\n"))
  end
elsif File.directory?(source)
  copy = false
  destination = ARGV[1]
  failure_destination = ARGV[2]
  
  if !destination.nil? && !destination.empty? && File.directory?(destination)
    copy = true
  end
  if !failure_destination.nil? && !failure_destination.empty? && File.directory?(failure_destination)
    copy_on_fail = true
  end
  CvLogger.log_line("Converting directory: #{source}, into: #{destination}")
  if copy
    CvLogger.log_line("mkdir -p #{File.join(destination, File.basename(source))}")
    FileUtils.mkdir_p(File.join(destination, File.basename(source)))
  end
  
  Dir.glob(File.join(source, "**", "*")) do |path|
    relative_path = path.gsub(/^#{source}/, '').gsub(/^\//, '')

    if File.directory?(path)
      if copy
        CvLogger.log_line("mkdir -p #{File.join(destination, File.basename(source), relative_path)}")
        FileUtils.mkdir_p(File.join(destination, File.basename(source), relative_path))
      end
    elsif File.file?(path) && VIDEO_EXTENSIONS.include?(File.extname(path).downcase)
      CvLogger.log_line("Converting: #{path}")
      v = VideoConverter.new(path)
      begin
        result_files = v.convert
      rescue Exception => e
        CvLogger.log_line("Exception while processing: #{path}")
        CvLogger.log(e.inspect + "\n" + e.backtrace.join("\n"))

        if copy_on_fail
          dest_fail_dir = File.join(failure_destination, File.dirname(source))
          CvLogger.log_line("mkdir -p #{dest_fail_dir}")
          FileUtils.mkdir_p(dest_fail_dir)
          CvLogger.log_line("mv #{path} #{dest_fail_dir}")
          FileUtils.mv(path, dest_fail_dir)          
        end
        
        next
      end
      CvLogger.log_line("Done: #{result_files.values.join(',')}")
      if copy
        CvLogger.log_line("mv #{result_files.values.join(' ')} #{File.join(destination, File.basename(source), File.dirname(relative_path))}")
        FileUtils.mv(result_files.values.compact, File.join(destination, File.basename(source), File.dirname(relative_path)))
      end
    end
  end
end

release_pid()
