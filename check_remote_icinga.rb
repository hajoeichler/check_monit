#! /usr/bin/ruby

# A Nagios/Icinga plugin to check remote Monit installations.
#
# This can be used in Cloud-Computing setups, where Monit is used for node monitoring
# and Icinga to monitor the whole environement.

require 'rubygems'
require 'optparse'
require 'excon'
require 'base64'
require 'pp'
require 'timeout'

module Icinga
  EXIT_OK = 0
  EXIT_WARN = 1
  EXIT_CRIT = 2
  EXIT_UNKNOWN = 3

  module HTTPTools
    def basic_auth(username, password)
      credentials = Base64.encode64("#{username}:#{password}").strip
      return "Basic #{credentials}"
    end

    def validate(resp)
      raise "HTTP 401 - Password wrong?" if resp.status == 401
      raise "Did not get HTTP 200 (but a #{resp.status})." unless resp.status == 200
      return resp
    end
  end
  class CheckMonit
    include Icinga::HTTPTools

    def initialize(args, opts = {:stdout => $stdout, :stderr => $stderr, :excon => {}})
      @args = args
      @modes = [:hosts, :services]
      @stdout, @stderr = opts.delete(:stdout), opts.delete(:stderr)
      @options = { :help => false,
                   :debug => false,
                   :timeout => 10,
                   :min => -1,
                   :warn => 1,
                   :crit => 1,
                   :exclude => [],
                   :base_url => "http://localhost:2812",
                   :status_uri => "_status?format=xml&level=summary",
                   :username => nil,
                   :password => nil }.merge(opts)

      @parser = OptionParser.new("Check Monit - Icinga/Nagios plugin to Monit") do |opts|
        opts.on("--min N", Integer, "Number of services to expect.") do |arg|
          @options[:min] = arg
        end
        opts.on("--warn N", Integer, "Warning level") do |arg|
          @options[:warn] = arg
        end
        opts.on("--crit N", Integer, "Critical level") do |arg|
          @options[:crit] = arg
        end
        opts.on("--username NAME", "HTTP username") do |arg|
          @options[:username] = arg
        end
        opts.on("--password password", "HTTP password") do |arg|
          @options[:password] = arg
        end
        opts.on("--url URL", "URL (default: #{@options[:base_url]})") do |arg|
          @options[:base_url] = arg
        end
        opts.on("--status-uri PATH", "path to XML output (default: #{@options[:status_uri]})") do |arg|
          @options[:status_uri] = arg
        end
        opts.on("--timeout SECONDS", Integer, "Timeout for HTTP request (default: #{@options[:timeout]})") do |arg|
          @options[:timeout] = arg
        end
        opts.on("--exclude PATTERN", "Exclude service where the name matches the pattern") do |p|
          @options[:exclude] << Regexp.new(p)
        end
        opts.on("-d", "--debug") do
          @options[:debug] = true
        end
        opts.on("-h", "--help") do
          @options[:help] = true
        end
      end

      @parser.parse(args)
    end

    def debug(msg)
      puts msg if @options[:debug]
    end

    def run
      if @options[:help]
        @stdout.puts @parser
        return EXIT_OK
      end
      return check_services
    end

    private
    def headers
      unless @options[:username].nil? or @options[:password].nil?
        return { "Authorization" => basic_auth(@options[:username], @options[:password]) }
      end
      return {}
    end

    def init_state
      state = { :timeout => true }
      state.default = 0
      return state
    end

    def check_services
      params = @options[:excon].merge({ :path => @options[:status_uri],
                                        :headers => headers })
      debug "Will fetch: #{@options[:base_url]}/#{@options[:status_uri]}"

      result = init_state
      begin
        resp = Timeout::timeout@options[:timeout] do
          Excon.get(@options[:base_url], params)
        end
        result[:timeout] = false
        validate(resp)
        #state = parse(validate(resp))
        #result = state["status"]["service_status"].inject(result) { |memo, s| analyze_state(memo, s, "OK", "service") }
      rescue Timeout::Error => e
      end
      return check_limits(result, "services")
    end

    def check_limits(result, msg)
      if result[:timeout]
        @stdout.puts "CRIT: Timeout after #{@options[:timeout]}"
        return EXIT_CRIT
      end
#      if @options[:min] > result[:ok] + result[:fail]
#        @stdout.puts "CRIT: Only #{result[:ok] + result[:fail]} #{msg} found (#{result[:ok]}=ok, #{result[:fail]}=fail, #{result[:other]}=other)."
#        return EXIT_CRIT
#      end
#      if result[:fail] >= @options[:crit]
#        @stdout.puts "CRIT: #{result[:fail]} #{msg} fail (#{result[:ok]}=ok, #{result[:fail]}=fail, #{result[:other]}=other)."
#        return EXIT_CRIT
#      end
#      if result[:fail] >= @options[:warn]
#        @stdout.puts "WARN: #{result[:fail]} #{msg} fail (#{result[:ok]}=ok, #{result[:fail]}=fail, #{result[:other]}=other)."
#        return EXIT_WARN
#      end
#      @stdout.puts "OK: #{result[:ok]}=ok, #{result[:fail]}=fail, #{result[:other]}=other."
      return EXIT_OK
    end
  end
end

if __FILE__ == $0
  begin
    exit Icinga::CheckMonit.new(ARGV).run
  rescue => e
    warn e.message
    warn e.backtrace.join("\n\t")
    exit Icinga::EXIT_UNKNOWN
  end
end
