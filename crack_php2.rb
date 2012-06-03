# authoer: hysios@gmail.com 

require 'cgi'
require 'pp'

def usage
	"""
USAGE: 

	crack_php src.php decode.php
	"""
end

class Context
	attr_accessor :operator, :left, :right, :last

	def initialize(*args)
		@context = []
		if args.length > 0
			operator_code = args.shift.to_sym
			@context.push operator_code, *args
		end
	end


	def push(value)
		@context.push value
	end

	def operator
		@context[0]
	end

	def left
		@context[1]
	end

	def left=(value)
		@context[1] = value
	end

	def right
		@context[2]
	end

	def right=(value)
		@context[2] = value
	end

	def last
		@context.last
	end

	def last=(value)
		@context.last = value
	end
end

class FuncContext < Context

end

class Crack
	SINGLE_OPERATOR_REG = /^[\!\-]/
		   BRACKETS_REG = /^\(/
			 ASSIGN_REG = /(\$*\w+)=(.+)/
		COMMA_CHAIN_REG = /(.+)\,/
	      MULTI_DIV_REG = /(.+)[*\/](.+)/
	     PLUS_MINUS_REG = /(.+)[\+\-](.+)/
	     	 CONCAT_REG = /(.+)\.(.+)/
	      URLENCODE_REG = /urldecode\(\'(.+)\'\)/
	  ASSIGN_CONCAT_REG = /(\$*\w+)\.=(.+)/
	ASSIGN_OPERATOR_REG = /(\$*\w+)[\.\+\-\*\\]=(.+)/
	  FUNCTION_CALL_REG = /(\$*\w+)\(/
	         NUMBER_REG = /^\d+$/
	       CONSTANT_REG = /^\w+$/
	         STRING_REG = /^\'(.+)\'$/
	      INDEX_EXP_REG = /(\$*\w+)\{(\d+)\}/
	       OPERATOR_REG = /^[\.\+\-\*\/]/
	            TAG_REG = /^[\(\)]/
	          COMMA_REG = /^\,/
	          SPLIT_REG = /^[\,\;\s\}\)]/

	attr_accessor :line

	def initialize(src, dst)
		@f = open(src, 'r')
		@content = @f.read
		@values = {}
		@line_stacks = []	
		@statements	= []
	end

	def crack
		raise 'This file format invalid.' unless check_symbol
		headcode = code_line(head_code)
		headcode.each do |_line|
			parse _line
		end
		pp @statements
	end

	def context
		if @current_context.nil?
			@statements.push Context.new
			@statements.last
		else
			@current_context
		end
	end

	def new_context(*args)
		@statements.push Context.new(*args)
		@current_context = @statements.last
	end

	def add_context(*args)
		new_context = Context.new(*args)
		context.right = new_context
		@current_context = new_context 
	end

	def push_context(value)
		@current_context.push(value)
	end

	def close_context
		@current_context = nil
	end

	def get_value(value)
		if value =~ NUMBER_REG
			value.to_i 
		elsif m = value.match(STRING_REG)
			m[1]
		else
			value
		end
	end

	def nested(tag, _line)
		nested_start = ["'", "\"", "(", "[", "{"]
		nested_over = ["'", "\"", ")", "]", "}"]

		founds = { "'" => 0,"\"" => 0, "(" => 0, "[" => 0, "{" => 0 }
		over_tag = nested_over[nested_start.index(tag)]

		i = 0
		prec = ''
		_line.chars do |c|
			
			if c == over_tag && prec == '\\' #ignore
				i += 1
				prec = c
				next
			end
			if c == over_tag && founds.values.reduce(:+) == 0
				break i
			end
		
			if nested_start.include?(c) 
			 	founds[c] += 1
 				prec = c

			elsif nested_over.include?(c)
				_c = nested_start[n = nested_over.index(c)]
				founds[_c] -= 1  
				prec = _c
			end
			i += 1
		end
		i
	end

	def line
		@line
	end

	def new_line(value)
		@line = value
		@line_start = 0
		@line_end = value.size - 1
	end

	def m 
		@m
	end

	def last
		line[@line_start..@line_end]
	end

	def set_line(s = nil, e = nil)
		@line_start = s unless s.nil?
		@line_end = e unless s.nil?
	end

	def line_push
		@line_stacks.push({
		       :line => @line,
		 :line_start => @line_start,
	       :line_end => @line_end,
			      :m => @m,
		})
	end

	def line_pop
		      store = @line_stacks.pop 
		      @line = store[:line]
		@line_start = store[:line_start]
		  @line_end = store[:line_end]
		         @m = store[:m]
	end

	def end_line

	end

	def match(regexp)
		if @m = last.match(regexp)
			@m_index = 0
			@line_start += @m.end(@m.size - 1)
		end
		not @m.nil?
	end

	def shift(index = nil)

		@m_index = index unless index.nil?
		@line_start = m.begin(@m_index)
		@line_end = m.end(@m_index)
		@m_index += 1
	end

	def test(regexp)
		last =~ regexp
	end

	def parse(_line = nil)
		new_line _line unless _line.nil?
		if last.nil? || last.strip == ""
			dump("END")
			close_context
			return
		elsif match(SINGLE_OPERATOR_REG)
			dump("SINGLE_OPERATOR")
			operator = m1
			add_context "^" + operator
			parse

		elsif test(NUMBER_REG) || test(STRING_REG) || test(CONSTANT_REG)
			dump("CONSTANT")
			context.right = get_value(last)
			close_context
			return
		elsif match(BRACKETS_REG)
			dump("BRACKETS")
			n = nested('(', last) + 1
			# left = last[0...n]
			# last = last[n..-1]
			line_push
			set_line(0, n - 1)
			add_context
			parse
			line_pop

			set_line(n)
			parse

		elsif match(COMMA_CHAIN_REG)
			dump("COMMA_CHAIN")
			line_push
			m.each do |section|
				push_context section
				shift
				parse
			end
			line_pop

		elsif match(MULTI_DIV_REG)
			dump("MULTI_DIV")
			left = m[1]
			operator = m[2]
			right = m[3]

			add_context(operator, left)
			parse_left

			add_context(operator, right)
			parse_right

		elsif match(PLUS_MINUS_REG)
			dump("PLUS_MINUS")
			left = m[1]
			operator = m[2]
			right = m[3]

			add_context(operator, left)
			parse_left

			add_context(operator, right)
			parse_right

		elsif match(CONCAT_REG)
			dump("CONCAT")
			left = m[1]
			operator = m[2]
			right = m[3]

			add_context(operator, left)
			parse_left

			add_context(operator, right)
			parse_right

		elsif match(OPERATOR_REG)
			dump("OPERATOR")
			left = m[1]
			operator = m[2]
			right = m[3]

			add_context(operator, left)
			parse_left

			add_context(operator, right)
			parse_right			

		elsif match(ASSIGN_REG)
			dump("ASSIGN")
			left = m[1]
			new_context '=', left
			shift 2
			parse

		elsif match(ASSIGN_OPERATOR_REG)
			dump("ASSIGN_OPERATOR")
			left = m[1]
			operator = m[2]
			new_context '=', left
			add_context operator, left
			shift 3
			parse 

		elsif match(FUNCTION_CALL_REG)
			dump("FUNCTION_CALL")
			name = m[1]
			puts line, name, last
			n = nested('(', last) + 1

			# right = args[0...n - 1]
			# last = args[n..-1]
			line_push
			add_context(name)
			set_line(nil, n - 1)
			parse
			line_pop

			line_push
			set_line(n + 1)
			parse
			line_pop
		else
			# pp @statements
			raise "invalid syntax #{line} ||| #{last}"
		end

	end

	def dump(msg)
		puts msg if debug
	end

	def debug 
		true
	end

	def parse_left
		line_push
		shift(1)
		parse
		line_pop
	end

	def parse_right
		line_push
		shfit[3]
		parse
		line_pop
	end

	def temp
		while true
			name = (0...8).map{65.+(rand(25)).chr}.join
			break unless @values.key?(name)
		end
		name
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