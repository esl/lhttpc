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

-record(lhttpc_url, {
    host :: string(),
    port :: integer(),
    path :: string(),
    is_ssl:: boolean(),
    user = "" :: string(),
    password = "" :: string()
}).

%used by lhttpc_manager.
-record(httpc_man, {
        destinations = dict:new(),
        sockets = dict:new(),
        clients = dict:new(), % Pid => {Dest, MonRef}
        queues = dict:new(),  % Dest => queue of Froms
        max_pool_size = 50 :: non_neg_integer(),
        timeout = 300000 :: non_neg_integer()
    }).

%record that keeps the state of the client.
-record(client_state, {
        host :: string(),
        port = 80 :: integer(),
        ssl = false :: true | false,
        method :: string(),
        request :: iolist(),
        request_headers :: headers(),
        socket,
        connect_timeout = infinity :: timeout(),
        connect_options = [] :: [any()],
        attempts :: integer(),
        requester :: pid(),
        partial_upload = false :: true | false,
        chunked_upload = false :: true | false,
        upload_window :: non_neg_integer() | infinity,
        partial_download = false :: true | false,
        download_window = infinity :: timeout(),
        part_size :: non_neg_integer() | infinity,
        %% in case of infinity we read whatever data we can get from
        %% the wire at that point or in case of chunked one chunk
        proxy :: undefined | #lhttpc_url{},
        proxy_ssl_options = [] :: [any()],
        proxy_setup = false :: true | false
    }).
