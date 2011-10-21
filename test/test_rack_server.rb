require 'test/unit'
require 'puma'
require 'rack/lint'
require 'test/testhelp'

class TestRackServer < Test::Unit::TestCase

  class ErrorChecker
    def initialize(app)
      @app = app
      @exception = nil
      @env = nil
    end

    attr_reader :exception, :env

    def call(env)
      begin
        @env = env
        return @app.call(env)
      rescue Exception => e
        @exception = e

        [
          500,
          { "X-Exception" => e.message, "X-Exception-Class" => e.class.to_s },
          ["Error detected"]
        ]
      end
    end
  end

  class ServerLint < Rack::Lint
    def call(env)
      assert("No env given") { env }
      check_env env

      @app.call(env)
    end
  end

  def setup
    @valid_request = "GET / HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\n\r\n"
    
    @simple = lambda { |env| [200, { "X-Header" => "Works" }, ["Hello"]] }
    @server = Puma::Server.new @simple
    @server.add_tcp_listener "127.0.0.1", 9998
  end

  def teardown
    @server.stop(true)
  end

  def test_lint
    @checker = ErrorChecker.new ServerLint.new(@simple)
    @server.app = @checker

    @server.run

    hit(['http://localhost:9998/test'])

    if exc = @checker.exception
      raise exc
    end
  end

  def test_path_info
    input = nil
    @server.app = lambda { |env| input = env; @simple.call(env) }
    @server.run

    hit(['http://localhost:9998/test/a/b/c'])

    assert_equal "/test/a/b/c", input['PATH_INFO']
  end

  def test_after_reply
    closed = false

    @server.app = lambda do |env|
      env['rack.after_reply'] << lambda { closed = true }
      @simple.call(env)
    end

    @server.run

    hit(['http://localhost:9998/test'])

    assert_equal true, closed
  end
end