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
require File.expand_path(File.dirname(__FILE__) + '/common')
load '../bin/sensible-cinema'

module SensibleSwing
  describe MainWindow do

    it "should be able to start up" do
      MainWindow.new.dispose# shouldn't crash :)
    end

    it "should auto-select a EDL if it matches a DVD's title" do
      MainWindow.new.single_edit_list_matches_dvd("19d121ae8dc40cdd70b57ab7e8c74f76").should_not be nil
    end

    it "should not auto-select if you pass it nil" do
      MainWindow.new.single_edit_list_matches_dvd(nil).should be nil
    end

    it "should prompt if two EDL's match a DVD title" do
      old_edl = MainWindow::EDL_DIR
      begin
        MainWindow.const_set(:EDL_DIR, 'temp')
        FileUtils.rm_rf 'temp'
        Dir.mkdir 'temp'
        MainWindow.new.single_edit_list_matches_dvd("BOBS_BIG_PLAN").should be nil
        Dir.chdir 'temp' do
          File.binwrite('a.txt', "\"disk_unique_id\" => \"abcdef1234\"")
          File.binwrite('b.txt', "\"disk_unique_id\" => \"abcdef1234\"")
        end
        MainWindow.new.single_edit_list_matches_dvd("abcdef1234").should be nil
      ensure
      MainWindow.const_set(:EDL_DIR, old_edl)
      end
    end

    it "should modify path to have mencder available, and ffmpeg, and download them on the fly" do
      ENV['PATH'].should include("mencoder")
    end

    before do
      @subject = MainWindow.new
      @subject.stub!(:choose_dvd_drive) {
        ["mock_dvd_drive", "Volume", "19d121ae8dc40cdd70b57ab7e8c74f76"] # happiest baby on the block
      }
      @subject.stub!(:get_mencoder_commands) { |*args|
        args[-5].should match(/abc/)
        @args = args
        'sleep 0.1'
      }
      @subject.stub!(:new_filechooser) {
        FakeFileChooser.new
      }
      @subject.stub!(:get_drive_with_most_space_with_slash) {
        "e:\\"
      }
      @subject.stub!(:show_blocking_message_dialog) {}
      @subject.stub!(:get_user_input) {'01:00'}
      @subject.stub!(:system_non_blocking) { |command|
        @command = command
        Thread.new {} # fake out the return...
      }
      @subject.stub!(:open_file_to_edit_it) {}
    end

    class FakeFileChooser
      def set_title x
      end
      def set_file y
      end
      def go
        'abc'
      end
    end
    
    it "should be able to do a normal copy to hard drive, edited" do
      @subject.do_copy_dvd_to_hard_drive(false).should == [false, "abc.fulli.tmp.avi"]
      File.exist?('test_file_to_see_if_we_have_permission_to_write_to_this_folder').should be false
    end
    
    it "should call through to explorer for the full thing" do
      @subject.do_copy_dvd_to_hard_drive(false)
      @subject.background_thread.join
      @args[-3].should == nil
      @command.should match /explorer/
      @command.should_not match /fulli/
    end
    
    it "should be able to return the full list if it already exists" do
      FileUtils.touch "abc.fulli.tmp.avi.done"
      @subject.do_copy_dvd_to_hard_drive(false,true).should == [true, "abc.fulli.tmp.avi"]
      FileUtils.rm "abc.fulli.tmp.avi.done"
    end
    
    it "should call explorer for the we can't reach this path of opening a partial without telling it what to do with it" do
     @subject.do_copy_dvd_to_hard_drive(true).should == [false, "abc.fulli.tmp.avi"]
     @subject.background_thread.join
     @args[-2].should == 1
     @args[-3].should == "01:00"
     @command.should match /explorer/
     @command.should_not match /fulli/
    end

    def prompt_for_start_and_end_times
      @subject.instance_variable_get(:@preview_section).simulate_click
      @args[-2].should == 1
      @args[-3].should == "01:00"
      @subject.background_thread.join
      @command.should match /smplayer/
    end

    it "should prompt for start and end times" do
      prompt_for_start_and_end_times
    end
    
    it "should be able to reprompt for start and end times automagically" do
      prompt_for_start_and_end_times
      old_args = @args
      @args = nil
      @subject.repeat_last_copy_dvd_to_hard_drive.join
      @args.should == old_args
    end
    
    
    it "if the .done file exists, it should directly call smplayer" do
      FileUtils.touch "abc.fulli.tmp.avi.done"
      @subject.instance_variable_get(:@watch_unedited).simulate_click
      @command.should == "smplayer abc.fulli.tmp.avi"
      FileUtils.rm "abc.fulli.tmp.avi.done"
    end
    
    it "if the .done file does not exist, it should call mplayer later" do
      @subject.instance_variable_get(:@watch_unedited).simulate_click
      @subject.after_success_once.should_not == nil
      @command.should == nil # scary timing spec
      @subject.background_thread.join
      # should have cleaned up...
      @subject.after_success_once.should == nil
      @command.should_not == nil
    end
    
    it "should create a new file for ya" do
      out = MainWindow::EDL_DIR + "/sweetest_disc_ever.txt"
      File.exist?( out ).should be_false
      @subject.stub!(:get_user_input) {'sweetest disc ever'}
      @subject.instance_variable_get(:@create_new_edl_for_current_dvd).simulate_click
      begin
        File.exist?( out ).should be_true
        content = File.read(out)
        p content
        content.should_not include("\"title\"")
        content.should include("disk_unique_id")
        content.should include("dvd_title_track")
      ensure
        FileUtils.rm_rf out
      end
    end
    
    it "should display unique disc in an input box" do
      @subject.instance_variable_get(:@display_unique).simulate_click.should == "01:00"
    end
    
    it "should create an edl" do
      @subject.instance_variable_get(:@edl).simulate_click
      
      @command.should match(/mplayer.*-edl/)
      @command.should match(/-dvd-device /)
      p @command
    end
    
  end
end
