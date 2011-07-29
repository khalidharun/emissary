Given /^I have (not |)created a configuration file$/ do |negate|
  @config = nil
end

When /^Emissary starts$/ do
  @emissary = lambda {
    Emissary::Daemon.new(
      'emissary-master',
      :log_level => :debug,
      :config_file => @config,
      :daemonize => true
    )
  }
end

Then /^it should raise an ([^\s]+) error containing message '(.+)'$/ do |ex, msg|
  expect {
    @emissary.call
  }.to raise_error(eval(ex), /#{Regexp.quote(msg)}/)
end

Then /^it should not raise an error$/ do
  expect {
    @emissary.call
  }.to_not raise_error
end

Given /^it is not a well formed configuration file$/ do
  @config = '/tmp/bad_config.ini'
  File.open(@config, 'w') do |file|
    file.puts <<-END
[fail]

# what operator types are monitoring for message events (comma seperated list)
operators = [ amqt ]

# pid_dir: Where to store the Process ID file which contains the id of the process
# and is used for stoping and reloading the service
pid_dir = /var/fail

# log_level: the level of information to log. see 'man 3 syslog' for list of log levels
log_level = Fail

agents = [ all ]
    END
  end
end

Given /^it is a well formed configuration file$/ do
  @config = '/tmp/good_config.ini'
  File.open(@config, 'w') do |file|
    file.puts <<-END
[general]

# what operator types are monitoring for message events (comma seperated list)
operators = [ amqp ]

# pid_dir: Where to store the Process ID file which contains the id of the process
# and is used for stoping and reloading the service
pid_dir = /tmp

# log_level: the level of information to log. see 'man 3 syslog' for list of log levels
log_level = debug

agents = [ all ]

[agents]
    execute = {
        safe_path = /opt/nyt/emissary/bin
    }

    sshkeys = {
        valid_users = [
            root, dev, logpoll
        ]
    }

[amqp]
    node = {
        # URI schema is: <scheme>://<user>:<pass>@<server>:<port>/<vhost>
        # scheme is either amqp (non-ssl) or amqps (ssl)
        URI = amqp://nimbul:cucumber@127.0.0.1:5672/nimbul

        subscriptions = [
            request.2:topic
            request.2.12:topic
            request.2.12.263:topic
            request.2.12.263.__ID_INSTANCE_ID__:topic
        ]

        startup  = startup.2.12.263.__ID_INSTANCE_ID__:topic
        shutdown = shutdown.2.12.263.__ID_INSTANCE_ID__:topic

        stats    = {
            interval = 300
            queue_base = info.stat.2.12.263.__ID_INSTANCE_ID__:topic
        }

        # no stats for the time being
        disable = [ stats ]
    }
    END
  end
end

Then /^it should daemonize$/ do
  puts @emissary.call.startup
end
