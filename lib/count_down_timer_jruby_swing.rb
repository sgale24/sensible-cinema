require 'rubygems'
require 'sane' # require_relative
require_relative 'jruby-swing-helpers/swing_helpers'

include SwingHelpers
  
class MainWindow < JFrame

  def show_blocking_message_dialog(message, title = message.split("\n")[0], style= JOptionPane::INFORMATION_MESSAGE)
    # I think I'm already on top...
    setVisible(true);
    toFront()
    JOptionPane.showMessageDialog(self, message, title, style)
    true
  end
  
  def set_normal_size
      set_size 165,100
  end
  
  def super_size
    set_size 1650,1000
  end

  def initialize
      super "welcome..."
      set_normal_size
      com.sun.awt.AWTUtilities.setWindowOpacity(self, 0.8) 
      setDefaultCloseOperation JFrame::EXIT_ON_CLOSE # happiness
      @jlabel = JLabel.new 'Welcome...'
      happy = Font.new("Tahoma", Font::PLAIN, 11)
      @jlabel.set_bounds(44,44,160,14)
      @jlabel.font = happy
      @name_label = JLabel.new
      @name_label.font = happy
      @name_label.set_bounds(44,4,160,14)
      
      panel = JPanel.new
      @panel = panel
      panel.set_layout nil
      add panel # why can't I just slap these down?
      panel.add @jlabel
      panel.add @name_label
      @start_time = Time.now
      cur_index = 0
      starting_seconds_requested = ARGV.map{|a| a.to_f*60}
      setup_pomo_name starting_seconds_requested[0]
      @switch_image_timer = javax.swing.Timer.new(1000, nil) # nil means it has no default person to call when the action has occurred...
      @switch_image_timer.add_action_listener do |e|
        seconds_requested = starting_seconds_requested[cur_index % starting_seconds_requested.length]
        next_up = starting_seconds_requested[(cur_index+1) % starting_seconds_requested.length]
        seconds_left = (seconds_requested - (Time.now - @start_time)).to_i
        if seconds_left < 0
          setState ( java.awt.Frame::NORMAL )
          setVisible(true)
          toFront()
          super_size
          set_title 'done!'
          show_blocking_message_dialog "Timer done! #{seconds_requested/60}m at #{Time.now}. Next up #{next_up/60}m." 
          setup_pomo_name next_up
          set_normal_size
          @start_time = Time.now
          cur_index += 1
        else
          # avoid weird re-draw issues
          minutes = (seconds_left/60).to_i          
          if minutes > 0
            current_time = "#{minutes}m"
            set_title current_time
          else
            current_time = "%2ds" % seconds_left
            set_title "#{seconds_left}s" % seconds_left
          end
          @jlabel.set_text current_time
        end
      end
      @switch_image_timer.start
      self.always_on_top=true # setAlwaysOnTop what?
  end
  
  def setup_pomo_name next_up
     if (next_up/60) > 6 # preferenc-ize
       @real_name = SwingHelpers.get_user_input('name for next pomodoro?', @real_name) 
       @name = @real_name
     else
       @name = "break!"
     end
    @name_label.text=@name
  end
       
end

if $0 == __FILE__
  if ARGV.length == 0
    p 'syntax: minutes1 minutes2 [it will loop, for pomodoro]'
  else
    MainWindow.new.show
  end
end

