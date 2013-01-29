-module(webserver_utils).

-compile(export_all).

-define(DEFAULT_STRING, "Great success!").
-define(LONG_BODY_PART,
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "

        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
        "This is a relatively long body, that we send to the client... "
    ).

default_string() ->
    ?DEFAULT_STRING.

long_body_part() ->
    ?LONG_BODY_PART.

long_body_part(Size) ->
    list_to_binary(
      lists:foldl(
	fun(_, Acc) ->
		Acc ++ " " ++ webserver_utils:long_body_part()
	end, webserver_utils:long_body_part(), lists:seq(1, Size))).

%%% Responders
simple_response(Module, Socket, _Request, _Headers, Body) ->
    Module:send(
        Socket,
        [
            "HTTP/1.1 200 OK\r\n"
            "Content-type: text/plain\r\nContent-length: 14\r\n"
            "X-Test-Orig-Body: ", Body, "\r\n\r\n"
            ?DEFAULT_STRING
        ]
    ).

large_response(Module, Socket, _, _, _) ->
    BodyPart = <<?LONG_BODY_PART>>,
    ContentLength = 3 * size(BodyPart),
    Module:send(
        Socket,
        [
            "HTTP/1.1 200 OK\r\n"
            "Content-type: text/plain\r\n"
            "Content-length: ", integer_to_list(ContentLength), "\r\n\r\n"
        ]
    ),
    Module:send(Socket, BodyPart),
    Module:send(Socket, BodyPart),
    Module:send(Socket, BodyPart).

large_chunked_response(Module, Socket, _, _, _) ->
    BodyPart = <<?LONG_BODY_PART>>,
    ChunkSize = erlang:integer_to_list(size(BodyPart), 16),
    Chunk = [ChunkSize, "\r\n", BodyPart, "\r\n"],
    Module:send(
        Socket,
        [
            "HTTP/1.1 200 OK\r\n"
            "Content-type: text/plain\r\n"
            "Transfer-Encoding: chunked\r\n\r\n"
        ]
    ),
    Module:send(Socket, Chunk),
    Module:send(Socket, Chunk),
    Module:send(Socket, Chunk),
    Module:send(Socket, "0\r\n\r\n").

slow_chunked_response(Module, Socket, _, _, _) ->
    ChunkSize = erlang:integer_to_list(length(?LONG_BODY_PART) * 2, 16),
    Module:send(
        Socket,
        [
            "HTTP/1.1 200 OK\r\n"
            "Content-type: text/plain\r\n"
            "Transfer-Encoding: chunked\r\n\r\n"
        ]),
    Module:send(Socket, [ChunkSize, "\r\n", <<?LONG_BODY_PART>>]),
    timer:sleep(200),
    Module:send(Socket, [<<?LONG_BODY_PART>>, "\r\n"]),
    Module:send(Socket, "0\r\n\r\n").


chunked_upload(Module, Socket, _, Headers, <<>>) ->
    TransferEncoding = lhttpc_lib:header_value("transfer-encoding", Headers),
    {Body, HeadersAndTrailers} =
        webserver:read_chunked(Module, Socket, Headers),
    Trailer1 = lhttpc_lib:header_value("x-trailer-1", HeadersAndTrailers,
        "undefined"),
    Module:send(
        Socket,
        [
            "HTTP/1.1 200 OK\r\n"
            "Content-Length: 14\r\n"
            "X-Test-Orig-Trailer-1:", Trailer1, "\r\n"
            "X-Test-Orig-Enc: ", TransferEncoding, "\r\n"
            "X-Test-Orig-Body: ", Body, "\r\n\r\n"
            ?DEFAULT_STRING
        ]
    ).

head_response(Module, Socket, _Request, _Headers, _Body) ->
    Module:send(
        Socket,
        "HTTP/1.1 200 OK\r\n"
        "Server: Test server!\r\n\r\n"
    ).

no_content_response(Module, Socket, _Request, _Headers, _Body) ->
    Module:send(
        Socket,
        "HTTP/1.1 204 OK\r\n"
        "Server: Test server!\r\n\r\n"
    ).

empty_body(Module, Socket, _, _, _) ->
    Module:send(
        Socket,
        "HTTP/1.1 200 OK\r\n"
        "Content-type: text/plain\r\nContent-length: 0\r\n\r\n"
    ).

copy_body(Module, Socket, _, _, Body) ->
    Module:send(
        Socket,
        [
            "HTTP/1.1 200 OK\r\n"
            "Content-type: text/plain\r\nContent-length: "
            ++ integer_to_list(size(Body)) ++ "\r\n\r\n",
            Body
        ]
    ).

copy_body_100_continue(Module, Socket, _, _, Body) ->
    Module:send(
        Socket,
        [
            "HTTP/1.1 100 Continue\r\n\r\n"
            "HTTP/1.1 200 OK\r\n"
            "Content-type: text/plain\r\nContent-length: "
            ++ integer_to_list(size(Body)) ++ "\r\n\r\n",
            Body
        ]
    ).

respond_and_close(Module, Socket, _, _, Body) ->
    Pid = list_to_pid(binary_to_list(Body)),
    Module:send(
        Socket,
        "HTTP/1.1 200 OK\r\n"
        "Connection: close\r\n"
        "Content-type: text/plain\r\nContent-length: 14\r\n\r\n"
        ?DEFAULT_STRING
    ),
    {error, closed} = Module:recv(Socket, 0),
    Pid ! closed,
    Module:close(Socket).

respond_and_wait(Module, Socket, _, _, Body) ->
    Pid = list_to_pid(binary_to_list(Body)),
    Module:send(
        Socket,
        "HTTP/1.1 200 OK\r\n"
        "Content-type: text/plain\r\nContent-length: 14\r\n\r\n"
        ?DEFAULT_STRING
    ),
    % We didn't signal a connection close, but we want the client to do that
    % any way
    {error, closed} = Module:recv(Socket, 0),
    Pid ! closed,
    Module:close(Socket).

pre_1_1_server(Module, Socket, _, _, Body) ->
    Pid = list_to_pid(binary_to_list(Body)),
    Module:send(
        Socket,
        "HTTP/1.0 200 OK\r\n"
        "Content-type: text/plain\r\nContent-length: 14\r\n\r\n"
        ?DEFAULT_STRING
    ),
    % We didn't signal a connection close, but we want the client to do that
    % any way since we're 1.0 now
    {error, closed} = Module:recv(Socket, 0),
    Pid ! closed,
    Module:close(Socket).

pre_1_1_server_keep_alive(Module, Socket, _, _, _) ->
    Module:send(
        Socket,
        "HTTP/1.0 200 OK\r\n"
        "Content-type: text/plain\r\n"
        "Connection: Keep-Alive\r\n"
        "Content-length: 14\r\n\r\n"
        ?DEFAULT_STRING
    ).

very_slow_response(Module, Socket, _, _, _) ->
    timer:sleep(1000),
    Module:send(
        Socket,
        "HTTP/1.1 200 OK\r\n"
        "Content-type: text/plain\r\nContent-length: 14\r\n\r\n"
        ?DEFAULT_STRING
    ).

no_content_length(Module, Socket, _, _, _) ->
    Module:send(
        Socket,
        "HTTP/1.1 200 OK\r\n"
        "Content-type: text/plain\r\nConnection: close\r\n\r\n"
        ?DEFAULT_STRING
    ).

no_content_length_1_0(Module, Socket, _, _, _) ->
    Module:send(
        Socket,
        "HTTP/1.0 200 OK\r\n"
        "Content-type: text/plain\r\n\r\n"
        ?DEFAULT_STRING
    ).

chunked_response(Module, Socket, _, _, _) ->
    Module:send(
        Socket,
        "HTTP/1.1 200 OK\r\n"
        "Content-type: text/plain\r\nTransfer-Encoding: chunked\r\n\r\n"
        "5\r\n"
        "Great\r\n"
        "1\r\n"
        " \r\n"
        "8\r\n"
        "success!\r\n"
        "0\r\n"
        "\r\n"
    ).

chunked_response_t(Module, Socket, _, _, _) ->
    Module:send(
        Socket,
        "HTTP/1.1 200 OK\r\n"
        "Content-type: text/plain\r\nTransfer-Encoding: ChUnKeD\r\n\r\n"
        "7\r\n"
        "Again, \r\n"
        "E\r\n"
        "great success!\r\n"
        "0\r\n"
        "Trailer-1: 1\r\n"
        "Trailer-2: 2\r\n"
        "\r\n"
    ).

close_connection(Module, Socket, _, _, _) ->
    Module:send(
        Socket,
        "HTTP/1.1 200 OK\r\n"
        "Content-type: text/plain\r\nContent-length: 14\r\n\r\n"
    ),
    Module:close(Socket).

not_modified_response(Module, Socket, _Request, _Headers, _Body) ->
    Module:send(
        Socket,
		[
			"HTTP/1.1 304 Not Modified\r\n"
			"Date: Tue, 15 Nov 1994 08:12:31 GMT\r\n\r\n"
		]
    ).

basic_auth_responder(User, Passwd) ->
    fun(Module, Socket, _Request, Headers, _Body) ->
        case proplists:get_value("Authorization", Headers) of
            undefined ->
                Module:send(
                    Socket,
                    [
                        "HTTP/1.1 401 Unauthorized\r\n",
                        "Content-Type: text/plain\r\n",
                        "Content-Length: 12\r\n\r\n",
                        "missing_auth"
                    ]
                );
            "Basic " ++ Auth ->
                [U, P] = string:tokens(
                    binary_to_list(base64:decode(iolist_to_binary(Auth))), ":"),
                case {U, P} of
                    {User, Passwd} ->
                        Module:send(
                            Socket,
                            [
                                "HTTP/1.1 200 OK\r\n",
                                "Content-Type: text/plain\r\n",
                                "Content-Length: 2\r\n\r\n",
                                "OK"
                            ]
                        );
                    _ ->
                        Module:send(
                            Socket,
                            [
                                "HTTP/1.1 401 Unauthorized\r\n",
                                "Content-Type: text/plain\r\n",
                                "Content-Length: 10\r\n\r\n",
                                "wrong_auth"
                            ]
                        )
                end
        end
    end.

trailing_space_header(Module, Socket, _, _, _) ->
    Module:send(
      Socket,
      "HTTP/1.1 200 OK\r\n"
          "Content-type: text/plain\r\n"
          "Content-Length: 14 \r\n\r\n"
          ?DEFAULT_STRING
    ).

set_cookie_response(Module, Socket, _, _, _) ->
     Module:send(
      Socket,
       "HTTP/1.1 200 OK\r\n"
       "Connection: Keep-Alive\r\n"
       "Set-Cookie: name=value\r\n"
       "Set-Cookie: name2=value2; Expires=Wed, 09-Jun-2021 10:18:14 GMT\r\n"
       "Content-type: text/plain\r\n"
       "Content-length: 0\r\n\r\n"
      ).


expired_cookie_response(Module, Socket, _Request, Headers, _Body) ->
    case lhttpc_lib:header_value("Cookie", Headers) of
            undefined ->
                Module:send(
                    Socket,
		     "HTTP/1.1 500 Internal Server Error\r\n"
		     "Content-type: text/plain\r\n"
		     "Content-length: 0\r\n\r\n"
                );
	"name=value; name2=value2" ->
	    Module:send(
	      Socket,
	      "HTTP/1.1 200 OK\r\n"
	      "Connection: Keep-Alive\r\n"
	      "Set-Cookie: name2=value2; Expires=Wed, 09-Jun-1975 10:18:14 GMT\r\n"
	      "Content-type: text/plain\r\n"
              "Content-length: 0\r\n\r\n"
	     );
	%The order should not matter.
	"name2=value2; name=value"->
	    Module:send(
	      Socket,
	      "HTTP/1.1 200 OK\r\n"
	      "Connection: Keep-Alive\r\n"
	      "Set-Cookie: name2=value2; Expires=Wed, 09-Jun-1975 10:18:14 GMT\r\n"
	      "Content-type: text/plain\r\n"
              "Content-length: 0\r\n\r\n"
	     )
    end.

receive_right_cookies(Module, Socket, _Request, Headers, _Body) ->
    case proplists:get_value("Cookie", Headers) of
	"name=value" ->
	    Module:send(
	      Socket,
	      "HTTP/1.1 200 OK\r\n"
	      "Content-type: text/plain\r\n"
	      "Content-length: 0\r\n\r\n"
	     );
	_ ->
	     Module:send(
                    Socket,
		     "HTTP/1.1 500 Internal Server Error\r\n"
		     "Content-type: text/plain\r\n"
		     "Content-length: 0\r\n\r\n"
                )
    end.
