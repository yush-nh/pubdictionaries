#!/usr/bin/env ruby

require 'json'
require 'rest_client'


# Get a list of IDs for each term.
#
# * (string)  url              - The URL generated from the "Get Mapper URL" menu.
# * (string)  email            - User's login ID.
# * (string)  password         - User's login password.
# * (array)   terms            - An array of term string for mapping.
#
def get_idlists(url, email, password, terms)
  # 1. Initialize the options hash.
  options = {
    :headers => {
      :content_type => :json,
      :accept       => :json,
    },
    :user         => email,
    :password     => password, 
    :timeout      => 9999, 
    :open_timeout => 9999,
  }

  # 2. Create a rest client resource.
  resource = RestClient::Resource.new  url, options

  # 3. Retrieve the list of IDs.
  data = resource.post(:terms => terms.to_json) do |response, request, result|
    case response.code
    when 200
      JSON.parse(response.body)
    else
      $stdout.puts "Error code: #{response.code}"
    end
  end

  return data
end


# Test code.
#
# * ARGV[0]  -  User's email.
# * ARGV[1]  -  User's password.
# * ARGV[2]  -  URL including a REST-API URL & dictionaries.
#
if __FILE__ == $0
  if ARGV.size != 3
    $stdout.puts "Usage:  #{$0}  Email  Password  URL"
    exit
  end

  # 1. Prepare necessary information.
  email          = ARGV[0]
  password       = ARGV[1]
  url            = ARGV[2]
  example_terms  = [ "NF-kappa B", "C-REL", "c-rel", "Brox", "this_term_does_not_exist", "kabuki syndrome"]
  
  # 2. Retrieve a ID list for each term.
  results = get_idlists(url, email, password, example_terms)
  
  # 3. Print the mapping results.
  $stdout.puts "Output:"
  $stdout.puts "   %-20s | %s" % ["TERM", "Mapped IDs"]    
  results.each_pair do |term, ids|
    $stdout.puts "   %-20s | %s" % [term, ids.inspect]
  end

end


