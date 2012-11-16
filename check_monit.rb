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
require "rexml/document"

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
                   :warn_nm => 1,
                   :crit_nm => 1,
                   :exclude => [],
                   :base_url => "http://localhost",
                   :port => 2812,
                   :status_uri => "_status?format=xml&level=summary",
                   :username => nil,
                   :password => nil }.merge(opts)

      @parser = OptionParser.new("Check Monit - Icinga/Nagios plugin to Monit") do |opts|
        opts.on("--min N", Integer, "Number of services to expect.") do |arg|
          @options[:min] = arg
        end
        opts.on("--warn N", Integer, "Warning level for services in bad state") do |arg|
          @options[:warn] = arg
        end
        opts.on("--crit N", Integer, "Critical level for service in bad state") do |arg|
          @options[:crit] = arg
        end
        opts.on("--warn-not-monitored N", Integer, "Warning level for not monitored services") do |arg|
          @options[:warn_nm] = arg
        end
        opts.on("--crit-not-monitored N", Integer, "Critical level for not monitored services") do |arg|
          @options[:crit_nm] = arg
        end
        opts.on("--username NAME", "HTTP username") do |arg|
          @options[:username] = arg
        end
        opts.on("--password password", "HTTP password") do |arg|
          @options[:password] = arg
        end
        opts.on("--base-url URL", "URL (default: #{@options[:base_url]})") do |arg|
          @options[:base_url] = arg
        end
        opts.on("--port PORT", "Port (default: #{@options[:port]})") do |arg|
          @options[:port] = arg
        end
        opts.on("--status-uri PATH", "Path to XML output (default: #{@options[:status_uri]})") do |arg|
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

    def parse(xml_string)
      debug "Raw XML response: #{xml_string}"
      states = { :services => 0, :bad_status => [], :not_monitored => [] }
      doc = REXML::Document.new xml_string
      doc.elements.each("monit/service") do |serv|
        n = get_val(serv, "name")
        states[:services] += 1
        s = get_val(serv, "status")
        states[:bad_status] << n unless s == "0"
        m = get_val(serv, "monitor")
        states[:not_monitored] << n unless m == "1"
      end
      debug "Calculated states: #{states}"
      states
    end

    def get_val(node, attribute, default=nil)
      node.elements[attribute].nil? ? default : node.elements[attribute].text
    end

    def check_services
      params = @options[:excon].merge({ :path => @options[:status_uri],
                                        :headers => headers })
      debug "Will fetch: #{@options[:base_url]}:#{@options[:port]}/#{@options[:status_uri]}"

      result = init_state
      begin
        resp = Timeout::timeout@options[:timeout] do
          Excon.get("#{@options[:base_url]}:#{@options[:port]}", params)
        end
        result[:timeout] = false
        validate resp
        result = parse resp.body
      rescue Timeout::Error => e
      end
      return check_limits(result)
    end

    def check_limits(result)
      if result[:timeout]
        @stdout.puts "CRIT: Timeout after #{@options[:timeout]}"
        return EXIT_CRIT
      end
      msg = "(#{result[:services] - result[:bad_status].size - result[:not_monitored].size }=ok, #{result[:bad_status].size}=fail, #{result[:not_monitored].size}=not monitored)."
      msg = "#{msg}\nFailed: #{result[:bad_status].join(', ')}" unless result[:bad_status].empty?
      msg = "#{msg}\nNot monitored: #{result[:not_monitored].join(', ')}" unless result[:not_monitored].empty?
      if @options[:min] > result[:services]
        @stdout.puts "CRIT: due to number of services: only #{result[:services]} found #{msg}"
        return EXIT_CRIT
      end
      if result[:bad_status].size >= @options[:crit]
        @stdout.puts "CRIT: due to status #{msg}"
        return EXIT_CRIT
      end
      if result[:not_monitored].size >= @options[:crit_nm]
        @stdout.puts "CRIT: due to not monitored #{msg}"
        return EXIT_CRIT
      end
      if result[:bad_status].size >= @options[:warn]
        @stdout.puts "WARN: due to status #{msg}"
        return EXIT_WARN
      end
      if result[:not_monitored].size >= @options[:warn_nm]
        @stdout.puts "WARN: due to not monitored #{msg}"
        return EXIT_WARN
      end
      @stdout.puts "OK: #{msg}"
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
