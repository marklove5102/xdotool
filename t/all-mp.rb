#!/usr/bin/env ruby

require "getoptlong"
require "shellwords"

options = GetoptLong.new(
  ["-x", GetoptLong::REQUIRED_ARGUMENT],
  ["-w", GetoptLong::REQUIRED_ARGUMENT],
)

x = Shellwords.split("Xvfb")
wm = []

begin
  options.each do |option, argument|
    case option
    when "-x"
      x = Shellwords.split(argument)
    when "-w"
      wm = Shellwords.split(argument)
    else
      puts "Unsupported option #{option}"
    end
  end
rescue GetoptLong::MissingArgument => e
  exit 1
end

#files = Dir.glob(File.join(__dir__, "test_*.rb"))
files = Dir.glob(File.join(__dir__, "test_*.rb"))

def xserver(cmd)
  (0..30).each do |i|

    pipes = {
      :out => IO.pipe,
      :err => IO.pipe,
      :display => IO.pipe,
    }

    options = {
      :close_others => true,
      :in => "/dev/null",
      :err => pipes[:err][1],
      :out => pipes[:out][1],

      pipes[:display][1].fileno => pipes[:display][1].fileno ,
    }
    args = [*cmd, "-displayfd", pipes[:display][1].fileno.to_s, ":#{i}"]
    pid = Process::spawn(*args, options)
    pipes[:display][1].close

    begin
      display = pipes[:display][0].readline("\n").chomp("\n");
      return pid, display
    rescue EOFError
      # X didn't write the display number, it failed. Try next
      #puts "Display #{i} didn't seem to work... #{e}"
      Process.wait(pid)
      next
    ensure
      #pipes.each { |k,v| v[0].close; v[1].close }
    end
  end

  throw Error.new("Failed to start X server.")
rescue Errno::ENOENT => e
  puts "Error starting X server: #{e.message}"
  puts " > Failing X server command: #{cmd}"
  raise
end

def run(x, wm, test_file)
  
  return Ractor.new(x, wm, test_file) do |x, wm, test_file|
    puts "Run: #{test_file}"
    env = {}
    env["LD_LIBRARY_PATH"] = File.join(__dir__, "..")

    begin
      xpid, display = xserver(x)
      env["DISPLAY"] = ":#{display}"
      puts "Got X on #{display} with pid #{xpid}"
      options = {
        :close_others => true,
        :in => "/dev/null",
      }

      args = ["ruby", "-r", test_file, "-e", "exit(Minitest.run(['--verbose']))"]
      pid = Process::spawn(env, *args, options)
      _, status = Process.wait2(pid)
      status.exitstatus
    rescue Errno::ENOENT => e
      puts "Couldn't start test? #{e}"
      raise
    rescue => e
      puts "Error: #{e.message}"
      puts e
      raise
    ensure
      if xpid
        Process.kill(9, xpid) 
        Process.wait2(xpid)
      end
    end
  end
end

begin
  pids = files.collect { |file| [file, run(x, wm, file)] }

  pids.collect { |file, child| [file, child.take] }.each do |file, result|
    if result == 0
      puts "pass: #{file}"
    else
      puts "fail: #{file}"
    end
  end
ensure
  # Clean up any stranded processes.
  puts "Exiting -- Cleaning up all subprocesses"
  begin
    #Process.kill(:TERM, *pids)
  rescue Errno::ESRCH
    # ignore
  rescue => e
    raise
    #p :kill_term => e
  end
end
