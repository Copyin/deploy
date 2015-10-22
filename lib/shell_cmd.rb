require "open3"
require "colored"

class ShellCmd

  class Failure < StandardError; end

  def initialize cmd_string
    @cmd_string = cmd_string
  end

  # available options:
  # `ignore_failure: true`: do not raise Exception if the cmd_string fails
  # `in_background: true`: run the command in background (probably work only
  # along with `with_system: true`
  # `with_system: true`: use Ruby `system` to run the cmd_string, useful to see 
  # the
  # output of the cmd_string during its execution, or for some cmd_strings which don't
  # work with `Open3.popen3`
  def run options = {}
    if options[:with_system]
      cmd_string = options[:in_background] ? @cmd_string + " &" : @cmd_string
      @stdout    = system cmd_string
      @is_successful = @stdout
    else
      stdin, stdout, stderr, wait_thread = Open3.popen3 @cmd_string
      @stdout = stdout.read
      @stderr = stderr.read
      @is_successful = wait_thread.value.success?
    end

    unless @is_successful || options[:ignore_failure]
      puts "\nCommand failed!".red
      unless options[:with_system]
        puts "\nError output:\n\n #{@stderr}".red unless @stderr.empty?
        puts "\nStandard output:\n\n #{@stdout}" unless @stdout.empty?
      end
      raise Failure
    end

    @stdout
  end

end