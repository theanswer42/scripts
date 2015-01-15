#!/usr/bin/ruby

# Building the options
# 1. for Video, This is straightforward:
# if(video stream is encoded with x264) { copy }
# else { add x264 with options }

# What are the input video codecs i see?
# ansi mpeg4 msmpeg4v3 none theora
#
# out of these, mpeg4 is straightforward
# ansi - my mistake.. all text files are treated as "ansi" video streams
# msmpeg4v3 (MP43) seems just another video codec
# theora - should be no problemo
# none - there's not a lot with this, so this is strange. lets see how this goes.
VIDEO_STREAMS_TO_COPY = ["h264", "png", "mjpeg"]
VIDEO_STREAMS_TO_ENCODE = ["mpeg4", "msmpeg4v3", "theora", "none"]
X264_ENCODE_OPTIONS = "libx264 -preset slow -crf 18"
def get_video_options(stream)
  if VIDEO_STREAMS_TO_COPY.include?(stream[:codec_name])
    return "copy"
  elsif VIDEO_STREAMS_TO_ENCODE.include?(stream[:codec_name])
    return X264_ENCODE_OPTIONS
  end
  ""
end

def get_subtitle_options(stream)
  "-map #{stream[:stream_specifier]} -c:#{stream[:stream_specifier]} copy"
end

# For audio, there are these streams:
# aac -> copy
# ac3 -> encode 
# dts -> encode
# flac -> encode
# mp3 -> copy
# vorbis -> encode
AUDIO_STREAMS_TO_COPY = ["aac", "mp3"]
AUDIO_STREAMS_TO_ENCODE = ["ac3", "dts", "flac", "vorbis"]
AAC_ENCODE_OPTIONS = "libfdk_aac --cutoff 15000 -vbr 5"
def get_audio_options(stream)
  if AUDIO_STREAMS_TO_COPY.include?(stream[:codec_name])
    return "copy"
  elsif AUDIO_STREAMS_TO_ENCODE.include?(stream[:codec_name])
    return AAC_ENCODE_OPTIONS
  end
  ""
end

filename = ARGV[0]

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

puts streams.inspect

options = ["-fix_sub_duration -i \"#{filename}\""]
stream_counts = {}
streams.each do |stream|
  stream_options = self.send("get_#{stream[:codec_type]}_options", stream)
  unless stream_options.empty?
    options << "-map #{stream[:stream_specifier]} -c:#{stream[:stream_specifier]} #{stream_options}"
    stream_counts[stream[:codec_type]] ||= 0
    stream_counts[stream[:codec_type]] += 1
  else
    stream[:skipped] = true
  end
end

puts options.join(" ")
