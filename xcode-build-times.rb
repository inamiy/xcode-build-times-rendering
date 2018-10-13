#!/usr/bin/ruby
#encoding: utf-8
require 'xcodeproj'
require 'FileUtils'
require_relative 'stringcolors'

class XcodeBuildTimer

  def initialize(options)
    @inject_path = options[:inject_path] || ''
    @events_file_path = options[:events_file_path]

    puts "Events file path #{@events_file_path}"
  end

  def add_timings(xcodeproj_path)
    begin
      project = Xcodeproj::Project.open(xcodeproj_path)
    rescue Exception => e
      puts '[???]'.yellow + " There were some problems in opening #{xcodeproj_path} : #{e.to_s}"
      return
    end

    project.native_targets.each do |target|
      unless target.shell_script_build_phases.find {|phase| phase.name == 'Timing START'
      }
        timing_start = target.new_shell_script_build_phase('Timing START')
        timing_start.shell_script = <<-eos
      DATE=`date "+%Y-%m-%dT%H:%M:%S.%s"`
      echo "{\\"date\\":\\"$DATE\\", \\"taskName\\":\\"$TARGETNAME\\", \\"event\\":\\"start\\"}," >> "#{@events_file_path}"
        eos

        index = target.build_phases.index {|phase| (defined? phase.name) && phase.name == 'Timing START'
        }
        target.build_phases.move_from(index, 0)

      end

      unless target.shell_script_build_phases.find {|phase| phase.name == 'Timing END'
      }

        timing_end = target.new_shell_script_build_phase('Timing END')
        timing_end.shell_script = <<-eos
      DATE=`date "+%Y-%m-%dT%H:%M:%S.%s"`
      echo "{\\"date\\":\\"$DATE\\", \\"taskName\\":\\"$TARGETNAME\\", \\"event\\":\\"end\\"}," >> "#{@events_file_path}"
        eos
      end

    end

    project.save

  end

  def remove_timings(xcodeproj_path)
    begin
      project = Xcodeproj::Project.open(xcodeproj_path)
    rescue Exception => e
      puts '[???]'.yellow + " There were some problems in opening #{xcodeproj_path} : #{e.to_s}"
      return
    end

    project.native_targets.each do |target|
      start_target = target.shell_script_build_phases.find {|phase| phase.name == 'Timing START' }
      start_target.remove_from_project if start_target

      end_target = target.shell_script_build_phases.find {|phase| phase.name == 'Timing END' }
      end_target.remove_from_project if end_target
    end

    project.save

  end

  def inject_timings_to_all_projects

    Dir.chdir(@inject_path) {
      all_xcode_projects = Dir.glob('**/*.xcodeproj').reject {|path| !File.directory?(path)}
      all_xcode_projects.each {|xcodeproj|
        puts "Adding timings phases to #{xcodeproj.green}"
        add_timings(xcodeproj)
      }
    }
  end

  def remove_timings_from_all_projects

    Dir.chdir(@inject_path) {
      all_xcode_projects = Dir.glob('**/*.xcodeproj').reject {|path| !File.directory?(path)}
      all_xcode_projects.each {|xcodeproj|
        puts "Removing timings phases from #{xcodeproj.green}"
        remove_timings(xcodeproj)
      }
    }
  end


  def generate_events_js
    begin
      raw_events = File.read(File.expand_path(@events_file_path))
    rescue
      puts '[???]'.yellow + " There were some problems in opening #{@events_file_path} (It doesn't seem that build was created)"
      return
    end

    js_chart_directory = 'xcode-build-times-chart'
    unless File.exist?(js_chart_directory)
      puts "[CHART] Will copy chart to #{Dir.pwd}"
      source_dir = File.expand_path("../#{js_chart_directory}", __FILE__)
      FileUtils.copy_entry(source_dir, File.expand_path(js_chart_directory))
    end

    js_valid_file = "var raw_events = [\n" + raw_events + "\n]"
    open("#{js_chart_directory}/events.js", 'w') do |f|
      f << js_valid_file
      puts '[EVENTS]'.green + " Updated events.js at #{f.path}\n" +
           '[EVENTS]'.green + " It's time to open #{js_chart_directory}/gantt.html"
    end
  end

end

options = {
  :events_file_path => '~/.timings.xcode',
  :command => 'unknown'
}

arguments = ARGV.clone
until arguments.empty?
  item = arguments.shift
  case item
  when 'install'
    options[:command] = item
    options[:inject_path] = File.expand_path(arguments.shift)
  when 'uninstall'
    options[:command] = item
    options[:inject_path] = File.expand_path(arguments.shift)
  when 'generate'
    options[:command] = item
  when '--events-file'
    options[:events_file_path] = File.expand_path(arguments.shift)
  else
    puts '[?PARAMETER?] '.yellow + "Unknown parameter #{item}"
  end
end

buildtimer = XcodeBuildTimer.new(options)
case options[:command]
when 'generate'
  buildtimer.generate_events_js
when 'install'
  puts '[?PATH?]'.yellow + 'Please provide path' unless options[:inject_path]
  buildtimer.inject_timings_to_all_projects
when 'uninstall'
  puts '[?PATH?]'.yellow + 'Please provide path' unless options[:inject_path]
  buildtimer.remove_timings_from_all_projects
else
  puts '[HELP] '.yellow + 'Run ' + 'xcode-build-time.rb install   <path>'.magenta + ' to install build script phases in all .xcodeproj files in specified dir' + "\n" +
       '[HELP] '.yellow + 'Run ' + 'xcode-build-time.rb uninstall <path>'.magenta + ' to uninstall build script phases from all .xcodeproj files in specified dir' + "\n" +
       '[HELP] '.yellow + 'Run ' + 'xcode-build-time.rb generate        '.magenta + ' to generate events for visualization after build' + "\n" +
       '[HELP] '.yellow + 'OPTIONS' + "\n" +
       '[HELP] '.yellow + ' --events-file [path] '.magenta + ' Specifies where events should be stored to or read from on generation '

end
