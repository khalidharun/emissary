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
require 'tempfile'
require 'fileutils'

module Emissary
  class Agent::Emissary < Agent
    INIT_DATA = [
      ::Emissary.identity.name,
      ::Emissary.identity.public_ip,
      ::Emissary.identity.local_ip,
      ::Emissary.identity.instance_id,
      ::Emissary.identity.server_id,
      ::Emissary.identity.cluster_id,
      ::Emissary.identity.account_id,
      ::Emissary.identity.queue_name,
      ::Emissary.version
    ]
    
    def valid_methods
      [ :reconfig, :selfupdate, :startup, :shutdown, :initdata, :reinit ]
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

    def selfupdate version = :latest
      begin
        emissary_gem = ::Emissary::GemHelper.new('emissary')
        request_version, source_uri = emissary_gem.versions(version).flatten
        current_version, _ = emissary_gem.versions(:current).flatten

        unless not emissary_gem.installable? request_version
          ::Emissary.logger.debug "Emissary SelfUpdate to version '#{request_version.to_s}' requested."
          new_version = emissary_gem.update(request_version, source_uri)
          ::Emissary.logger.debug "Emissary gem updated from '#{::Emissary.version}' to '#{new_version}'"
        else
          ::Emissary.logger.debug " -- SELFUPDATE -- [         VERSION: #{version}]"
          ::Emissary.logger.debug " -- SELFUPDATE -- [ CURRENT_VERSION: #{current_version}]"
          ::Emissary.logger.debug " -- SELFUPDATE -- [ REQUEST_VERSION: #{request_version}]"
          
          notice = 'Emissary selfupdate skipped - ' + case true
            when request_version.nil?
              if version == :latest
                "already at latest version."
              else
                "non-existent version '#{version}'"
              end
            when current_version == request_version
              "already at specified version #{version}."
            when current_version > request_version
              "downgrade to version #{request_version} not allowed."
            else
              "unable to update from #{::Emissary.version} to requested version #{request_version}."
          end
          ::Emissary.logger.warn notice
          response = message.response
          response.status_note = notice
          return response
        end
      rescue ::Gem::InstallError, ::Gem::GemNotFoundException => e
        ::Emissary.logger.error "Emissary selfupdate failed with reason: #{e.message}"
        return message.error(e)
      else
        ::Emissary.logger.debug "SelfUpdate: About to detach and run commands"
        with_detached_process('emissary-selfupdate') do
          %x{
            emissary stop;
            sleep 2; 
            ps uxa | grep -v grep | grep '(emissary|emop_)' | awk '{ print $2 }' | xargs kill -9;
            sleep 1;
            source /etc/cloudrc;
            emissary start -d;
          }
        end
        ::Emissary.logger.debug "SelfUpdate: Child detached"
        throw :skip_implicit_response
      end
    end
    
    def startup
      message = initdata
      message.recipient = config[:startup]
      ::Emissary.logger.notice "Sending Startup message with args: #{message.args.inspect}"
      message
    end
    alias :reinit :startup
    
    def initdata
      response = message.response
      response.args = INIT_DATA
      response
    end
    
    def shutdown
      message.recipient = config[:shutdown]
      message.args = [
        ::Emissary.identity.server_id,
        ::Emissary.identity.cluster_id,
        ::Emissary.identity.account_id,
        ::Emissary.identity.instance_id
      ]
      ::Emissary.logger.notice "Sending Shutdown message with args: #{message.args.inspect}"
      message
    end

private

    def with_detached_process(name = nil)
      raise Exception, 'Block missing for with_detached_process call' unless block_given?

      # completely seperate from our parent process
      pid = Kernel.fork do
        Process.setsid
        exit!(0) if fork
        $0 = name unless name.nil?
        Dir.chdir '/'
        ::Emissary.logger.debug "SelfUpdate: Detached and running update command block now..."
        yield
        ::Emissary.logger.debug "SelfUpdate: Finished running update command block - exiting..."
        exit!(0)
      end

      ::Emissary.logger.debug "SelfUpdate: Detaching child process now."
      #don't worry about the child anymore - it's on it's own
      Process.detach(pid)
    end
  end
end
