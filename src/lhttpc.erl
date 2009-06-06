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
%%% @doc Main interface to the lightweight http client.
%%% See `request/4' and `request/5' functions.
%%% @end
-module(lhttpc).
-behaviour(application).

-export([request/4, request/5]).
-export([start/2, stop/1]).

-include("lhttpc_types.hrl").

-type result() :: {ok, {{pos_integer(), string()}, headers(), binary()}} |
    {error, atom()}.

%% @hidden
-spec start(normal | {takeover, node()} | {failover, node()}, any()) ->
    {ok, pid()}.
start(_, _) ->
	% Make sure that the ssl random number generator is seeded
	ssl:seed(crypto:rand_bytes(255)),
    lhttpc_sup:start_link().

%% @hidden
-spec stop(any()) -> ok.
stop(_) ->
    ok.

%% @spec (URL, Method, Hdrs, Timeout) -> Result
%%   URL = string()
%%   Method = string() | atom()
%%   Hdrs = [{Header, Value}]
%%   Header = string() | binary() | atom()
%%   Value = string() | binary()
%%   Timeout = integer() | infinity
%%   Result = {ok, {{StatusCode, ReasonPhrase}, Hdrs, Body}}
%%            | {error, Reason}
%%   StatusCode = integer()
%%   ReasonPhrase = string()
%%   Body = binary()
%% @doc Sends a request without a body.
%% Would be the same as calling `request(URL, Method, Hdrs, [], Timeout)',
%% that is `request/5' with an empty body (`Body' could also be `<<>>').
%% @end
-spec request(string(), string() | atom(), headers(), pos_integer() |
        infinity) -> result().
request(URL, Method, Hdrs, Timeout) ->
    request(URL, Method, Hdrs, [], Timeout).

%% @spec (URL, Method, Hdrs, RequestBody, Timeout) -> Result
%%   URL = string()
%%   Method = string() | atom()
%%   Hdrs = [{Header, Value}]
%%   Header = string() | binary() | atom()
%%   Value = string() | binary()
%%   RequestBody = iolist()
%%   Timeout = integer() | infinity
%%   Result = {ok, {{StatusCode, ReasonPhrase}, Hdrs, ResponseBody}}
%%            | {error, Reason}
%%   StatusCode = integer()
%%   ReasonPhrase = string()
%%   ResponseBody = binary()
%% @doc Sends a request with a body.
%% `URL' is expected to be a valid URL: 
%% `scheme://host[:port][/path]'.
%% `Method' is either a string, stating the HTTP method exactly as in the
%% protocol, i.e: `"POST"' or `"GET"'. It could also be an atom, which is
%% then made in to uppercase, if it isn't already.
%% `Hdrs' is a list of headers to send. Mandatory headers such as
%% `Host' or `Content-Length' (for some requests) are added.
%% `Body' is the entity to send in the request. Please don't include entity
%% bodies where there shouldn't be any (such as for `GET').
%% `Timeout' is the timeout for the request in milliseconds.
%% @end
-spec request(string(), string() | atom(), headers(), iolist(),
        pos_integer() | infinity) -> result().
request(URL, Method, Hdrs, Body, Timeout) ->
    Args = [self(), URL, Method, Hdrs, Body],
    Pid = spawn_link(lhttpc_client, request, Args),
    receive
        {response, Pid, R} ->
            R;
        {'EXIT', Pid, Reason} ->
            % This could happen if the process we're running in taps exits
            erlang:error(Reason)
    after Timeout ->
            kill_client(Pid)
    end.

kill_client(Pid) ->
    Monitor = erlang:monitor(process, Pid),
    unlink(Pid), % or we'll kill ourself :O
    exit(Pid, timeout),
    receive
        {response, Pid, R} ->
            erlang:demonitor(Monitor, [flush]),
            R;
        {'DOWN', _, process, Pid, timeout} ->
            {error, timeout};
        {'DOWN', _, process, Pid, Reason}  ->
            erlang:error(Reason)
    end.
