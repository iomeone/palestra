#!/usr/bin/env ruby

require 'pp'

module TestOracle
  puts "start #{self}"
  require './oracle_analyser'
  code = IO.read('test-cases/msg_delay.utf8.sql')
  ast = Oracle::parse(code)
  pp ast.to_tree

  #pp Oracle::analyse(code)
end
