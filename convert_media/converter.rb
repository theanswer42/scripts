require 'fileutils'

require File.join(File.dirname(__FILE__), "logger")
require File.join(File.dirname(__FILE__), "ffmpeg")

module ConvertMedia
  class Converter
    # mjpeg should be copied, because many times it will be used for things like dvd-covers.
    # But older cameras use mjpeg as their actual video codec, so, changing this to encode.
    # Perhaps the code here should say: "If mjpeg is the only video codec, then encode it, otherwise copy it"
    #
    # Also removed mjpeg from audio_ctr_codecs. This is slightly problematic because for audio ctrs, mjpeg is
    # always for copy...
    # 
    # For now, I will always try to encode mjpeg (this could lead to trouble)
    
    VIDEO_CTR_CODECS = {
      :video => {
        :copy => ["h264", "png"],
        :encode => ["mpeg4", "msmpeg4v3", "theora", "none", "mpeg1video", "mpeg2video", "mjpeg", "dvvideo", "h263"],
        :options => "libx264 -preset slow -crf 18",
      },
      :audio => {
        :copy => ["aac", "mp3"],
        :encode => ["ac3", "dts", "flac", "vorbis", "dca", "mp2", "pcm_s24le", "pcm_s16le", "amrnb", "pcm_u8", "mp1"],
        :options => "libfdk_aac -cutoff 15000 -vbr 5",
      },
      :subtitle => {
        :copy => ["mov_text"],
        :encode => ["srt", "ass", "microdvd", "text"],
        :options => "mov_text",
      }
    }

    # As far as possible, we don't want to convert one lossy format into another
    # see: https://trac.ffmpeg.org/wiki/Encode/HighQualityAudio
    # Which is why we'll let other html5-compatible audio codecs go through
    # see:https://developer.mozilla.org/en-US/docs/Web/HTML/Supported_media_formats#Browser_compatibility
    
    AUDIO_CTR_CODECS = {
      :audio => {
        :copy => ["mp3", "vorbis", "opus"],
        :encode => ["aac", "flac", "wmav2"],
        :options => "libopus",
      },
      :video => {
        :copy => ["png"]
      },

    }

    def self.medianame(filename)
      name = filename.gsub(/^(.*)\.[a-zA-Z0-9]*$/, '\1')
    end
    
    def self.convert(filename, options={})
      streams = ::ConvertMedia::Ffmpeg.ffprobe(filename)
      video_codecs = (VIDEO_CTR_CODECS[:video][:copy] + VIDEO_CTR_CODECS[:video][:encode]) - AUDIO_CTR_CODECS[:video][:copy]
      audio_codecs = AUDIO_CTR_CODECS[:audio][:copy] + AUDIO_CTR_CODECS[:audio][:encode]
      result = {}
      
      if streams.detect {|stream| stream[:codec_type] == "video" && video_codecs.include?(stream[:codec_name]) }
        # A workable video stream found... must be a video container.
        
        result.merge!(convert_video(filename, options))
        unless options[:dry_run]
          srt_name = extract_srt(filename)
          unless srt_name.empty?
            result[:converted] << srt_name 
            vtt_name = extract_vtt(srt_name)
            result[:converted] << vtt_name unless vtt_name.empty?
          end
        end
      elsif streams.detect {|stream| stream[:codec_type] == "audio" && audio_codecs.include?(stream[:codec_name]) }
        # Audio stream found... must be an audio container
        result = convert_audio(filename, options)
      else
        # No usable streams?
        ::ConvertMedia::Logger.log_line("Not video or audio: #{filename}")
      end
      
      return result
      
    rescue Exception => e
      ::ConvertMedia::Logger.log_line("Exception while processing: #{filename}")
      ::ConvertMedia::Logger.log(e.inspect + "\n" + e.backtrace.join("\n"))
      return {:failed => [filename]}
    end

    def self.convert_audio(filename, options={})
      streams = ::ConvertMedia::Ffmpeg.ffprobe(filename)
      extension = File.extname(filename)
      
      audio_stream = streams.detect {|stream| stream[:codec_type] == "audio" }
      raise "no audio stream found for: \"#{filename}\"" unless audio_stream
      
      # There is one little hole here. ogg containers can contain other audio
      # codecs than vorbis and opus: flac or pcm.
      # I do not currently support that (I'd have to then worry about what to do
      # With the converted file, which will potentially have the same name)
      
      if [".oga", ".ogg"].include?(extension)
        if !["opus", "vorbis"].include?(audio_stream[:codec_name])
          raise "#{audio_stream[:codec_name]} codec in ogg is not yet supported: #{filename}"
        end
        return {:converted => [filename]}
      end
      oga_name = "#{medianame(filename)}.oga"

      # If the audio stream does not need transcoding, then let it go.
      audio_stream_options = get_stream_options(:audio, audio_stream)
      if audio_stream_options == "copy"
        return {:converted => [filename]}
      end

      output_options = []
      streams.each do |stream|
        stream_options = get_stream_options(:audio, stream)
        unless stream_options.empty?
          output_options << "-map #{stream[:stream_specifier]} -c:#{stream[:stream_specifier]} #{stream_options}"
        end
      end

      if options[:dry_run]
        ::ConvertMedia::Ffmpeg.noop_ffmpeg([], filename, output_options, oga_name)
        return {:converted => [oga_name], :original => [filename]}
      end
      
      begin
        ::ConvertMedia::Ffmpeg.ffmpeg([], filename, output_options, oga_name)
      rescue Exception => e
        File.delete(oga_name) if File.exists?(oga_name)
        raise e
      end
      
      return {:converted => [oga_name], :original => [filename]}
    end
    
    def self.convert_video(filename, options={})
      return {:converted => [filename]} if File.extname(filename) == ".mp4"
      
      mp4_name = "#{medianame(filename)}.mp4"
      return {:converted => [mp4_name], :original => [filename]} if File.file?(mp4_name)
      
      streams = ::ConvertMedia::Ffmpeg.ffprobe(filename)
      unless streams.detect {|stream| stream[:codec_type] == 'video' }
        raise "no video stream found for: \"#{filename}\""
      end
      output_options = []
      
      # Copy global metadata. This should preserve creation timestamps. 
      output_options << "-map_metadata:g 0:g"
      
      streams.each do |stream|
        # We'll handle subs later
        next if stream[:codec_type] == "subtitle"
        
        stream_options = get_stream_options(:video, stream)
        unless stream_options.empty?
          output_options << "-map #{stream[:stream_specifier]} -c:#{stream[:stream_specifier]} #{stream_options}"
        end
      end

      # Note that I'm applying subtitle options to all sub streams (c:s <options>)
      # This is because with multiple sub tracks in the input, it seems to confuse
      # ffmpeg and doesn't seem to pick up the specific sub option correctly. 
      if sub_stream = get_sub_stream(streams)
        sub_options = get_stream_options(:video, sub_stream)
        output_options << "-map #{sub_stream[:stream_specifier]} -c:s #{sub_options} -metadata:#{sub_stream[:stream_specifier]} title=\"English\"" if sub_options
      end
      
      if options[:dry_run]
        ::ConvertMedia::Ffmpeg.noop_ffmpeg(["-fix_sub_duration"], filename, output_options, mp4_name)
        return {:converted => [mp4_name], :original => [filename]}
      end

      # We can now run the encode
      begin
        ::ConvertMedia::Ffmpeg.ffmpeg(["-fix_sub_duration"], filename, output_options, mp4_name)
      rescue Exception => e
        File.delete(mp4_name) if File.exists?(mp4_name)
        raise e
      end
      
      return {:converted => [mp4_name], :original => [filename]}
      
    end


    def self.extract_srt(filename)
      name = medianame(filename)
      srt_name = "#{name}.srt"
      
      return srt_name if File.exists?(srt_name)
      
      streams = ::ConvertMedia::Ffmpeg.ffprobe(filename)

      sub_stream = get_sub_stream(streams)
      return "" if !sub_stream
      sub_options = ["-map #{sub_stream[:stream_specifier]} -c:#{sub_stream[:stream_specifier]} srt"]
      begin
        ::ConvertMedia::Ffmpeg.ffmpeg(["-fix_sub_duration"], filename, sub_options, srt_name)
      rescue Exception => e
        FileUtils.rm(srt_name) if File.exists?(srt_name)
        return ""
      end

      # Sometimes, blank srt files are generated? Remove the file if empty
      if File.read(srt_name).strip.empty?
        FileUtils.rm(srt_name)
        return ""
      end
      return srt_name
    end

    def self.extract_vtt(filename)
      name = medianame(filename)
      vtt_name = "#{name}.vtt"
      return vtt_name if File.exists?(vtt_name)
      
      begin
        ::ConvertMedia::Ffmpeg.ffmpeg([], filename, ["-map s:0 -c:s webvtt"], vtt_name)
      rescue Exception => e
        FileUtils.rm(vtt_name) if File.exists?(vtt_name)
        return ""
      end
      return vtt_name
    end

    
    def self.get_stream_options(ctr_type, stream)
      codecs = nil
      if ctr_type == :video
        codecs = VIDEO_CTR_CODECS[stream[:codec_type].to_sym]
      elsif ctr_type == :audio && stream[:codec_type] == "audio"
        codecs = AUDIO_CTR_CODECS[stream[:codec_type].to_sym]
      end
      return "" unless codecs
      
      if codecs[:copy].include?(stream[:codec_name])
        # perhaps not the best way to do it, but don't know better.
        # videos produced by some things use h.264 lossless. This needs
        # to be detected and compressed. 
        if stream[:codec_name] == "h264" && stream[:bit_rate] == "N/A" && stream[:max_bit_rate] == "N/A"
          return codecs[:options]
        else
          return "copy"
        end
      elsif codecs[:encode].include?(stream[:codec_name])
        return codecs[:options]
      else
        return ""
      end
    end

    SUBTITLE_CODECS_SUPPORTED = VIDEO_CTR_CODECS[:subtitle][:encode] + VIDEO_CTR_CODECS[:subtitle][:copy]
    def self.get_sub_stream(streams)
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
      
      subtitle_streams = streams.select {|stream| stream[:codec_type] == 'subtitle' && SUBTITLE_CODECS_SUPPORTED.include?(stream[:codec_name])}
      subtitle_streams.detect {|stream| stream[:codec_name] != "ass" && stream[:language] == "eng"} ||
        subtitle_streams.detect {|stream| stream[:language] == "eng"} ||
        subtitle_streams.first
    end


  end
end
