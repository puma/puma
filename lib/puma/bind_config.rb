# frozen_string_literal: true

require 'puma/util'

module Puma
  class BindConfig
    CERT_OBJECT_KEYS = ['cert_pem', 'key_pem']

    # Builds a BindConfig object from a URI
    def self.parse(p_uri)
      uri = URI.parse(p_uri)
      _host = p_uri.start_with?('unix://@') ? "@#{uri.host}" : uri.host
      new(
        scheme: uri.scheme,
        host: _host,
        port: uri.port,
        path: uri.path,
        query: uri.query,
        params: Util.parse_query(uri.query)
      )
    end

    attr_reader :scheme, :host, :port, :path, :params

    def initialize(scheme: , host: , port: , path: nil, query: nil, params: {})
      @scheme = scheme
      @host = host
      @port = port
      @path = path
      @query = query
      @params = params
    end

    def query
      @query ||=
        begin
          # Don't add cert and key objects in the query params
          query_params = @params.reject { |k, _v| CERT_OBJECT_KEYS.include?(k) }

          # To properly handle file descriptors logic for binder, we need to
          # uniquely identify BindConfig as URI using cert and key object details.
          query_params['cert_pem_hash'] = @params['cert_pem'].hash if @params['cert_pem']
          query_params['key_pem_hash']  = @params['key_pem'].hash if @params['key_pem']
          query_params.empty? ? nil : query_params.sort.map { |k, v| "#{k}=#{v}"}.join('&')
        end
    end

    def uri
      @uri ||=
        if scheme == 'unix'
          "unix://#{host}#{path}"
        else
          URI::Generic.build(scheme: scheme, host: host, port: port, path: path, query: query).to_s
        end
    end
  end
end
