#!/usr/bin/ruby

# Building the options
# 1. for Video, This is straightforward:
# if(video stream is encoded with x264) { copy }
# else { add x264 with options }

CODECS = {
  :video => {
    :copy => ["h264", "png", "mjpeg"],
    :encode => ["mpeg4", "msmpeg4v3", "theora", "none"],
    :options => "libx264 -preset slow -crf 18",
  },
  :audio => {
    :copy => ["aac", "mp3"],
    :encode => ["ac3", "dts", "flac", "vorbis"],
    :options => "libfdk_aac --cutoff 15000 -vbr 5",
  },
  :subtitle => {
    :copy => ["mov_text"],
    :encode => ["subrip", "ass", "dvdsub", "xsub", "microdvd"],
    :options => "mov_text",
  }
}

def get_stream_options(stream)
  codecs = CODECS[stream[:codec_type].to_sym]
  if codecs[:copy].include?(stream[:codec_name])
    return "copy"
  elsif codecs[:encode].include?(stream[:codec_name])
    return codecs[:options]
  else
    return ""
  end
end

def get_sub_extract_options(stream)
  options = get_stream_options(stream)
  if options != "copy"
    options = "subrip"
  end
end

filename = ARGV[0]
option = ARGV[1]

raise "Not a file: #{filename}" unless(File.file?(filename))

ffprobe_output = `ffprobe -show_streams -i "#{filename}" 2>&1`.split("\n").collect {|l| l.strip }

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

# First, generate an mp4 file: 
unless File.exists?("#{File.basename(filename)}.mp4")
  options = [" -nostats -fix_sub_duration -i \"#{filename}\""]
  stream_counts = {}
  streams.each do |stream|
    stream_options = get_stream_options(stream)
    unless stream_options.empty?
      options << "-map #{stream[:stream_specifier]} -c:#{stream[:stream_specifier]} #{stream_options}"
      stream_counts[stream[:codec_type]] ||= 0
      stream_counts[stream[:codec_type]] += 1
    else
      stream[:skipped] = true
    end
  end
  options << "\"#{File.basename(filename)}\""

  # We can now run the encode
  puts "ffmpeg #{options.join(' ')}"
end

# next up, generate an srt file.
unless File.exists?("#{File.basename(filename)}.srt")
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
  
  extract_subs_options = [" -fix_sub_duration -i \"#{filename}\""]
  subtitle_streams = streams.select {|stream| next unless stream[:codec_type] == 'subtitle' }
  
  stream_to_extract =
    subtitle_streams.detect {|stream| stream[:codec_name] != "ass" && stream[:language] == "eng"} ||
    subtitle_streams.detect {|stream| stream[:language] == "eng"} ||
    subtitle_streams.first

  if stream_to_extract
    subs_options = get_sub_extract_options(stream)
    if !subs_options.empty?
      extract_subs_options << "-map #{stream[:stream_specifier]} -c:#{stream[:stream_specifier]} #{subs_options}"
      extract_subs_options << "\"#{File.basename(filename)}.srt\""
      puts "ffmpeg #{extract_subs_options.join(' ')}"
    end
  end
end

# Finally, generate a vtt file
if File.exists?("#{File.basename(filename)}.srt") &&
   !File.exists?("#{File.basename(filename)}.vtt")
  puts "ffmpeg -i \"#{File.basename(filename)}.srt\" -map s:0 -c:s:0 webvtt \"#{File.basename(filename)}.vtt\""
end
