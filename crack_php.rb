# encoding : utf-8
require 'cgi'
require 'pp'

def usage
	"""
USAGE: 

	crack_php src.php decode.php
	"""
end

class Crack
	attr_accessor :command_line
	ASSIGN_REG = /(\$?\w+)=(.+)/
	URLENCODE_REG = /urldecode\(\'(.+)\'\)/
	ASSIGN_CONCAT_REG = /(\$?\w+)\.=(.+)/
	FUNCTION_CALL_REG = /\$(\w+)\(/
	NUMBER_REG = /^\d+$/
	CONSTANT_REG = /^\w+$/
	STRING_REG = /^\'(.+)\'$/
	INDEX_EXP_REG = /(\$?\w+)\{(\d+)\}/
	OPERATOR_REG = /^[\.\+\-\*\/]/
	TAG_REG = /^[\(\)]/
	COMMA_REG = /^\,/
	EVAL_REG = /^$$(\w+)/
	SPLIT_REG = /^[\,\;\s\}\)]/

	def initialize(src, dst)
		@f = open(src, 'r')
		@content = @f.read
		@values = {}
		@stack = []
	end
	
	def command_line
		@values['command_line']
	end

	def command_line=(value)
		@values['command_line'] = value
	end

	def crack
		raise 'This file format invalid.' unless check_symbol
		headcode = code_line(head_code)
		headcode.each do |line|
			parse_line line
		end
		pp headcode
	end

	ASSIGN = lambda { |x| @values[@stack.pop] = x }
	ADD = lambda { |x| @values[@stack.pop] + x }

	def parse_line(line, left = nil, operator = '')
		dump "line: #{line}, left: #{left}, operator: #{operator}"
		if m = line.match(ASSIGN_REG)
			dump 'ASSIGN_REG'
			key = m[1]
			value = m[2]
			if value =~ STRING_REG || value =~ CONSTANT_REG || value =~ NUMBER_REG
				@values[key] = value
			else
				@values[key] = nil
				parse_line(value, key, '=')
			end
		elsif m = line.match(ASSIGN_CONCAT_REG)
			dump 'ASSIGN_CONCAT_REG'
			key = m[1]
			value = m[2]
			if value =~ STRING_REG || value =~ CONSTANT_REG || value =~ NUMBER_REG
				@values[key] += value
			else
				parse_line(value, key, '.')
			end
		elsif m = line.match(URLENCODE_REG)
			dump 'URLENCODE_REG'
			@values[left] = CGI::unescape(m[1])
		elsif m = line.match(OPERATOR_REG)
			dump 'OPERATOR_REG'
			parse_line(m.post_match, left, '.')	if m[0] == '.' 
		elsif m = line.match(INDEX_EXP_REG) 
			dump "INDEX_EXP_REG"
			origin = m[1]
			index = m[2].to_i

			string = @values[origin]
			char = string[index]

			if operator == '.'
				if m.post_match.chomp == ""
					@values[left] += char
				else
					@values[left] += char
					parse_line(m.post_match, left)
				end
			elsif operator == '='
				@values[left] = char
				parse_line(m.post_match, left) unless m.post_match.chomp == ""
			end
		elsif m = line.match(FUNCTION_CALL_REG)
			raise 'Does not match parentheses' unless find_end_tag(m.post_match)
			name = m[1]
			parse_args(m.post_match, name)
		end
	end

	def parse_args(line, name)
		if m = line.match(TAG_REG)
			arg = m.post_match[0..find_func_tag(m.post_match)]
			parse_args(arg, name)
		elsif line =~ STRING_REG || line =~ CONSTANT_REG || line =~ NUMBER_REG
		elsif multi_args(line)
		end
	end

	def multi_args(line)
		args = line.split(',')
		args.each do |arg|
			if arg =~ STRING_REG || arg =~ CONSTANT_REG || arg =~ NUMBER_REG
						
		end
	end

	def is_exp?(line)
		if line =~ STRING_REG || line =~ CONSTANT_REG || line =~ NUMBER_REG
			|| is_func?(line)  || line =~ EVAL_REG || is_compute?(line)

	end

	def is_compute?(line)
		
	end

	def is_func?(line)
		if m = line.match(FUNCTION_CALL_REG)
			l = m.post_match.sub(find_func_tag(m.post_match), "")
			return l =~ SPLIT_REG
		end
		false
	end

	def get_func(line)
		if m = line.match(FUNCTION_CALL_REG)
			l = m.post_match.sub(find_func_tag(m.post_match), "")
			return l =~ SPLIT_REG
		end
		false		
	end

	def nested(tag, line)
		nested_start = ["'", "\"", "(", "[", "{"]
		nested_over = ["'", "\"", ")", "]", "}"]

		founds = { "'" => 0,"\"" => 0, "(" => 0, "[" => 0, "{" => 0 }
		over_tag = nested_over[nested_start.index(tag)]

		i = 0
		prec = ''
		line.chars do |c|
			if c == over_tag && prec == '\\' #ignore
				i += 1
				prec = c
				next
			end
			if c == over_tag && founds.values.reduce(:+) == 0
				break i
			end
			founds[c] += 1 if nested_start.has_key?(c) 
			founds[c] -= 1 if nested_over.has_key?(c) 
			prec = c
			i += 1
		end
		i
	end


	def find_func_tag(line)
		n = nested('(', line)
		line[0..n]
	end

	def find_end_tag(line)
		@tags ||= []
		s = 0
		line.chars do |c|
			s += 1 if c == '('
			s -= 1 if c == ')'
		end
		s == -1
	end

	def call_func(method, *args)

	end

	def debug 
		false
	end

	def dump(msg)
		puts msg if debug
	end

	def check_symbol
		@content[0..24] == '<?php // Web kernel file.'
	end

	def head_code
		@content[25...@content.index('?>')]
	end

	def code_line(code)
		code.split(";")
	end

end

if ARGV.length < 1
	puts usage
	exit(1)
end

dst = "crack_#{File.basename(ARGV[0])}.php"
cr = Crack.new(ARGV[0], ARGV[1] || dst)
cr.crack

