require "uri"
require "cgi"

module URI
  class << self
    def unescape(str)
      CGI.unescape(str)
    end
  end
end
