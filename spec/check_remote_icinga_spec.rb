require 'spec_helper'
require 'stringio'

module Icinga
  describe CheckIcinga do
    let(:stdout)   { StringIO.new }
    let(:stderr)   { StringIO.new }

    describe "#run" do
      let(:stdopts) { {:stdout => stdout, :stderr => stderr } }
      it "Will print a help message" do
        args = [ "--help" ]
        Icinga::CheckIcinga.new(args, stdopts).run

        stdout.string.should match(/check icinga/i)
        stdout.string.should match(/--url/i)
      end

      it "Will fail, when neither check_services nor check_hosts mode is active" do
        args = [ ]
        Icinga::CheckIcinga.new(args, stdopts).run.should eq(Icinga::EXIT_UNKNOWN)

        stderr.string.should match(/choose either hosts or services mode/i)
      end
    end

    describe "#check" do
      let(:stdopts) { {:stdout => stdout, :stderr => stderr, :excon => {:mock => true} } }
      before(:each) do
        Excon.stubs.clear
      end
      describe "#check_hosts" do

        it "Will return ok, when all hosts are good" do
          resp = {
            "cgi_json_version"=>"1.5.0",
            "status"=>
            {"host_status"=> [{"host"=>"host1",
                                "status"=>"UP",
                                "last_check"=>"01-25-2012 17:15:22",
                                "duration"=>"9d  8h 18m 50s",
                                "attempts"=>"1/3",
                                "status_information"=> "HTTP OK"},
                              {"host"=>"host2",
                                "status"=>"UP",
                                "last_check"=>"01-25-2012 17:15:32",
                                "duration"=>"9d  7h 58m  4s",
                                "attempts"=>"1/3",
                                "status_information"=>"PING OK - Packet loss = 0%, RTA = 0.44 ms"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "hosts", "--min", "2" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run

          rc.should == Icinga::EXIT_OK
          stdout.string.should match(/ok: 2=ok, 0=fail/i)
        end

        it "Will return warning, when warning limit is reached" do
          resp = {
            "cgi_json_version"=>"1.5.0",
            "status"=>
            {"host_status"=> [{"host"=>"host1",
                                "status"=>"DOWN",
                                "last_check"=>"01-25-2012 17:15:22",
                                "duration"=>"9d  8h 18m 50s",
                                "attempts"=>"1/3",
                                "status_information"=> "HTTP OK"},
                              {"host"=>"host2",
                                "status"=>"UP",
                                "last_check"=>"01-25-2012 17:15:32",
                                "duration"=>"9d  7h 58m  4s",
                                "attempts"=>"1/3",
                                "status_information"=>"PING OK - Packet loss = 0%, RTA = 0.44 ms"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "hosts", "--warn", "1", "--crit", "2", "--min", "2" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_WARN
          stdout.string.should match(/warn: 1 hosts fail/i)
        end

        it "Will return critial, when critical limit is reached" do
          resp = {
            "cgi_json_version"=>"1.5.0",
            "status"=>
            {"host_status"=> [{"host"=>"host1",
                                "status"=>"DOWN",
                                "last_check"=>"01-25-2012 17:15:22",
                                "duration"=>"9d  8h 18m 50s",
                                "attempts"=>"1/3",
                                "status_information"=> "HTTP OK"},
                              {"host"=>"host2",
                                "status"=>"DOWN",
                                "last_check"=>"01-25-2012 17:15:32",
                                "duration"=>"9d  7h 58m  4s",
                                "attempts"=>"1/3",
                                "status_information"=>"PING OK - Packet loss = 0%, RTA = 0.44 ms"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "hosts", "--warn", "1", "--crit", "2", "--min", "2" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_CRIT
          stdout.string.should match(/crit: 2 hosts fail/i)
        end

        it "Will return critical, when less than expected hosts are found" do
          resp = {
            "cgi_json_version"=>"1.5.0",
            "status"=>
            {"host_status"=> [{"host"=>"host1",
                                "status"=>"UP",
                                "last_check"=>"01-25-2012 17:15:22",
                                "duration"=>"9d  8h 18m 50s",
                                "attempts"=>"1/3",
                                "status_information"=> "HTTP OK"},
                              {"host"=>"host2",
                                "status"=>"UP",
                                "last_check"=>"01-25-2012 17:15:32",
                                "duration"=>"9d  7h 58m  4s",
                                "attempts"=>"1/3",
                                "status_information"=>"PING OK - Packet loss = 0%, RTA = 0.44 ms"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "hosts", "--warn", "1", "--crit", "2", "--min", "5" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          stdout.string.should match(/crit: only 2 hosts/i)
          rc.should == Icinga::EXIT_CRIT
        end

        it "Will return critical, when timeout is met" do
          Excon.stub({:method => :get}) do |_|
            sleep 2
          end

          args = [ "--mode", "hosts", "--warn", "1", "--crit", "2", "--min", "2", "--timeout", "1" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_CRIT
          stdout.string.should match(/Timeout after/i)
        end
      end

      describe "#check_services" do
        it "Will return ok, when all services are good" do
          resp = {
            "cgi_json_version" => "1.5.0",
            "status" => { "service_status" => [{ "host" => "hostA",
                                                 "service" => "HTTP",
                                                 "status" => "OK",
                                                 "last_check" => "01-25-2012 18:05:30",
                                                 "duration" => "15d 19h 55m  1s",
                                                 "attempts" => "1/5",
                                                 "status_information" => "HTTP OK"},
                                               { "host" => "hostB",
                                                 "service" => "ActiveMQ MemoryPercentUsage",
                                                 "status" => "OK",
                                                 "last_check" => "01-25-2012 18:05:25",
                                                 "duration" => "13d  6h 30m 42s",
                                                 "attempts" => "1/5",
                                                 "status_information" => "JMX OK PercentUsage=0"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "services", "--warn", "1", "--crit", "2", "--min", "2" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_OK
          stdout.string.should match(/ok: 2=ok, 0=fail/i)
        end

        it "Will return warning, when warning limit is reached" do
          resp = {
            "cgi_json_version" => "1.5.0",
            "status" => { "service_status" => [{ "host" => "hostA",
                                                 "service" => "HTTP",
                                                 "status" => "WARNING",
                                                 "last_check" => "01-25-2012 18:05:30",
                                                 "duration" => "15d 19h 55m  1s",
                                                 "attempts" => "1/5",
                                                 "status_information" => "HTTP OK"},
                                               { "host" => "hostB",
                                                 "service" => "ActiveMQ MemoryPercentUsage",
                                                 "status" => "OK",
                                                 "last_check" => "01-25-2012 18:05:25",
                                                 "duration" => "13d  6h 30m 42s",
                                                 "attempts" => "1/5",
                                                 "status_information" => "JMX OK PercentUsage=0"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "services", "--warn", "1", "--crit", "2", "--min", "2" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_WARN
          stdout.string.should match(/warn: 1 services fail/i)
        end

        it "Will return critial, when critical limit is reached" do
          resp = {
            "cgi_json_version" => "1.5.0",
            "status" => { "service_status" => [{ "host" => "hostA",
                                                 "service" => "HTTP",
                                                 "status" => "WARNING",
                                                 "last_check" => "01-25-2012 18:05:30",
                                                 "duration" => "15d 19h 55m  1s",
                                                 "attempts" => "1/5",
                                                 "status_information" => "HTTP OK"},
                                               { "host" => "hostB",
                                                 "service" => "ActiveMQ MemoryPercentUsage",
                                                 "status" => "CRITICAL",
                                                 "last_check" => "01-25-2012 18:05:25",
                                                 "duration" => "13d  6h 30m 42s",
                                                 "attempts" => "1/5",
                                                 "status_information" => "JMX OK PercentUsage=0"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "services", "--warn", "1", "--crit", "2", "--min", "2" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_CRIT
          stdout.string.should match(/crit: 2 services fail/i)
        end

        it "Will return critical, when less than expected services are found" do
          resp = {
            "cgi_json_version" => "1.5.0",
            "status" => { "service_status" => [{ "host" => "hostA",
                                                 "service" => "HTTP",
                                                 "status" => "WARNING",
                                                 "last_check" => "01-25-2012 18:05:30",
                                                 "duration" => "15d 19h 55m  1s",
                                                 "attempts" => "1/5",
                                                 "status_information" => "HTTP OK"},
                                               { "host" => "hostB",
                                                 "service" => "ActiveMQ MemoryPercentUsage",
                                                 "status" => "OK",
                                                 "last_check" => "01-25-2012 18:05:25",
                                                 "duration" => "13d  6h 30m 42s",
                                                 "attempts" => "1/5",
                                                 "status_information" => "JMX OK PercentUsage=0"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "services", "--warn", "1", "--crit", "2", "--min", "3" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_CRIT
          stdout.string.should match(/crit: only 2 services found/i)
        end

        it "Will return critical, when timeout is met" do
          Excon.stub({:method => :get}) do |_|
            sleep 2
          end

          args = [ "--mode", "services", "--warn", "1", "--crit", "2", "--min", "2", "--timeout", "1" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_CRIT
          stdout.string.should match(/Timeout after/i)
        end

      end
    end
  end
end