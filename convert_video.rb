#!/usr/bin/ruby

require 'fileutils'

class CvLogger
  LOG_DIR = File.join(ENV["HOME"], "log/convert_video")
  
  def self.logfilename
    @logfilename ||= "#{Time.now.to_i}_#{rand(1000)}.log"
  end
  
  def self.log(command, output)
    FileUtils.mkdir_p(LOG_DIR)
    file = File.open(File.join(LOG_DIR, self.logfilename), "a")
    file << "#{Time.now.to_s}\n"
    file << "#{command}\n"
    file << "---\n"
    file << output
    file << "\n---\n"
    file.close
  end
end
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
    :encode => ["srt", "ass", "dvdsub", "xsub", "microdvd"],
    :options => "mov_text",
  }
}

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
  CvLogger.log(command, output)
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
      options << "-map #{sub_stream[:stream_specifier]} -c:s #{sub_options} -metadata:#{sub_stream[:stream_specifier]} title=\"English\""
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

def extract_srt(filename)
  videoname = filename.gsub(/^(.*)\.[a-zA-Z0-9]*$/, '\1')
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
    
    streams = ffprobe(filename)    
    extract_subs_options = [" -fix_sub_duration -i \"#{filename}\""]
    
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
  return srt_name
end

def extract_vtt(filename)
  videoname = filename.gsub(/^(.*)\.[a-zA-Z0-9]*$/, '\1')
  vtt_name = "#{videoname}.vtt"

  # next up, generate an srt file.
  unless File.exists?(vtt_name)
    begin
      run_command("ffmpeg -nostats -i \"#{filename}\" -map s:0 -c:s webvtt \"#{vtt_name}\"")
    rescue Exception => e
      File.delete(vtt_name) if File.exists?(vtt_name)
      raise e
    end
  end
  return vtt_name
end


filename = ARGV[0]

raise "Not a file: #{filename}" unless(File.file?(filename))

mp4_name = convert_video(filename)
srt_name = extract_srt(mp4_name)
vtt_name = extract_vtt(srt_name) if srt_name

puts "Done!"

