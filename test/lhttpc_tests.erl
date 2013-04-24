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

%%% @author Oscar Hellström <oscar@hellstrom.st>
-module(lhttpc_tests).

-export([test_no/2]).
-import(webserver, [start/2, start/3]).

-include_lib("eunit/include/eunit.hrl").

test_no(N, Tests) ->
    setelement(2, Tests,
        setelement(4, element(2, Tests),
            lists:nth(N, element(4, element(2, Tests))))).

%%% Eunit setup stuff

start_app() ->
    application:start(crypto),
    application:start(public_key),
    ok = application:start(ssl),
    ok = lhttpc:start().

stop_app(_) ->
    ok = lhttpc:stop(),
    ok = application:stop(ssl).

tcp_test_() ->
    {inorder,
        {setup, fun start_app/0, fun stop_app/1, [
                ?_test(simple_get()),
                ?_test(simple_get_ipv6()),
                ?_test(empty_get()),
                ?_test(connection_refused()),
                ?_test(basic_auth()),
                ?_test(missing_basic_auth()),
                ?_test(wrong_basic_auth()),
                ?_test(get_with_mandatory_hdrs()),
                ?_test(get_with_mandatory_hdrs_by_atoms()),
                ?_test(get_with_mandatory_hdrs_by_binaries()),
                ?_test(get_with_connect_options()),
                ?_test(no_content_length()),
                ?_test(no_content_length_1_0()),
                ?_test(get_not_modified()),
                ?_test(simple_head()),
                ?_test(simple_head_atom()),
                ?_test(delete_no_content()),
                ?_test(delete_content()),
                ?_test(options_content()),
                ?_test(options_no_content()),
                ?_test(server_connection_close()),
                ?_test(client_connection_close()),
                ?_test(pre_1_1_server_connection()),
                ?_test(pre_1_1_server_keep_alive()),
                ?_test(simple_put()),
                ?_test(post()),
                ?_test(post_100_continue()),
                ?_test(bad_url()),
                ?_test(persistent_connection()),
                ?_test(request_timeout()),
                ?_test(connection_timeout()),
                ?_test(suspended_manager()),
                ?_test(chunked_encoding()),
                ?_test(partial_upload_identity()),
                ?_test(partial_upload_identity_iolist()),
                ?_test(partial_upload_chunked()),
                ?_test(partial_upload_chunked_no_trailer()),
                ?_test(partial_download_illegal_option()),
                ?_test(partial_download_identity()),
	        ?_test(partial_download_infinity_window()),
                ?_test(partial_download_no_content_length()),
                ?_test(partial_download_no_content()),
                ?_test(limited_partial_download_identity()),
                ?_test(partial_download_chunked()),
                ?_test(partial_download_chunked_infinite_part()),
                ?_test(partial_download_smallish_chunks()),
                ?_test(partial_download_slow_chunks())
              %  ?_test(close_connection()),
              %  ?_test(message_queue()),
              %  ?_test(trailing_space_header()),
              %  ?_test(connection_count()) % just check that it's 0 (last)
            ]}
    }.

ssl_test_() ->
    {inorder,
        {setup, fun start_app/0, fun stop_app/1, [
                ?_test(ssl_get()),
                ?_test(ssl_get_ipv6()),
                ?_test(ssl_post()),
                ?_test(ssl_chunked()),
                ?_test(connection_count()) % just check that it's 0 (last)
            ]}
    }.

options_test() ->
    invalid_options().

cookies_test() ->
    cookies().

%%% Tests

simple_get() ->
    simple(get),
    simple("GET").

simple_get_ipv6() ->
    simple(get, inet6),
    simple("GET", inet6).

empty_get() ->
    Port = start(gen_tcp, [fun webserver_utils:empty_body/5]),
    URL = url(Port, "/empty"),
    {ok, Response} = lhttpc:request(URL, "GET", [], 1000),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(<<>>, body(Response)).

connection_refused() ->
    Response = lhttpc:request("http://127.0.0.1:50234/none", "GET", [], 100),
    ?assertEqual({error, econnrefused}, Response).

basic_auth() ->
    User = "foo",
    Passwd = "bar",
    Port = start(gen_tcp, [webserver_utils:basic_auth_responder(User, Passwd)]),
    URL = url(Port, "/empty", User, Passwd),
    {ok, Response} = lhttpc:request(URL, "GET", [], 1000),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(<<"OK">>, body(Response)).

missing_basic_auth() ->
    User = "foo",
    Passwd = "bar",
    Port = start(gen_tcp, [webserver_utils:basic_auth_responder(User, Passwd)]),
    URL = url(Port, "/empty"),
    {ok, Response} = lhttpc:request(URL, "GET", [], 1000),
    ?assertEqual({401, "Unauthorized"}, status(Response)),
    ?assertEqual(<<"missing_auth">>, body(Response)).

wrong_basic_auth() ->
    User = "foo",
    Passwd = "bar",
    Port = start(gen_tcp, [webserver_utils:basic_auth_responder(User, Passwd)]),
    URL = url(Port, "/empty", User, "wrong_password"),
    {ok, Response} = lhttpc:request(URL, "GET", [], 1000),
    ?assertEqual({401, "Unauthorized"}, status(Response)),
    ?assertEqual(<<"wrong_auth">>, body(Response)).

get_with_mandatory_hdrs() ->
    Port = start(gen_tcp, [fun webserver_utils:simple_response/5]),
    URL = url(Port, "/host"),
    Body = list_to_binary(webserver_utils:default_string()),
    Hdrs = [
        {"content-length", integer_to_list(size(Body))},
        {"host", "localhost"}
    ],
    {ok, Response} = lhttpc:request(URL, "POST", Hdrs, Body, 1000),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response)).

get_with_mandatory_hdrs_by_atoms() ->
    Port = start(gen_tcp, [fun webserver_utils:simple_response/5]),
    URL = url(Port, "/host"),
    Body = list_to_binary(webserver_utils:default_string()),
    Hdrs = [
        {'Content-Length', integer_to_list(size(Body))},
        {'Host', "localhost"}
    ],
    {ok, Response} = lhttpc:request(URL, "POST", Hdrs, Body, 1000),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response)).

get_with_mandatory_hdrs_by_binaries() ->
    Port = start(gen_tcp, [fun webserver_utils:simple_response/5]),
    URL = url(Port, "/host"),
    Body = list_to_binary(webserver_utils:default_string()),
    Hdrs = [
        {<<"Content-Length">>, integer_to_list(size(Body))},
        {<<"Host">>, "localhost"}
    ],
    {ok, Response} = lhttpc:request(URL, "POST", Hdrs, Body, 1000),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response)).

get_with_connect_options() ->
    Port = start(gen_tcp, [fun webserver_utils:empty_body/5]),
    URL = url(Port, "/empty"),
    Options = [{connect_options, [{ip, {127, 0, 0, 1}}, {port, 0}]}],
    {ok, Response} = lhttpc:request(URL, "GET", [], [], 1000, Options),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(<<>>, body(Response)).

no_content_length() ->
    Port = start(gen_tcp, [fun webserver_utils:no_content_length/5]),
    URL = url(Port, "/no_cl"),
    {ok, Response} = lhttpc:request(URL, "GET", [], 1000),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response)).

no_content_length_1_0() ->
    Port = start(gen_tcp, [fun webserver_utils:no_content_length_1_0/5]),
    URL = url(Port, "/no_cl"),
    {ok, Response} = lhttpc:request(URL, "GET", [], 1000),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response)).

%% Check the header value is trimming spaces on header values
%% which can cause crash in lhttpc_client:body_type when Content-Length
%% is converted from list to integer
trailing_space_header() ->
    Port = start(gen_tcp, [fun webserver_utils:trailing_space_header/5]),
    URL = url(Port, "/no_cl"),
    {ok, Response} = lhttpc:request(URL, "GET", [], 1000),
    Headers = headers(Response),
    ContentLength = lhttpc_lib:header_value("Content-Length", Headers),
    ?assertEqual("14", ContentLength).

get_not_modified() ->
    Port = start(gen_tcp, [fun webserver_utils:not_modified_response/5]),
    URL = url(Port, "/not_modified"),
    {ok, Response} = lhttpc:request(URL, "GET", [], [], 1000),
    ?assertEqual({304, "Not Modified"}, status(Response)),
    ?assertEqual(<<>>, body(Response)).

simple_head() ->
    Port = start(gen_tcp, [fun webserver_utils:head_response/5]),
    URL = url(Port, "/HEAD"),
    {ok, Response} = lhttpc:request(URL, "HEAD", [], 1000),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(<<>>, body(Response)).

simple_head_atom() ->
    Port = start(gen_tcp, [fun webserver_utils:head_response/5]),
    URL = url(Port, "/head"),
    {ok, Response} = lhttpc:request(URL, head, [], 1000),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(<<>>, body(Response)).

delete_no_content() ->
    Port = start(gen_tcp, [fun webserver_utils:no_content_response/5]),
    URL = url(Port, "/delete_no_content"),
    {ok, Response} = lhttpc:request(URL, delete, [], 1000),
    ?assertEqual({204, "OK"}, status(Response)),
    ?assertEqual(<<>>, body(Response)).

delete_content() ->
    Port = start(gen_tcp, [fun webserver_utils:simple_response/5]),
    URL = url(Port, "/delete_content"),
    {ok, Response} = lhttpc:request(URL, "DELETE", [], 1000),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response)).

options_no_content() ->
    Port = start(gen_tcp, [fun webserver_utils:head_response/5]),
    URL = url(Port, "/options_no_content"),
    {ok, Response} = lhttpc:request(URL, "OPTIONS", [], 1000),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(<<>>, body(Response)).

options_content() ->
    Port = start(gen_tcp, [fun webserver_utils:simple_response/5]),
    URL = url(Port, "/options_content"),
    {ok, Response} = lhttpc:request(URL, "OPTIONS", [], 1000),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response)).

server_connection_close() ->
    Port = start(gen_tcp, [fun webserver_utils:respond_and_close/5]),
    URL = url(Port, "/close"),
    Body = pid_to_list(self()),
    {ok, Response} = lhttpc:request(URL, "PUT", [], Body, 1000),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response)),
    receive closed -> ok end.

client_connection_close() ->
    Port = start(gen_tcp, [fun webserver_utils:respond_and_wait/5]),
    URL = url(Port, "/close"),
    Body = pid_to_list(self()),
    Hdrs = [{"Connection", "close"}],
    {ok, _} = lhttpc:request(URL, put, Hdrs, Body, 1000),
    % Wait for the server to see that socket has been closed
    receive closed -> ok end.

pre_1_1_server_connection() ->
    Port = start(gen_tcp, [fun webserver_utils:pre_1_1_server/5]),
    URL = url(Port, "/close"),
    Body = pid_to_list(self()),
    {ok, _} = lhttpc:request(URL, put, [], Body, 1000),
    % Wait for the server to see that socket has been closed.
    % The socket should be closed by us since the server responded with a
    % 1.0 version, and not the Connection: keep-alive header.
    receive closed -> ok end.

pre_1_1_server_keep_alive() ->
    Port = start(gen_tcp, [
            fun webserver_utils:pre_1_1_server_keep_alive/5,
            fun webserver_utils:pre_1_1_server/5
        ]),
    URL = url(Port, "/close"),
    Body = pid_to_list(self()),
    %this test need to use a client now (or a pool).
    {ok, Response1} = lhttpc:request(URL, get, [], [], 1000, [{pool_options, [{pool_ensure, true}, {pool, pool_name}]}]),
    {ok, Response2} = lhttpc:request(URL, put, [], Body, 1000, [{pool_options, [{pool_ensure, true}, {pool, pool_name}]}]),
    ?assertEqual({200, "OK"}, status(Response1)),
    ?assertEqual({200, "OK"}, status(Response2)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response1)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response2)),
    % Wait for the server to see that socket has been closed.
    % The socket should be closed by us since the server responded with a
    % 1.0 version, and not the Connection: keep-alive header.
    receive closed -> ok end.

simple_put() ->
    simple(put),
    simple("PUT").

post() ->
    Port = start(gen_tcp, [fun webserver_utils:copy_body/5]),
    URL = url(Port, "/post"),
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

post_100_continue() ->
    Port = start(gen_tcp, [fun webserver_utils:copy_body_100_continue/5]),
    URL = url(Port, "/post"),
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

bad_url() ->
    ?assertError(_, lhttpc:request(ost, "GET", [], 100)).

persistent_connection() ->
    Port = start(gen_tcp, [
            fun webserver_utils:simple_response/5,
            fun webserver_utils:simple_response/5,
            fun webserver_utils:copy_body/5
        ]),
    URL = url(Port, "/persistent"),
    {ok, FirstResponse} = lhttpc:request(URL, "GET", [], [], 1000, [{pool_options, [{pool_ensure, true}, {pool, pool_name}]}]),
    Headers = [{"KeepAlive", "300"}], % shouldn't be needed
    {ok, SecondResponse} = lhttpc:request(URL, "GET", Headers, [], 1000, [{pool_options, [{pool_ensure, true}, {pool, pool_name}]}]),
    {ok, ThirdResponse} = lhttpc:request(URL, "POST", [], [], 1000, [{pool_options, [{pool_ensure, true}, {pool, pool_name}]}]),
    ?assertEqual({200, "OK"}, status(FirstResponse)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(FirstResponse)),
    ?assertEqual({200, "OK"}, status(SecondResponse)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(SecondResponse)),
    ?assertEqual({200, "OK"}, status(ThirdResponse)),
    ?assertEqual(<<>>, body(ThirdResponse)).

request_timeout() ->
    Port = start(gen_tcp, [fun webserver_utils:very_slow_response/5]),
    URL = url(Port, "/slow"),
    ?assertEqual({error, timeout}, lhttpc:request(URL, get, [], 50)).

connection_timeout() ->
    Port = start(gen_tcp, [fun webserver_utils:simple_response/5, fun webserver_utils:simple_response/5]),
    URL = url(Port, "/close_conn"),
    {ok, _PoolManager} = lhttpc:add_pool(lhttpc_manager),
    lhttpc_manager:update_connection_timeout(lhttpc_manager, 50), % very short keep alive
    {ok, Response} = lhttpc:request(URL, get, [], 100),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response)),
    timer:sleep(100),
    ?assertEqual(0,
        lhttpc_manager:connection_count(lhttpc_manager, {"localhost", Port, false})),
    lhttpc_manager:update_connection_timeout(lhttpc_manager, 300000). % set back

suspended_manager() ->
    Port = start(gen_tcp, [fun webserver_utils:simple_response/5, fun webserver_utils:simple_response/5]),
    URL = url(Port, "/persistent"),
    {ok, FirstResponse} = lhttpc:request(URL, get, [], [], 50, [{pool_options, [{pool_ensure, true}, {pool, lhttpc_manager}]}]),
    ?assertEqual({200, "OK"}, status(FirstResponse)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(FirstResponse)),
    Pid = whereis(lhttpc_manager),
    true = erlang:suspend_process(Pid),
    ?assertEqual({error, connection_timeout}, lhttpc:request(URL, get, [], [], 50, [{pool_options, [{pool_ensure, true}, {pool, lhttpc_manager}]}])),
    true = erlang:resume_process(Pid),
    ?assertEqual(1,
        lhttpc_manager:connection_count(lhttpc_manager, {"localhost", Port, false})),
    {ok, SecondResponse} = lhttpc:request(URL, get, [], [], 50, [{pool_options, [{pool_ensure, true}, {pool, lhttpc_manager}]}]),
    ?assertEqual({200, "OK"}, status(SecondResponse)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(SecondResponse)).

chunked_encoding() ->
    Port = start(gen_tcp, [fun webserver_utils:chunked_response/5, fun webserver_utils:chunked_response_t/5]),
    URL = url(Port, "/chunked"),
    {ok, Client} = lhttpc:connect_client(URL, []),
    {ok, FirstResponse} = lhttpc:request_client(Client, URL, get, [], 1000),
    ?assertEqual({200, "OK"}, status(FirstResponse)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(FirstResponse)),
    ?assertEqual("chunked", lhttpc_lib:header_value("transfer-encoding",
            headers(FirstResponse))),
    {ok, SecondResponse} = lhttpc:request_client(Client, URL, get, [], 1000),
    ?assertEqual({200, "OK"}, status(SecondResponse)),
    ?assertEqual(<<"Again, great success!">>, body(SecondResponse)),
    ?assertEqual("ChUnKeD", lhttpc_lib:header_value("transfer-encoding",
            headers(SecondResponse))),
    ?assertEqual("1", lhttpc_lib:header_value("trailer-1",
            headers(SecondResponse))),
    ?assertEqual("2", lhttpc_lib:header_value("trailer-2",
            headers(SecondResponse))).

partial_upload_identity() ->
    Port = start(gen_tcp, [fun webserver_utils:simple_response/5, fun webserver_utils:simple_response/5]),
    URL = url(Port, "/partial_upload"),
    Body = [<<"This">>, <<" is ">>, <<"chunky">>, <<" stuff!">>],
    Hdrs = [{"Content-Length", integer_to_list(iolist_size(Body))}],
    Options = [{partial_upload, true}],
    {ok, Client} = lhttpc:connect_client(URL, []),
    {ok, partial_upload} =
        lhttpc:request_client(Client, URL, post, Hdrs, hd(Body), 1000, Options),
    {ok, Response1} = upload_parts(Client, tl(Body) ++ [http_eob]),
    ?assertEqual({200, "OK"}, status(Response1)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response1)),
    ?assertEqual("This is chunky stuff!",
        lhttpc_lib:header_value("x-test-orig-body", headers(Response1))),
    % Make sure it works with no body part in the original request as well
    {ok, partial_upload} = lhttpc:request_client(Client, URL, post, Hdrs, [], 1000, Options),
    {ok, Response2} = upload_parts(Client, Body ++ [http_eob]),
    ?assertEqual({200, "OK"}, status(Response2)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response2)),
    ?assertEqual("This is chunky stuff!",
        lhttpc_lib:header_value("x-test-orig-body", headers(Response2))).

partial_upload_identity_iolist() ->
    Port = start(gen_tcp, [fun webserver_utils:simple_response/5, fun webserver_utils:simple_response/5]),
    URL = url(Port, "/partial_upload"),
    Body = ["This", [<<" ">>, $i, $s, [" "]], <<"chunky">>, [<<" stuff!">>]],
    Hdrs = [{"Content-Length", integer_to_list(iolist_size(Body))}],
    Options = [{partial_upload, true}],
    {ok, Client} = lhttpc:connect_client(URL, []),
    {ok, partial_upload} =
        lhttpc:request_client(Client, URL, post, Hdrs, hd(Body), 1000, Options),
    {ok, Response1} = upload_parts(Client, tl(Body) ++ [http_eob]),
    ?assertEqual({200, "OK"}, status(Response1)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response1)),
    ?assertEqual("This is chunky stuff!",
        lhttpc_lib:header_value("x-test-orig-body", headers(Response1))),
    % Make sure it works with no body part in the original request as well
    {ok, UploadState2} = lhttpc:request_client(Client, URL, post, Hdrs, [], 1000, Options),
    {ok, Response2} = upload_parts(Client, Body ++ [http_eob]),
    ?assertEqual({200, "OK"}, status(Response2)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response2)),
    ?assertEqual("This is chunky stuff!",
        lhttpc_lib:header_value("x-test-orig-body", headers(Response2))).

partial_upload_chunked() ->
    Port = start(gen_tcp, [fun webserver_utils:chunked_upload/5, fun webserver_utils:chunked_upload/5]),
    URL = url(Port, "/partial_upload_chunked"),
    Body = ["This", [<<" ">>, $i, $s, [" "]], <<"chunky">>, [<<" stuff!">>]],
    Options = [{partial_upload, true}],
    {ok, Client} = lhttpc:connect_client(URL, []),
    {ok, partial_upload} = lhttpc:request_client(Client, URL, post, [], hd(Body), 1000, Options),
    Trailer = {"X-Trailer-1", "my tail is tailing me...."},
    upload_parts(Client, tl(Body)),
    {ok, Response1} = lhttpc:send_trailers(Client, [Trailer]),
    ?assertEqual({200, "OK"}, status(Response1)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response1)),
    ?assertEqual("This is chunky stuff!",
        lhttpc_lib:header_value("x-test-orig-body", headers(Response1))),
    ?assertEqual(element(2, Trailer),
        lhttpc_lib:header_value("x-test-orig-trailer-1", headers(Response1))),
    % Make sure it works with no body part in the original request as well
    Headers = [{"Transfer-Encoding", "chunked"}],
    {ok, partial_upload} = lhttpc:request_client(Client, URL, post, Headers, [], 1000, Options),
    upload_parts(Client, Body),
    {ok, Response2} = lhttpc:send_trailers(Client, [Trailer]),
    ?assertEqual({200, "OK"}, status(Response2)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response2)),
    ?assertEqual("This is chunky stuff!",
        lhttpc_lib:header_value("x-test-orig-body", headers(Response2))),
    ?assertEqual(element(2, Trailer),
        lhttpc_lib:header_value("x-test-orig-trailer-1", headers(Response2))).

partial_upload_chunked_no_trailer() ->
    Port = start(gen_tcp, [fun webserver_utils:chunked_upload/5]),
    URL = url(Port, "/partial_upload_chunked_no_trailer"),
    Body = [<<"This">>, <<" is ">>, <<"chunky">>, <<" stuff!">>],
    Options = [{partial_upload, true}],
    {ok, Client} = lhttpc:connect_client(URL, []),
    {ok, partial_upload} = lhttpc:request_client(Client, URL, post, [], hd(Body), 1000, Options),
    ok = upload_parts(Client, tl(Body)),
    {ok, Response} = lhttpc:send_body_part(Client, http_eob, 1000),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response)),
    ?assertEqual("This is chunky stuff!",
                    lhttpc_lib:header_value("x-test-orig-body", headers(Response))).

partial_download_illegal_option() ->
    ?assertError({bad_option, {partial_download, {foo, bar}}},
        lhttpc:request("http://localhost/", get, [], <<>>, 1000,
            [{partial_download, [{foo, bar}]}])).

long_body_part(Size) ->
    list_to_binary(
      lists:flatten(
    [webserver_utils:long_body_part() || _ <- lists:seq(1, Size)])).

partial_download_identity() ->
    Port = start(gen_tcp, [fun webserver_utils:large_response/5]),
    URL = url(Port, "/partial_download_identity"),
    PartialDownload = [
        {window_size, 1},
        {recv_proc, self()}
    ],
    Options = [{partial_download, PartialDownload}],
    {ok, Client} = lhttpc:connect_client(URL, []),
    {ok, {Status, _Hdrs, partial_download}} =
        lhttpc:request_client(Client, URL, get, [], <<>>, 1000, Options),
    Body = read_partial_body(Client),
    ?assertEqual({200, "OK"}, Status),
    ?assertEqual(size(long_body_part(3)), size(Body)),
    ?assertEqual(long_body_part(3), Body).

partial_download_infinity_window() ->
    Port = start(gen_tcp, [fun webserver_utils:large_response/5]),
    URL = url(Port, "/partial_download_identity"),
    PartialDownload = [
               {window_size, infinity},
               {recv_proc, self()}
    ],
    Options = [{partial_download, PartialDownload}],
    {ok, Client} = lhttpc:connect_client(URL, []),
    {ok, {Status, _Hdrs, partial_download}} =
        lhttpc:request_client(Client, URL, get, [], <<>>, 1000, Options),
    Body = read_partial_body(Client),
    ?assertEqual({200, "OK"}, Status),
    ?assertEqual(long_body_part(3), Body).

partial_download_no_content_length() ->
    Port = start(gen_tcp, [fun webserver_utils:no_content_length/5]),
    URL = url(Port, "/no_cl"),
    PartialDownload = [
               {window_size, 1},
               {recv_proc, self()}
    ],
    Options = [{partial_download, PartialDownload}],
    {ok, Client} = lhttpc:connect_client(URL, []),
    {ok, {Status, _Hdrs, partial_download}} =
        lhttpc:request_client(Client, URL, get, [], <<>>, 1000, Options),
    Body = read_partial_body(Client),
    ?assertEqual({200, "OK"}, Status),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), Body).

partial_download_no_content() ->
    Port = start(gen_tcp, [fun webserver_utils:no_content_response/5]),
    URL = url(Port, "/partial_download_identity"),
    PartialDownload = [
               {window_size, 1},
               {recv_proc, self()}
    ],
    Options = [{partial_download, PartialDownload}],
    {ok, Client} = lhttpc:connect_client(URL, []),
    {ok, {Status, _Hdrs, Body}} =
        lhttpc:request_client(Client, URL, get, [], <<>>, 1000, Options),
    ?assertEqual({204, "OK"}, Status),
    ?assertEqual(undefined, Body).

limited_partial_download_identity() ->
    Port = start(gen_tcp, [fun webserver_utils:large_response/5]),
    URL = url(Port, "/partial_download_identity"),
    PartialDownload = [
               {window_size, 1},
               {part_size, 512}, % bytes
               {recv_proc, self()}
              ],
    Options = [{partial_download, PartialDownload}],
    {ok, Client} = lhttpc:connect_client(URL, []),
    {ok, {Status, _Hdrs, partial_download}} =
        lhttpc:request_client(Client, URL, get, [], <<>>, 1000, Options),
    Body = read_partial_body(Client, 512),
    ?assertEqual({200, "OK"}, Status),
    ?assertEqual(long_body_part(3), Body).

partial_download_chunked() ->
    Port = start(gen_tcp, [fun webserver_utils:large_chunked_response/5]),
    URL = url(Port, "/partial_download_identity"),
    PartialDownload = [
               {window_size, 1},
               {part_size, length(webserver_utils:long_body_part()) * 3},
               {recv_proc, self()}
    ],
    Options = [{partial_download, PartialDownload}],
    {ok, Client} = lhttpc:connect_client(URL, []),
    {ok, {Status, _Hdrs, partial_download}} =
        lhttpc:request_client(Client, URL, get, [], <<>>, 1000, Options),
    Body = read_partial_body(Client),
    ?assertEqual({200, "OK"}, Status),
    ?assertEqual(long_body_part(3), Body).

partial_download_chunked_infinite_part() ->
    Port = start(gen_tcp, [fun webserver_utils:large_chunked_response/5]),
    URL = url(Port, "/partial_download_identity"),
    PartialDownload = [
               {window_size, 1},
               {part_size, infinity},
               {recv_proc, self()}
    ],
    Options = [{partial_download, PartialDownload}],
    {ok, Client} = lhttpc:connect_client(URL, []),
    {ok, {Status, _Hdrs, partial_download}} =
        lhttpc:request_client(Client, URL, get, [], <<>>, 1000, Options),
    Body = read_partial_body(Client),
    ?assertEqual({200, "OK"}, Status),
    ?assertEqual(size(long_body_part(3)), size(Body)),
    ?assertEqual(long_body_part(3), Body).

partial_download_smallish_chunks() ->
    Port = start(gen_tcp, [fun webserver_utils:large_chunked_response/5]),
    URL = url(Port, "/partial_download_identity"),
    PartialDownload = [
               {window_size, 1},
               {part_size, length(webserver_utils:long_body_part()) - 1},
               {recv_proc, self()}
    ],
    Options = [{partial_download, PartialDownload}],
    {ok, Client} = lhttpc:connect_client(URL, []),
    {ok, {Status, _Hdrs, partial_download}} =
        lhttpc:request_client(Client, URL, get, [], <<>>, 1000, Options),
    Body = read_partial_body(Client),
    ?assertEqual({200, "OK"}, Status),
    ?assertEqual(long_body_part(3), Body).

partial_download_slow_chunks() ->
    Port = start(gen_tcp, [fun webserver_utils:slow_chunked_response/5]),
    URL = url(Port, "/slow"),
    PartialDownload = [
               {window_size, 1},
               {part_size, length(webserver_utils:long_body_part()) div 2},
               {recv_proc, self()}
    ],
    Options = [{partial_download, PartialDownload}],
    {ok, Client} = lhttpc:connect_client(URL, []),
    {ok, {Status, _Hdrs, partial_download}} =
        lhttpc:request_client(Client, URL, get, [], <<>>, 1000, Options),
    Body = read_partial_body(Client),
    ?assertEqual({200, "OK"}, Status),
    ?assertEqual(long_body_part(2), Body).

close_connection() ->
    Port = start(gen_tcp, [fun webserver_utils:close_connection/5]),
    URL = url(Port, "/close"),
    ?assertEqual({error, closed}, lhttpc:request(URL, "GET", [],
            1000)).

ssl_get() ->
    Port = start(ssl, [fun webserver_utils:simple_response/5]),
    URL = ssl_url(Port, "/simple"),
    {ok, _PoolManager} = lhttpc:add_pool(lhttpc_manager),
    {ok, Response} = lhttpc:request(URL, "GET", [], [], 1000, [{pool_options, [{pool_ensure, true}, {pool, lhttpc_manager}]}]),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response)).

ssl_get_ipv6() ->
    Port = start(ssl, [fun webserver_utils:simple_response/5], inet6),
    URL = ssl_url(inet6, Port, "/simple"),
    {ok, Response} = lhttpc:request(URL, "GET", [], [], 1000, [{pool_options, [{pool_ensure, true}, {pool, lhttpc_manager}]}]),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response)).

ssl_post() ->
    Port = start(ssl, [fun webserver_utils:copy_body/5]),
    URL = ssl_url(Port, "/simple"),
    Body = "SSL Test <o/",
    BinaryBody = list_to_binary(Body),
    {ok, Response} = lhttpc:request(URL, "POST", [], Body, 1000, [{pool_options, [{pool_ensure, true}, {pool, lhttpc_manager}]}]),
    ?assertEqual({200, "OK"}, status(Response)),
    ?assertEqual(BinaryBody, body(Response)).

ssl_chunked() ->
    Port = start(ssl, [fun webserver_utils:chunked_response/5, fun webserver_utils:chunked_response_t/5]),
    URL = ssl_url(Port, "/ssl_chunked"),
    {ok, Client} = lhttpc:connect_client(URL, []),
    FirstResult = lhttpc:request_client(Client, URL, get, [], [], 100, [{pool_options, [{pool_ensure, true}, {pool, lhttpc_manager}]}]),
    ?assertMatch({ok, _}, FirstResult),
    {ok, FirstResponse} = FirstResult,
    ?assertEqual({200, "OK"}, status(FirstResponse)),
    ?assertEqual(list_to_binary(webserver_utils:default_string()), body(FirstResponse)),
    ?assertEqual("chunked", lhttpc_lib:header_value("transfer-encoding",
            headers(FirstResponse))),
    SecondResult = lhttpc:request_client(Client, URL, get, [], [], 100, [{pool_options, [{pool_ensure, true}, {pool, lhttpc_manager}]}]),
    {ok, SecondResponse} = SecondResult,
    ?assertEqual({200, "OK"}, status(SecondResponse)),
    ?assertEqual(<<"Again, great success!">>, body(SecondResponse)),
    ?assertEqual("ChUnKeD", lhttpc_lib:header_value("transfer-encoding",
            headers(SecondResponse))),
    ?assertEqual("1", lhttpc_lib:header_value("Trailer-1",
            headers(SecondResponse))),
    ?assertEqual("2", lhttpc_lib:header_value("Trailer-2",
            headers(SecondResponse))).

connection_count() ->
    timer:sleep(50), % give the TCP stack time to deliver messages
    ?assertEqual(0, lhttpc_manager:connection_count(lhttpc_manager)).

invalid_options() ->
    ?assertError({bad_option, bad_option},
        lhttpc:request("http://localhost/", get, [], <<>>, 1000,
            [bad_option, {foo, bar}])),
    ?assertError({bad_option, {foo, bar}},
        lhttpc:request("http://localhost/", get, [], <<>>, 1000,
            [{foo, bar}, bad_option])).

cookies() ->
    Port = start(gen_tcp, [fun webserver_utils:set_cookie_response/5, fun webserver_utils:expired_cookie_response/5,
            fun webserver_utils:receive_right_cookies/5]),
    URL = url(Port, "/cookies"),
    Options = [{use_cookies, true}],
    {ok, Client} = lhttpc:connect_client(URL, Options),
    {ok, Response1} = lhttpc:request_client(Client, URL, get, [], 1000),
    ?assertEqual({200, "OK"}, status(Response1)),
    {ok, Response2} = lhttpc:request_client(Client, URL, get, [], 1000),
    ?assertEqual({200, "OK"}, status(Response2)),
    {ok, Response3} = lhttpc:request_client(Client, URL, get, [], 1000),
    ?assertEqual({200, "OK"}, status(Response3)).


%%% Helpers functions
upload_parts(Client, Parts) ->
    lists:foldl(fun(BodyPart, _) ->
            lhttpc:send_body_part(Client, BodyPart, 1000)
        end, ok, Parts).

read_partial_body(Client) ->
    read_partial_body(Client, infinity, <<>>).

read_partial_body(Client, Size) ->
    read_partial_body(Client, Size, <<>>).

read_partial_body(Client, Size, Acc) ->
    receive
    {body_part,  http_eob} ->
        %% chunked download
        ok = lhttpc:get_body_part(Client),
        read_partial_body(Client, Size, Acc);
    {body_part,  window_finished} ->
        ok = lhttpc:get_body_part(Client),
        read_partial_body(Client, Size, Acc);
    {body_part, Bin} ->
        if
                Size =:= infinity ->
                    ok;
                Size =/= infinity ->
                    ?assert(Size >= iolist_size(Bin))
        end,
        read_partial_body(Client, Size, <<Acc/binary,Bin/binary>>);
    {http_eob, Trailers} ->
        Acc;
    {body_part_error, Reason} ->
        {error, Reason, Acc}
    after
    1000 ->
        {error, receive_clause, Acc}
    end.

simple(Method) ->
    simple(Method, inet).

simple(Method, Family) ->
    case start(gen_tcp, [fun webserver_utils:simple_response/5], Family) of
        {error, family_not_supported} when Family =:= inet6 ->
            % Localhost has no IPv6 support - not a big issue.
            ?debugMsg("WARNING: impossible to test IPv6 support~n");
        Port when is_number(Port) ->
            URL = url(Family, Port, "/simple"),
            {ok, Response} = lhttpc:request(URL, Method, [], 1000),
            {StatusCode, ReasonPhrase} = status(Response),
            ?assertEqual(200, StatusCode),
            ?assertEqual("OK", ReasonPhrase),
            ?assertEqual(list_to_binary(webserver_utils:default_string()), body(Response))
    end.

url(Port, Path) ->
    url(inet, Port, Path).

url(inet, Port, Path) ->
    "http://localhost:" ++ integer_to_list(Port) ++ Path;
url(inet6, Port, Path) ->
    "http://[::1]:" ++ integer_to_list(Port) ++ Path.

url(Port, Path, User, Password) ->
    url(inet, Port, Path, User, Password).

url(inet, Port, Path, User, Password) ->
    "http://" ++ User ++ ":" ++ Password ++
        "@localhost:" ++ integer_to_list(Port) ++ Path;
url(inet6, Port, Path, User, Password) ->
    "http://" ++ User ++ ":" ++ Password ++
        "@[::1]:" ++ integer_to_list(Port) ++ Path.

ssl_url(Port, Path) ->
    "https://localhost:" ++ integer_to_list(Port) ++ Path.

ssl_url(inet6, Port, Path) ->
    "https://[::1]:" ++ integer_to_list(Port) ++ Path.

status({Status, _, _}) ->
    Status.

body({_, _, Body}) ->
    Body.

headers({_, Headers, _}) ->
    Headers.
