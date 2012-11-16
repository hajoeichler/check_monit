require 'spec_helper'
require 'stringio'
require 'rexml/document'

module Icinga
  describe CheckMonit do
    let(:stdout)   { StringIO.new }
    let(:stderr)   { StringIO.new }

    describe "#run" do
      let(:stdopts) { {:stdout => stdout, :stderr => stderr } }
      it "Will print a help message" do
        args = [ "--help" ]
        Icinga::CheckMonit.new(args, stdopts).run

        stdout.string.should match(/check monit/i)
        stdout.string.should match(/--status-uri/i)
      end
    end

    describe "#check" do
      let(:stdopts) { {:stdout => stdout, :stderr => stderr, :excon => {:mock => true} } }
      before(:each) do
        Excon.stubs.clear
      end
      it "Will return OK when there are the minium required services" do
        xml = <<EOF
<monit>
  <service type="5">
    <name>system</name>
    <status>0</status>
    <monitor>1</monitor>
  </service>
</monit>
EOF
        Excon.stub({:method => :get}, {:body => xml, :status => 200})

        args = [ "--min", "1" ]
        rc = Icinga::CheckMonit.new(args, stdopts).run

        rc.should == Icinga::EXIT_OK
        stdout.string.should match(/OK: \(1=ok, 0=fail, 1=monitored, 0=NOT monitored\)./i)
      end
      it "Will return FAIL when the number of services in bad state is above or equal the critical level" do
        xml = <<EOF
<monit>
  <service type="5">
    <name>system</name>
    <status>1</status>
    <monitor>1</monitor>
  </service>
</monit>
EOF
        Excon.stub({:method => :get}, {:body => xml, :status => 200})

        args = [ "--crit", "1" ]
        rc = Icinga::CheckMonit.new(args, stdopts).run

        rc.should == Icinga::EXIT_CRIT
        stdout.string.should match(/CRIT: due to status \(0=ok, 1=fail, 1=monitored, 0=NOT monitored\)./i)
      end
      it "Will return WARN when the number of unmonitored services is above or equal the critical level" do
        xml = <<EOF
<monit>
  <service type="5">
    <name>system</name>
    <status>0</status>
    <monitor>-1</monitor>
  </service>
</monit>
EOF
        Excon.stub({:method => :get}, {:body => xml, :status => 200})

        args = [ "--warn-not-monitored", "1", "--crit-not-monitored", "2" ]
        rc = Icinga::CheckMonit.new(args, stdopts).run

        rc.should == Icinga::EXIT_WARN
        stdout.string.should match(/WARN: due to NOT monitored \(1=ok, 0=fail, 0=monitored, 1=NOT monitored\)./i)
      end
    end
  end
end
