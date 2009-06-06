%%% ----------------------------------------------------------------------------
%%% Copyright (c) 2009, Erlang Training and Consulting Ltd.
%%% All rights reserved.
%%% 
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions are met:
%%%    * Redistributions of source code must retain the above copyright
%%%      notice, this list of conditions and the following disclaimer.
%%%    * Redistributions in binary form must reproduce the above copyright
%%%      notice, this list of conditions and the following disclaimer in the
%%%      documentation and/or other materials provided with the distribution.
%%%    * Neither the name of Erlang Training and Consulting Ltd. nor the
%%%      names of its contributors may be used to endorse or promote products
%%%      derived from this software without specific prior written permission.
%%% 
%%% THIS SOFTWARE IS PROVIDED BY Erlang Training and Consulting Ltd. ''AS IS''
%%% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
%%% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
%%% ARE DISCLAIMED. IN NO EVENT SHALL Erlang Training and Consulting Ltd. BE
%%% LIABLE SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
%%% BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
%%% WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
%%% OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
%%% ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%%% ----------------------------------------------------------------------------

%%% @author Oscar Hellström <oscar@erlang-consulting.com>
-module(lhttpc_tests).

-import(webserver, [start/2]).

-include_lib("eunit/include/eunit.hrl").

%%% Eunit setup stuff

start_app() ->
    ok = application:start(lhttpc).

stop_app(_) ->
    ok = application:stop(lhttpc).

tcp_test_() ->
    {setup, fun start_app/0, fun stop_app/1, [
            ?_test(simple_get()),
            ?_test(empty_get()),
            ?_test(no_content_length_get()),
            ?_test(connection_close()),
            ?_test(simple_put()),
            ?_test(post()),
%            ?_test(bad_url())
            ?_test(persistent_connection()),
            ?_test(timeout()),
            ?_test(suspended_manager())
        ]}.

%%% Tests

simple_get() ->
    simple(get),
    simple("GET").

empty_get() ->
    Port = start(gen_tcp, [fun empty_body/5]),
    URL = "http://localhost:" ++ integer_to_list(Port) ++ "/empty",
    {ok, Response} = lhttpc:request(URL, "GET", [], 1000),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(<<>>, body(Response)).

no_content_length_get() ->
    Port = start(gen_tcp, [fun no_content_length/5]),
    URL = "http://localhost:" ++ integer_to_list(Port) ++ "/no_cl",
    {ok, Response} = lhttpc:request(URL, "GET", [], 1000),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(<<"Great success!">>, body(Response)).

connection_close() ->
    Port = start(gen_tcp, [fun respond_and_close/5]),
    URL = "http://localhost:" ++ integer_to_list(Port) ++ "/close",
    Body = pid_to_list(self()),
    {ok, Response} = lhttpc:request(URL, "PUT", [], Body, 1000),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(<<"Great success!">>, body(Response)),
    receive closed -> ok end.

simple_put() ->
    simple(put),
    simple("PUT").

post() ->
    Port = start(gen_tcp, [fun copy_body/5]),
    URL = "http://localhost:" ++ integer_to_list(Port) ++ "/post",
    {X, Y, Z} = now(),
    Body = [
        "This is a rather simple post :)",
        integer_to_list(X),
        integer_to_list(Y),
        integer_to_list(Z)
    ],
    {ok, Response} = lhttpc:request(URL, "POST", [], Body, 1000),
    {StatusCode, ReasonPhrase} = status(Response),
    ?assertEqual(200, StatusCode),
    ?assertEqual("OK", ReasonPhrase),
    ?assertEqual(iolist_to_binary(Body), body(Response)).

% Can't test this, since eunit uses catch, which won't catch exit signals
% coming from other processes (such as the request process)...
% Maybe I should "fix" that in lhttpc... or not?
%bad_url() ->
%    ?assertExit(_, lhttpc:request(ost, "GET", [], 100)).

persistent_connection() ->
    Port = start(gen_tcp, [
            fun simple_response/5,
            fun simple_response/5,
            fun copy_body/5
        ]),
    URL = "http://localhost:" ++ integer_to_list(Port) ++ "/persistent",
    {ok, FirstResponse} = lhttpc:request(URL, "GET", [], 1000),
    Headers = [{"KeepAlive", "300"}], % shouldn't be needed
    {ok, SecondResponse} = lhttpc:request(URL, "GET", Headers, 1000),
    {ok, ThirdResponse} = lhttpc:request(URL, "POST", [], 1000),
    ?assertEqual({200, "OK"}, status(FirstResponse)),
    ?assertEqual(<<"Great success!">>, body(FirstResponse)),
    ?assertEqual({200, "OK"}, status(SecondResponse)),
    ?assertEqual(<<"Great success!">>, body(SecondResponse)),
    ?assertEqual({200, "OK"}, status(ThirdResponse)),
    ?assertEqual(<<>>, body(ThirdResponse)).

timeout() ->
    Port = start(gen_tcp, [fun slow_response/5]),
    URL = "http://localhost:" ++ integer_to_list(Port) ++ "/slow",
    ?assertEqual({error, timeout}, lhttpc:request(URL, get, [], 50)).

suspended_manager() ->
    Port = start(gen_tcp, [fun simple_response/5, fun simple_response/5]),
    URL = "http://localhost:" ++ integer_to_list(Port) ++ "/persistent",
    {ok, FirstResponse} = lhttpc:request(URL, get, [], 50),
    ?assertEqual({200, "OK"}, status(FirstResponse)),
    ?assertEqual(<<"Great success!">>, body(FirstResponse)),
    Pid = whereis(lhttpc_manager),
    true = erlang:suspend_process(Pid),
    ?assertEqual({error, timeout}, lhttpc:request(URL, get, [], 50)),
    true = erlang:resume_process(Pid),
    ?assertEqual(1,
        lhttpc_manager:connection_count({"localhost", Port, false})),
    {ok, SecondResponse} = lhttpc:request(URL, get, [], 50),
    ?assertEqual({200, "OK"}, status(SecondResponse)),
    ?assertEqual(<<"Great success!">>, body(SecondResponse)).

%%% Helpers functions

simple(Method) ->
    Port = start(gen_tcp, [fun simple_response/5]),
    URL = "http://localhost:" ++ integer_to_list(Port) ++ "/simple",
    {ok, Response} = lhttpc:request(URL, Method, [], 1000),
    {StatusCode, ReasonPhrase} = status(Response),
    ?assertEqual(200, StatusCode),
    ?assertEqual("OK", ReasonPhrase),
    ?assertEqual(<<"Great success!">>, body(Response)).

status({Status, _, _}) ->
    Status.

body({_, _, Body}) ->
    Body.


%%% Responders
simple_response(Module, Socket, _Request, _Headers, _Body) ->
    Module:send(
        Socket,
        "HTTP/1.1 200 OK\r\n"
        "Content-type: text/plain\r\nContent-length: 14\r\n\r\n"
        "Great success!"
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

respond_and_close(Module, Socket, _, _, Body) ->
    Pid = list_to_pid(binary_to_list(Body)),
    Module:send(
        Socket,
        "HTTP/1.1 200 OK\r\n"
        "Connection: close\r\n"
        "Content-type: text/plain\r\nContent-length: 14\r\n\r\n"
        "Great success!"
    ),
    case Module:recv(Socket, 0) of
        {error, closed} -> Pid ! closed
    end,
    Module:close(Socket).

slow_response(Module, Socket, _, _, _) ->
    timer:sleep(1000),
    Module:send(
        Socket,
        "HTTP/1.1 200 OK\r\n"
        "Content-type: text/plain\r\nContent-length: 14\r\n\r\n"
        "Great success!"
    ).

no_content_length(Module, Socket, _, _, _) ->
    Module:send(
        Socket,
        "HTTP/1.1 200 OK\r\n"
        "Content-type: text/plain\r\nConnection: close\r\n\r\n"
        "Great success!"
    ).
