# frozen_string_literal: true

require 'rack'
require 'prometheus/client/rack/collector'
require 'prometheus/client/rack/exporter'

module Yabeda
  module Prometheus
    module Mmap
      # Rack application or middleware that provides metrics exposition endpoint
      class Exporter < ::Prometheus::Client::Rack::Exporter
        NOT_FOUND_HANDLER = lambda do |_env|
          [404, { 'Content-Type' => 'text/plain' }, ["Not Found\n"]]
        end.freeze

        class << self
          # Allows to use middleware as standalone rack application
          def call(env)
            @app ||= new(NOT_FOUND_HANDLER, path: '/')
            @app.call(env)
          end

          def start_metrics_server!
            Thread.new do
              default_port = ENV.fetch('PORT', 9394)

              rack_handler.run(
                rack_app,
                Host: ENV['PROMETHEUS_EXPORTER_BIND'] || '0.0.0.0',
                Port: ENV.fetch('PROMETHEUS_EXPORTER_PORT', default_port),
                AccessLog: []
              )
            end
          end

          def rack_handler
            if Gem.loaded_specs['rack']&.version&.>= Gem::Version.new('3.0')
              require 'rackup'
              ::Rackup::Handler::WEBrick
            else
              ::Rack::Handler::WEBrick
            end
          rescue LoadError
            warn 'Please add gems rackup and webrick to your Gemfile to expose Yabeda metrics from prometheus-mmap'
            ::Rack::Handler::WEBrick
          end

          def rack_app(exporter = self, path: '/metrics')
            ::Rack::Builder.new do
              use ::Rack::CommonLogger if ENV['PROMETHEUS_EXPORTER_LOG_REQUESTS'] != 'false'
              use ::Rack::ShowExceptions
              use exporter, path: path
              run NOT_FOUND_HANDLER
            end
          end
        end

        def initialize(app, options = {})
          super(app, options.merge(registry: Yabeda::Prometheus::Mmap.registry))
        end

        def call(env)
          ::Yabeda.collect! if env['PATH_INFO'] == path

          if ::Yabeda.debug?
            result = nil
            ::Yabeda.yabeda_prometheus_mmap.render_duration.measure({}) do
              result = super
            end
            result
          else
            super
          end
        end
      end
    end
  end
end
