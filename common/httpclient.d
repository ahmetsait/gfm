module gfm.common.httpclient;

/// Couldn't resist the urge to write a HTTP client

// TODO: pool TCP connections

import std.socketstream,
       std.stream,
       std.socket,
       std.string,
       std.conv,
       std.stdio;

import gfm.common.uri;

class HTTPException : Exception
{
    public
    {
        this(string msg)
        {
            super(msg);
        }
    }
}

enum HTTPMethod
{
    OPTIONS,
    GET,
    HEAD,
    POST,
    PUT,
    DELETE,
    TRACE,
    CONNECT
}

class HTTPResponse
{
    int statusCode;
    string[string] headers;
    ubyte[] content;
}

class HTTPClient
{
    public
    {
        this()
        {
            buffer.length = 4096;
        }

        ~this()
        {
            close();
        }

        void close()
        {
            if (_socket !is null)
            {
                _socket.close();
                _socket = null;
            }
        }

        /// From an absolute HTTP url, return content.
        HTTPResponse GET(URI uri)
        {
            checkURI(uri);
            return request(HTTPMethod.GET, uri.hostName(), uri.port(), uri.toString());
        }

        /// same as GET but without content
        HTTPResponse HEAD(URI uri)
        {
            checkURI(uri);
            return request(HTTPMethod.HEAD, uri.hostName(), uri.port(), uri.toString());
        }

        /**
         * Perform a HTTP request.
         * requestURI can be "*", an absolute URI, an absolute path, or an authority
         * depending on the method.
         */
        HTTPResponse request(HTTPMethod method, string host, int port, string requestURI)
        {
            auto res = new HTTPResponse();

            try
            {
                connectTo(host, port);
                assert(_socket !is null);

                string request = format("%s %s HTTP/1.0\r\n"
                                        "Host: %s\r\n"
                                        "\r\n", to!string(method), requestURI, host);
                auto scope ss = new SocketStream(_socket);
                ss.writeString(request);

                // parse status line
                auto line = ss.readLine();
                if (line.length < 12 || line[0..5] != "HTTP/" || line[6] != '.')
                    throw new HTTPException("Cannot parse HTTP status line");

                if (line[5] != '1' || (line[7] != '0' && line[7] != '1'))
                    throw new HTTPException("Unsupported HTTP version");

                // parse error code
                res.statusCode = 0;
                for (int i = 0; i < 3; ++i)
                {
                    char c = line[9 + i];
                    if (c >= '0' && c <= '9')
                        res.statusCode = res.statusCode * 10 + (c - '0');
                    else
                        throw new HTTPException("Expected digit in HTTP status code");
                }

                // parse headers
                while(true)
                {
                    auto headerLine = ss.readLine();

                    if (headerLine.length == 0)
                        break;

                    sizediff_t colonIdx = indexOf(headerLine, ':');
                    if (colonIdx == -1)
                        throw new HTTPException("Cannot parse HTTP header: missing colon");

                    string key = headerLine[0..colonIdx].idup;

                    // trim leading spaces and tabs
                    sizediff_t valueStart = colonIdx + 1;
                    for ( ; valueStart <= headerLine.length; ++valueStart)
                    {
                        char c = headerLine[valueStart];
                        if (c != ' ' && c != '\t')
                            break;
                    }

                    // trim trailing spaces and tabs
                    sizediff_t valueEnd = headerLine.length;
                    for ( ; valueEnd > valueStart; --valueEnd)
                    {
                        char c = headerLine[valueEnd - 1];
                        if (c != ' ' && c != '\t')
                            break;
                    }

                    string value = headerLine[valueStart..valueEnd].idup;
                    res.headers[key] = value;
                }

                while (!ss.eof())
                {
                    int read = ss.readBlock(buffer.ptr, buffer.length);
                    res.content ~= buffer[0..read];
                }

                return res;
            }
            catch (Exception e)
            {
                throw new HTTPException(e.msg);
            }
        }
    }

    private
    {
        TcpSocket _socket;
        ubyte[] buffer;

        void connectTo(string host, int port)
        {
            if (_socket !is null)
            {
                _socket.close();
                _socket = null;
            }
            ushort uport = cast(ushort) port;
            _socket = new TcpSocket(new InternetAddress(host, uport));
        }

        static checkURI(URI uri)
        {
            if (uri.scheme() != "http")
                throw new HTTPException(format("'%' is not an HTTP absolute url", uri.toString()));
        }
    }
}

