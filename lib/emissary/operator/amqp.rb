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
require 'rubygems'
require 'eventmachine'
gem 'amqp', '=0.6.7'
require 'mq'
require 'uri'

module Emissary
  class Operator
    module AMQP

      class InvalidExchange < ArgumentError; end
      class InvalidConfig < StandardError; end

      REQUIRED_KEYS   = [ :uri, :subscriptions ]
      VALID_EXCHANGES = [ :headers, :topic, :direct, :fanout ]
      
      attr_accessor :subscriptions
      attr_accessor :not_acked
      
      @@queue_count = 1
      
      def validate_config! 
        errors = []
        errors << 'config not a hash!' unless config.instance_of? Hash

        REQUIRED_KEYS.each do |key|
            errors << "missing required option '#{key}'" unless config.has_key? key
        end

        u = ::URI.parse(config[:uri])
        errors << "URI scheme /must/ be one of 'amqp' or 'amqps'" unless !!u.scheme.match(/^amqps{0,1}$/)
        [ :user, :password, :host, :path ].each do |v|
            errors << "invalid value 'nil' for URI part [#{v}]" if u.respond_to? v and u.send(v).nil?
        end
        
        raise errors.join("\n") unless errors.empty?
        return true
      end

      def post_init
        uri = ::URI.parse @config[:uri]
        ssl = (uri.scheme.to_sym == :amqps)

        @connect_details = {
          :host  => uri.host,
          :ssl   => ssl,
          :user  => (::URI.decode(uri.user) rescue nil)     || 'guest',
          :pass  => (::URI.decode(uri.password) rescue nil) || 'guest',
          :vhost => (! uri.path.empty? ? uri.path : '/nimbul'),
          :port  => uri.port || (ssl ? 5671 : 5672),
          :logging => !!@config[:debug],
        }
        
        # normalize the subscriptions
        @subscriptions = @config[:subscriptions].inject({}) do |hash,queue|
          key, type = queue.split(':')
          type = type.nil? ? DEFAULT_EXCHANGE : (VALID_EXCHANGES.include?(type.to_sym) ? type.to_sym : DEFAULT_EXCHANGE)
          (hash[type] ||= []) << key
          hash
        end
        
        # one unique receiving queue per connection
        @queue_name = "#{Emissary.identity.queue_name}.#{@@queue_count}"
        @@queue_count += 1
        
        @not_acked = {}
      end
      
      def connect
        if @connect_details[:ssl] and not EM.ssl?
          raise ::Emissary::Error::ConnectionError ,
            "Requested SSL connection but EventMachine not compiled with SSL support - quitting!"
        end

        @message_pool = Queue.new

        @connection = ::AMQP.connect(@connect_details)
        @channel = ::MQ.new(@connection)
        
        @queue_config = {
          :durable     => @config[:queue_durable].nil?     ? false : @config[:queue_durable],
          :auto_delete => @config[:queue_auto_delete].nil? ? true  : @config[:queue_auto_delete],
          :exclusive   => @config[:queue_exclusive].nil?   ? true  : @config[:queue_exclusive]
        }

        @queue = ::MQ::Queue.new(@channel, @queue_name, @queue_config)
        
        @exchanges = {}
        @exchanges[:topic]  = ::MQ::Exchange.new(@channel, :topic,  'amq.topic')
        @exchanges[:fanout] = ::MQ::Exchange.new(@channel, :fanout, 'amq.fanout')
        @exchanges[:direct] = ::MQ::Exchange.new(@channel, :direct, 'amq.direct')
        
        true
      end
      
      def subscribe
        @subscriptions.each do |exchange, keys|
          keys.map do |routing_key|
            Emissary.logger.debug "Subscribing To Key: '#{routing_key}' on Exchange '#{exchange}'"
            @queue.bind(@exchanges[exchange], :key => routing_key)
          end
        end

        # now bind to our name directly so we get messages that are
        # specifically for us 
        @queue.bind(@exchanges[:direct], :key => Emissary.identity.queue_name)

        @queue.subscribe(:ack => true) do |info, message|
          begin
            message = Emissary::Message.decode(message).stamp_received!
          rescue ::Emissary::Error::InvalidMessageFormat => e
            message = Emissary::Message.new
            message.errors << e
          end
          
          @not_acked[message.uuid] = info
          Emissary.logger.debug "Received through '#{info.exchange}' and routing key '#{info.routing_key}'"

          receive message 
        end
      end

      def unsubscribe
        @subscriptions.each do |exchange, keys|
          keys.map do |routing_key|
            Emissary.logger.info "Unsubscribing from '#{routing_key}' on Exchange '#{exchange}'"
            @queue.unbind(@exchanges[exchange], :key => routing_key)
          end
        end
        
        Emissary.logger.info "Unsubscribing from my own queue."
        @queue.unbind(@exchanges[:direct], :key => Emissary.identity.queue_name)

        Emissary.logger.info "Cancelling all subscriptions."
        @queue.unsubscribe # could get away with only calling this but, the above "feels" cleaner
      end
      
      def send_data msg
        begin
          Emissary.logger.debug "Sending message through exchange '#{msg.exchange_type.to_s}' with routing key '#{msg.routing_key}'"
          Emissary.logger.debug "Message Originator: #{msg.originator} - Recipient: #{msg.recipient}"
          @exchanges[msg.exchange_type].publish msg.stamp_sent!.encode, :routing_key => msg.routing_key
        rescue NoMethodError
          raise InvalidExchange, "publish request on invalid exchange '#{msg.exchange_type}' with routing key '#{msg.routing_key}'"
        end
      end
      
      def acknowledge message
        unless message.kind_of? Emissary::Message
          Emissary.logger.warning "Can't acknowledge message not deriving from Emissary::Message class" 
        end
        
        @not_acked.delete(message.uuid).ack 
        Emissary.logger.debug "Acknowledged Message ID: #{message.uuid}"
      rescue NoMethodError
        Emissary.logger.warning "Message with UUID #{message.uuid} not acknowledged."
      rescue Exception => e
        Emissary.logger.error "Error in Emissary::Operator::AMQP#acknowledge: #{e.class.name}: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
      end
      
      def reject message, opts = { :requeue => true }
        return true # currently not implemented in RabbitMQ 1.7.x (coming in versions supporting 0.9.1 AMQP spec)
        unless message.kind_of? Emissary::Message
          Emissary.logger.warning "Unable to reject message not deriving from Emissary::Message class" 
        end
        
        @not_acked.delete(message.uuid).reject(opts)
        Emissary.logger.debug "Rejected Message ID: #{message.uuid}"
      rescue Exception => e
        Emissary.logger.error "Error in AMQP::Reject: #{e.class.name}: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
      end
      
      def close
        # Note: NOT currently supported by current version of RabbitMQ (1.7.x)
        #Emissary.logger.info "Requeueing unacknowledged messages"
        #@not_acked.each { |i| i.reject :requeue => true }

        # unfortunately, due to the nature of amqp's deferred asyncronous handling of data send/recv
        # and no ability to determine whether our shutdown message was /actually/ sent, we have to resort
        # to sleeping for 1s to ensure our message went out
        sleep 1 # XXX: HACK HACK HACK - BAD BAD BAD :-(
        unsubscribe
        ::AMQP.stop 
      end
      
      def status
      end
    end
  end
end
