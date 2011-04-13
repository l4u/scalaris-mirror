#!/usr/bin/ruby
# Copyright 2008-2011 Zuse Institute Berlin
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

require 'rubygems'
require 'json'
require 'net/http'
require 'benchmark'
require 'optparse'
require 'pp'
require 'scalaris'

$url = 'http://localhost:8000/jsonrpc.yaws'

def write(key_value_list)
  key, value = key_value_list
  Scalaris::write(key, value)
end

options = {}

optparse = OptionParser.new do |opts|
  options[:read] = nil
  opts.on('-r', '--read KEY', 'read key KEY' ) do |key|
    options[:read] = key
  end

  options[:read] = nil
  opts.on('-w', '--write KEY,VALUE', Array, 'write key KEY to VALUE' ) do |list|
    raise OptionParser::InvalidOption.new(list) unless list.size == 2
    options[:write] = list
  end

  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end

begin
  optparse.parse!
rescue OptionParser::ParseError
  $stderr.print "Error: " + $! + "\n"
  exit
end

pp Scalaris::read(options[:read]) unless options[:read] == nil
pp write(options[:write]) unless options[:write] == nil
