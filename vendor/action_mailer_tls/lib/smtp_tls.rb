require "openssl"
require "net/smtp"

Net::SMTP.class_eval do
  private
  
  def ruby_post_1_8_6?
    ruby_major, ruby_minor, ruby_teeny = *RUBY_VERSION.split(".").map {|str| str.to_i}
    ruby_minor >= 9 ||( [ruby_major, ruby_minor] == [1, 8] && ruby_teeny > 6)
  end
    
  def do_start(helodomain, user, secret, authtype)
    raise IOError, 'SMTP session already started' if @started
    if user or secret
      if ruby_post_1_8_6?
        check_auth_args user, secret
      else
        check_auth_args user, secret, authtype
      end
    end

    sock = timeout(@open_timeout) { TCPSocket.open(@address, @port) }
    @socket = Net::InternetMessageIO.new(sock)
    @socket.read_timeout = 60 #@read_timeout

    check_response(critical { recv_response() })
    do_helo(helodomain)

    if starttls
      raise 'openssl library not installed' unless defined?(OpenSSL)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.sync_close = true
      ssl.connect
      @socket = Net::InternetMessageIO.new(ssl)
      @socket.read_timeout = 60 #@read_timeout
      do_helo(helodomain)
    end

    authenticate user, secret, authtype if user
    @started = true
  ensure
    unless @started
      # authentication failed, cancel connection.
      @socket.close if not @started and @socket and not @socket.closed?
      @socket = nil
    end
  end

  def do_helo(helodomain)
    begin
      if @esmtp
        ehlo helodomain
      else
        helo helodomain
      end
    rescue Net::ProtocolError
      if @esmtp
        @esmtp = false
        @error_occured = false
        retry
      end
      raise
    end
  end

  def starttls
    getok('STARTTLS') rescue return false
    return true
  end

  def quit
    begin
      getok('QUIT')
    rescue EOFError
    end
  end
end