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
#
# $Id $
# author: Carl P. corliss
# Copyright 2009, The New York Times
#
require 'syslog'
require 'fastthread'

module Emissary
  class Logger

    LOG_SYSLOG = 0x01 unless const_defined? 'LOG_SYSLOG'
    LOG_STDOUT = 0x02 unless const_defined? 'LOG_STDOUT'
    LOG_STDERR = 0x03 unless const_defined? 'LOG_STDERR'

    EMERGENCY = Syslog::Constants::LOG_EMERG unless const_defined? 'EMERGENCY'
    EMERG     = Syslog::Constants::LOG_EMERG unless const_defined? 'EMERG'
    ALERT     = Syslog::Constants::LOG_ALERT unless const_defined? 'ALERT'
    FATAL     = Syslog::Constants::LOG_CRIT unless const_defined? 'FATAL'
    CRITICAL  = Syslog::Constants::LOG_CRIT unless const_defined? 'CRITICAL'
    CRIT      = Syslog::Constants::LOG_CRIT unless const_defined? 'CRIT'
    ERROR     = Syslog::Constants::LOG_ERR unless const_defined? 'ERROR'
    ERR       = Syslog::Constants::LOG_ERR unless const_defined? 'ERR'
    WARNING   = Syslog::Constants::LOG_WARNING unless const_defined? 'WARNING'
    WARN      = Syslog::Constants::LOG_WARNING unless const_defined? 'WARN'
    NOTICE    = Syslog::Constants::LOG_NOTICE unless const_defined? 'NOTICE'
    INFO      = Syslog::Constants::LOG_INFO unless const_defined? 'INFO'
    DEBUG     = Syslog::Constants::LOG_DEBUG unless const_defined? 'DEBUG'

    CONSTANT_ID_MAP = {
      EMERGENCY => [ :emergency, :emerg ],
      ALERT     => [ :alert ],
      CRITICAL  => [ :fatal, :critical, :crit ],
      ERROR     => [ :error, :err ],
      WARNING   => [ :warning, :warn ],
      NOTICE    => [ :notice ],
      INFO      => [ :info ],
      DEBUG     => [ :debug ]
    } unless const_defined? 'CONSTANT_ID_MAP'

    CONSTANT_NAME_MAP = CONSTANT_ID_MAP.inject({}) do |mappings,(id,names)|
      names.each { |name| mappings.merge!({ name => id, name.to_s.upcase => id, name.to_s.downcase => id }) }
    mappings
    end unless const_defined? 'CONSTANT_NAME_MAP'

    attr_accessor :mode, :level, :name

    def self.instance(mode = LOG_STDERR, log_level = NOTICE, name = nil)
      @@logger ||= Emissary::Logger.new mode, log_level
    end

    private :initialize

    def initialize mode, log_level, name = nil
      @mode  = mode || LOG_STDERR
      @level = log_level || INFO
      @name  = name
      @mutex = Mutex.new
    end

    def name=(p) @name = n || File.basename($0); end

    def normalize log_level
      return log_level unless not log_level.kind_of? Fixnum
      return CONSTANT_NAME_MAP[log_level.to_s.downcase] rescue INFO
      return INFO
    end

    def level_to_sym
      CONSTANT_ID_MAP[@level].first
    end

    def level_to_s
      level_to_sym.to_s.upcase
    end

    def loggable?(log_level)
      log_level <= normalize(@level)
    end

    def syslogger
      @mutex.synchronize {
        Syslog.open(name, Syslog::LOG_PID | Syslog::LOG_NDELAY, Syslog::LOG_DAEMON) do |s|
        s.LOG_UPTO(level)
        yield s
        end
      }
    end

    def log(log_level, message, *args)
      case @mode
      when Logger::LOG_SYSLOG
        messages = "#{CONSTANT_ID_MAP[log_level].first.to_s.upcase}: #{message}".gsub(/\t/, ' '*8).split(/\n/)
        # some syslog daemons have a hard time with newlines, so split into multiple lines
        messages.each do |message|
          syslogger { |s| s.log(log_level, message, *args) }
        end
      when Logger::LOG_STDOUT
        $stdout << sprintf(message << "\n", *args) unless not loggable? log_level
      when Logger::LOG_STDERR
        $stderr << sprintf(message << "\n", *args) unless not loggable? log_level
      end

      self
    end

    CONSTANT_ID_MAP.values.flatten.each do |log_level|
      class_eval %(
                def #{log_level}(message, *args)
                    log(#{'::Emissary::Logger::' + log_level.to_s.upcase}, message, *args)
                end
      )
    end
  end
end
