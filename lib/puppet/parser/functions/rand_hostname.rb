module Puppet::Parser::Functions
  newfunction(
    :rand_hostname,
    :type => :rvalue,
    :doc  => "Like fqdn_rand(), but instead 'randomly' updates the numeric suffix of a hostname."
  ) do |args|
    template, max, seed = *args

    if max.to_i <= 1
      template
    else
      index = function_fqdn_rand( [max.to_i - 1, seed] ).to_i + 1

      parts = template.split( "." )
      parts.first.sub!( /\d+$/, index.to_s )
      parts.join( "." )
    end
  end
end
