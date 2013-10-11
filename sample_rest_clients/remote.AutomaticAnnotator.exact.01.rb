#!/usr/bin/env ruby

require 'json'
require 'rest_client'


# Prepare data and option objects

#text = "Negative regulation of human immunodeficiency virus type 1 expression in monocytes: role of the 65-kDa plus 50-kDa NF-kappa B dimer.
#Although monocytic cells can provide a reservoir for viral production in vivo, their regulation of human immunodeficiency virus type 1 (HIV-1) transcription can be either latent, restricted, or productive. These differences in gene expression have not been molecularly defined. In THP-1 cells with restricted HIV expression, there is an absence of DNA-protein binding complex formation with the HIV-1 promoter-enhancer associated with markedly less viral RNA production. This absence of binding was localized to the NF-kappa B region of the HIV-1 enhancer; the 65-kDa plus 50-kDa NF-kappa B heterodimer was preferentially lost. Adding purified NF-kappa B protein to nuclear extracts from cells with restricted expression overcomes this lack of binding. In addition, treatment of these nuclear extracts with sodium deoxycholate restored their ability to form the heterodimer, suggesting the presence of an inhibitor of NF-kappa B activity. Furthermore, treatment of nuclear extracts from these cells that had restricted expression with lipopolysaccharide increased viral production and NF-kappa B activity. Antiserum specific for NF-kappa B binding proteins, but not c-rel-specific antiserum, disrupted heterodimer complex formation. Thus, both NF-kappa B-binding complexes are needed for optimal viral transcription. Binding of the 65-kDa plus 50-kDa heterodimer to the HIV-1 enhancer can be negatively regulated in monocytes, providing one mechanism restricting HIV-1 gene expression."

text = "This is a sample text. ABCA1 is related to alpha 1 b glycoprotein."

json_data = JSON.generate( { 
	"text"      => text,
	} )

json_options = JSON.generate( { 
	"dictionary_name" => "100 samples",
	"user_name"       => "priancho@gmail.com",     # Use the user dictionary correspoding to this user name
	"top_n"           => 3,
#   "password"        => "",     # How to implement authentication with Devise's User model? See Warden with Sinatra
#	"threshold"       => 0.60,
#	"min_tokens"      => 1,
#	"max_tokens"      => 5,

### Automatically identified by the options used to create a dictionary
#	"case_insensitive_search" => true,
#	"replace_hyphen" => true,
#	"stemming" => true,
	} )


# Prepare connection to a web service
server  = "pubdictionaries.dbcls.jp"
service = "rest_api/annotate_text/exact_string_matching/"

resource = RestClient::Resource.new( 
	"#{server}/#{service}",
	:timeout => 300, 
	:open_timeout => 300 )

# Send the request and get the results
response = resource.post( :annotation   => json_data,
                          :options      => json_options, 
                          :content_type => :json,
                          :accept       => :json )

# Output the results
puts "Input text: #{text}" 
puts 

puts response.code
puts

JSON.parse(response)["denotations"].each do |item|
	puts "ann: #{item.inspect}"
end


