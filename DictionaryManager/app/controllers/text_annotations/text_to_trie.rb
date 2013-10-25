#!/usr/bin/env ruby
# encoding: UTF-8
Encoding.default_external="UTF-8"
Encoding.default_internal="UTF-8"

=begin

=end

require 'set'
require 'stemmify'
require 'triez'


class TEXT_TO_TRIE
	# Initialize a retriever instance
	def initialize( min_tokens, max_tokens )
		@min_tokens = min_tokens
		@max_tokens = max_tokens

		@STOP_WORDS = Set.new [
			'this', 'that', 'these', 'those',
			'plus', 'minus',
			'one', 'two', 'three',
			'and', 'or', 'but', 'as',
			'at', 'by', 'from', 'to', 'in', 'of', 'with', 'for',
			'an', 'the', 'not', 'no',
			'can', 'has', 'have', 'had', 'am', 'are', 'is', 'was', 'were', 'do', 'does' 'did',
			'we',
			'blocked', 'regulated', 'transformed',
			'clear', 'early', 'essential', 'functional', 'high', 'multiple', 'little', 'partial', 'unclear', 
			'cytosolic', 'secreting', 'function', 'per', 'se', 'set', 'line', 'lines', 'run',
			'activator', 'binding', 'bp', 'cell', 'dna', 'factor', 'factors', 'mitochondria', 
			'mitochondrial', 'mrna', 'rna',
			'metabolite', 'reduced', 'regulation', 'regulatory', 'replication',
			'enzyme', 'fragment', 'fragments', 'membrane', 'type', 'dna binding', 'fold', 'receptor',
		]
	end

	# convert a text into a trie	
	def to_trie( text, bCaseInsensitive, bReplaceHyphen, bStemming )
		trie    = Triez.new value_type: :object, default: []

		offsets = tokenize( text )

		(@min_tokens..@max_tokens).each do |ss_len|
			(0..offsets.length-ss_len).each do |beg|              # Nothing happens when tokens.length-ss_len < 0
				# get a query string
				beg_tidx = beg
				end_tidx = beg+ss_len
				q = text[offsets[beg_tidx][:begin]...offsets[end_tidx-1][:end]]
				
				# pass this query if it is a stopword
				next if stopwords?( q )

				# stem a token sequence 
				if bStemming == true
					q = stem_it( text, offsets, beg_tidx, end_tidx )
				end

				# apply string normalization
				if bCaseInsensitive == true
					q.downcase!
				end
				if bReplaceHyphen == true
					q.gsub!("-", " ")
				end

				# record the beginning and end offsets
				if trie.has_key?( q )
					value = trie[q]
				else
					value = [ ]
				end
				value.push( offsets[beg_tidx][:begin]...offsets[end_tidx-1][:end] )

				trie[q] = value
			end
		end
	
		# 2. make a list of pairs of a query string and the offsets where the query string appears in the text
		queries_with_offsets = { }
		trie.each do |query, offsets|
			queries_with_offsets[ query ] = offsets
		end

		# $stdout.puts "The number of unique queries: #{trie.size}"

		return queries_with_offsets
	end

	def tokenize( text )
		# 1. tokenize an input text
		tokens = text.split(/\s|(\W|_)/).reject { |t| t.empty? }   # does not match unicode, check \p{word}
	
		# 2. find the index of each token
		token_indices = [ ]
		abs_pos = 0
		tokens.each do |t|
			cur_pos = text.index( t, abs_pos )
			token_indices << {:begin=>cur_pos, :end=>cur_pos + t.length}
			abs_pos = cur_pos + t.length 
		end

		return token_indices
	end
	
	def stopwords?( query )
		if @STOP_WORDS.include?(query.downcase) or
		   query.length <= 1 or                       # a one character string is a stop word
		   query.downcase.start_with?('the ', 'a ', 'an ') or
		   query.start_with?('-', '(', ')', ',', '.') or
		   query.end_with?('-', '(', ')', ',', '.') or
		   /^[\d.]+$/.match( query ) or               # a numeric string is a stop word or
		   /^\d[a-zA-Z]$/.match( query )
			return true
		else
			return false
		end
	end

	def stem_it( text, offsets, beg_tidx, end_tidx )
		query = ""

		(beg_tidx...end_tidx).each do |tidx|
			# attach a string between two previous and current tokens
			if tidx > beg_tidx
				query += text[offsets[tidx-1][:end]...offsets[tidx][:begin]]
			end

			# attach a stem
			query += text[offsets[tidx][:begin]...offsets[tidx][:end]].stem
		end

		return query
	end


end


if __FILE__ == $0
	puts "This is not a stand-alone program."

end
