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
%%% See {@link request/4}, {@link request/5} and {@link request/6} functions.
%%% @end
-module(lhttpc).
-behaviour(application).

-export([request/4, request/5, request/6]).
-export([send_body_part/2, send_body_part/3, 
        send_trailers/2, send_trailers/3]).
-export([start/2, stop/1]).

-include("lhttpc_types.hrl").

-type result() :: {ok, {{pos_integer(), string()}, headers(), binary()}} |
    {error, atom()}.

%% @hidden
-spec start(normal | {takeover, node()} | {failover, node()}, any()) ->
    {ok, pid()}.
start(_, _) ->
    case lists:member({seed,1}, ssl:module_info(exports)) of
        true ->
            % Make sure that the ssl random number generator is seeded
            % This was new in R13 (ssl-3.10.1 in R13B vs. ssl-3.10.0 in R12B-5)
            ssl:seed(crypto:rand_bytes(255));
        false ->
            ok
    end,
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
%%   Result = {ok, {{StatusCode, ReasonPhrase}, Hdrs, ResponseBody}}
%%            | {error, Reason}
%%   StatusCode = integer()
%%   ReasonPhrase = string()
%%   ResponseBody = binary()
%%   Reason = connection_closed | connect_timeout | timeout
%% @doc Sends a request without a body.
%% Would be the same as calling `request(URL, Method, Hdrs, [], Timeout)',
%% that is {@link request/5} with an empty body (`Body' could also be `<<>>').
%% @end
-spec request(string(), string() | atom(), headers(), pos_integer() |
        infinity) -> result().
request(URL, Method, Hdrs, Timeout) ->
    request(URL, Method, Hdrs, [], Timeout, []).

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
%%   Reason = connection_closed | connect_timeout | timeout
%% @doc Sends a request with a body.
%% Would be the same as calling
%% `request(URL, Method, Hdrs, Body, Timeout, [])', that is {@link request/6} with
%% no options.
%% @end
-spec request(string(), string() | atom(), headers(), iolist(),
        pos_integer() | infinity) -> result().
request(URL, Method, Hdrs, Body, Timeout) ->
    request(URL, Method, Hdrs, Body, Timeout, []).

%% @spec (URL, Method, Hdrs, RequestBody, Timeout, Options) -> Result
%%   URL = string()
%%   Method = string() | atom()
%%   Hdrs = [{Header, Value}]
%%   Header = string() | binary() | atom()
%%   Value = string() | binary()
%%   RequestBody = iolist()
%%   Timeout = integer() | infinity
%%   Options = [Option]
%%   Option = {connect_timeout, Milliseconds | infinity} |
%%            {send_retry, integer()} | {partial_upload, WindowSize}
%%   Milliseconds = integer()
%%   WindowSize = integer() | infinity
%%   Result = {ok, {{StatusCode, ReasonPhrase}, Hdrs, ResponseBody}} |
%%            {ok, UploadState} | {error, Reason}
%%   StatusCode = integer()
%%   ReasonPhrase = string()
%%   ResponseBody = binary()
%%   Reason = connection_closed | connect_timeout | timeout
%% @doc Sends a request with a body.
%% `URL' is expected to be a valid URL: 
%% `scheme://host[:port][/path]'.
%% `Method' is either a string, stating the HTTP method exactly as in the
%% protocol, i.e: `"POST"' or `"GET"'. It could also be an atom, which is
%% then made in to uppercase, if it isn't already.
%% `Hdrs' is a list of headers to send. Mandatory headers such as
%% `Host', `Content-Length' or `Transfer-Encoding' (for some requests) 
%% are added.
%% `Body' is the entity to send in the request. Please don't include entity
%% bodies where there shouldn't be any (such as for `GET').
%% `Timeout' is the timeout for the request in milliseconds.
%% `Options' is a list of options.
%%
%% Options:
%%
%% `{connect_timeout, Milliseconds}' specifies how many milliseconds the
%% client can spend trying to establish a connection to the server. This
%% doesn't affect the overall request timeout. However, if it's longer than
%% the overall timeout it will be ignored. Also note that the TCP layer my
%% choose to give up earlier than the connect timeout, in which case the
%% client will also give up. The default value is infinity, which means that
%% it will either give up when the TCP stack gives up, or when the overall
%% request timeout is reached. 
%%
%% `{send_retry, N}' specifies how many times the client should retry
%% sending a request if the connection is closed after the data has been
%% sent. The default value is `1'. If `{partial_upload, WindowSize}'
%% (see below) is specified, the client cannot retry after the first part
%% of the body has been sent since it doesn't keep the whole entitity body
%% in memory.
%%
%% `{partial_upload, WindowSize}' means that the body will be supplied in
%% parts to the client by the calling process. The `WindowSize' specifies how
%% many parts can be sent to the process controlling the socket before waiting
%% for an acknowledgement. This is to create a kind of internal flow control
%% if the network is slow and the process is blocked by the TCP stack. Flow
%% control is disabled if `WindowSize' is `infinity'. If `WindowSize' is an
%% integer, it must be >= 0.  If partial upload is specified and no
%% `Content-Length' is specified in `Hdrs' the client will use chunked
%% transfer encoding to send the entity body. If a content length is
%% specified, this must be the total size of the entity body.
%% The call to {@link request/6} will return `{ok, UploadState}'. The
%% `UploadState' is supposed to be used as the first argument to the {@link
%% send_body_part/2} or {@link send_body_part/3} functions to send body parts.
%% Partial upload is intended to avoid keeping large request bodies in
%% memory but can also be used when the complete size of the body isn't known
%% when the request is started.
%% @end
-spec request(string(), string() | atom(), headers(), iolist(),
        pos_integer() | infinity, [option()]) -> result().
request(URL, Method, Hdrs, Body, Timeout, Options) ->
    verify_options(Options, []),
    Args = [self(), URL, Method, Hdrs, Body, Options],
    Pid = spawn_link(lhttpc_client, request, Args),
    receive
        {response, Pid, R} ->
            R;
        {exit, Pid, Reason} ->
            % We would rather want to exit here, instead of letting the
            % linked client send us an exit signal, since this can be
            % caught by the caller.
            exit(Reason);
        {'EXIT', Pid, Reason} ->
            % This could happen if the process we're running in taps exits
            % and the client process exits due to some exit signal being
            % sent to it. Very unlikely though
            exit(Reason)
    after Timeout ->
            kill_client(Pid)
    end.

%% @spec (UploadState :: UploadState, BodyPart :: BodyPart) -> Result
%%   BodyPart = iolist() | binary()
%%   Timeout = integer() | infinity
%%   Result = {error, Reason} | UploadState
%%   Reason = connection_closed | connect_timeout | timeout
%% @doc Sends a body part to an ongoing request when
%% `{partial_upload, WindowSize}' is used. The default timeout, `infinity'
%% will be used. Notice that if `WindowSize' is infinity, this call will never
%% block.
%% Would be the same as calling
%% `send_body_part(UploadState, BodyPart, infinity)'.
%% @end
-spec send_body_part({pid(), window_size()}, binary()) -> 
        {pid(), window_size()} | result().
send_body_part({Pid, Window}, Bin) ->
    send_body_part({Pid, Window}, Bin, infinity).

%% @spec (UploadState :: UploadState, BodyPart :: BodyPart, Timeout) -> Result
%%   BodyPart = iolist() | binary()
%%   Timeout = integer() | infinity
%%   Result = {error, Reason} | UploadState
%%   Reason = connection_closed | connect_timeout | timeout
%% @doc Sends a body part to an ongoing request when
%% `{partial_upload, WindowSize}' is used.
%% `Timeout' is the timeout for the request in milliseconds.
%%
%% If the window size reaches 0 the call will block for at maximum Timeout
%% milliseconds. If there is no acknowledgement received during that time the
%% the request is cancelled and `{error, timeout}' is returned.
%%
%% As long as the window size is larger than 0 the function will return 
%% immediately after sending the body part to the request handling process.
%% 
%% The `BodyPart' `http_eob' signals an end of the entity body, the request
%% is considered sent and the response will be read from the socket. If
%% there is no response within `Timeout' milliseconds, the request is
%% canceled and `{error, timeout}' is returned.
%% @end
-spec send_body_part({pid(), window_size()}, binary(), timeout()) -> 
        {ok, {pid(), window_size()}} | result().
send_body_part({Pid, 0}, Bin, Timeout) 
        when is_binary(Bin), is_pid(Pid) ->
    receive
        {ack, Pid} ->
            send_body_part({Pid, 1}, Bin, Timeout);
        {response, Pid, R} ->
            R;
        {exit, Pid, Reason} ->
            exit(Reason);
        {'EXIT', Pid, Reason} ->
            exit(Reason)
    after Timeout ->
        kill_client(Pid)
    end;
send_body_part({Pid, Window}, Bin, _Timeout) 
        when Window > 0, is_binary(Bin), is_pid(Pid) ->
    Pid ! {body_part, self(), Bin},
    receive
        {ack, Pid} ->
            %% body_part ACK
            {ok, {Pid, Window}};
        {reponse, Pid, R} ->
            %% something went wrong in the client
            %% for example the connection died or
            %% the last body part has been sent 
            R;
        {exit, Pid, Reason} ->
            exit(Reason);
        {'EXIT', Pid, Reason} ->
            exit(Reason)
    after 0 ->
        {ok, {Pid, dec(Window)}}
    end;
send_body_part({Pid, _Window}, http_eob, Timeout) when is_pid(Pid) ->
    Pid ! {body_part, self(), http_eob},
    read_response(Pid, Timeout).

%% @spec (UploadState :: UploadState, Trailers) -> Result
%%   Header = string() | binary() | atom()
%%   Value = string() | binary()
%%   Result = {ok, {{StatusCode, ReasonPhrase}, Hdrs, ResponseBody}}
%%            | {error, Reason}
%%   Reason = connection_closed | connect_timeout | timeout
%% @doc Sends trailers to an ongoing request when `{partial_upload,
%% WindowSize}' is used and no `Content-Length' was specified. The default
%% timout `infinity' will be used. Note that after this the request is
%% considered complete and the response will be read from the socket. 
%% Would be the same as calling
%% `send_trailers(UploadState, BodyPart, infinity)'.
%% @end
-spec send_trailers({pid(), window_size()}, headers()) -> result().
send_trailers({Pid, Window}, Trailers) ->
    send_trailers({Pid, Window}, Trailers, infinity).

%% @spec (UploadState :: UploadState, Trailers, Timeout) -> Result
%%   Trailers = [{Header, Value}]
%%   Header = string() | binary() | atom()
%%   Value = string() | binary()
%%   Timeout = integer() | infinity
%%   Result = {ok, {{StatusCode, ReasonPhrase}, Hdrs, ResponseBody}}
%%            | {error, Reason}
%%   Reason = connection_closed | connect_timeout | timeout
%% @doc Sends trailers to an ongoing request when
%% `{partial_upload, WindowSize}' is used and no `Content-Length' was
%% specified.
%% `Timeout' is the timeout for sending the trailers and reading the
%% response in milliseconds.
%%
%% Sending trailers also signals the end of the entity body, which means
%% that no more body parts, or trailers can be sent and the response to the
%% request will be read from the socket. If no response is received within
%% `Timeout' milliseconds the request is canceled and `{error, timeout}' is
%% returned.
%% @end
-spec send_trailers({pid(), window_size()}, [{string() | string()}], 
        timeout()) -> result().
send_trailers({Pid, _Window}, Trailers, Timeout)
        when is_list(Trailers), is_pid(Pid) ->
    Pid ! {trailers, self(), Trailers},
    % XXX: You claimed earlier in the docs that if the window size would be
    % 0 we would block, but we don't. I can't see why it would make any
    % sense waiting for an ack here though since we're blocked in
    % read_response any way.
    read_response(Pid, Timeout).

-spec read_response(pid(), timeout()) -> result().
read_response(Pid, Timeout) ->
    receive
        {ack, Pid} ->
            read_response(Pid, Timeout);
        {response, Pid, R} ->
            R;
        {exit, Pid, Reason} ->
            exit(Reason);
        {'EXIT', Pid, Reason} ->
            exit(Reason)
    after Timeout ->
        kill_client(Pid)
    end.

%%% Internal functions

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

-spec dec(timeout()) -> timeout().
dec(Num) when is_integer(Num) -> Num - 1;
dec(Else)                     -> Else.

-spec verify_options(options(), options()) -> ok.
verify_options([{send_retry, N} | Options], Errors)
        when is_integer(N), N >= 0 ->
    verify_options(Options, Errors);
verify_options([{connect_timeout, infinity} | Options], Errors) ->
    verify_options(Options, Errors);
verify_options([{connect_timeout, MS} | Options], Errors)
        when is_integer(MS), MS >= 0 ->
    verify_options(Options, Errors);
verify_options([{partial_upload, WindowSize} | Options], Errors)
        when is_integer(WindowSize), WindowSize >= 0 ->
    verify_options(Options, Errors);
verify_options([{partial_upload, infinity} | Options], Errors)  ->
    verify_options(Options, Errors);
verify_options([{partial_download, DownloadOptions} | Options], Errors)
        when is_list(DownloadOptions) ->
    case verify_partial_download(DownloadOptions, []) of
        [] ->
            verify_options(Options, Errors);
        OptionErrors ->
            NewErrors = [{partial_download, OptionErrors} | Errors],
            verify_options(Options, NewErrors)
    end;
verify_options([Option | Options], Errors) ->
    verify_options(Options, [Option | Errors]);
verify_options([], []) ->
    ok;
verify_options([], Errors) ->
    bad_options(Errors).

-spec bad_options(options()) -> no_return().
bad_options(Errors) ->
    erlang:error({bad_options, Errors}).

verify_partial_download([{window_size, Size} | Options], Errors) when
        is_integer(Size), Size >= 0 ->
    verify_partial_download(Options, Errors);
verify_partial_download([{receiver, Pid} | Options], Errors) when is_pid(Pid) ->
    verify_partial_download(Options, Errors);
verify_partial_download([{part_size, Size} | Options], Errors) when
        is_integer(Size), Size >= 0 ->
    verify_partial_download(Options, Errors);
verify_partial_download([Option | Options], Errors) ->
    verify_partial_download(Options, [Option | Errors]);
verify_partial_download([], Errors) ->
    Errors.
