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
module Emissary

  class Error< StandardError
    class ConnectionError < StandardError; end
    class InvalidMessageFormat < StandardError; end
    class NotImplementedError < StandardError; end
    
    attr_reader :origin

    def self.new(*args) #:nodoc:
      allocate.instance_eval(<<-EOS, __FILE__, __LINE__)
        alias :original_instance_of? :instance_of?
        alias :original_kind_of? :kind_of?
  
        def instance_of? klass
          self.original_instance_of? klass or origin.instance_of? klass
        end
    
        def kind_of? klass
          self.original_kind_of? klass or origin.kind_of? klass
        end

        # Call a superclass's #initialize if it has one
        initialize(*args)

        self
      EOS
    end

    def initialize(origin = Exception, message = '')
      
      case origin
        when Exception
          @origin = origin
        when Class
          @origin = origin.new message
        else
          @origin = Exception.new message
      end

      super message
    end

    def origin_backtrace
      origin.backtrace
    end

    def origin_message
      origin.message
    end
    
    def message
      "#{super}\n\t#{self.backtrace.join("\n\t")}\n" +
      "Origin: #{origin.class}: #{origin_message}\n\t#{origin_backtrace.join("\n\t")}"
    end
  end
end

if __FILE__ == $0
  class Emissary::TrackingError < Emissary::Error; end
  class Emissary::NetworkEncapsulatedError < Emissary::Error; end
  def a() raise ArgumentError, 'testing'; end
  def b() a; end
  def c() b; end
  def d() c; end
  def test() d; end

  begin
    begin
      begin
        begin
          test
        rescue Exception => e
          raise Emissary::Error.new e, 'general error'
        end
      rescue Emissary::Error => e
        puts "----------------- 1 -----------------\n#{e.message}"
        raise Emissary::TrackingError.new(e, 'testing tracking')
      end
    rescue Emissary::Error => e
      puts "----------------- 2 -----------------\n#{e.message}"
      raise Emissary::NetworkEncapsulatedError.new(e, 'testing network encapsulated')
    end
  rescue Emissary::Error => e
    puts "----------------- 3 -----------------\n#{e.message}"
  end
  
  [ Exception, ArgumentError, Emissary::Error, Emissary::TrackingError, Emissary::NetworkEncapsulatedError].each do |k|
    puts "e.kind_of?(#{k.name}): #{e.kind_of? k}"
  end
end
