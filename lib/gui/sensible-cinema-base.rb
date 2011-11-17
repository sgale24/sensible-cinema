#!/usr/bin/ruby # so my editor will like the file...
=begin
Copyright 2010, Roger Pack 
This file is part of Sensible Cinema.

    Sensible Cinema is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Sensible Cinema is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Sensible Cinema.  If not, see <http://www.gnu.org/licenses/>.
=end

alias system_original system
require 'fileutils'

class String
  def snake_case
    self.gsub(/::/, '/').
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    tr("-", "_").
    downcase
  end
end

# a few I'll always need no matter what...
require_relative '../jruby-swing-helpers/swing_helpers'
require_relative '../storage'
require_relative '../edl_parser'
require 'tmpdir'
require 'whichr'
require 'os'
if OS.doze?
  autoload :WMI, 'ruby-wmi'
  autoload :EightThree, './lib/eight_three'
end

# attempt to load on demand...i.e. faster...
for kls in [:MencoderWrapper, :MplayerEdl, :PlayAudio, :SubtitleProfanityFinder, :ConvertThirtyFps]
  autoload kls, "./lib/#{kls.to_s.snake_case}"
end

for kls in [:PlayAudio, :RubyClip, :DriveInfo]
  autoload kls, "./lib/jruby-swing-helpers/#{kls.to_s.snake_case}"
end


if OS.windows?
  vendor_cache = File.expand_path(File.dirname(__FILE__)) + '/../../vendor/cache'
  for name in ['.', 'mencoder', 'ffmpeg']
    # put them all before the old path
    ENV['PATH'] = (vendor_cache + '/' + name).to_filename + ';' + ENV['PATH']
  end
  
  installed_smplayer_folders = Dir['{c,d,e,f,g}:/program files*/MPlayer for Windows*'] # sometimes ends with UI? huh?

  for folder in installed_smplayer_folders
    ENV['PATH'] = ENV['PATH'] + ";#{folder.gsub('/', "\\")}"
  end

else
  ENV['PATH'] = ENV['PATH'] + ':' + '/opt/local/bin' # add macports' bin in, just in case...
end

import 'javax.swing.ImageIcon'
require_relative './sensible-cinema-dependencies'

module SensibleSwing
  include SwingHelpers # various swing classes
  JFrame
  VERSION = File.read(File.dirname(__FILE__) + "/../../VERSION").strip
  puts "v. " + VERSION
  
  UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName()) # <sigh>
  
  class MainWindow < JFrame
    include SwingHelpers # work-around?
    
    def initialize be_visible = true
      super "Sensible-Cinema #{VERSION} (GPL)"
      force_accept_license_first
      setDefaultCloseOperation JFrame::EXIT_ON_CLOSE # closes the whole app when they hit X ...
      @panel = JPanel.new
      @buttons = []
      @panel.set_layout nil
      add @panel # why can't I just slap these down? panel? huh?
      @starting_button_y = 40
      @button_width = 400      
      
      add_text_line "Welcome to Sensible Cinema!"
      @starting_button_y += 10 # kinder ugly...
      add_text_line "      Rest mouse over buttons for \"help\" type descriptions (tooltips)."
      add_text_line ""
      
      setIconImage(ImageIcon.new(__DIR__ + "/../vendor/profs.png").getImage())
      check_for_various_dependencies
      set_visible be_visible
    end
    
    def get_title_track descriptors, use_default_of_one = true
      given = descriptors["dvd_title_track"] 
      given ||= "1" if use_default_of_one
      given
    end

    def we_are_in_create_mode
     ARGV.index("--create-mode")
    end
    
    def we_are_in_developer_mode?
      ARGV.detect{|a| a == '--developer-mode'}
    end
    
    def new_jbutton title, tooltip = nil
      button = JButton.new title
      button.tool_tip = tooltip
      button.set_bounds(44, @starting_button_y, @button_width, 23)
      @panel.add button
      @buttons << button
      if block_given? # allow for new_jbutton("xx") do ... end [this is possible through some miraculous means LOL]
        button.on_clicked { yield }
      end
      increment_button_location
      button
    end
    
    def add_text_line line
      jlabel = JLabel.new line
      happy = Font.new("Tahoma", Font::PLAIN, 11)
      jlabel.setFont(happy)
      jlabel.set_bounds(44,@starting_button_y ,460,14)
      @panel.add jlabel
      increment_button_location 18
      jlabel
    end
    
    def increment_button_location how_much = 30
      @starting_button_y += how_much
      setSize @button_width+80, @starting_button_y + 50
    end
    
    def force_accept_license_first
      if !(LocalStorage['main_license_accepted'] == VERSION)
        require_blocking_license_accept_dialog 'Sensible Cinema', 'gplv3', 'http://www.gnu.org/licenses/gpl.html', 'Sensible Cinema license agreement', 
            "Sensible Cinema is distributed under the gplv3 (http://www.gnu.org/licenses/gpl.html).\nBY CLICKING \"accept\" YOU SIGNIFY THAT YOU HAVE READ, UNDERSTOOD AND AGREED TO ABIDE BY THE TERMS OF THIS AGREEMENT"
        require_blocking_license_accept_dialog 'Sensible Cinema', 'is_it_legal_to_copy_dvds.txt file', File.expand_path(File.dirname(__FILE__) + "/../../documentation/is_it_legal_to_copy_dvds.txt"), 
            'is_it_legal_to_copy_dvds.txt file', 'I acknowledge that I have read, understand, accept and agree to abide by the implications noted in the documentation/is_it_legal_to_copy_dvds.txt file'
        LocalStorage['main_license_accepted'] = VERSION
      end
    end

    LocalStorage = Storage.new("sensible_cinema_storage")
    
    def when_thread_done(thread)
      Thread.new {thread.join; yield }
    end
    

    # a window that when closed doesn't bring the whole app down
    def new_child_window
      child = MainWindow.new
      child.setDefaultCloseOperation(JFrame::DISPOSE_ON_CLOSE)
      child.parent=self # this should have failed in the PPL
      # make both windows visible z-wise
      x, y = self.get_location.x, self.get_location.y
      child.set_location(x + 100, y + 100)
      child
    end
    
    def run_smplayer_non_blocking *args
      @background_thread = Thread.new {
        run_smplayer_blocking *args
      }
    end

    # basically run mplayer/smplayer on a file or DVD
    def run_smplayer_blocking play_this, title_track_maybe_nil, passed_in_extra_options, force_use_mplayer, show_subs, start_full_screen
      unless File.exist?(File.expand_path(play_this))
        raise play_this + ' non existing?' # sanity check, I get these in mac :)
      end

      extra_options = []
      # -framedrop is for slow CPU's
      # same with -autosync to try and help it stay in sync... -mc 0.03 is to A/V correct 1s audio per 2s video
      # -hardframedrop might help but hurts the eyes just too much
      extra_options << "-framedrop" # even in create mode, if the audio ever gets off, we're hosed with making accurate timestamps...so drop, until I hear otherwise...
      extra_options << "-mc 1"
      extra_options << "-autosync 30" 
      
      unless show_subs
        # disable all subtitles :P
        extra_options << "-nosub -noautosub -forcedsubsonly -sid 1000"
      end
      extra_options << "-alang en"
      extra_options << "-slang en"

      parent_parent = File.basename(File.dirname(play_this))
      force_use_mplayer ||= OS.mac?
      if parent_parent == 'VIDEO_TS'
        # case d:\yo\VIDEO_TS\title0.vob
        dvd_device_dir = normalize_path(File.dirname(play_this))
        play_this = "\"dvdnav://#{title_track_maybe_nil}/#{dvd_device_dir}/..\""
      elsif File.exist?(play_this + '/VIDEO_TS')
        # case d:\ where d:\VIDEO_TS exists [DVD mounted in drive] or mac's /Volumes/YO
        play_this = "\"dvdnav://#{title_track_maybe_nil}/#{play_this}\""
      else
        # case g:\video\filename.mpg
        # leave it the same...
      end
      if play_this =~ /dvdnav/ && title_track_maybe_nil
        extra_options << "-msglevel identify=4" # prevent smplayer from using *forever* to look up info on DVD's with -identify ...
      end
      
      extra_options << "-mouse-movements #{get_upconvert_secondary_settings}" # just in case smplayer also needs -mouse-movements... :) LODO
      extra_options << "-lavdopts threads=#{OS.cpu_count}" # just in case this helps [supposed to with h.264] # NB fast *crashes* doze...
      if force_use_mplayer
       conf_file = File.expand_path './mplayer_input_conf'
       File.write conf_file, "ENTER {dvdnav} dvdnav select\nMOUSE_BTN0 {dvdnav} dvdnav select\nMOUSE_BTN0_DBL vo_fullscreen\nMOUSE_BTN2 vo_fullscreen\nKP_ENTER dvdnav select\n" # that KP_ENTER doesn't actually work.  Nor the MOUSE_BTN0 on windows. Weird.
       extra_options << "-font #{File.expand_path('vendor/subfont.ttf')}"
       extra_options << "-volume 100" # why start low? mplayer why oh why LODO
       if OS.windows?
        # direct3d for windows 7 old nvidia cards' sake [yipes] and also dvdnav sake
        extra_options << "-vo direct3d"
        conf_file = conf_file[2..-1] # strip off drive letter, which it doesn't seem to like no sir
       end
       if start_full_screen
         extra_options << "-fs"
         upconv = get_upconvert_vf_settings
         upconv = "-vf #{upconv}" if upconv.present?
       else
        upconv = ""
       end
       mplayer_loc = "mplayer"
       if OS.doze? && we_are_in_create_mode
         p 'using mplayer-edl for smplayer\'s mplayer 1'
         # we want this even if we don't have -osd-add, since it adds confidence :)
         mplayer_loc = LocalModifiedMplayer
         assert File.exist?(mplayer_loc)
       else
         p 'using normal mplayer'
       end
       c = "#{mplayer_loc} #{extra_options.join(' ')} #{upconv} -input conf=\"#{conf_file}\" #{passed_in_extra_options} \"#{play_this}\" "
      else
        if OS.windows?
          extra_options << "-vo direct3d" # more light nvidia...should be ok...LODO check
        end
        set_smplayer_opts extra_options.join(' ') + " " + passed_in_extra_options, get_upconvert_vf_settings, show_subs
        c = "smplayer_portable \"#{play_this}\" -config-path \"#{File.dirname SMPlayerIniFile}\" " 
        c += " -fullscreen " if start_full_screen
        if !we_are_in_create_mode
          c += " -close-at-end "
        end
      end
      puts c
      system_blocking c
    end
    
    SMPlayerIniFile = File.expand_path("~/.smplayer_sensible_cinema/smplayer.ini")
    LocalModifiedMplayer = File.expand_path "vendor/cache/mplayer_edl/mplayer.exe"
    
    def set_smplayer_opts to_this, video_settings, show_subs = false
      p 'setting smplayer extra opts to this:' + to_this
      old_prefs = File.read(SMPlayerIniFile) rescue ''
      unless old_prefs.length > 0
        # LODO double check the rest here...
        old_prefs = "[%General]\nmplayer_bin=\n[advanced]\nmplayer_additional_options=\nmplayer_additional_video_filters=\n[subtitles]\nautoload_sub=false\n[performance]\npriority=3" 
      end
      raise to_this if to_this =~ /"/ # unexpected, unfortunately... <smplayer bug>
      assert new_prefs = old_prefs.gsub(/mplayer_additional_options=.*/, "mplayer_additional_options=#{to_this}")
      assert new_prefs.gsub!(/autoload_sub=.*$/, "autoload_sub=#{show_subs.to_s}")
      raise 'unexpected' if get_upconvert_vf_settings =~ /"/
      assert new_prefs.gsub!(/mplayer_additional_video_filters=.*$/, "mplayer_additional_video_filters=\"#{video_settings}\"")
      raise 'smplayer on non doze not expected...' unless OS.doze?
      mplayer_to_use = File.expand_path 'vendor/cache/mencoder/mplayer.exe'
      if we_are_in_create_mode
        p 'using mplayer-edl for smplayer\'s mplayer 2'
        mplayer_to_use = LocalModifiedMplayer 
        assert File.exist?(mplayer_to_use)
      else
        p 'using normal mplayer'
      end
      new_value = "\"" + mplayer_to_use.to_filename.gsub("\\", '/') + '"' # forward slashes. Weird.
      assert new_prefs.gsub!(/mplayer_bin=.*$/, "mplayer_bin=" + new_value)
      # now some less important ones...
      new_prefs.gsub!(/priority=.*$/, "priority=3") # normal priority...scary otherwise! lodo tell smplayer...
      # enable dvdnav navigation, just for kicks I guess.
      new_prefs.gsub!(/use_dvdnav=.*$/, "use_dvdnav=true")
      
      FileUtils.mkdir_p File.dirname(SMPlayerIniFile)
      File.write(SMPlayerIniFile, new_prefs)
      new_prefs.each_line{|l| print l if l =~ /additional_video/} # debug
    end
    
    def system_blocking command, low_prio = false
      return true if command =~ /^@rem/ # JRUBY-5890 bug
      if low_prio
        out = IO.popen(command) # + " 2>&1"
        low_prio = 64 # from msdn
        
        if command =~ /(ffmpeg|mencoder)/
          # XXXX not sure if there's a better way...because some *are* complex and have ampersands...
          # unfortunately have to check for nil because it could exit too early [?]
          exe_name = $1 + '.exe'
          begin
            p = proc{ ole = ::WMI::Win32_Process.find(:first,  :conditions => {'Name' => exe_name}); sleep 1 unless ole; ole }
            piddy = p.call || p.call || p.call # we actually do need this to loop...guess we're too quick
            # but the first time through this still inexplicably fails all 3...odd
            piddys = ::WMI::Win32_Process.find(:all,  :conditions => {'Name' => exe_name})
            for piddy in piddys
              # piddy.SetPriority low_prio # this call can seg fault at times...JRUBY-5422
              pid = piddy.ProcessId # this doesn't seg fault, tho
              system_original("vendor\\setpriority -lowest #{pid}") # uses PID for the command line
            end
          rescue Exception => e
            p 'warning, got exception trying to set priority [jruby prob? ...]', e
          end
        end
        print out.read # let it finish
        out.close
        $?.exitstatus == 0 # 0 means success
      else
        raise command + " failed env #{ENV['PATH']}" unless system_original command
      end
    end
    
    def system_non_blocking command
      @background_thread = Thread.new { system_original command }
    end
    
    # force them choose which system call to use explicitly
    if respond_to? :system
      undef system
    else # it's a reload
    end
   
    def play_dvd_smplayer_unedited use_mplayer_instead
      drive_or_file, dvd_volume_name, dvd_id, edl_path_maybe_nil, descriptors = choose_dvd_or_file_and_edl_for_it(force_choose_edl_file_if_no_easy_match = true)
      title_track_maybe_nil = get_title_track(descriptors, false)
      run_smplayer_non_blocking drive_or_file, title_track_maybe_nil, get_dvd_playback_options(descriptors), use_mplayer_instead, true, false
    end
    
    def get_dvd_playback_options descriptors
      out = "-osdlevel 2 -osd-fractions 1"
      return out unless we_are_in_create_mode # early out, since they won't be seeing subs anyway :)
      
      if OS.doze? 
        offset_time = "0.20" # readings: 0.213  0.173 0.233 0.21 0.18 0.197 they're almost all right around 0.20...we can guess this come on everyone's doing it...
        if offset = descriptors['dvd_start_offset']
          offset = offset.to_f
          if offset < 0.10
            offset_time = offset
            puts 'using a small osd offset, which almost never happens ' + offset_time
          end
          if offset == 0
            offset = 0.001 # so it knows we really do know what we're doing :)
          end
          out += " -osd-add #{offset_time}"
        else
          show_blocking_message_dialog "warning--EDL does not contain dvd_start_offset, so your mplayer on screen display timestamp will probably display low-accuracy and be about 0.20s too small, add 0.20 to match real DVD time, or use the show info button to calculate dvd_start_offset"
        end
      else
        show_blocking_message_dialog "warning, since we're not in windows with a patched mplayer OSD timestamps will probably be 0.19s too small,\n and their fraction past the decimal point will be off.\nPing me for instructions to build a patched mplayer."
      end
      out
    end

    if OS.doze? # avoids spaces in filenames :)
      EdlTempFile = EightThree.convert_path_to_8_3(Dir.tmpdir) + '\\mplayer.temp.edl'
    else
      raise if Dir.tmpdir =~ / / # that would be unexpected, and probably cause problems...
      EdlTempFile = Dir.tmpdir + '/mplayer.temp.edl'
    end
    
    
    def choose_dvd_or_file_and_edl_for_it force_choose_edl_file_if_no_easy_match = true
      drive_or_file, dvd_volume_name, dvd_id = choose_dvd_drive_or_file false
      
      unless @_edit_list_path # cache file selection...
        edit_list_path = EdlParser.single_edit_list_matches_dvd(dvd_id)
        if !edit_list_path && force_choose_edl_file_if_no_easy_match
          edit_list_path = new_existing_file_selector_and_select_file("Please pick a DVD Edit List File (none or more than one were found that seem to match #{dvd_volume_name})--may need to create one for it", EdlParser::EDL_DIR)
          raise 'cancelled choosing EDL...' unless edit_list_path
        end
        @_edit_list_path = edit_list_path
      end
      p 're/loading ' + @_edit_list_path
      if @_edit_list_path
        # reload it every time just in case it has changed on disk
        descriptors = nil
        begin
          descriptors = parse_edl @_edit_list_path
        rescue SyntaxError => e
          show_non_blocking_message_dialog("this file has an error--please fix then hit ok: \n" + @_edit_list_path + "\n " + e)
          raise e
        end
      end
      [drive_or_file, dvd_volume_name, dvd_id, @_edit_list_path, descriptors]
    end
    
    MplayerBeginingBuffer = 1.0
    MplayerEndBuffer = 0.0
    
    def play_smplayer_edl_non_blocking optional_file_with_edl_path = nil, extra_mplayer_commands_array = [], force_mplayer = false, start_full_screen = true, add_secs_end = MplayerEndBuffer, add_secs_begin = MplayerBeginingBuffer, show_subs = false
      if optional_file_with_edl_path
        drive_or_file, edl_path = optional_file_with_edl_path
        dvd_id = NonDvd # fake it out...LODO a bit smelly
      else
        drive_or_file, dvd_volume_name, dvd_id, edl_path, descriptors = choose_dvd_or_file_and_edl_for_it
      end
      start_add_this_to_all_ts = 0
      if edl_path # some don't care...
        descriptors = EdlParser.parse_file edl_path
        title_track = get_title_track(descriptors)
        splits = descriptors['mplayer_dvd_splits']
      end
      
      if dvd_id == NonDvd && !(File.basename(File.dirname(drive_or_file)) == 'VIDEO_TS') # VOB's...always start at 0
        # check if it has a start offset...
        all =  `ffmpeg -i "#{drive_or_file}" 2>&1` # => Duration: 01:35:49.59, start: 600.000000
        all =~ /Duration.*start: ([\d\.]+)/
        start = $1.to_f
        if start > 1 # LODO huh? dvd's themselves start at 0.3 [sintel]?
          show_non_blocking_message_dialog "Warning: file seems to start at an extra offset, adding it to the timestamps... #{start}
            maybe not compatible with XBMC, if that's what you use, and you probably don't" # LODO test it XBMC...
          start_add_this_to_all_ts = start
        end
        splits = []
      else
        # it's a DVD
        if splits == nil
          show_blocking_message_dialog("warning: edit list does not contain mplayer replay information [mplayer_dvd_splits] so edits past a certain time period might not won't work ( http://goo.gl/yMfqX ).")
          splits = []
        else
          splits.map!{|s| EdlParser.translate_string_to_seconds(s)}
        end
        extra_mplayer_commands_array << get_dvd_playback_options(descriptors)
      end
      
      if edl_path
        edl_contents = MplayerEdl.convert_to_edl descriptors, add_secs_end, add_secs_begin, splits, start_add_this_to_all_ts # add a sec to mutes to accomodate for mplayer's oddness..
        File.write(EdlTempFile, edl_contents)
        extra_mplayer_commands_array << "-edl #{File.expand_path EdlTempFile}" 
      end
      
      run_smplayer_non_blocking drive_or_file, title_track, extra_mplayer_commands_array.join(' '), force_mplayer, show_subs, start_full_screen
    end
    
    def print *args
      Kernel.print *args # avoid bin\sensible-cinema.rb:83:in `system_blocking': cannot convert instance of class org.jruby.RubyString to class java.awt.Graphics (TypeError)
    end
    
    def open_file_to_edit_it filename, options = {} # :start_minimized is the only option
      if OS.windows?
        if options[:start_minimized]
          system_non_blocking "start /min notepad \"#{filename}\""
        else
          system_non_blocking "notepad \"#{filename}\""
        end
      else
        # ignore minimized :P
        system_non_blocking "open -a TextEdit \"#{filename}\""
      end
    end
    
    def new_nonexisting_filechooser_and_go title = nil, default_dir = nil, default_file = nil
      bring_to_front # LODO not need...
      JFileChooser.new_nonexisting_filechooser_and_go title, default_dir, default_file
    end

    def show_blocking_message_dialog(message, title = message.split("\n")[0], style= JOptionPane::INFORMATION_MESSAGE)
      bring_to_front
      SwingHelpers.show_blocking_message_dialog message, title, style
    end
    
    # call dispose on this to close it if it hasn't been canceled yet...
    def show_non_blocking_message_dialog message, close_button_text = 'Close'
      bring_to_front
      # lodo NonBlockingDialog it can get to the top instead of being so buried...
      SwingHelpers.show_non_blocking_message_dialog message, close_button_text
    end
    
    include_class javax.swing.UIManager
    
    def get_user_input(message, default = '', cancel_ok = false)
      bring_to_front
      SwingHelpers.get_user_input message, default, cancel_ok
    end
    
    def show_copy_pastable_string(message, value)
      bring_to_front
      RubyClip.set_clipboard value            
      get_user_input message + " (has been copied to clipboard)", value, true
    end
    
    # also caches directory previously selected ...
    def new_existing_file_selector_and_select_file title, dir = nil
      bring_to_front
      unique_trace = caller.inspect
      dir ||= LocalStorage[unique_trace]
      p 'using system default dir' unless dir # happens more frequently after code changes alter the path :P
      got = FileDialog.new_previously_existing_file_selector_and_go title, dir
      LocalStorage[unique_trace] = File.dirname(got)
      got
    end
    
    def show_in_explorer filename
      SwingHelpers.show_in_explorer filename
    end
    
    def show_select_buttons_prompt message, names
      JOptionPane.show_select_buttons_prompt(message, names)
    end
    
  end
  
end


class ::File
      def self.get_root_dir this_path
        this_path = File.expand_path this_path
        if OS.doze?
          this_path[0..2]
        else
          this_path.split('/')[0]
        end
      end
      
      def self.strip_drive_windows this_complete_path
        if OS.doze?
          this_complete_path[2..-1]
        else
          this_complete_path
        end
      end
end
