# see also todo.subtitle file, though what"s here is mostly pretty well functional/complete
require "./std_lib_helpers"
  require "./profanities.cr"


module SubtitleProfanityFinder
   @@expected_min_size = 10 # so unit tests can change it
   def self.expected_min_size=(new_min)
     @@expected_min_size = new_min
   end

   # splits into timestamps -> timestamps\ncontent blocks
   def self.split_to_entries(subtitles_raw_text)
     # p subtitles_raw_text.valid_encoding? # no crystal equiv.
     # also crystal length => size hint plz
     all = subtitles_raw_text.gsub("\r\n", "\n").scan(/^\d+\n\d\d:\d\d:\d\d.*?^$/m) # gsub line endings first so that it parses right when linux reads a windows file [maybe?]
     all = all.map{ |glop|
       lines = glop[0].lines.to_a
       index_line = lines[0]
       timing_line = lines[1].strip
       text = lines.to_a[2..-1].join(" ")
       # create english-ified version
       test = text.gsub(/<(.|)(\/|)i>/i, "") # kill <i> type things
       text = text.gsub(/[^'a-zA-Z0-9\-!,.\?"\n\(\)]/, " ") # kill weird stuff like ellipseses, also quotes would hurt so kill them too
       text = text.gsub(/  +/, " ") # remove duplicate "  " "s now since we may have inserted many
       text = text.strip
       # extract timing info
       # "00:03:00.0" , "00:04:00.0", "violence", "of some sort",
       timing_line =~ /((\d\d:\d\d:\d\d),(\d\d\d) --> (\d\d:\d\d:\d\d),(\d\d\d))/
       ts_begin = "#{$2}.#{$3}"
       ts_end = "#{$4}.#{$5}"
       out = { index_number: index_line.strip.to_i,
         beginning_time: translate_string_to_seconds(ts_begin),
         ending_time: translate_string_to_seconds(ts_end),
         text: text,
       }
       # add_single_line_minimized_text_from_multiline(text)
       out
     }
     if all.size < @@expected_min_size
       raise "unable to parse subtitle file? size=#{all.size} from #{subtitles_raw_text}"
     end

     # strip out auto inserted trailer/header subtitles since they don't actually match up to text
     reg =  / by|download| eng|www|http|sub/i
     while all[0][:text] =~ reg
      all.shift
     end
     while all[-1][:text] =~ reg
      all.pop
     end
     all
   end

   #def self.strip_trailer_header_punctuation(text) # useful?
   #  text.strip.gsub(/^[- ,_\.]+/, "").gsub(/[- ,_]+$/, "")
   #end

   def self.convert_to_regexps(profanity_tuples)
    all_profanity_combinations = [] of {Regex, String, String} # category, replace_with
    profanity_tuples.each{ |profanity_tuple|
      category = profanity_tuple[:category]
      profanity = profanity_tuple[:bad_word]
      sanitized = profanity_tuple[:sanitized]
      
      permutations = [profanity]
      if profanity =~ /l/
        permutations << profanity.gsub(/l/i, "i")
      end
      if profanity =~ /i/
        permutations << profanity.gsub(/i/i, "i")
      end
      
      replace_with = "[" + sanitized + "]"
      
      permutations.each{ |permutation| 
        if profanity_tuple[:type] == :full_word_only
          # \s is whitespace
          as_regexp = Regex.new("(?:\s|^|[^a-zA-Z])" + permutation + "(?:\s|$|[^a-zA-Z])", Regex::Options::IGNORE_CASE)
          all_profanity_combinations << {as_regexp, category, " " + replace_with + " "} # might introduce an extra space in there, but that"s prolly ok since they"re full-word already, and we collapse them
        else
          as_regexp = Regex.new(profanity, Regex::Options::IGNORE_CASE) # partial is the default
          all_profanity_combinations << {as_regexp, category, replace_with}
        end
      }
    }
    all_profanity_combinations
  end

  def self.edl_output_from_string(subtitles, include_minor_profanities=true) 
     # no crystal equiv? subtitles = subtitles.scrub # invalid UTF-8 creeps in at times... ruby 2.1+


    all_profanity_combinationss = [convert_to_regexps(Bad_profanities)] # double array so we can do the lesser ones second
    if include_minor_profanities
      all_profanity_combinationss += [convert_to_regexps(Semi_bad_profanities)]
    end
    
    output = [] of NamedTuple(start: Float64, endy: Float64, category: String, details: String)
    entries = split_to_entries(subtitles)
    all_profanity_combinationss.each{ |all_profanity_combinations|
      entries.each{ |entry|
        text = entry[:text]
        ts_begin = entry[:beginning_time]

        ts_end = entry[:ending_time]
        found_category = nil
        all_profanity_combinations.each{ |profanity, category, sanitized|
          if text =~ profanity
            found_category = category
            break
          end
        }
        
        if found_category
          # sanitize/euphemize the subtitle text for this and all profanities...
          all_profanity_combinationss.each{ |all_profanity_combinations2|
            all_profanity_combinations2.each{|profanity, category, sanitized|
              text = text.gsub(profanity, sanitized)
            }
          }
          
          # because we now may have duplicates for profs containing the letter l/i, refactor [[[euph]]] to just [euph]
          text = text.gsub(/\[+/, "[")
          text = text.gsub(/\]+/, "]")
          # crystal gah! entry[:text] = text # add_single_line_minimized_text_from_multiline text
          text = text.gsub(/[\r\n]|\n/, " ") # flatten up to x lines of text to just 1
          # crystal poor includes? here?
          unless output.index{|me| me[:start] == ts_begin} # i.e. some previous profanity already found this line :P
            output << {start: ts_begin, endy: ts_end, category: found_category, details: text.strip}
          end
        end
      }
    }
    output
  end
  
  # this one is 1:01:02.0 => 36692.0
  # its reverse is this: translate_time_to_human_readable
  def self.translate_string_to_seconds(s)
    # might actually already be a float, or int, depending on the yaml
    # int for 8 => 9 and also for 1:09 => 1:10
    if s.is_a? Number
      return s.to_f # easy out.
    end
    
    s = s.strip
    # s is like 1:01:02.0
    total = 0.0
    seconds = nil
    seconds = s.split(":")[-1]
    raise "does not look like a timestamp? " + seconds.inspect unless seconds =~ /^\d+(|[,.]\d+)$/
    seconds = seconds.gsub("," , ".")
    total += seconds.to_f
    minutes = s.split(":")[-2] || "0"
    total += 60 * minutes.to_i
    hours = s.split(":")[-3] || "0"
    total += 60* 60 * hours.to_i
    total
  end
  
end


if ARGV[0] == "--create-edl" # then .srt name
  incoming_filename = ARGV[1]
  stuff = SubtitleProfanityFinder.edl_output_from_string File.read(incoming_filename)
  puts "got"
  pp stuff
end