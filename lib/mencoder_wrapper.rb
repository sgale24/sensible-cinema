require 'sane'
require_relative 'vlc_programmer'

class MencoderWrapper

  class << self
  
    def get_bat_commands these_mutes, this_drive, to_here_final_file, start_here = nil, end_here = nil
      combined = VLCProgrammer.convert_incoming_to_split_sectors these_mutes
      
      if start_here || end_here
        raise 'need both' unless end_here && start_here
        start_here = OverLayer.translate_string_to_seconds(start_here)
        end_here   = OverLayer.translate_string_to_seconds(end_here)
        combined.select!{|start, endy, type| start > start_here && endy < end_here }
        raise Exception.new('unable to find any edit decisions to do within that range') unless combined.length > 0
        previous_end = start_here
      else
        previous_end = 0
      end
      @big_temp = to_here_final_file + ".fulli.tmp.avi"
      out = ""
      out += "call mencoder dvd:// -oac copy -lavcopts keyint=1 -ovc lavc -o #{@big_temp} -dvd-device #{this_drive} \n"
      @idx = 0
      combined.each {|start, endy, type|
        if start > previous_end
          out += get_section previous_end, start, false, to_here_final_file
        end
        # type is either mute or :blank or :mute
        if type == :blank
         # do nothing... clip will be avoided
        else
          out += get_section start, endy, true, to_here_final_file
        end
        previous_end = endy
      }
      out += get_section previous_end, end_here || 1_000_000, false, to_here_final_file
      partials = (1..@idx).map{|n| "#{to_here_final_file}.avi.#{n}"}
      
      out += "del #{to_here_final_file}\n"
      out += "mencoder #{partials.join(' ')} -o #{to_here_final_file} -ovc copy -oac copy\n"
      out += "@rem del #{@big_temp}\n" # LODO
      
      out += "@rem del " + partials.join(' ') + "\n"# LODO

      out
    end
    
    def get_section start, endy, should_mute, to_here_final_file    
      raise if start == endy # should never be able to happen...
      # delete 0.001 as per wiki's suggestion.
      endy = endy - start - 0.001
      # very decreased volume is like muting :)
      sound_command = should_mute ? "-af volume=-200 -oac lavc" : "-oac lavc"  # LODO -oac copy ?
      "call mencoder #{@big_temp} -ss #{start} -endpos #{endy} -o #{to_here_final_file}.avi.#{@idx += 1} -ovc copy #{sound_command}\n"
    end
  
  end

end

if $0 == __FILE__
  require 'rubygems'
  require 'sane'
  puts 'syntax: yaml_file_name e:\ to_here.avi 00:15 (start) 00:25 (end)'
  a = YAML.load_file ARGV.shift
  File.write('range.bat', MencoderWrapper.get_bat_commands(a, *ARGV))
  print 'wrote range.bat'
end