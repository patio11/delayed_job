require 'rubygems'
require 'daemons'
require 'optparse'
require 'ostruct'

module Delayed
  class Command
    def initialize(args)
      @options = OpenStruct.new(:sleep => 5)
      
      opts = OptionParser.new do |opts|
        opts.banner = "Usage: #{File.basename($0)} [options] start|stop|restart|run"

        opts.on('-h', '--help', 'Show this message') do
          puts opts
          exit 1
        end
        opts.on('-e', '--environment=NAME', 'Specifies the environment to run this delayed jobs under (test/development/production).') do |e|
          ENV['RAILS_ENV'] = e
        end
        opts.on('-s', '--sleep=seconds', "Number of seconds between checking for new jobs") do |secs|
          @options.sleep = secs
        end
        opts.on('-n', '--number_of_workers=workers', "Number of unique workers to spawn") do |worker_count|
          @options.worker_count = worker_count.to_i rescue 1
        end
      end
      @args = opts.parse!(args)
    end
  
    def run
      worker_count = @options.worker_count || 1

      1.upto(worker_count) do |worker_index|
        if (worker_count == 1)
          process_name = "delayed_job"
        else
          process_name = "delayed_job.#{worker_index}"
        end
        Daemons.run_proc(process_name, :dir => "#{RAILS_ROOT}/tmp/pids", :dir_mode => :normal, :ARGV => @args) do |*args|
          begin
            require File.join(RAILS_ROOT, 'config', 'environment')

            # Replace the default logger
            logger = Logger.new(File.join(RAILS_ROOT, 'log', 'delayed_job.log'))
            logger.level = ActiveRecord::Base.logger.level
            ActiveRecord::Base.logger = logger
            ActiveRecord::Base.clear_active_connections!
            if (worker_count != 1)
              Delayed::Job.worker_name = Delayed::Job.worker_name + " worker: #{worker_index}"
            end
            logger.info "*** Starting job worker #{Delayed::Job.worker_name}"

            trap('TERM') { puts 'Exiting...'; $exit = true }
            trap('INT')  { puts 'Exiting...'; $exit = true }

            loop do
              result = nil
              realtime = Benchmark.realtime { result = Delayed::Job.work_off }
              count = result.sum

              break if $exit

              if count.zero?
                sleep @options.sleep
                logger.debug 'Waiting for more jobs...'
              else
                logger.info "#{count} jobs processed at %.4f j/s, %d failed ..." % [count / realtime, result.last]
              end

              break if $exit
            end
          rescue => e
            logger.fatal e
            STDERR.puts e.message
            exit 1
          end
        end
      end
    end
  end
end