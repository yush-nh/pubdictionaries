#!/usr/bin/env ruby

require 'json'
require 'rest_client'


# Annotate the text by using the base dictionary and the associated user dictionary.
#
# * (string)  uri           - The URI of the sign in route. It involves a dictionary name.
#                             (e.g., http://localhost/dictionaries/EntrezGene%20-%20Homo%20Sapiens/text_annotation?matching_method=approximate&max_tokens=6&min_tokens=1&threshold=0.6&top_n=10)
# * (string)  email         - User's login ID.
# * (string)  password      - User's login password.
# * (hash)    annotation    - The hash including text for annotation.
#
def annotate_text(uri, email, password, annotation)
	# Prepare the connection to the text annotation service.
	resource = RestClient::Resource.new( 
		"#{uri}",
		:timeout      => 300, 
		:open_timeout => 300,
		)

	# Annotate the text.
	data = resource.post( 
		:user         => {email:email, password:password},
		:annotation   => annotation.to_json,
		:content_type => :json,
		:accept       => :json,
	) do |response, request, result|
		case response.code
		when 200
			JSON.parse(response.body)
		else
			$stdout.puts "Error code: #{response.code}"
			annotation
		end
	end
	
	return data
end


# Text code.
#
# * ARGV[0]   -  User's email.
# * ARGV[1]   -  User's password.
# * ARGV[2]   -  URI
# * ARGV[3-n] -  Dictionaries
# 
if __FILE__ == $0	
	if ARGV.size != 3
		$stdout.puts "Usage:  #{$0}  Email  Password  URI"
		exit
	end
	email      = ARGV[0]
	password   = ARGV[1]
	uri        = ARGV[2]
	annotation = { "text"=>"Negative regulation of human immunodeficiency virus type 1 expression in monocytes: role of the 65-kDa plus 50-kDa NF-kappa B dimer.\nAlthough monocytic cells can provide a reservoir for viral production in vivo, their regulation of human immunodeficiency virus type 1 (HIV-1) transcription can be either latent, restricted, or productive. These differences in gene expression have not been molecularly defined. In THP-1 cells with restricted HIV expression, there is an absence of DNA-protein binding complex formation with the HIV-1 promoter-enhancer associated with markedly less viral RNA production. This absence of binding was localized to the NF-kappa B region of the HIV-1 enhancer; the 65-kDa plus 50-kDa NF-kappa B heterodimer was preferentially lost. Adding purified NF-kappa B protein to nuclear extracts from cells with restricted expression overcomes this lack of binding. In addition, treatment of these nuclear extracts with sodium deoxycholate restored their ability to form the heterodimer, suggesting the presence of an inhibitor of NF-kappa B activity. Furthermore, treatment of nuclear extracts from these cells that had restricted expression with lipopolysaccharide increased viral production and NF-kappa B activity. Antiserum specific for NF-kappa B binding proteins, but not c-rel-specific antiserum, disrupted heterodimer complex formation. Thus, both NF-kappa B-binding complexes are needed for optimal viral transcription. Binding of the 65-kDa plus 50-kDa heterodimer to the HIV-1 enhancer can be negatively regulated in monocytes, providing one mechanism restricting HIV-1 gene expression."}
	
	# Annotate the text.
	result = annotate_text(uri, email, password, annotation)
	
	$stdout.puts "Input:"
	$stdout.puts result["text"].inspect
	
	$stdout.puts "Output:"
	if result.has_key? "error"
		$stdout.puts "   Error: #{result["error"]["message"]}"
	end
	if result.has_key? "denotations"
		result["denotations"].each do |entry|
			$stdout.puts "   #{entry.inspect} - matched string in the text: \"#{annotation["text"][entry["begin"]...entry["end"]]}\""
		end
	end
	$stdout.puts

end
