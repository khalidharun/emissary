require 'spec_helper'
require 'emissary/agent'

module Emissary
  describe Agent do
    let(:message) { double(:message) }
    let(:operator) { double(:operator) }
    let(:config) { double(:config) }
    let(:agent) {
      Emissary::Agent.new(
        :operator => operator,
        :config => config,
        :message => message
      )
    }

    describe "#new" do
      context "with no arguments" do
        it "should raise an ArgumentError" do
          expect { Emissary::Agent.new }.should raise_error(ArgumentError)
        end
      end

      it "should take a message object"
    end

    describe "#post_init" do
      it "should do nothing" do
      end
    end

    describe "#valid_methods" do
      it "should raise error" do
      end
    end
    describe "#activate"
    describe "send_message"
  end
end
