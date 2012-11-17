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

        stdout.string.should match(/Check Monit/)
        stdout.string.should match(/--status-uri/)
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
  <service>
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
        stdout.string.should match(/OK: \(1=ok, 0=fail, 0=not monitored\)./)
      end
      it "Will return FAIL when the number of services in bad state is above or equal the critical level" do
        xml = <<EOF
<monit>
  <service>
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
        stdout.string.should match(/CRIT: due to status \(0=ok, 1=fail, 0=not monitored\)./)
        stdout.string.should match(/Failed: system/i)
      end
      it "Will return WARN when the number of unmonitored services is above or equal the critical level" do
        xml = <<EOF
<monit>
  <service>
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
        stdout.string.should match(/WARN: due to not monitored \(0=ok, 0=fail, 1=not monitored\)./)
        stdout.string.should match(/Not monitored: system/)
      end
      it "Check multiple services with all kind of stati" do
        xml = <<EOF
<monit>
  <service>
    <name>s1</name>
    <status>0</status>
    <monitor>1</monitor>
  </service>
  <service>
    <name>s2</name>
    <status>1</status>
    <monitor>0</monitor>
  </service>
  <service>
    <name>s3</name>
    <status>1</status>
    <monitor>1</monitor>
  </service>
  <service>
    <name>s4</name>
    <status>0</status>
    <monitor>0</monitor>
  </service>
</monit>
EOF
        Excon.stub({:method => :get}, {:body => xml, :status => 200})

        args = [ "--warn", "5", "--crit", "5", "--warn-not-monitored", "5", "--crit-not-monitored", "5" ]
        rc = Icinga::CheckMonit.new(args, stdopts).run

        rc.should == Icinga::EXIT_OK
        stdout.string.should match(/OK: \(1=ok, 2=fail, 2=not monitored\)./)
        stdout.string.should match(/Failed: s2, s3/)
        stdout.string.should match(/Not monitored: s2, s4/)
      end
    end
  end
end
