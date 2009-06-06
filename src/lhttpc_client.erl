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

%%% @private
%%% @author Oscar Hellström <oscar@erlang-consulting.com>
%%% @doc
%%% This module implements the HTTP request handling. This should normally
%%% not be called directly since it should be spawned by the lhttpc module.
%%% @end
-module(lhttpc_client).

-export([request/5]).

-include("lhttpc_types.hrl").

-spec request(pid(), string(), string() | atom(), headers(), iolist()) -> 
    no_return().
%% @spec (From, URL, Method, Hdrs, Body) -> void()
%%    From = pid()
%%    URL = string()
%%    Method = atom() | string()
%%    Hdrs = [Header]
%%    Header = {string() | atom(), string()}
%%    Body = iolist()
request(From, URL, Method, Hdrs, Body) ->
    case catch execute(From, URL, Method, Hdrs, Body) of
        {'EXIT', Reason} -> exit(Reason);
        _                -> exit(normal) % this should never return
    end.

execute(From, URL, Method, Hdrs, Body) ->
    {Host, Port, Path, Ssl} = lhttpc_lib:parse_url(URL),
    Request = lhttpc_lib:format_request(Path, Method, Hdrs, Host, Body),
    SocketRequest = {socket, self(), Host, Port, Ssl},
    Socket = case gen_server:call(lhttpc_manager, SocketRequest, infinity) of
        {ok, S}   -> S; % Re-using HTTP/1.1 connections
        no_socket -> undefined % Opening a new HTTP/1.1 connection
    end,
    Response = case send_request(Host, Port, Ssl, Request, Socket, 1) of
        {ok, R, undefined} ->
            {ok, R};
        {ok, R, NewSocket} ->
            % The socket we ended up doing the request over is returned
            % here, it might be the same as Socket, but we don't know.
            ManagerPid = whereis(lhttpc_manager),
            % If this fails, we're still the owner and the socket is closed
            % when we exit, which is fine.
            lhttpc_sock:controlling_process(NewSocket, ManagerPid, Ssl),
            gen_server:cast(lhttpc_manager, {done, Host, Port, Ssl, NewSocket}),
            {ok, R};
        {error, Reason} ->
            {error, Reason}
    end,
    From ! {response, self(), Response},
    ok.

send_request(_, _, _, _, _, 3) ->
    % Only do two attempts to connect to the server and send the request,
    % if it closes the connection on us twice, something is very wrong.
    {error, connection_closed};
send_request(Host, Port, Ssl, Request, undefined, Attempt) ->
    Options = [binary, {packet, http}, {active, false}],
    case lhttpc_sock:connect(Host, Port, Options, Ssl) of
        {ok, Socket} ->
            send_request(Host, Port, Ssl, Request, Socket, Attempt);
        {error, etimedout} ->
            % Connect timed out (the TCP stack decided so), try again.
            % Notice, no attempt to actually send the data has been made
            % here.
            send_request(Host, Port, Ssl, Request, undefined, Attempt);
        {error, Reason} ->
            {error, Reason}
    end;
send_request(Host, Port, Ssl, Request, Socket, Attempt) ->
    case lhttpc_sock:send(Socket, Request, Ssl) of
        ok ->
            Acc = {nil, nil, [], <<>>},
            lhttpc_sock:setopts(Socket, [{packet, http}], Ssl),
            case read_response(Host, Port, Ssl, Request, Acc, Socket, Attempt) of
                {ok, Response, NewSocket} ->
                    {ok, Response, NewSocket};
                {error, Reason} ->
                    lhttpc_sock:close(Socket, Ssl),
                    {error, Reason}
            end;
        {error, closed} ->
            lhttpc_sock:close(Socket, Ssl),
            send_request(Host, Port, Ssl, Request, undefined, Attempt + 1);
        Other ->
            lhttpc_sock:close(Socket, Ssl),
            Other
    end.

read_response(Host, Port, Ssl, Request, Acc, Socket, Attempt) ->
    {Vsn, Status, Hdrs, Body} = Acc,
    case lhttpc_sock:read(Socket, Ssl) of
        {ok, {http_response, NewVsn, StatusCode, Reason}} ->
            NewStatus = {StatusCode, Reason},
            NewAcc = {NewVsn, NewStatus, Hdrs, Body},
            read_response(Host, Port, Ssl, Request, NewAcc, Socket, Attempt);
        {ok, {http_header, _, Name, _, Value}} ->
            Header = {lhttpc_lib:maybe_atom_to_list(Name), Value},
            NewAcc = {Vsn, Status, [Header | Hdrs], Body},
            read_response(Host, Port, Ssl, Request, NewAcc, Socket, Attempt);
        {ok, http_eoh} ->
            lhttpc_sock:setopts(Socket, [{packet, raw}], Ssl),
            case read_body(Vsn, Hdrs, Ssl, Socket) of
                {ok, NewBody} ->
                    {ok, {Status, Hdrs, NewBody}, Socket};
                {ok, NewBody, NewSocket} ->
                    {ok, {Status, Hdrs, NewBody}, NewSocket};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, closed} ->
            % Either we only noticed that the socket was closed after we
            % sent the request, the server closed it just after we put
            % the request on the wire or the server has some issues and is
            % closing connections without sending responses.
            % If this the first attempt to send the request, we will try again.
            lhttpc_sock:close(Socket, Ssl),
            send_request(Host, Port, Ssl, Request, Socket, Attempt + 1);
        {error, Reason} ->
            {error, Reason}
    end.

read_body(Vsn, Hdrs, Ssl, Socket) ->
    % Find out how to read the entity body from the request.
    % * If we have a Content-Length, just use that and read the complete
    %   entity.
    % * If Transfer-Encoding is set to chunked, we should read one chunk at
    %   the time
    % * If neither of this is true, we need to read until the socket is
    %   closed (this was common in versions before 1.1).
    case lhttpc_lib:header_value("content-length", Hdrs) of
        undefined ->
            case lhttpc_lib:header_value("transfer-encoding", Hdrs) of
                "chunked" -> read_chunked_body(Socket, Ssl);
                undefined -> read_infinite_body(Socket, Vsn, Hdrs, Ssl)
            end;
        ContentLength ->
            read_length(Hdrs, Ssl, Socket, list_to_integer(ContentLength))
    end.

read_length(Hdrs, Ssl, Socket, Length) ->
    Response = lhttpc_sock:read(Socket, Length, Ssl),
    case Response of
        {ok, Data} ->
            NewSocket = case lhttpc_lib:header_value("connection", Hdrs) of
                "close" ->
                    lhttpc_sock:close(Socket, Ssl),
                    undefined;
                _ ->
                    Socket
            end,
            {ok, Data, NewSocket};
        {error, closed} ->
            {error, connection_closed};
        Other ->
            Other
    end.

read_chunked_body(_, _) ->
    % TODO: Implement chunked reading
    erlang:error(not_imlemented).

read_infinite_body(Socket, {1, 1}, Hdrs, Ssl) ->
    case lhttpc_lib:header_value("connection", Hdrs) of
        "close" -> read_until_closed(Socket, <<>>, Ssl);
        _       -> {error, bad_response}
    end;
read_infinite_body(Socket, _, Hdrs, Ssl) ->
    case lhttpc_lib:header_value("KeepAlive", Hdrs) of
        undefined -> read_until_closed(Socket, <<>>, Ssl);
        _         -> {error, bad_response}
    end.

read_until_closed(Socket, Acc, Ssl) ->
    case lhttpc_sock:read(Socket, Ssl) of
        {ok, Body} ->
            NewAcc = <<Acc/binary, Body/binary>>,
            read_until_closed(Socket, NewAcc, Ssl);
        {error, closed} ->
            lhttpc_sock:close(Socket, Ssl),
            {ok, Acc};
        Other ->
            Other
    end.
