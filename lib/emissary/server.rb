#   Copyright 2010 The New York Times
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
#
require 'emissary/servolux'
require 'emissary/logger'
require 'eventmachine'

module Emissary
  class Server < Servolux::Server
    attr_accessor :running

    def initialize(name, opts = {}, &block)
      opts[:logger] ||= Emissary::Logger.instance #Pass in a logger or default to Emissary.logger instance
      @logger = opts[:logger]
      @running = false
      @operator = opts.delete(:operator) or raise Emissary::Error.new(ArgumentError, "Operator not provided")

      at_exit { shutdown! :graceful }
      super(name, opts, &block)
    end

    def running?() !!@running; end

    def shutdown! type = :graceful
      begin
        case type
          when :graceful
            @operator.shutdown! if @operator.connected?
            EventMachine::stop_event_loop
        end
      rescue Exception => e
        @logger.error "Exception caught during graceful shutdown: #{e.class.name}: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
      ensure
        Kernel.exit!(0)
      end
    end

    alias :int :shutdown!
    alias :term :shutdown!

    # override Servolux::Server's startup because we don't need threaded here.
    # also, we want to enforce exiting on completion of startup's run
    def startup
      return self unless not running?

      begin
        create_pid_file
        logger.debug "created pid"
        trap_signals
        run
      rescue Exception => e
        # if something is caught here, then we can only log it. at this point we are in an
        # unknown state and can only delete our pid file and #exit!. Attempting to call
        # our #term method could cause other problems here.
        Emissary.logger.error "Server '#{$0}': #{e.class.name}: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
      ensure
        delete_pid_file
        shutdown! :hard
      end

      return self
    end

    def run
      return if running?

      EM.run {
        EM.add_periodic_timer(0.5) {
          begin
            @operator.shutdown! if @operator.shutting_down?
          rescue Exception => e
            shutdown! :graceful
          end
        }

        begin
          begin
            $0 = @name
            logger.info "Starting up new Operator process"
            @running = @operator.run
          rescue Exception => e
            Emissary.logger.error "Server '#{$0}': #{e.class.name}: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
            raise e
          end
        rescue ::Emissary::Error::ConnectionError => e
          shutdown! :hard
        rescue Exception => e
          shutdown! :graceful
        end
      }
    end
  end

end
