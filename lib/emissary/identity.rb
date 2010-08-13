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
require 'net/http'
require 'socket'

module Emissary
  class Identity
    
    INTERNAL_IDENTITY_GLOB = ::File.join(Emissary::LIBPATH, 'emissary', 'identity', '*.rb')
    EXTERNAL_IDENTITY_GLOB = ::File.join(Emissary::EXTERNAL_IDENTITIES, '*.rb')
    
    attr_reader :loaded, :methods
    alias :loaded? :loaded

    private :initialize
    
    def initialize
      @loaded     = false
      @methods    = nil
      @identities = nil
    end

    def self.instance
      @@instance ||= self.new
    end
    
    def self.new(*largs)
      # prevent subclasses from being instantiated directly, except through
      # the identities() method of this parent class. This class is just a
      # simple method factory and the children shouldn't need to be accessed
      # except through the interface provided here.
      if self == Emissary::Identity
        raise Exception, "Cannot instantiate singleton class directly - use #{self.name}#instance" unless __caller__ == :instance
      else
        klass = self.name.split(/::/)[0..-2].join '::'; subklass = self.name.split(/::/).last
        raise Exception, "Cannot instantiate '#{klass}' subclass '#{subklass}' directly" unless __caller__ == :identities
      end

      allocate.instance_eval(<<-EOS, __FILE__, __LINE__)
        load_identities unless self.class != Emissary::Identity
        self
      EOS
    end

    # Delegation Factory - Uses registered high priority subclasses 
    # for delegation of method calls, falling back to lower priority 
    # subclasess when the method isn't available or throws a :pass
    # in the higher priority subclass
    #
    def method_missing name, *args
      # don't perform lookups on subclasses
      super name, *args unless self.class == Emissary::Identity
      
      name = name.to_sym
      unless (@methods||={}).has_key? name
        method_delegate = value = nil

        # loop through each possible identity, higher priority identities
        # first (0 == low, > 0 == higher). 
        identities.each do |id,object|
          value = nil
          if object.respond_to?(name)
            method_delegate = catch(:pass) {
              value = object.__send__(name, *args) # test for :pass request
              object
            }
            break unless method_delegate.nil?
          end
        end
        
        # if we've gone through all the possible delegates, then pass it
        # up to the superclass (in this case, Object)
        if method_delegate.nil?
          return super(name, *args)
        end
        
        @methods[name] = method_delegate
        return value
      end
 
      return @methods[name].__send__(name, *args)
    end

    def self.register name, opts = {}
      priority = if name != :unix
        opts[:priority].to_i > 0 ? opts.delete(:priority).to_i : 1
      else
        # unix identity always gets zero - though this locks us
        # into *nix as our base. XXX maybe rethink this?
        0 
      end
      
      (self.registry[priority] ||= [])  << name
    end

    def self.exclude names
      @@exclusions ||= []
      @@exclusions |= (names.is_a?(String) ? names.split(/\s*,\s*/) : names.to_a.collect { |n| n.to_s.to_sym })
    end

    # Exclude an identity type when delegating identity method calls
    #
    def self.exclusions
      @@exclusions ||= []
      @@exclusions.to_a.map! { |e| e.to_sym }
    end

    def to_s
      s = ''
      s << '#<%s:0x%x ' % [ self.class, self.__id__ * 2]
      s << to_h.inject([]) { |a,(k,v)| a << %Q|@#{k}="#{v}"| }.join(', ')
      s << '>'
    end

    # Retrieve a list of all the available identifers through reflection of the subclasses
    #
    def identifiers
      identities.inject([]) do |list,(id,object)|
        list |= object.public_methods - object.class.superclass.public_methods - self.public_methods;  list
      end.sort.collect { |id| id.to_sym }
    end

    # Retreive a hash of all identifiers and their values
    #
    def to_h
      Hash[(identifiers).zip(identifiers.collect { |identifier| self.send(identifier) })]
    end

    private
    
    def self.registry
      @@registry ||= []
    end
    
    # Loads all available identities included with this gem
    #
    def load_identities
      return unless not !!loaded? 

      Dir[INTERNAL_IDENTITY_GLOB, EXTERNAL_IDENTITY_GLOB].reject do |id|
        self.class.exclusions.include?("/#{id.to_s.downcase}.rb")
      end.each do |file|
        ::Emissary.logger.info "Loading Identity: #{file}"
        require File.expand_path(file)
      end

      @loaded = true
    end

    # Generates list of possible identities after removing registered exclusions
    # and then ordering them highest priority (> 0) to lowest priority (== 0)
    #
    def identities
      @@identities ||= begin
        self.class.registry.reverse.flatten.reject do |id|
          id.nil? || self.class.exclusions.include?(id)
        end.inject([]) do |a,id|
          a << [ id.to_s, ::Emissary.klass_const("Emissary::Identity::#{id.to_s.capitalize}").new ]; a
        end
      end
    end
  end
end

if __FILE__ == $0
  puts "-----> Name: " + (Emissary.identity.name rescue 'Could not acquire name')
  puts "-----> P IP: " + (Emissary.identity.public_ip rescue 'Could not acquire public ip')
  puts "-----> L IP: " + (Emissary.identity.local_ip rescue 'Could not acquire local_ip')
  puts "-- Identity: " + (Emissary.identity.to_s rescue 'identity not set...')
end
