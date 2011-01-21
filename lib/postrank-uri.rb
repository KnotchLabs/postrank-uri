# -*- encoding: utf-8 -*-

require 'addressable/uri'
require 'domainatrix'
require 'yaml'

module PostRank
  module URI

    c18ndb = YAML.load_file(File.dirname(__FILE__) + '/postrank-uri/c18n.yml')

    C18N = {}
    C18N[:global] = c18ndb[:all].freeze
    C18N[:hosts]  = c18ndb[:hosts].inject({}) {|h,(k,v)| h[/#{Regexp.escape(k)}$/.freeze] = v; h}

    URIREGEX = {}
    URIREGEX[:protocol] = /https?:\/\//i
    URIREGEX[:valid_preceding_chars] = /(?:|\.|[^-\/"':!=A-Z0-9_@＠]|^|\:)/i
    URIREGEX[:valid_domain] = /(?:[^[:punct:]\s][\.-](?=[^[:punct:]\s])|[^[:punct:]\s]){1,}\.[a-z]{2,}(?::[0-9]+)?/i
    URIREGEX[:valid_general_url_path_chars] = /[a-z0-9!\*';:=\+\,\$\/%#\[\]\-_~]/i

    # Allow URL paths to contain balanced parens
    #  1. Used in Wikipedia URLs like /Primer_(film)
    #  2. Used in IIS sessions like /S(dfd346)/
    URIREGEX[:wikipedia_disambiguation] = /(?:\(#{URIREGEX[:valid_general_url_path_chars]}+\))/i

    # Allow @ in a url, but only in the middle. Catch things like http://example.com/@user
    URIREGEX[:valid_url_path_chars] = /(?:
      #{URIREGEX[:wikipedia_disambiguation]}|
      @#{URIREGEX[:valid_general_url_path_chars]}+\/|
      [\.,]#{URIREGEX[:valid_general_url_path_chars]}+|
      #{URIREGEX[:valid_general_url_path_chars]}+
    )/ix

    # Valid end-of-path chracters (so /foo. does not gobble the period).
    #   1. Allow =&# for empty URL parameters and other URL-join artifacts
    URIREGEX[:valid_url_path_ending_chars] = /[a-z0-9=_#\/\+\-]|#{URIREGEX[:wikipedia_disambiguation]}/io
    URIREGEX[:valid_url_query_chars] = /[a-z0-9!\*'\(\);:&=\+\$\/%#\[\]\-_\.,~]/i
    URIREGEX[:valid_url_query_ending_chars] = /[a-z0-9_&=#\/]/i

    URIREGEX[:valid_url] = %r{
          (                                               #   $1 total match
            (#{URIREGEX[:valid_preceding_chars]})         #   $2 Preceeding chracter
            (                                             #   $3 URL
              (https?:\/\/)?                              #   $4 Protocol
              (#{URIREGEX[:valid_domain]})                #   $5 Domain(s) and optional post number
              (/
                (?:
                  # 1+ path chars and a valid last char
                  #{URIREGEX[:valid_url_path_chars]}+#{URIREGEX[:valid_url_path_ending_chars]}|
                  # Optional last char to handle /@foo/ case
                  #{URIREGEX[:valid_url_path_chars]}+#{URIREGEX[:valid_url_path_ending_chars]}?|
                  # Just a # case
                  #{URIREGEX[:valid_url_path_ending_chars]}
                )?
              )?                                          #   $6 URL Path and anchor
              # $7 Query String
              (\?#{URIREGEX[:valid_url_query_chars]}*#{URIREGEX[:valid_url_query_ending_chars]})?
            )
          )
        }iox;

    URIREGEX[:escape]   = /([^ a-zA-Z0-9_.-]+)/x
    URIREGEX[:unescape] = /((?:%[0-9a-fA-F]{2})+)/x
    URIREGEX.each_pair{|k,v| v.freeze }

    def self.extract(text)
      return [] if !text
      urls = []
      text.to_s.scan(URIREGEX[:valid_url]) do |all, before, url, protocol, domain, path, query|
        begin
          url = clean(url).to_s
          Domainatrix.parse(url)
          urls.push url
        rescue NoMethodError
        end
      end

      urls.compact
    end

    def self.escape(uri)
      uri.gsub(URIREGEX[:escape]) do
        '%' + $1.unpack('H2' * $1.size).join('%').upcase
      end.gsub(' ','%20')
    end

    def self.unescape(uri)
      uri.tr('+', ' ').gsub(URIREGEX[:unescape]) do
        [$1.delete('%')].pack('H*')
      end
    end

    def self.clean(uri)
      normalize(c18n(unescape(uri))).to_s
    end

    def self.normalize(uri)
      u = parse(uri)
      u.path = u.path.squeeze('/')
      u.query = nil if u.query && u.query.empty?
      u.fragment = nil
      u
    end

    def self.c18n(uri)
      u = parse(uri)

      if q = u.query_values(:notation => :flat_array)
        q.delete_if { |k,v| C18N[:global].include?(k) }
        q.delete_if { |k,v| C18N[:hosts].find {|r,p| u.host =~ r && p.include?(k) } }
      end

      u.query_values = q
      u
    end

    def self.parse(uri)
      return uri if uri.is_a? Addressable::URI

      uri = uri.index(URIREGEX[:protocol]) == 0 ? uri : "http://#{uri}"
      Addressable::URI.parse(uri).normalize
    end

  end
end