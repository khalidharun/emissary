require 'spec/spec_helper'
require 'emissary/server'

module Emissary
  describe Server do
    let(:logger) { double('logger').as_null_object }
    let(:operator) { double('operator').as_null_object }
    let(:server) { Emissary::Server.new('test', :operator => operator, :logger => logger) }

    describe "#new" do
      context "with no arguments" do
        it "should throw an error" do
          expect {
            Emissary::Server.new()
          }.should raise_error(ArgumentError)
        end
      end

      context "with one string argument" do
        it "should throw an Emissary::Error" do
          expect {
            Emissary::Server.new('test')
          }.should raise_error(Emissary::Error)
        end
      end

      context "with a string argument and a hash but no 'operator'" do
        it "should throw an error Emissary::Error" do
          expect {
            Emissary::Server.new('test', :logger => logger)
          }.should raise_error(Emissary::Error)
        end
      end

      context "with a string argument and a hash including 'operator'" do
        it "should not throw an error" do
          expect {
            Emissary::Server.new('test', :logger => logger, :operator => 'test')
          }.should_not raise_error(Emissary::Error)
        end
      end

    end #end describe '#new'

    describe "#running?" do
      context "when not running" do
        it "should return False" do
          server.running?.should be_false
        end
      end

      context "when running" do
        it "should return True" do
          s = server
          s.running = true
          s.running?.should be_true
        end
      end
    end

    describe "#shutdown!" do
      it "should exit with return code 0" do
        Kernel.should_receive(:exit!).and_raise(SystemExit)
        lambda { server.shutdown! }.should exit_with_code(0)
      end

      context "with exit! overridden" do
        before :each do
          Kernel.should_receive(:exit!)
        end

        it 'should check for the operator being connected' do
          operator.should_receive(:connected?)
          server.shutdown!
        end

        context "when not running" do
          it 'should not send shutdown message' do
            operator.stub(:connected?).and_return(false)
            operator.should_not_receive('shutdown!')
            server.shutdown!
          end
        end

        context "when running" do
          it 'should send shutdown message' do
            operator.stub(:connected?).and_return(true)
            operator.should_receive('shutdown!')
            server.shutdown!
          end
        end
      end

    end

    describe "#startup" do
      context "when not running" do
        context "with 'run' mocked" do
          before :each do
            server.should_receive(:running?).and_return(false)
            Kernel.should_receive(:exit!)
            server.should_receive(:run)
          end

          it "should create a pid file" do
            server.should_receive(:create_pid_file)
            server.startup
          end

          it "should log a debug message" do
            logger.should_receive(:debug).with("created pid")
            server.startup
          end

          it "should trap signals" do
            server.should_receive(:trap_signals)
            server.startup
          end

        end

        context "without 'run' mocked" do
          before :each do
            Kernel.should_receive(:exit!).at_least(:once)
          end

          it "should receive run command" do
            server.should_receive(:run)
            server.startup
          end

          it "should delete the pid file" do
            server.should_receive(:run)
            server.should_receive(:delete_pid_file)
            server.startup
          end

          it "should run" do
            operator.should_receive(:shutting_down?).and_raise(Exception)
            server.startup
          end
        end
      end

      context "when running" do
        it "should not start up and should return itself" do
          server.should_receive(:running?).and_return(true)
          ret = server.startup
          ret.should equal(server)
        end
      end
    end

    describe "#run" do
      context "when running" do
        it "should not run and should return nil" do
          server.should_receive(:running?).and_return(true)
          ret = server.run
          ret.should be_nil
        end
      end

      context "when not running" do
        let(:server) { Emissary::Server.new('test', :operator => operator, :logger => logger) }

        before :each do
          Kernel.should_receive(:exit!)
        end

        it "should log an info message" do
          logger.should_receive(:info).with("Starting up new Operator process")
          operator.should_receive(:shutting_down?).and_raise(Exception)
          server.run
        end
      end
    end
  end #end describe Server
end #end module
