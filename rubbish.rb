#!/usr/bin/env ruby

require_relative 'builtin.rb'
require_relative 'env.rb'
require_relative 'job.rb'
require_relative 'script.rb'
require_relative 'shell.rb'
require_relative 'util.rb'

$shell = 'rubbish'

signal_init
job_init

repl
