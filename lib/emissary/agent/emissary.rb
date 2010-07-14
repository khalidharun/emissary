require 'emissary/agent'
require 'emissary/gem'
require 'tempfile'
require 'fileutils'

module Emissary
  class Agent::Emissary < Agent
    def valid_methods
      [ :reconfig, :selfupdate, :startup, :shutdown ]
    end
    
    def reconfig new_config
      throw :skip_implicit_response if new_config.strip.empty?
      
      if (test(?w, config[:agents][:emissary][:config_path]))
        begin
          ((tmp = Tempfile.new('new_config')) << new_config).flush
          Emissary::Daemon.get_config(tmp.path)
        rescue Exception => e
          resonse = message.response
          response.status_type = :error
          response.status_note = e.message
          return response
        else
          FileUtils.mv tmp.path, config[:agents][:emissary][:config_path]
          # signal a USR1 to our parent, which will cause it to kill the
          # children and restart them after rereading it's configuration
          Process.kill('HUP', config[:parent_pid])
        ensure
          tmp.close
        end
      end      

    end

    def selfupdate version = :latest, source_url = :default
      with_detached_process do 
        require 'emissary/agent/gem'
        begin
          ::Emissary::Gem.new('emissary').update(version, source_url)
        rescue ::Gem::InstallError, ::Gem::GemNotFoundException => e
          response = message.response
          response.status_type = :error
          response.status_note = e.message
          return response
        else
          %x{
            /etc/init.d/emissary stop
            # now make sure that it is stopped
            ps uxa | grep '(emissary|emop_)' | awk '{ print $2 }' | xargs kill -9
            /etc/init.d/emissary start
          }
          throw :skip_implicit_response
        end
      end
    end
    
    def startup
      message.recipient = config[:startup]
      message.args = [
        ::Emissary.identity.name,
        ::Emissary.identity.public_ip,
        ::Emissary.identity.local_ip,
        ::Emissary.identity.instance_id,
        ::Emissary.identity.server_id,
        ::Emissary.identity.cluster_id,
        ::Emissary.identity.account_id,
        ::Emissary.identity.queue_name,
      ]

      ::Emissary.logger.notice "Sending Startup message with args: #{message.args.inspect}"

      message
    end
    
    def shutdown
      message.recipient = config[:shutdown]
      message.args = [ config[:agents][:emissary][:server_id] ]
      ::Emissary.logger.notice "Sending Shutdown message with args: #{message.args.inspect}"
      message
    end

private

    def with_detached_process
      raise Exception, 'Block missing for with_detached_process call' unless block_given?
      
      # completely seperate from our parent process
      pid = Kernel.fork do
        Process.setsid
        exit!(0) if fork # prevent process from acquiring a controlling terminal
        Dir.chdir '/'
        File.umask 0000
        STDIN.reopen  '/dev/null'       # Free file descriptors and
        STDOUT.reopen '/dev/null', 'a' # point them somewhere sensible.
        STDERR.reopen '/dev/null', 'a'
        yield
      end
      
      Process.detach(pid)
    end
    
  end
end
